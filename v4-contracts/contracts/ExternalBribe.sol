// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import 'contracts/interfaces/IBribe.sol';
import 'contracts/interfaces/IERC20.sol';
import 'contracts/interfaces/IGauge.sol';
import 'contracts/interfaces/IVoter.sol';
import 'contracts/interfaces/IVotingEscrow.sol';

// Bribes pay out rewards for a given pool based on the votes that were received from the user (goes hand in hand with Voter.vote())
contract ExternalBribe is IBribe {
    address public immutable voter; // only voter can modify balances (since it only happens on vote())
    address public immutable _ve; // 天使のたまご

    uint internal constant DURATION = 7 days; // rewards are released over the voting period
    uint internal constant MAX_REWARD_TOKENS = 16;

    uint public totalSupply;
    mapping(uint => uint) public balanceOf;
    mapping(address => mapping(uint => uint)) public tokenRewardsPerEpoch;
    mapping(address => uint) public periodFinish;
    mapping(address => mapping(uint => uint)) public lastEarn;

    address[] public rewards;
    mapping(address => bool) public isReward;

    /// @notice A checkpoint for marking balance
    struct Checkpoint {
        uint timestamp;
        uint balanceOf;
    }

    /// @notice A checkpoint for marking supply
    struct SupplyCheckpoint {
        uint timestamp;
        uint supply;
    }

    /// @notice A record of balance checkpoints for each account, by index
    mapping (uint => mapping (uint => Checkpoint)) public checkpoints;
    /// @notice The number of checkpoints for each account
    mapping (uint => uint) public numCheckpoints;
    /// @notice A record of balance checkpoints for each token, by index
    mapping (uint => SupplyCheckpoint) public supplyCheckpoints;
    /// @notice The number of checkpoints
    uint public supplyNumCheckpoints;

    event Deposit(address indexed from, uint tokenId, uint amount);
    event Withdraw(address indexed from, uint tokenId, uint amount);
    event NotifyReward(address indexed from, address indexed reward, uint epoch, uint amount);
    event ClaimRewards(address indexed from, address indexed reward, uint amount);
    event HandleLeftOverRewards(address indexed reward, uint originalEpoch, uint updatedEpoch, uint amount);

    constructor(address _voter, address[] memory _allowedRewardTokens) {
        voter = _voter;
        _ve = IVoter(_voter)._ve();

        for (uint i; i < _allowedRewardTokens.length; i++) {
            if (_allowedRewardTokens[i] != address(0)) {
                isReward[_allowedRewardTokens[i]] = true;
                rewards.push(_allowedRewardTokens[i]);
            }
        }
    }

    // simple re-entrancy check
    uint internal _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    function _bribeStart(uint timestamp) internal pure returns (uint) {
        return timestamp - (timestamp % (7 days));
    }

    function getEpochStart(uint timestamp) public pure returns (uint) {
        uint bribeStart = _bribeStart(timestamp);
        uint bribeEnd = bribeStart + DURATION;
        return timestamp < bribeEnd ? bribeStart : bribeStart + 7 days;
    }

    /**
    * @notice Determine the prior balance for an account as of a block number
    * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
    * @param tokenId The token of the NFT to check
    * @param timestamp The timestamp to get the balance at
    * @return The balance the account had as of the given block
    */
    function getPriorBalanceIndex(uint tokenId, uint timestamp) public view returns (uint) {
        uint nCheckpoints = numCheckpoints[tokenId];
        if (nCheckpoints == 0) {
            return 0;
        }
        // First check most recent balance
        if (checkpoints[tokenId][nCheckpoints - 1].timestamp <= timestamp) {
            return (nCheckpoints - 1);
        }
        // Next check implicit zero balance
        if (checkpoints[tokenId][0].timestamp > timestamp) {
            return 0;
        }

        uint lower = 0;
        uint upper = nCheckpoints - 1;
        while (upper > lower) {
            uint center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[tokenId][center];
            if (cp.timestamp == timestamp) {
                return center;
            } else if (cp.timestamp < timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    function getPriorSupplyIndex(uint timestamp) public view returns (uint) {
        uint nCheckpoints = supplyNumCheckpoints;
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (supplyCheckpoints[nCheckpoints - 1].timestamp <= timestamp) {
            return (nCheckpoints - 1);
        }

        // Next check implicit zero balance
        if (supplyCheckpoints[0].timestamp > timestamp) {
            return 0;
        }

        uint lower = 0;
        uint upper = nCheckpoints - 1;
        while (upper > lower) {
            uint center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            SupplyCheckpoint memory cp = supplyCheckpoints[center];
            if (cp.timestamp == timestamp) {
                return center;
            } else if (cp.timestamp < timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    function _writeCheckpoint(uint tokenId, uint balance) internal {
        uint _timestamp = block.timestamp;
        uint _nCheckPoints = numCheckpoints[tokenId];
        if (_nCheckPoints > 0 && checkpoints[tokenId][_nCheckPoints - 1].timestamp == _timestamp) {
            checkpoints[tokenId][_nCheckPoints - 1].balanceOf = balance;
        } else {
            checkpoints[tokenId][_nCheckPoints] = Checkpoint(_timestamp, balance);
            numCheckpoints[tokenId] = _nCheckPoints + 1;
        }
    }

    function _writeSupplyCheckpoint() internal {
        uint _nCheckPoints = supplyNumCheckpoints;
        uint _timestamp = block.timestamp;

        if (_nCheckPoints > 0 && supplyCheckpoints[_nCheckPoints - 1].timestamp == _timestamp) {
            supplyCheckpoints[_nCheckPoints - 1].supply = totalSupply;
        } else {
            supplyCheckpoints[_nCheckPoints] = SupplyCheckpoint(_timestamp, totalSupply);
            supplyNumCheckpoints = _nCheckPoints + 1;
        }
    }

    function rewardsListLength() external view returns (uint) {
        return rewards.length;
    }

    // returns the last time the reward was modified or periodFinish if the reward has ended
    function lastTimeRewardApplicable(address token) public view returns (uint) {
        return Math.min(block.timestamp, periodFinish[token]);
    }

    // allows a user to claim rewards for a given token
    function getReward(uint tokenId, address[] memory tokens) external lock  {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, tokenId));
        for (uint i = 0; i < tokens.length; i++) {
            uint _reward = earned(tokens[i], tokenId);
            lastEarn[tokens[i]][tokenId] = block.timestamp;
            if (_reward > 0) _safeTransfer(tokens[i], msg.sender, _reward);

            emit ClaimRewards(msg.sender, tokens[i], _reward);
        }
    }

    // used by Voter to allow batched reward claims
    function getRewardForOwner(uint tokenId, address[] memory tokens) external lock  {
        require(msg.sender == voter);
        address _owner = IVotingEscrow(_ve).ownerOf(tokenId);
        for (uint i = 0; i < tokens.length; i++) {
            uint _reward = earned(tokens[i], tokenId);
            lastEarn[tokens[i]][tokenId] = block.timestamp;
            if (_reward > 0) _safeTransfer(tokens[i], _owner, _reward);

            emit ClaimRewards(_owner, tokens[i], _reward);
        }
    }

    function earned(address token, uint tokenId) public view returns (uint) {
        if (numCheckpoints[tokenId] == 0) {
            return 0;
        }

        uint reward = 0;
        uint _bal = 0;
        uint _supply = 1;
        uint _index = 0;
        uint _currTs = _bribeStart(lastEarn[token][tokenId]); // take epoch last claimed in as starting point

        _index = getPriorBalanceIndex(tokenId, _currTs);

        // accounts for case where lastEarn is before first checkpoint
        _currTs = Math.max(_currTs, _bribeStart(checkpoints[tokenId][_index].timestamp)); 

        // get epochs between current epoch and first checkpoint in same epoch as last claim
        uint numEpochs = (_bribeStart(block.timestamp) - _currTs) / DURATION;

        if (numEpochs > 0) {
            for (uint256 i = 0; i < numEpochs; i++) {
                // get index of last checkpoint in this epoch
                _index = getPriorBalanceIndex(tokenId, _currTs + DURATION); 
                // get checkpoint in this epoch
                _bal = checkpoints[tokenId][_index].balanceOf;
                // get supply of last checkpoint in this epoch
                _supply = supplyCheckpoints[getPriorSupplyIndex(_currTs + DURATION)].supply;
                if (_supply != 0) {
                    reward += _bal * tokenRewardsPerEpoch[token][_currTs] / _supply;
                }
                _currTs += DURATION;
            }
        }

        return reward;
    }

    // This is an external function, but internal notation is used since it can only be called "internally" from Gauges
    function _deposit(uint amount, uint tokenId) external {
        require(msg.sender == voter);

        totalSupply += amount;
        balanceOf[tokenId] += amount;

        _writeCheckpoint(tokenId, balanceOf[tokenId]);
        _writeSupplyCheckpoint();

        emit Deposit(msg.sender, tokenId, amount);
    }

    function _withdraw(uint amount, uint tokenId) external {
        require(msg.sender == voter);

        totalSupply -= amount;
        balanceOf[tokenId] -= amount;

        _writeCheckpoint(tokenId, balanceOf[tokenId]);
        _writeSupplyCheckpoint();

        emit Withdraw(msg.sender, tokenId, amount);
    }

    function left(address token) external view returns (uint) {
        uint adjustedTstamp = getEpochStart(block.timestamp);
        return tokenRewardsPerEpoch[token][adjustedTstamp];
    }

    function notifyRewardAmount(address token, uint amount) external lock {
        require(amount > 0);
        if (!isReward[token]) {
          require(IVoter(voter).isWhitelisted(token), "bribe tokens must be whitelisted");
          require(rewards.length < MAX_REWARD_TOKENS, "too many rewards tokens");
        }
        // bribes kick in at the start of next bribe period
        uint adjustedTstamp = getEpochStart(block.timestamp);
        uint epochRewards = tokenRewardsPerEpoch[token][adjustedTstamp];

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        amount = balanceAfter - balanceBefore;

        tokenRewardsPerEpoch[token][adjustedTstamp] = epochRewards + amount;

        periodFinish[token] = adjustedTstamp + DURATION;

        if (!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
        }

        emit NotifyReward(msg.sender, token, adjustedTstamp, amount);
    }

    // This is an external function that can only be called by teams to handle unclaimed rewards due to zero vote
    function handleLeftOverRewards(uint epochTimestamp, address[] memory tokens) external {
        require(msg.sender == IVotingEscrow(_ve).team(), "only team");

        // require that supply of that epoch to be ZERO
        uint epochStart = getEpochStart(epochTimestamp);
        SupplyCheckpoint memory sp0 = supplyCheckpoints[getPriorSupplyIndex(epochStart + DURATION)];
        if (epochStart + DURATION > _bribeStart(sp0.timestamp)) {
            require(sp0.supply == 0, "this epoch has votes");
        }

        // do sth like notifyRewardAmount
        uint length = tokens.length;
        for (uint i = 0; i < length;) {
            // check bribe amount 
            uint previousEpochRewards = tokenRewardsPerEpoch[tokens[i]][epochStart];
            require(previousEpochRewards != 0, "no bribes for this epoch");

            // get timestamp of current epoch
            uint adjustedTstamp = getEpochStart(block.timestamp);

            // get notified reward of current epoch
            uint currentEpochRewards = tokenRewardsPerEpoch[tokens[i]][adjustedTstamp];

            // add previous unclaimed rewards to current epoch
            tokenRewardsPerEpoch[tokens[i]][adjustedTstamp] = currentEpochRewards + previousEpochRewards;

            // remove token rewards from previous epoch
            tokenRewardsPerEpoch[tokens[i]][epochStart] = 0;

            // amend period finish
            periodFinish[tokens[i]] = adjustedTstamp + DURATION;

            emit HandleLeftOverRewards(tokens[i], epochStart, adjustedTstamp, previousEpochRewards);

            unchecked {
                ++i;
            }
        }
    }

    function swapOutRewardToken(uint i, address oldToken, address newToken) external {
        require(msg.sender == IVotingEscrow(_ve).team(), 'only team');
        require(rewards[i] == oldToken);
        isReward[oldToken] = false;
        isReward[newToken] = true;
        rewards[i] = newToken;
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) =
        token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) =
        token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}

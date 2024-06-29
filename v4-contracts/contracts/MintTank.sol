// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "contracts/interfaces/IFlow.sol";
import "contracts/interfaces/IVotingEscrow.sol";

/**
 * @dev This contract allow the team to hold a large amount of FLOW but not pre lock them.
 * It requires that FLOW exiting this be locked for more than 90days.
 */
contract MintTank is Ownable {
    address public immutable FLOW;
    address public immutable votingEscrow;
    uint256 public immutable minLockTime;

    constructor(
        address _flow,
        address _votingEscrow,
        address _team,
        uint256 _minLockTime
    ) {
        FLOW = _flow;
        votingEscrow = _votingEscrow;
        minLockTime = _minLockTime;
        _transferOwnership(_team);
    }

    /**
     * @dev Mints a new NFT to an address designated with a minimum of a 90day lock
     */
    function mintFor(
        uint _value,
        uint _lock_duration,
        address _to
    ) public onlyOwner {
        require(_lock_duration >= minLockTime, "Check minLockTime");
        IFlow(FLOW).approve(votingEscrow, _value);
        IVotingEscrow(votingEscrow).create_lock_for(
            _value,
            _lock_duration,
            _to
        );
    }

    /**
     * @dev Allows owner to clean out the contract of ANY tokens including v2, but not v1
     */
    function inCaseTokensGetStuck(
        address _token,
        address _to,
        uint256 _amount
    ) public onlyOwner {
        require(_token != address(FLOW), "FLOW must be minted to get it out");
        SafeERC20.safeTransfer(IERC20(_token), _to, _amount);
    }
}

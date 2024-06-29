// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "contracts/interfaces/IMinter.sol";
import "contracts/interfaces/IRewardsDistributor.sol";
import "contracts/interfaces/IFlow.sol";
import "contracts/interfaces/IVoter.sol";
import "contracts/interfaces/IVotingEscrow.sol";

// codifies the minting rules as per ve(3,3), abstracted from the token to support any token that allows minting

contract Minter is IMinter {
    uint internal constant WEEK = 86400 * 7; // allows minting once per week (reset every Thursday 00:00 UTC)
    uint internal constant PRECISION = 1000;
    IFlow public immutable _flow;
    IVoter public immutable _voter;
    IVotingEscrow public immutable _ve;
    IRewardsDistributor[] public _rewards_distributors;
    uint public weeklyPerGauge = 2000 * 1e18;
    uint public active_period;

    address internal initializer;
    address public team;
    address public teamEmissions;

    address public pendingTeam;
    uint public teamRate;
    uint public constant MAX_TEAM_RATE = 50; // 5% max

    event Mint(address indexed sender, uint weekly, uint circulating_supply);
    event EmissionPerGaugeSet(uint256 emissionPerGauge);

    struct Claim {
        address claimant;
        uint256 amount;
        uint256 lockTime;
    }

    constructor(
        address __voter, // the voting & distribution system
        address __ve, // the ve(3,3) system that will be locked into
        address __rewards_distributor // the distribution system that ensures users aren't diluted
    ) {
        initializer = msg.sender;
        team = msg.sender;
        teamEmissions = msg.sender;
        teamRate = 50; // 30 bps = 3%
        _flow = IFlow(IVotingEscrow(__ve).baseToken());
        _voter = IVoter(__voter);
        _ve = IVotingEscrow(__ve);
        _rewards_distributors.push(IRewardsDistributor(__rewards_distributor));
        active_period = ((block.timestamp + (2 * WEEK)) / WEEK) * WEEK;
    }

    function startActivePeriod() external {
        require(initializer == msg.sender, "not initializer");
        initializer = address(0);
        // allow minter.update_period() to mint new emissions THIS Thursday
        active_period = ((block.timestamp) / WEEK) * WEEK;
    }

    function setTeam(address _team) external {
        require(msg.sender == team, "not team");
        pendingTeam = _team;
    }

    function acceptTeam() external {
        require(msg.sender == pendingTeam, "not pending team");
        team = pendingTeam;
        teamEmissions = pendingTeam;
    }

    function setTeamRate(uint _teamRate) external {
        require(msg.sender == team, "not team");
        require(_teamRate <= MAX_TEAM_RATE, "rate too high");
        teamRate = _teamRate;
    }

    function setTeamEmissionAddress(address _teamEmissions) external {
        require(msg.sender == team, "not team");
        teamEmissions = _teamEmissions;
    }

    function setWeeklyEmissionPerGauge(uint _weeklyPerGauge) external {
        require(msg.sender == team, "not team");
        weeklyPerGauge = _weeklyPerGauge;
        emit EmissionPerGaugeSet(_weeklyPerGauge);
    }

    // calculate circulating supply as total token supply - locked supply
    function circulating_supply() public view returns (uint) {
        return _flow.totalSupply() - _ve.totalSupply();
    }

    // weekly emission takes the max of calculated (aka target) emission versus circulating tail end emission
    function weekly_emission() public view returns (uint) {
        uint256 numberOfGauges = _voter.activeGaugeNumber();
        if(numberOfGauges == 0) { 
            return weeklyPerGauge;
        }
        return weeklyPerGauge * numberOfGauges;
    }

    // calculate inflation and adjust ve balances accordingly
    function calculate_growth(uint _minted) public view returns (uint) {
        return 0;
    }

    // update period can only be called once per cycle (1 week)
    function update_period() external returns (uint) {
        uint _period = active_period;
        if (block.timestamp >= _period + WEEK && initializer == address(0)) { // only trigger if new week
            _period = (block.timestamp / WEEK) * WEEK;
            active_period = _period;
            uint256 weekly = weekly_emission();

            uint _teamEmissions = (teamRate * weekly) /
                (PRECISION - teamRate);
            uint _required =  weekly + _teamEmissions;
            uint _balanceOf = _flow.balanceOf(address(this));
            if (_balanceOf < _required) {
                _flow.mint(address(this), _required - _balanceOf);
            }

            require(_flow.transfer(teamEmissions, _teamEmissions));

            _checkpointRewardsDistributors();

            _flow.approve(address(_voter), weekly);
            _voter.notifyRewardAmount(weekly);

            emit Mint(msg.sender, weekly, circulating_supply());
        }
        return _period;
    }

    function addRewardsDistributor(address __rewards_distributor) external {
        require(msg.sender == team, "not team");
        _rewards_distributors.push(IRewardsDistributor(__rewards_distributor));
    }

    function removeRewardsDistributor(uint index) external {
        require(msg.sender == team, "not team");
        // Move the last element into the place to delete
        _rewards_distributors[index] = _rewards_distributors[_rewards_distributors.length - 1];
        // Remove the last element
        _rewards_distributors.pop();
    }

    function _checkpointRewardsDistributors() internal {
        for (uint i = 0; i < _rewards_distributors.length; i++) {
            _rewards_distributors[i].checkpoint_token(); // checkpoint token balance that was just minted in rewards distributor
            _rewards_distributors[i].checkpoint_total_supply(); // checkpoint supply
        }
    }
}

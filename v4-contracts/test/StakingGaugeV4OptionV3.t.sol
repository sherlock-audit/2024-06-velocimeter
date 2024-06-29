// 1:1 with Hardhat test
pragma solidity 0.8.13;

import './BaseTest.sol';
import "contracts/GaugeV4.sol";
import "contracts/factories/GaugeFactoryV4.sol";

contract StakingGaugeV4OptionV3 is BaseTest {
    GaugeFactoryV4 gaugeFactory;
    GaugeV4 gauge;
    TestStakingRewards staking;
    TestVotingEscrow escrow;
    TestVoter voter;

    function deployBaseCoins() public {
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e27;
        amounts[1] = 1e27;
        amounts[2] = 1e27;
        mintFlow(owners, amounts);
        mintLR(owners, amounts);
        mintStake(owners, amounts);
        escrow = new TestVotingEscrow(address(flowDaiPair),address(FLOW));
        voter = new TestVoter();
    }

    function createLock() public {
        deployBaseCoins();

        FLOW.approve(address(escrow), TOKEN_1);
        escrow.create_lock(TOKEN_1, FIFTY_TWO_WEEKS);
    }

    function createLock2() public {
        createLock();

        owner2.approve(address(FLOW), address(escrow), TOKEN_1);
        owner2.create_lock(address(escrow), TOKEN_1, FIFTY_TWO_WEEKS);
    }

    function createLock3() public {
        createLock2();

        owner3.approve(address(FLOW), address(escrow), TOKEN_1);
        owner3.create_lock(address(escrow), TOKEN_1, FIFTY_TWO_WEEKS);
    }

    function deployFactory(bool oFlowSet) public {
        createLock3();

        gaugeFactory = new GaugeFactoryV4();
        deployOptionTokenV3WithOwner(address(owner), address(gaugeFactory), address(voter), address(escrow));
        if (oFlowSet) {
            gaugeFactory.setOFlow(address(oFlowV3));
        }
        address[] memory allowedRewards = new address[](1);
        vm.prank(address(voter));
        gaugeFactory.createGauge(address(stake), address(owner), address(escrow), false, allowedRewards);
        address gaugeAddr = gaugeFactory.last_gauge();
        gauge = GaugeV4(gaugeAddr);

        staking = new TestStakingRewards(address(stake), address(FLOW));
    }

    function depositEmpty(bool oFlowSet) public {
        deployFactory(oFlowSet);

        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);

        assertEq(gauge.earned(address(FLOW), address(owner)), staking.earned(address(owner)));
    }

    function depositEmpty2(bool oFlowSet) public {
        depositEmpty(oFlowSet);

        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);

        assertEq(gauge.earned(address(FLOW), address(owner2)), staking.earned(address(owner2)));
    }

    function depositEmpty3(bool oFlowSet) public {
        depositEmpty2(oFlowSet);

        owner3.approve(address(stake), address(staking), 1e21);
        owner3.approve(address(stake), address(gauge), 1e21);
        owner3.stakeStake(address(staking), 1e21);
        owner3.deposit(address(gauge), 1e21, 3);

        assertEq(gauge.earned(address(FLOW), address(owner3)), staking.earned(address(owner3)));
    }

    function notifyRewardsAndCompare(bool oFlowSet) public {
        depositEmpty3(oFlowSet);

        FLOW.approve(address(staking), TOKEN_1M);
        FLOW.approve(address(gauge), TOKEN_1M);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        staking.notifyRewardAmount(TOKEN_1M);
        gauge.notifyRewardAmount(address(FLOW), TOKEN_1M);
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        FLOW.approve(address(staking), TOKEN_1M);
        FLOW.approve(address(gauge), TOKEN_1M);
        staking.notifyRewardAmount(TOKEN_1M);
        gauge.notifyRewardAmount(address(FLOW), TOKEN_1M);
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
    }

    function notifyReward2AndCompare(bool oFlowSet) public {
        notifyRewardsAndCompare(oFlowSet);

        LR.approve(address(gauge), TOKEN_1M);
        gauge.notifyRewardAmount(address(LR), TOKEN_1M);
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
        LR.approve(address(gauge), TOKEN_1M);
        gauge.notifyRewardAmount(address(LR), TOKEN_1M);
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
    }

    function notifyRewardsAndCompareOwner1(bool oFlowSet) public {
        notifyReward2AndCompare(oFlowSet);
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        vm.warp(block.timestamp + 604800);
        vm.roll(block.number + 1);
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
    }

    function notifyRewardsAndCompareOwner2(bool oFlowSet) public {
        notifyRewardsAndCompareOwner1(oFlowSet);

        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
    }

    function notifyRewardsAndCompareOwner3(bool oFlowSet) public {
        notifyRewardsAndCompareOwner2(oFlowSet);

        owner3.withdrawStake(address(staking), 1e21);
        owner3.withdrawGauge(address(gauge), 1e21);
        owner3.approve(address(stake), address(staking), 1e21);
        owner3.approve(address(stake), address(gauge), 1e21);
        owner3.stakeStake(address(staking), 1e21);
        owner3.deposit(address(gauge), 1e21, 3);
        owner3.withdrawStake(address(staking), 1e21);
        owner3.withdrawGauge(address(gauge), 1e21);
        owner3.approve(address(stake), address(staking), 1e21);
        owner3.approve(address(stake), address(gauge), 1e21);
        owner3.stakeStake(address(staking), 1e21);
        owner3.deposit(address(gauge), 1e21, 3);
        owner3.withdrawStake(address(staking), 1e21);
        owner3.withdrawGauge(address(gauge), 1e21);
        owner3.approve(address(stake), address(staking), 1e21);
        owner3.approve(address(stake), address(gauge), 1e21);
        owner3.stakeStake(address(staking), 1e21);
        owner3.deposit(address(gauge), 1e21, 3);
        owner3.withdrawStake(address(staking), 1e21);
        owner3.withdrawGauge(address(gauge), 1e21);
        owner3.approve(address(stake), address(staking), 1e21);
        owner3.approve(address(stake), address(gauge), 1e21);
        owner3.stakeStake(address(staking), 1e21);
        owner3.deposit(address(gauge), 1e21, 3);
        owner3.withdrawStake(address(staking), 1e21);
        owner3.withdrawGauge(address(gauge), 1e21);
        owner3.approve(address(stake), address(staking), 1e21);
        owner3.approve(address(stake), address(gauge), 1e21);
        owner3.stakeStake(address(staking), 1e21);
        owner3.deposit(address(gauge), 1e21, 3);
        owner3.withdrawStake(address(staking), 1e21);
        owner3.withdrawGauge(address(gauge), 1e21);
        owner3.approve(address(stake), address(staking), 1e21);
        owner3.approve(address(stake), address(gauge), 1e21);
        owner3.stakeStake(address(staking), 1e21);
        owner3.deposit(address(gauge), 1e21, 3);
    }

    function depositAndWithdrawWithoutRewards(bool oFlowSet) public {
        notifyRewardsAndCompareOwner3(oFlowSet);

        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        vm.warp(block.timestamp + 604800);
        vm.roll(block.number + 1);
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
    }

    function notifyRewardsAndCompareSet2(bool oFlowSet) public {
        depositAndWithdrawWithoutRewards(oFlowSet);

        FLOW.approve(address(staking), TOKEN_1M);
        FLOW.approve(address(gauge), TOKEN_1M);
        staking.notifyRewardAmount(TOKEN_1M);
        gauge.notifyRewardAmount(address(FLOW), TOKEN_1M);
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        FLOW.approve(address(staking), TOKEN_1M);
        FLOW.approve(address(gauge), TOKEN_1M);
        staking.notifyRewardAmount(TOKEN_1M);
        gauge.notifyRewardAmount(address(FLOW), TOKEN_1M);
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        assertEq(gauge.derivedSupply(), staking.totalSupply());
    }

    function notifyReward2AndCompareSet2(bool oFlowSet) public {
        notifyRewardsAndCompareSet2(oFlowSet);

        LR.approve(address(gauge), TOKEN_1M);
        gauge.notifyRewardAmount(address(LR), TOKEN_1M);
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
        LR.approve(address(gauge), TOKEN_1M);
        gauge.notifyRewardAmount(address(LR), TOKEN_1M);
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
    }

    function notifyRewardsAndCompareOwner1Again(bool oFlowSet) public {
        notifyReward2AndCompareSet2(oFlowSet);

        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        // uint256 sb = FLOW.balanceOf(address(owner));
        staking.getReward();
        // uint256 sa = FLOW.balanceOf(address(owner));
        // uint256 gb = FLOW.balanceOf(address(owner));
        address[] memory tokens = new address[](1);
        tokens[0] = address(FLOW);
        gauge.getReward(address(owner), tokens);
        // uint256 ga = FLOW.balanceOf(address(owner));
        vm.warp(block.timestamp + 604800);
        vm.roll(block.number + 1);
        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        assertGt(staking.rewardPerTokenStored(), 1330355346300364281191);
    }

    function notifyRewardsAndCompareOwner2Again(bool oFlowSet) public {
        notifyRewardsAndCompareOwner1Again(oFlowSet);

        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        owner2.getStakeReward(address(staking));
        address[] memory tokens = new address[](1);
        tokens[0] = address(FLOW);
        owner2.getGaugeReward(address(gauge), address(owner2), tokens);
        vm.warp(block.timestamp + 604800);
        vm.roll(block.number + 1);
        owner2.withdrawStake(address(staking), 1e21);
        owner2.withdrawGauge(address(gauge), 1e21);
        owner2.approve(address(stake), address(staking), 1e21);
        owner2.approve(address(stake), address(gauge), 1e21);
        owner2.stakeStake(address(staking), 1e21);
        owner2.deposit(address(gauge), 1e21, 2);
        assertEq(staking.rewardPerTokenStored(), gauge.rewardPerTokenStored(address(FLOW)));
        assertGt(staking.rewardPerTokenStored(), 1330355346300364281191);
    }

    function testClaimReward2Owner1() public {
        notifyRewardsAndCompareOwner2Again(true);

        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(LR), 200);
        uint256 assertEqed1 = gauge.earned(address(LR), address(owner));

        uint256 before = LR.balanceOf(address(owner));

        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);
        gauge.getReward(address(owner), rewards);
        uint256 after_ = LR.balanceOf(address(owner));

        assertEq(after_ - before, assertEqed1);
        assertGt(assertEqed1, 0);
    }

    function testClaimOFlowReward2Owner1() public {
        notifyRewardsAndCompareOwner2Again(true);

        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        uint256 assertEqed1 = gauge.earned(address(FLOW), address(owner));

        uint256 before = oFlowV3.balanceOf(address(owner));

        address[] memory rewards = new address[](1);
        rewards[0] = address(FLOW);
        gauge.getReward(address(owner), rewards);
        uint256 after_ = oFlowV3.balanceOf(address(owner));

        assertEq(after_ - before, assertEqed1);
        assertGt(assertEqed1, 0);
    }

    function testClaimReward2Owner1WithOFlowNotSet() public {
        notifyRewardsAndCompareOwner2Again(false);

        staking.withdraw(1e21);
        gauge.withdraw(1e21);
        stake.approve(address(staking), 1e21);
        stake.approve(address(gauge), 1e21);
        staking.stake(1e21);
        gauge.deposit(1e21, 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        uint256 assertEqed1 = gauge.earned(address(FLOW), address(owner));

        uint256 before = FLOW.balanceOf(address(owner));

        address[] memory rewards = new address[](1);
        rewards[0] = address(FLOW);
        gauge.getReward(address(owner), rewards);
        uint256 after_ = FLOW.balanceOf(address(owner));

        assertEq(after_ - before, assertEqed1);
        assertGt(assertEqed1, 0);
    }

    function testUpdateOFlowForGauge() public {
        deployFactory(true);

        gaugeFactory.setOFlow(address(0x01));
        gaugeFactory.updateOFlowFor(address(gauge));
        assertEq(gauge.oFlow(), address(0x01));
    }

    function testNonGaugeFactoryOwnerCannotUpdateOFlowForGauge() public {
        deployFactory(true);

        vm.startPrank(address(0x02));
        vm.expectRevert("Ownable: caller is not the owner");
        gaugeFactory.setOFlow(address(0x01));

        vm.expectRevert("Ownable: caller is not the owner");
        gaugeFactory.updateOFlowFor(address(gauge));
        vm.stopPrank();
    }

    function testNonGaugeFactoryCannotUpdateOFlow() public {
        deployFactory(true);

        vm.expectRevert("not gauge factory");
        gauge.setOFlow(address(0x01));
    }
}
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "solmate/tokens/WETH.sol";
import "contracts/Flow.sol";
import "contracts/factories/PairFactory.sol";
import "contracts/factories/GaugeFactoryV4.sol";
import "contracts/factories/ProxyGaugeFactory.sol";
import "contracts/factories/BribeFactory.sol";
import "contracts/Pair.sol";
import "contracts/Router.sol";
import "contracts/Voter.sol";
import "contracts/VotingEscrow.sol";
import "contracts/Minter.sol";
import "contracts/RewardsDistributorV2.sol";

contract LoseRewardsOnMergeTest is Test {
    address DEPLOYER = address(uint160(uint(keccak256("DEPLOYER"))));
    address ALICE = address(uint160(uint(keccak256("ALICE"))));
    address BOB = address(uint160(uint(keccak256("BOB"))));

    WETH weth;
    Flow flow;

    VotingEscrow votingEscrow;
    Voter voter;
    Router router;
    RewardsDistributorV2 rewardsDistributorWETH;
    RewardsDistributorV2 rewardsDistributorFlow;

    Pair flowWethPair;

    function setUp() public {
        vm.deal(DEPLOYER, 100 ether);
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);

        weth = new WETH();

        vm.startPrank(DEPLOYER);

        flow = new Flow(DEPLOYER, 1e21);

        PairFactory pairFactory = new PairFactory();
        GaugeFactoryV4 gaugeFactory = new GaugeFactoryV4();
        ProxyGaugeFactory proxyFactory = new ProxyGaugeFactory(address(flow));
        router = new Router(address(pairFactory), address(weth));

        _addLiquidityFlowWeth(2e18, DEPLOYER);

        flowWethPair = Pair(
            pairFactory.getPair(address(flow), address(weth), false)
        );

        votingEscrow = new VotingEscrow(
            address(flow),
            address(flowWethPair),
            address(0),
            DEPLOYER
        );

        voter = new Voter(
            address(votingEscrow),
            address(pairFactory),
            address(gaugeFactory),
            address(new BribeFactory()),
            address(0)
        );

        votingEscrow.setVoter(address(voter));

        voter.addFactory(address(pairFactory), address(proxyFactory));

        rewardsDistributorWETH = new RewardsDistributorV2(
            address(votingEscrow),
            address(weth)
        );

        rewardsDistributorFlow = new RewardsDistributorV2(
            address(votingEscrow),
            address(flow)
        );

        Minter minter = new Minter(
            address(voter),
            address(votingEscrow),
            address(rewardsDistributorFlow)
        );
        minter.addRewardsDistributor(address(rewardsDistributorWETH));

        rewardsDistributorWETH.setDepositor(address(minter));
        rewardsDistributorFlow.setDepositor(address(minter));

        minter.startActivePeriod();

        flow.setMinter(address(minter));

        pairFactory.setVoter(address(voter));
        flowWethPair.setVoter();

        address[] memory whitelistedTokens = new address[](2);

        whitelistedTokens[0] = address(flow);
        whitelistedTokens[1] = address(weth);

        voter.initialize(whitelistedTokens, address(minter));

        proxyFactory.deployGauge(
            address(rewardsDistributorFlow),
            address(flowWethPair),
            "veNFT"
        );

        voter.createGauge(address(flowWethPair), 1);

        // we need some votes, otherwise voter.distribute() -> ... -> voter.notifyRewardAmount() will revert due to divison by zero
        address[] memory pools = new address[](1);
        pools[0] = address(flowWethPair);
        uint[] memory weights = new uint[](1);
        weights[0] = 1;
        _createLockMaxDuration(1e18);
        vm.warp(block.timestamp + 1 weeks);
        voter.vote(1, pools, weights);

        weth.deposit{value: 10e18}();

        flow.transfer(ALICE, 1e20);
        flow.transfer(BOB, 1e20);

        vm.stopPrank();
    }

    function _addLiquidityFlowWeth(uint amount, address to) internal {
        flow.approve(address(router), amount);
        router.addLiquidityETH{value: amount}(
            address(flow),
            false,
            amount,
            0,
            0,
            to,
            block.timestamp
        );
    }

    function _createLockMaxDuration(uint amount) internal {
        flowWethPair.approve(address(votingEscrow), amount);
        votingEscrow.create_lock(amount, 52 weeks);
    }

    function testLoseRewardsOnMerge() public {
        // Alice and Bob both create 2 tokens with the same amounts and lock duration.
        vm.startPrank(ALICE);
        _addLiquidityFlowWeth(1e18, ALICE);
        _createLockMaxDuration(5e17);
        _createLockMaxDuration(5e17);
        vm.stopPrank();

        vm.startPrank(BOB);
        _addLiquidityFlowWeth(1e18, BOB);
        _createLockMaxDuration(5e17);
        _createLockMaxDuration(5e17);
        vm.stopPrank();

        // Alice owns tokens 2 and 3
        assertEq(votingEscrow.ownerOf(2), ALICE);
        assertEq(votingEscrow.ownerOf(3), ALICE);
        // Bob owns tokens 4 and 5.
        assertEq(votingEscrow.ownerOf(4), BOB);
        assertEq(votingEscrow.ownerOf(5), BOB);
        // All 4 tokens have the same balance.
        assertEq(votingEscrow.balanceOfNFT(2), votingEscrow.balanceOfNFT(3));
        assertEq(votingEscrow.balanceOfNFT(3), votingEscrow.balanceOfNFT(4));
        assertEq(votingEscrow.balanceOfNFT(4), votingEscrow.balanceOfNFT(5));

        vm.warp(block.timestamp + 1 weeks);
        voter.distribute();

        vm.startPrank(DEPLOYER);
        flow.approve(address(rewardsDistributorFlow), 1e18);
        // simulate rewards from emissions
        rewardsDistributorFlow.notifyRewardAmount(1e18);
        weth.approve(address(rewardsDistributorWETH), 1e18);
        // simulate rewards from oFlow exercise revenue
        rewardsDistributorWETH.notifyRewardAmount(1e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);
        voter.distribute();

        uint aliceWethBefore = weth.balanceOf(ALICE);
        uint aliceFlowBefore = flow.balanceOf(ALICE);
        uint bobWethBefore = weth.balanceOf(BOB);
        uint bobFlowBefore = flow.balanceOf(BOB);

        vm.startPrank(ALICE);
        rewardsDistributorWETH.claim(2);
        rewardsDistributorFlow.claim(2);
        rewardsDistributorWETH.claim(3);
        rewardsDistributorFlow.claim(3);
        vm.stopPrank();

        vm.startPrank(BOB);
        // Bob merges token 4 into token 5 and can not claim rewards on token 4
        votingEscrow.merge(4, 5);
        rewardsDistributorWETH.claim(4);
        rewardsDistributorFlow.claim(4);
        rewardsDistributorWETH.claim(5);
        rewardsDistributorFlow.claim(5);
        vm.stopPrank();

        uint aliceWethAfter = weth.balanceOf(ALICE);
        uint aliceWethGained = aliceWethAfter - aliceWethBefore;
        uint aliceFlowAfter = flow.balanceOf(ALICE);
        uint aliceFlowGained = aliceFlowAfter - aliceFlowBefore;
        uint bobWethAfter = weth.balanceOf(BOB);
        uint bobWethGained = bobWethAfter - bobWethBefore;
        uint bobFlowAfter = flow.balanceOf(BOB);
        uint bobFlowGained = bobFlowAfter - bobFlowBefore;

        // Bob receives only half the rewards of Alice, as
        // the rewards from the token that was merged are lost
        assertEq(aliceWethGained, bobWethGained);
        assertEq(aliceFlowGained, bobFlowGained);
    }
}
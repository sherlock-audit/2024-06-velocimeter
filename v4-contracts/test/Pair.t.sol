// 1:1 with Hardhat test
pragma solidity 0.8.13;

import './BaseTest.sol';

contract PairTest is BaseTest {
    VotingEscrow escrow;
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;
    RewardsDistributor distributor;
    Minter minter;
    TestStakingRewards staking;
    Gauge gauge;
    Gauge gauge2;
    Gauge gauge3;
    ExternalBribe xbribe;

    function deployPairCoins() public {
        vm.warp(block.timestamp + 1 weeks); // put some initial time in

        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2e25;
        amounts[1] = 1e25;
        amounts[2] = 1e25;
        mintFlow(owners, amounts);
        mintLR(owners, amounts);

        VeArtProxy artProxy = new VeArtProxy();
        deployPairFactoryAndRouter();
        deployMainPairWithOwner(address(owner));
        escrow = new VotingEscrow(address(FLOW),address(flowDaiPair), address(artProxy), owners[0]);
        assertEq(flowDaiPair.balanceOf(address(escrow)), 0);
    }

    function createLock() public {
        deployPairCoins();

        flowDaiPair.approve(address(escrow), 1e18);
        console2.log("lock1");
        escrow.create_lock(1e18, FIFTY_TWO_WEEKS);
        vm.roll(block.number + 1); // fwd 1 block because escrow.balanceOfNFT() returns 0 in same block
        assertGt(escrow.balanceOfNFT(1), 495063075414519385);
        assertEq(flowDaiPair.balanceOf(address(escrow)), 1e18);
    }

    function increaseLock() public {
        createLock();

        flowDaiPair.approve(address(escrow), 1e18);
        escrow.increase_amount(1, 1e18);
        vm.expectRevert(abi.encodePacked('Can only increase lock duration'));
        escrow.increase_unlock_time(1, FIFTY_TWO_WEEKS);
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(flowDaiPair.balanceOf(address(escrow)), 2*TOKEN_1);
    }

    function votingEscrowViews() public {
        increaseLock();

        uint256 block_ = escrow.block_number();
        assertEq(escrow.balanceOfAtNFT(1, block_), escrow.balanceOfNFT(1));
        assertEq(escrow.totalSupplyAt(block_), escrow.totalSupply());

        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(flowDaiPair.balanceOf(address(escrow)), 2*TOKEN_1);
    }

    function stealNFT() public {
        votingEscrowViews();

        vm.expectRevert(abi.encodePacked(''));
        owner2.transferFrom(address(escrow), address(owner), address(owner2), 1);
        vm.expectRevert(abi.encodePacked(''));
        owner2.approveEscrow(address(escrow), address(owner2), 1);
        vm.expectRevert(abi.encodePacked(''));
        owner2.merge(address(escrow), 1, 2);
    }

    function votingEscrowMerge() public {
        stealNFT();

        flowDaiPair.approve(address(escrow), TOKEN_1);
        console2.log("lock2");
        escrow.create_lock(TOKEN_1, FIFTY_TWO_WEEKS);
        assertGt(escrow.balanceOfNFT(2), 995063075414519385);
        assertEq(flowDaiPair.balanceOf(address(escrow)), 3 * TOKEN_1);
        console2.log(escrow.totalSupply());
        escrow.merge(2, 1);
        console2.log(escrow.totalSupply());
        assertGt(escrow.balanceOfNFT(1), 1990063075414519385);
        assertEq(escrow.balanceOfNFT(2), 0);
        (int256 id, uint256 amount) = escrow.locked(2);
        assertEq(amount, 0);
        assertEq(escrow.ownerOf(2), address(0));
        flowDaiPair.approve(address(escrow), TOKEN_1);
        console2.log("lock3");
        escrow.create_lock(TOKEN_1, FIFTY_TWO_WEEKS);
        assertGt(escrow.balanceOfNFT(3), 995063075414519385);
        assertEq(flowDaiPair.balanceOf(address(escrow)), 4 * TOKEN_1);
        console2.log(escrow.totalSupply());
        escrow.merge(3, 1);
        console2.log(escrow.totalSupply());
        assertGt(escrow.balanceOfNFT(1), 1990063075414519385);
        assertEq(escrow.balanceOfNFT(3), 0);
        (id, amount) = escrow.locked(3);
        assertEq(amount, 0);
        assertEq(escrow.ownerOf(3), address(0));
    }

    function confirmUsdcDeployment() public {
        votingEscrowMerge();

        assertEq(USDC.name(), "USDC");
    }

    function confirmFraxDeployment() public {
        confirmUsdcDeployment();

        assertEq(FRAX.name(), "FRAX");
    }

    function confirmTokensForFraxUsdc() public {
        confirmFraxDeployment();
        deployPairFactoryAndRouter();
        deployVoter();
        deployPairWithOwner(address(owner));
        deployPairWithOwner(address(owner2));
        deployOptionTokenWithOwner(address(owner), address(gaugeFactory));
        gaugeFactory.setOFlow(address(oFlow));

        (address token0, address token1) = router.sortTokens(address(USDC), address(FRAX));
        assertEq(pair.token0(), token0);
        assertEq(pair.token1(), token1);
    }

    function createPairWithNonGovernor() public {
        confirmTokensForFraxUsdc();

        TestOwner(payable(address(owner2))).approve(address(USDC), address(router), USDC_1);
        TestOwner(payable(address(owner2))).approve(address(DAI), address(router), TOKEN_1);
        vm.expectRevert("not governor");
        TestOwner(payable(address(owner2))).addLiquidity(payable(address(router)), address(USDC), address(DAI), true, TOKEN_1, TOKEN_1, 0, 0, address(owner), block.timestamp);
    }

    function mintAndBurnTokensForPairFraxUsdc() public {
        createPairWithNonGovernor();

        USDC.transfer(address(pair), USDC_1);
        FRAX.transfer(address(pair), TOKEN_1);
        pair.mint(address(owner));
        assertEq(pair.getAmountOut(USDC_1, address(USDC)), 982117769725505988);
        (uint256 amount, bool stable) = router.getAmountOut(USDC_1, address(USDC), address(FRAX));
        assertEq(pair.getAmountOut(USDC_1, address(USDC)), amount);
        assertTrue(stable);
        assertTrue(router.isPair(address(pair)));
    }

    function mintAndBurnTokensForPairFraxUsdcOwner2() public {
        mintAndBurnTokensForPairFraxUsdc();

        owner2.transfer(address(USDC), address(pair), USDC_1);
        owner2.transfer(address(FRAX), address(pair), TOKEN_1);
        owner2.mint(address(pair), address(owner2));
        assertEq(owner2.getAmountOut(address(pair), USDC_1, address(USDC)), 992220948146798746);
    }

    function routerAddLiquidity() public {
        mintAndBurnTokensForPairFraxUsdcOwner2();

        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.addLiquidity(address(FRAX), address(USDC), true, TOKEN_100K, USDC_100K, TOKEN_100K, USDC_100K, address(owner), block.timestamp);
        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.addLiquidity(address(FRAX), address(USDC), false, TOKEN_100K, USDC_100K, TOKEN_100K, USDC_100K, address(owner), block.timestamp);
        DAI.approve(address(router), TOKEN_100M);
        FRAX.approve(address(router), TOKEN_100M);
        router.addLiquidity(address(FRAX), address(DAI), true, TOKEN_100M, TOKEN_100M, 0, 0, address(owner), block.timestamp);
    }

    function routerRemoveLiquidity() public {
        routerAddLiquidity();

        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.quoteAddLiquidity(address(FRAX), address(USDC), true, TOKEN_100K, USDC_100K);
        router.quoteRemoveLiquidity(address(FRAX), address(USDC), true, USDC_100K);
    }

    function routerAddLiquidityOwner2() public {
        routerRemoveLiquidity();

        owner2.approve(address(USDC), address(router), USDC_100K);
        owner2.approve(address(FRAX), address(router), TOKEN_100K);
        owner2.addLiquidity(payable(address(router)), address(FRAX), address(USDC), true, TOKEN_100K, USDC_100K, TOKEN_100K, USDC_100K, address(owner2), block.timestamp);
        owner2.approve(address(USDC), address(router), USDC_100K);
        owner2.approve(address(FRAX), address(router), TOKEN_100K);
        owner2.addLiquidity(payable(address(router)), address(FRAX), address(USDC), false, TOKEN_100K, USDC_100K, TOKEN_100K, USDC_100K, address(owner2), block.timestamp);
        owner2.approve(address(DAI), address(router), TOKEN_100M);
        owner2.approve(address(FRAX), address(router), TOKEN_100M);
        owner2.addLiquidity(payable(address(router)), address(FRAX), address(DAI), true, TOKEN_100M, TOKEN_100M, 0, 0, address(owner2), block.timestamp);
    }

    function routerPair1GetAmountsOutAndSwapExactTokensForTokens() public {
        routerAddLiquidityOwner2();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), true);

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pair.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory assertedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, assertedOutput[1], routes, address(owner), block.timestamp);
        vm.warp(block.timestamp + 1801);
        vm.roll(block.number + 1);
    }

    function testRouterPair1GetAmountsOutAndSwapExactTokensForTokensPaused() public {
        routerAddLiquidityOwner2();

        factory.setPause(true);

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), true);

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pair.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory assertedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        vm.expectRevert("isPaused");
        router.swapExactTokensForTokens(USDC_1, assertedOutput[1], routes, address(owner), block.timestamp);
        vm.warp(block.timestamp + 1801);
        vm.roll(block.number + 1);
    }

    function testRouterPair1GetAmountsOutAndSwapExactTokensForTokensPausedPair() public {
        routerAddLiquidityOwner2();

        factory.setPausePair(address(pair),true);

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), true);

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pair.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory assertedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        vm.expectRevert("isPaused");
        router.swapExactTokensForTokens(USDC_1, assertedOutput[1], routes, address(owner), block.timestamp);
        vm.warp(block.timestamp + 1801);
        vm.roll(block.number + 1);
    }

    function routerPair1GetAmountsOutAndSwapExactTokensForTokensOwner2() public {
        routerPair1GetAmountsOutAndSwapExactTokensForTokens();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), true);

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pair.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        owner2.approve(address(USDC), address(router), USDC_1);
        owner2.swapExactTokensForTokens(payable(address(router)), USDC_1, expectedOutput[1], routes, address(owner2), block.timestamp);
    }

    function routerPair2GetAmountsOutAndSwapExactTokensForTokens() public {
        routerPair1GetAmountsOutAndSwapExactTokensForTokensOwner2();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), false);

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pair2.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPair3GetAmountsOutAndSwapExactTokensForTokens() public {
        routerPair2GetAmountsOutAndSwapExactTokensForTokens();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(FRAX), address(DAI), true);

        assertEq(router.getAmountsOut(TOKEN_1M, routes)[1], pair3.getAmountOut(TOKEN_1M, address(FRAX)));

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1M, routes);
        FRAX.approve(address(router), TOKEN_1M);
        router.swapExactTokensForTokens(TOKEN_1M, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function deployVoter() public {
        gaugeFactory = new GaugeFactory();
        bribeFactory = new BribeFactory();
        gaugePlugin = new GaugePlugin(address(FLOW), address(WETH), owners[0]);
        voter = new Voter(address(escrow), address(factory), address(gaugeFactory), address(bribeFactory), address(gaugePlugin));

        escrow.setVoter(address(voter));
        factory.setVoter(address(voter));
        assertEq(voter.length(), 0);
    }

    function deployMinter() public {
        routerAddLiquidity();

        distributor = new RewardsDistributor(address(escrow));

        minter = new Minter(address(voter), address(escrow), address(distributor));
        distributor.setDepositor(address(minter));
        FLOW.setMinter(address(minter));
        address[] memory tokens = new address[](5);
        tokens[0] = address(USDC);
        tokens[1] = address(FRAX);
        tokens[2] = address(DAI);
        tokens[3] = address(FLOW);
        tokens[4] = address(LR);
        voter.initialize(tokens, address(minter));
    }

    function deployPairFactoryGauge() public {
        deployMinter();

        FLOW.approve(address(gaugeFactory), 15 * TOKEN_100K);
        voter.createGauge(address(pair), 0);
        voter.createGauge(address(pair2), 0);
        voter.createGauge(address(pair3), 0);
        assertFalse(voter.gauges(address(pair)) == address(0));

        staking = new TestStakingRewards(address(pair), address(FLOW));

        address gaugeAddress = voter.gauges(address(pair));
        address xBribeAddress = voter.external_bribes(gaugeAddress);

        address gaugeAddress2 = voter.gauges(address(pair2));

        address gaugeAddress3 = voter.gauges(address(pair3));

        gauge = Gauge(gaugeAddress);
        gauge2 = Gauge(gaugeAddress2);
        gauge3 = Gauge(gaugeAddress3);

        xbribe = ExternalBribe(xBribeAddress);

        pair.approve(address(gauge), PAIR_1);
        pair.approve(address(staking), PAIR_1);
        pair2.approve(address(gauge2), PAIR_1);
        pair3.approve(address(gauge3), PAIR_1);
        gauge.deposit(PAIR_1, 0);
        staking.stake(PAIR_1);
        gauge2.deposit(PAIR_1, 0);
        gauge3.deposit(PAIR_1, 0);
        assertEq(gauge.totalSupply(), PAIR_1);
        assertEq(gauge.earned(address(escrow), address(owner)), 0);
    }

    function votingEscrowGaugeManipulate() public {
        deployPairFactoryGauge();

        assertEq(gauge.tokenIds(address(owner)), 0);
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        assertEq(gauge.tokenIds(address(owner)), 1);
        pair.approve(address(gauge), PAIR_1);
        vm.expectRevert(abi.encodePacked(''));
        gauge.deposit(PAIR_1, 2);
        assertEq(gauge.tokenIds(address(owner)), 1);
        vm.expectRevert(abi.encodePacked(''));
        gauge.withdrawToken(0, 2);
        assertEq(gauge.tokenIds(address(owner)), 1);
        gauge.withdrawToken(0, 1);
        assertEq(gauge.tokenIds(address(owner)), 0);
    }

    function deployPairFactoryGaugeOwner2() public {
        votingEscrowGaugeManipulate();

        owner2.approve(address(pair), address(gauge), PAIR_1);
        owner2.approve(address(pair), address(staking), PAIR_1);
        owner2.deposit(address(gauge), PAIR_1, 0);
        owner2.stakeStake(address(staking), PAIR_1);
        assertEq(gauge.totalSupply(), 3 * PAIR_1);
        assertEq(gauge.earned(address(escrow), address(owner2)), 0);
    }

    function withdrawGaugeStake() public {
        deployPairFactoryGaugeOwner2();

        gauge.withdraw(gauge.balanceOf(address(owner)));
        owner2.withdrawGauge(address(gauge), gauge.balanceOf(address(owner2)));
        staking.withdraw(staking._balances(address(owner)));
        owner2.withdrawStake(address(staking), staking._balances(address(owner2)));
        gauge2.withdraw(gauge2.balanceOf(address(owner)));
        gauge3.withdraw(gauge3.balanceOf(address(owner)));
        assertEq(gauge.totalSupply(), 0);
        assertEq(gauge2.totalSupply(), 0);
        assertEq(gauge3.totalSupply(), 0);
    }

    function addGaugeAndBribeRewards() public {
        withdrawGaugeStake();

        FLOW.approve(address(gauge), PAIR_1);
        FLOW.approve(address(xbribe), PAIR_1);
        FLOW.approve(address(staking), PAIR_1);

        gauge.notifyRewardAmount(address(FLOW), PAIR_1);
        xbribe.notifyRewardAmount(address(FLOW), PAIR_1);
        staking.notifyRewardAmount(PAIR_1);

        assertEq(gauge.rewardRate(address(FLOW)), 1653);
        // no reward rate, all or nothing
        // assertEq(xbribe.rewardRate(address(FLOW)), 1653);
        assertEq(staking.rewardRate(), 1653);
    }

    function exitAndGetRewardGaugeStake() public {
        addGaugeAndBribeRewards();

        uint256 supply = pair.balanceOf(address(owner));
        pair.approve(address(gauge), supply);
        gauge.deposit(supply, 1);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        assertEq(gauge.totalSupply(), 0);
        pair.approve(address(gauge), supply);
        gauge.deposit(PAIR_1, 1);
        pair.approve(address(staking), supply);
        staking.stake(PAIR_1);
    }

    function voterReset() public {
        exitAndGetRewardGaugeStake();

        vm.warp(block.timestamp + 1 weeks);

        voter.reset(1);
    }

    function voterPokeSelf() public {
        voterReset();

        voter.poke(1);
    }

    function createLock2() public {
        voterPokeSelf();

        console2.log("lock4");

        flowDaiPair = Pair(escrow.lpToken());
        flowDaiPair.approve(address(escrow), TOKEN_1);
        console2.log(flowDaiPair.balanceOf(address(owner)));
        console2.log(flowDaiPair.balanceOf(address(escrow)));

        vm.warp(block.timestamp + 1);
        escrow.create_lock(TOKEN_1, FIFTY_TWO_WEEKS);
        
        vm.warp(block.timestamp + 1);
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(flowDaiPair.balanceOf(address(escrow)), 5 * TOKEN_1);
    }

    function voteHacking() public {
        createLock2();

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        vm.warp(block.timestamp + 1 weeks);

        voter.vote(1, pools, weights);
        assertEq(voter.usedWeights(1), escrow.balanceOfNFT(1)); // within 1000
        assertEq(xbribe.balanceOf(1), uint256(voter.votes(1, address(pair))));
        vm.warp(block.timestamp + 1 weeks);

        voter.reset(1);
        assertLt(voter.usedWeights(1), escrow.balanceOfNFT(1));
        assertEq(voter.usedWeights(1), 0);
        assertEq(xbribe.balanceOf(1), uint256(voter.votes(1, address(pair))));
        assertEq(xbribe.balanceOf(1), 0);
    }

    function gaugePokeHacking() public {
        voteHacking();

        assertEq(voter.usedWeights(1), 0);
        assertEq(voter.votes(1, address(pair)), 0);
        voter.poke(1);
        assertEq(voter.usedWeights(1), 0);
        assertEq(voter.votes(1, address(pair)), 0);
    }

    function gaugeVoteAndBribeBalanceOf() public {
        gaugePokeHacking();

        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        pools[1] = address(pair2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        vm.warp(block.timestamp + 1 weeks);

        voter.vote(1, pools, weights);
        weights[0] = 50000;
        weights[1] = 50000;

        voter.vote(4, pools, weights);
        console2.log(voter.usedWeights(1));
        console2.log(voter.usedWeights(4));
        assertFalse(voter.totalWeight() == 0);
        assertFalse(xbribe.balanceOf(1) == 0);
    }

    function gaugePokeHacking2() public {
        gaugeVoteAndBribeBalanceOf();

        uint256 weightBefore = voter.usedWeights(1);
        uint256 votesBefore = voter.votes(1, address(pair));
        vm.expectRevert(abi.encodePacked("TOKEN_ALREADY_VOTED_THIS_EPOCH"));
        voter.poke(1);
    }

    function voteHackingBreakMint() public {
        gaugePokeHacking2();

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        vm.warp(block.timestamp + 1 weeks);

        voter.vote(1, pools, weights);

        assertEq(voter.usedWeights(1), escrow.balanceOfNFT(1)); // within 1000
        assertEq(xbribe.balanceOf(1), uint256(voter.votes(1, address(pair))));
    }

    function gaugePokeHacking3() public {
        voteHackingBreakMint();

        vm.expectRevert(abi.encodePacked("TOKEN_ALREADY_VOTED_THIS_EPOCH"));
        voter.poke(1);
    }

    function gaugeDistributeBasedOnVoting() public {
        gaugePokeHacking3();

        FLOW.transfer(address(minter), PAIR_1);
        vm.startPrank(address(minter));
        FLOW.approve(address(voter), PAIR_1);
        voter.notifyRewardAmount(PAIR_1);
        vm.stopPrank();
        voter.updateAll();
        voter.distro();
    }

    function bribeClaimRewards() public {
        gaugeDistributeBasedOnVoting();

        address[] memory rewards = new address[](1);
        rewards[0] = address(FLOW);
        xbribe.getReward(1, rewards);
        vm.warp(block.timestamp + 691200);
        vm.roll(block.number + 1);
        xbribe.getReward(1, rewards);
    }

    function routerPair1GetAmountsOutAndSwapExactTokensForTokens2() public {
        bribeClaimRewards();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), true);

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPair2GetAmountsOutAndSwapExactTokensForTokens2() public {
        routerPair1GetAmountsOutAndSwapExactTokensForTokens2();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), false);

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPair1GetAmountsOutAndSwapExactTokensForTokens2Again() public {
        routerPair2GetAmountsOutAndSwapExactTokensForTokens2();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(FRAX), address(USDC), false);

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1, routes);
        FRAX.approve(address(router), TOKEN_1);
        router.swapExactTokensForTokens(TOKEN_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPair2GetAmountsOutAndSwapExactTokensForTokens2Again() public {
        routerPair1GetAmountsOutAndSwapExactTokensForTokens2Again();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(FRAX), address(USDC), false);

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1, routes);
        FRAX.approve(address(router), TOKEN_1);
        router.swapExactTokensForTokens(TOKEN_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPair1Pair2GetAmountsOutAndSwapExactTokensForTokens() public {
        routerPair2GetAmountsOutAndSwapExactTokensForTokens2Again();

        Router.route[] memory route = new Router.route[](2);
        route[0] = Router.route(address(FRAX), address(USDC), false);
        route[1] = Router.route(address(USDC), address(FRAX), true);

        uint256 before = FRAX.balanceOf(address(owner)) - TOKEN_1;

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1, route);
        FRAX.approve(address(router), TOKEN_1);
        router.swapExactTokensForTokens(TOKEN_1, expectedOutput[2], route, address(owner), block.timestamp);
        uint256 after_ = FRAX.balanceOf(address(owner));
        assertEq(after_ - before, expectedOutput[2]);
    }

    function distributeAndClaimFees() public {
        routerPair1Pair2GetAmountsOutAndSwapExactTokensForTokens();

        vm.warp(block.timestamp + 691200);
        vm.roll(block.number + 1);
        address[] memory rewards = new address[](2);
        rewards[0] = address(FRAX);
        rewards[1] = address(USDC);
        xbribe.getReward(1, rewards);

        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.distribute(gauges[0]);
    }

    function minterMint() public {
        distributeAndClaimFees();

        console2.log(distributor.last_token_time());
        console2.log(distributor.timestamp());

        Minter.Claim[] memory claims = new Minter.Claim[](1);
        claims[0] = Minter.Claim({
            claimant: address(owner),
            amount: TOKEN_1,
            lockTime: FIFTY_TWO_WEEKS
        });
        //minter.initialMintAndLock(claims, TOKEN_1);
        minter.startActivePeriod();

        minter.update_period();
        voter.updateGauge(address(gauge));
        console2.log(FLOW.balanceOf(address(distributor)));
        console2.log(distributor.claimable(1));
        uint256 claimable = voter.claimable(address(gauge));
        FLOW.approve(address(staking), claimable);
        staking.notifyRewardAmount(claimable);
        voter.distro();
        vm.warp(block.timestamp + 1800);
        vm.roll(block.number + 1);
    }

    function gaugeClaimRewards() public {
        minterMint();

        assertEq(address(owner), escrow.ownerOf(1));
        assertTrue(escrow.isApprovedOrOwner(address(owner), 1));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        staking.withdraw(staking._balances(address(owner)));
        vm.warp(block.timestamp + 1);
        pair.approve(address(gauge), PAIR_1);
        vm.warp(block.timestamp + 1);
        gauge.deposit(PAIR_1, 0);
        staking.getReward();
        vm.warp(block.timestamp + 1);
        uint256 before = FLOW.balanceOf(address(owner));
        vm.warp(block.timestamp + 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        vm.warp(block.timestamp + 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        vm.warp(block.timestamp + 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        vm.warp(block.timestamp + 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        vm.warp(block.timestamp + 1);
        gauge.batchRewardPerToken(address(FLOW), 200);
        vm.warp(block.timestamp + 1);
        uint256 earned = gauge.earned(address(FLOW), address(owner));
        address[] memory rewards = new address[](1);
        rewards[0] = address(FLOW);
        vm.warp(block.timestamp + 1);
        gauge.getReward(address(owner), rewards);
        vm.warp(block.timestamp + 1);
        uint256 after_ = FLOW.balanceOf(address(owner));
        uint256 received = after_ - before;

        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 0);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 0);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 0);
        gauge.getReward(address(owner), rewards);
        vm.warp(block.timestamp + 604800);
        vm.roll(block.number + 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
    }

    function gaugeClaimRewardsAfterExpiry() public {
        gaugeClaimRewards();

        address[] memory rewards = new address[](1);
        rewards[0] = address(FLOW);
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 1);
        gauge.getReward(address(owner), rewards);
        vm.warp(block.timestamp + 604800);
        vm.roll(block.number + 1);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
    }

    function votingEscrowDecay() public {
        gaugeClaimRewardsAfterExpiry();

        address[] memory bribes_ = new address[](1);
        bribes_[0] = address(xbribe);
        address[][] memory rewards = new address[][](1);
        address[] memory reward = new address[](1);
        reward[0] = address(DAI);
        rewards[0] = reward;
        voter.claimBribes(bribes_, rewards, 1);
        uint256 supply = escrow.totalSupply();
        assertGt(supply, 0);
        vm.warp(block.timestamp + FIFTY_TWO_WEEKS);
        vm.roll(block.number + 1);
        assertEq(escrow.balanceOfNFT(1), 0);
        assertEq(escrow.totalSupply(), 0);
        vm.warp(block.timestamp + 1 weeks);

        voter.reset(1);
        escrow.withdraw(1);
    }

    function routerAddLiquidityOwner3() public {
        votingEscrowDecay();

        owner3.approve(address(USDC), address(router), 1e12);
        owner3.approve(address(FRAX), address(router), TOKEN_1M);
        owner3.addLiquidity(payable(address(router)), address(FRAX), address(USDC), true, TOKEN_1M, 1e12, 0, 0, address(owner3), block.timestamp);
    }

    function deployPairFactoryGaugeOwner3() public {
        routerAddLiquidityOwner3();

        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1, 0);
    }

    function gaugeClaimRewardsOwner3() public {
        deployPairFactoryGaugeOwner3();

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1, 0);
        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        gauge.batchRewardPerToken(address(FLOW), 200);
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1, 0);
        gauge.batchRewardPerToken(address(FLOW), 200);
        gauge.batchRewardPerToken(address(FLOW), 200);
        gauge.batchRewardPerToken(address(FLOW), 200);
        gauge.batchRewardPerToken(address(FLOW), 200);

        address[] memory rewards = new address[](1);
        rewards[0] = address(FLOW);
        owner3.getGaugeReward(address(gauge), address(owner3), rewards);
        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1, 0);
        owner3.getGaugeReward(address(gauge), address(owner3), rewards);
        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1, 0);
        owner3.getGaugeReward(address(gauge), address(owner3), rewards);
        owner3.getGaugeReward(address(gauge), address(owner3), rewards);
        owner3.getGaugeReward(address(gauge), address(owner3), rewards);
        owner3.getGaugeReward(address(gauge), address(owner3), rewards);

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1, 0);
        owner3.getGaugeReward(address(gauge), address(owner3), rewards);
    }

    function minterMint2() public {
        gaugeClaimRewardsOwner3();

        vm.warp(block.timestamp + ONE_WEEK * 2);
        vm.roll(block.number + 1);
        minter.update_period();
        voter.updateGauge(address(gauge));
        uint256 claimable = voter.claimable(address(gauge));
        FLOW.approve(address(staking), claimable);
        staking.notifyRewardAmount(claimable);
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.updateFor(gauges);
        voter.distro();
        address[][] memory tokens = new address[][](1);
        address[] memory token = new address[](1);
        token[0] = address(FLOW);
        tokens[0] = token;
        voter.claimRewards(gauges, tokens);
        assertEq(gauge.rewardRate(address(FLOW)), staking.rewardRate());
        console2.log(gauge.rewardPerTokenStored(address(FLOW)));
    }

    function gaugeClaimRewardsOwner3NextCycle() public {
        minterMint2();

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        console2.log(gauge.rewardPerTokenStored(address(FLOW)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1, 0);
        uint256 before = oFlow.balanceOf(address(owner3));
        vm.warp(block.timestamp + 1);
        // uint256 earned = gauge.earned(address(FLOW), address(owner3));
        address[] memory rewards = new address[](1);
        rewards[0] = address(FLOW);
        owner3.getGaugeReward(address(gauge), address(owner3), rewards);
        uint256 after_ = oFlow.balanceOf(address(owner3));
        uint256 received = after_ - before;
        assertGt(received, 0);
        console2.log(gauge.rewardPerTokenStored(address(FLOW)));

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner)));
        owner3.approve(address(pair), address(gauge), PAIR_1);
        owner3.deposit(address(gauge), PAIR_1, 0);
        owner3.getGaugeReward(address(gauge), address(owner3), rewards);
    }

    function gaugeClaimRewards2() public {
        gaugeClaimRewardsOwner3NextCycle();

        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 0);
        LR.approve(address(gauge), LR.balanceOf(address(owner)));
        gauge.notifyRewardAmount(address(LR), LR.balanceOf(address(owner)));

        vm.warp(block.timestamp + 604800);
        vm.roll(block.number + 1);
        uint256 reward1 = gauge.earned(address(LR), address(owner));
        uint256 reward3 = gauge.earned(address(LR), address(owner3));
        assertLt(2e25 - (reward1 + reward3), 1e5);
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);
        gauge.getReward(address(owner), rewards);
        owner2.getGaugeReward(address(gauge), address(owner2), rewards);
        owner3.getGaugeReward(address(gauge), address(owner3), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
    }

    function testGaugeClaimRewards3() public {
        gaugeClaimRewards2();

        pair.approve(address(gauge), PAIR_1);
        gauge.deposit(PAIR_1, 0);
        FLOW.approve(address(gauge), FLOW.balanceOf(address(owner)));
        gauge.notifyRewardAmount(address(FLOW), FLOW.balanceOf(address(owner)));

        vm.warp(block.timestamp + 604800);
        vm.roll(block.number + 1);
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);
        gauge.getReward(address(owner), rewards);
        gauge.withdraw(gauge.balanceOf(address(owner)));
    }
}

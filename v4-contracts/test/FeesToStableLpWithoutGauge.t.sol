pragma solidity 0.8.13;

import './BaseTest.sol';

contract FeesToStableLpWithoutGauge is BaseTest {
    VotingEscrow escrow;
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;
    Pair _pair;

    function deploySinglePairWithOwner(address payable _owner) public {
        TestOwner(_owner).approve(address(FRAX), address(router), TOKEN_1);
        TestOwner(_owner).approve(address(USDC), address(router), USDC_1);
        TestOwner(_owner).addLiquidity(payable(address(router)), address(FRAX), address(USDC), true, TOKEN_1, USDC_1, 0, 0, address(owner), block.timestamp);
    }

    function deployPair() public {
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2e25;
        amounts[1] = 1e25;
        amounts[2] = 1e25;
        mintFlow(owners, amounts);
        dealETH(owners, amounts);

        escrow = new VotingEscrow(address(FLOW), address(flowDaiPair), address(0), owners[0]);
        deployPairFactoryAndRouter();
        deployVoter();
        factory.setFee(true, 2); // 2 bps = 0.02%
        deploySinglePairWithOwner(payable(address(owner)));
        deploySinglePairWithOwner(payable(address(owner2)));

        _pair = Pair(factory.getPair(address(USDC), address(FRAX), true));
    }

    function deployVoter() public {
        gaugeFactory = new GaugeFactory();
        bribeFactory = new BribeFactory();

        gaugePlugin = new GaugePlugin(address(FLOW), address(WETH), owners[0]);
        voter = new Voter(
            address(escrow),
            address(factory),
            address(gaugeFactory),
            address(bribeFactory),
            address(gaugePlugin)
        );

        escrow.setVoter(address(voter));
        factory.setVoter(address(voter));
        deployPairWithOwner(address(owner));
        deployOptionTokenWithOwner(address(owner), address(gaugeFactory));
        gaugeFactory.setOFlow(address(oFlow));
    }

    function routerAddLiquidity() public {
        deployPair();

        // add initial liquidity from owner
        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.addLiquidity(address(USDC), address(FRAX), true, USDC_100K, TOKEN_100K, USDC_100K, TOKEN_100K, address(owner), block.timestamp);
    }

    function routerAddLiquidityOwner2() public {
        routerAddLiquidity();

        owner2.approve(address(USDC), address(router), USDC_100K);
        owner2.approve(address(FRAX), address(router), TOKEN_100K);
        owner2.addLiquidity(payable(address(router)), address(USDC), address(FRAX), true, USDC_100K, TOKEN_100K, USDC_100K, TOKEN_100K, address(owner), block.timestamp);
    }

    function testRemoveLiquidityAndEarnSwapFees() public {
        routerAddLiquidityOwner2();

        uint256 initial_frax = FRAX.balanceOf(address(owner2));
        uint256 initial_usdc = USDC.balanceOf(address(owner2));
        uint256 pair_initial_frax = FRAX.balanceOf(address(_pair));
        uint256 pair_initial_usdc = USDC.balanceOf(address(_pair));

        // add liquidity to pool
        vm.startPrank(address(owner2));
        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        (,, uint256 liquidity) = router.addLiquidity(address(USDC), address(FRAX), true, USDC_100K, TOKEN_100K, USDC_100K, TOKEN_100K, address(owner2), block.timestamp);
        vm.stopPrank();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), true);

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_100, routes);
        USDC.approve(address(router), USDC_100);
        router.swapExactTokensForTokens(USDC_100, expectedOutput[1], routes, address(owner), block.timestamp);

        routes = new Router.route[](1);
        routes[0] = Router.route(address(FRAX), address(USDC), true);

        expectedOutput = router.getAmountsOut(TOKEN_100, routes);
        FRAX.approve(address(router), TOKEN_100);
        router.swapExactTokensForTokens(TOKEN_100, expectedOutput[1], routes, address(owner), block.timestamp);

        (uint256 amountUSDC, uint256 amountFRAX) = router.quoteRemoveLiquidity(address(USDC), address(FRAX), true, liquidity);
        // approve transfer of lp tokens
        vm.startPrank(address(owner2));
        Pair(_pair).approve(address(router), liquidity);
        
        router.removeLiquidity(address(USDC), address(FRAX), true, liquidity, amountUSDC, amountFRAX, address(owner2), block.timestamp);
        vm.stopPrank();

        assertGt(FRAX.balanceOf(address(owner2)), initial_frax);
        assertGt(USDC.balanceOf(address(owner2)), initial_usdc);
        assertGt(FRAX.balanceOf(address(_pair)), pair_initial_frax);
        assertGt(USDC.balanceOf(address(_pair)), pair_initial_usdc);
    }
}
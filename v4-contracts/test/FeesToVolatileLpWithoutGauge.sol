pragma solidity 0.8.13;

import './BaseTest.sol';

contract FeesToVolatileLpWithoutGauge is BaseTest {

    Pair _pair;

    function deploySinglePairWithOwner(address payable _owner) public {
        TestOwner(_owner).approve(address(WETH), address(router), TOKEN_1);
        TestOwner(_owner).approve(address(FRAX), address(router), TOKEN_1);
        TestOwner(_owner).addLiquidity(payable(address(router)), address(WETH), address(FRAX), false, TOKEN_1, TOKEN_1, 0, 0, address(owner), block.timestamp);
    }

    function deployPair() public {
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2e25;
        amounts[1] = 1e25;
        amounts[2] = 1e25;
        mintWETH(owners, amounts);
        dealETH(owners, amounts);

        deployPairFactoryAndRouter();
        deploySinglePairWithOwner(payable(address(owner)));
        deploySinglePairWithOwner(payable(address(owner2)));

        _pair = Pair(factory.getPair(address(FRAX), address(WETH), false));
    }

    function routerAddLiquidityETH() public {
        deployPair();

        // add initial liquidity from owner
        FRAX.approve(address(router), TOKEN_100K);
        WETH.approve(address(router), TOKEN_100K);
        router.addLiquidityETH{value: TOKEN_100K}(address(FRAX), false, TOKEN_100K, TOKEN_100K, TOKEN_100K, address(owner), block.timestamp);
    }

    function routerAddLiquidityETHOwner2() public {
        routerAddLiquidityETH();

        owner2.approve(address(FRAX), address(router), TOKEN_100K);
        owner2.approve(address(WETH), address(router), TOKEN_100K);
        owner2.addLiquidityETH{value: TOKEN_100K}(payable(address(router)), address(FRAX), false, TOKEN_100K, TOKEN_100K, TOKEN_100K, address(owner), block.timestamp);
    }

    function testRemoveLiquidityAndEarnSwapFees() public {
        routerAddLiquidityETHOwner2();

        uint256 initial_weth = WETH.balanceOf(address(owner2));
        uint256 initial_frax = FRAX.balanceOf(address(owner2));
        uint256 pair_initial_eth = WETH.balanceOf(address(_pair));
        uint256 pair_initial_frax = FRAX.balanceOf(address(_pair));

        // add liquidity to pool
        vm.startPrank(address(owner2));
        FRAX.approve(address(router), TOKEN_100K);
        WETH.approve(address(router), TOKEN_100K);
        (,, uint256 liquidity) = router.addLiquidity(address(FRAX), address(WETH), false, TOKEN_100K, TOKEN_100K, TOKEN_100K, TOKEN_100K, address(owner2), block.timestamp);
        vm.stopPrank();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(WETH), address(FRAX), false);

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_10, routes);
        uint256[] memory amounts = router.swapExactETHForTokens{value: TOKEN_10}(expectedOutput[1], routes, address(owner), block.timestamp);

        routes = new Router.route[](1);
        routes[0] = Router.route(address(FRAX), address(WETH), false);

        expectedOutput = router.getAmountsOut(TOKEN_10, routes);
        FRAX.approve(address(router), TOKEN_10);
        router.swapExactTokensForETH(TOKEN_10, expectedOutput[1], routes, address(owner), block.timestamp);

        (uint256 amountFRAX, uint256 amountETH) = router.quoteRemoveLiquidity(address(FRAX), address(WETH), false, liquidity);
        // approve transfer of lp tokens
        vm.startPrank(address(owner2));
        Pair(_pair).approve(address(router), liquidity);
        
        router.removeLiquidity(address(FRAX), address(WETH), false, liquidity, amountFRAX, amountETH, address(owner2), block.timestamp);
        vm.stopPrank();

        assertGt(WETH.balanceOf(address(owner2)), initial_weth);
        assertGt(FRAX.balanceOf(address(owner2)), initial_frax);
        assertGt(WETH.balanceOf(address(_pair)), pair_initial_eth);
        assertGt(FRAX.balanceOf(address(_pair)), pair_initial_frax);
    }
}

// 1:1 with Hardhat test
pragma solidity 0.8.13;

import './BaseTest.sol';

contract OracleTest is BaseTest {
    VotingEscrow escrow;
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;

    function deployVoter() public {
        gaugeFactory = new GaugeFactory();
        bribeFactory = new BribeFactory();
        gaugePlugin = new GaugePlugin(address(FLOW), address(WETH), owners[0]);
        voter = new Voter(address(escrow), address(factory), address(gaugeFactory), address(bribeFactory), address(gaugePlugin));

        escrow.setVoter(address(voter));
        factory.setVoter(address(voter));
        assertEq(voter.length(), 0);
    }

    function deployBaseCoins() public {
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e25;
        mintFlow(owners, amounts);
        VeArtProxy artProxy = new VeArtProxy();
        escrow = new VotingEscrow(address(FLOW),address(flowDaiPair), address(artProxy), owners[0]);
    }

    function confirmTokensForFraxUsdc() public {
        deployBaseCoins();
        deployPairFactoryAndRouter();
        deployVoter();
        deployPairWithOwner(address(owner));

        (address token0, address token1) = router.sortTokens(address(USDC), address(FRAX));
        assertEq((pair.token0()), token0);
        assertEq((pair.token1()), token1);
    }

    function mintAndBurnTokensForPairFraxUsdc() public {
        confirmTokensForFraxUsdc();

        USDC.transfer(address(pair), USDC_1);
        FRAX.transfer(address(pair), TOKEN_1);
        pair.mint(address(owner));
        assertEq(pair.getAmountOut(USDC_1, address(USDC)), 945128557522723966);
    }

    function routerAddLiquidity() public {
        mintAndBurnTokensForPairFraxUsdc();

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

    function routerPair1GetAmountsOutAndSwapExactTokensForTokens() public {
        routerAddLiquidity();

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), true);

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pair.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory asserted_output = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, asserted_output[1], routes, address(owner), block.timestamp);
        vm.warp(block.timestamp + 1801);
        vm.roll(block.number + 1);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, 0, routes, address(owner), block.timestamp);
        vm.warp(block.timestamp + 1801);
        vm.roll(block.number + 1);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, 0, routes, address(owner), block.timestamp);
        vm.warp(block.timestamp + 1801);
        vm.roll(block.number + 1);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, 0, routes, address(owner), block.timestamp);
    }

    function testOracle() public {
        routerPair1GetAmountsOutAndSwapExactTokensForTokens();

        assertEq(pair.current(address(USDC), 1e9), 999999494004123828281); // hardhat: 999999494004123828281
        assertEq(pair.current(address(FRAX), 1e21), 999999506); // hardhat: 999999507
        assertEq(pair.quote(address(FRAX), 1e21, 1), 999999506);
    }
}

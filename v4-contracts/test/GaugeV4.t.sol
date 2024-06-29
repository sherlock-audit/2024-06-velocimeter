pragma solidity 0.8.13;

import "./BaseTest.sol";
import "contracts/factories/GaugeFactoryV4.sol";

contract GaugeV4Test is BaseTest {
    VotingEscrow escrow;
    GaugeFactoryV4 gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;
    GaugeV4 gauge;

    function setUp() public {
        deployOwners();
        deployCoins();
        mintStables();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2 * TOKEN_1M; // use 1/2 for veNFT position
        amounts[1] = TOKEN_1M;
        mintFlow(owners, amounts);

        VeArtProxy artProxy = new VeArtProxy();
        escrow = new VotingEscrow(address(FLOW), address(flowDaiPair), address(artProxy), owners[0]);

        deployPairFactoryAndRouter();

        gaugeFactory = new GaugeFactoryV4();
        bribeFactory = new BribeFactory();
        gaugePlugin = new GaugePlugin(address(FLOW), address(WETH), owners[0]);
        voter = new Voter(address(escrow), address(factory), address(gaugeFactory), address(bribeFactory), address(gaugePlugin));
        factory.setVoter(address(voter));

        address[] memory tokens = new address[](4);
        tokens[0] = address(USDC);
        tokens[1] = address(FRAX);
        tokens[2] = address(DAI);
        tokens[3] = address(FLOW);
        voter.initialize(tokens, address(owner));
        escrow.setVoter(address(voter));

        deployOptionTokenV3WithOwner(
            address(owner),
            address(gaugeFactory),
            address(voter),
            address(escrow)
        );

        gaugeFactory.setOFlow(address(oFlowV3));

        deployPairWithOwner(address(owner));
        
        address address1 = factory.getPair(address(FLOW), address(DAI), false);

        pair = Pair(address1);
        address gaugeAddress = voter.createGauge(address(pair), 0);
        gauge = GaugeV4(gaugeAddress);
        
        oFlowV3.setGauge(address(gauge));
        
    }

    function testGaugeDepositFor() public {
        vm.startPrank(address(owner));
        washTrades();
        flowDaiPair.approve(address(gauge),1000);

        uint256 lpBalanceBeforeOwner1 = flowDaiPair.balanceOf(address(owner));
        uint256 lpBalanceBeforeOwner2 = flowDaiPair.balanceOf(address(owner2));
        gauge.depositFor(address(owner2), 1);
        assertEq(gauge.balanceOf(address(owner2)), 1);
        vm.stopPrank();
        vm.warp(block.timestamp + 7 * 86400 + 1);
        vm.startPrank(address(owner2));
        gauge.withdraw(1);
        uint256 lpBalanceAfterOwner1 = flowDaiPair.balanceOf(address(owner));
        uint256 lpBalanceAfterOwner2 = flowDaiPair.balanceOf(address(owner2));
        vm.stopPrank();

        assertEq(gauge.balanceOf(address(owner2)),0);
        assertEq(lpBalanceBeforeOwner1 - lpBalanceAfterOwner1, 1);
        assertEq(lpBalanceAfterOwner2 - lpBalanceBeforeOwner2, 1);
    }

    function washTrades() public {
        FLOW.approve(address(router), TOKEN_100K);
        DAI.approve(address(router), TOKEN_100K);
        router.addLiquidity(
            address(FLOW),
            address(DAI),
            false,
            TOKEN_100K,
            TOKEN_100K,
            0,
            0,
            address(owner),
            block.timestamp
        );

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(FLOW), address(DAI), false);
        Router.route[] memory routes2 = new Router.route[](1);
        routes2[0] = Router.route(address(DAI), address(FLOW), false);

        uint256 i;
        for (i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 1801);
            assertEq(
                router.getAmountsOut(TOKEN_1, routes)[1],
                flowDaiPair.getAmountOut(TOKEN_1, address(FLOW))
            );

            uint256[] memory expectedOutput = router.getAmountsOut(
                TOKEN_1,
                routes
            );
            FLOW.approve(address(router), TOKEN_1);
            router.swapExactTokensForTokens(
                TOKEN_1,
                expectedOutput[1],
                routes,
                address(owner),
                block.timestamp
            );

            assertEq(
                router.getAmountsOut(TOKEN_1, routes2)[1],
                flowDaiPair.getAmountOut(TOKEN_1, address(DAI))
            );

            uint256[] memory expectedOutput2 = router.getAmountsOut(
                TOKEN_1,
                routes2
            );
            DAI.approve(address(router), TOKEN_1);
            router.swapExactTokensForTokens(
                TOKEN_1,
                expectedOutput2[1],
                routes2,
                address(owner),
                block.timestamp
            );
        }
    }
 
}
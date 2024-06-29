pragma solidity 0.8.13;

import "./BaseTest.sol";
import "contracts/GaugeV4.sol";
import "contracts/factories/GaugeFactoryV4.sol";
import "contracts/ExerciseVault.sol";

contract ExerciseVaultTest is BaseTest {
    GaugeFactoryV4 gaugeFactory;
    VotingEscrow escrow;
    Voter voter;
    BribeFactory bribeFactory;
    GaugeV4 gauge;
    ExerciseVault exerciseVault;

    error OptionToken_InvalidDiscount();
    error OptionToken_Paused();
    error OptionToken_NoAdminRole();
    error OptionToken_NoMinterRole();
    error OptionToken_NoPauserRole();
    error OptionToken_IncorrectPairToken();
    error OptionToken_InvalidTwapPoints();
    error OptionToken_SlippageTooHigh();
    error OptionToken_PastDeadline();

    event Exercise(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 paymentAmount
    );
    event ExerciseVe(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 paymentAmount,
        uint256 nftId
    );
    event ExerciseLp(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 paymentAmount,
        uint256 lpAmount
    );
    event SetPairAndPaymentToken(
        IPair indexed newPair,
        address indexed newPaymentToken
    );
    event SetTreasury(address indexed newTreasury,address indexed newVMTreasury);
    event SetDiscount(uint256 discount);
    event SetVeDiscount(uint256 veDiscount);
    event PauseStateChanged(bool isPaused);
    event SetTwapPoints(uint256 twapPoints);

    function setUp() public {
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e27;
        amounts[1] = 1e27;
        amounts[2] = 1e27;
        mintFlow(owners, amounts);

        gaugeFactory = new GaugeFactoryV4();
        bribeFactory = new BribeFactory();
        VeArtProxy artProxy = new VeArtProxy();
        
        escrow = new VotingEscrow(address(FLOW),address(flowDaiPair),address(artProxy), owners[0]);
        
        deployPairFactoryAndRouter();
        gaugePlugin = new GaugePlugin(address(FLOW), address(WETH), owners[0]);
        voter = new Voter(address(escrow), address(factory), address(gaugeFactory), address(bribeFactory), address(gaugePlugin));
        factory.setVoter(address(voter));
        flowDaiPair = Pair(
            factory.createPair(address(FLOW), address(DAI), false)
        );
       
        deployOptionTokenV3WithOwner(
            address(owner),
            address(gaugeFactory),
            address(voter),
            address(escrow)
        );
        gaugeFactory.setOFlow(address(oFlowV3));

        gauge = GaugeV4(voter.createGauge(address(flowDaiPair), 0));
        oFlowV3.updateGauge();
        oFlowV3.setDiscount(80);

        exerciseVault = new ExerciseVault(address(router));
        exerciseVault.addOToken(address(oFlowV3));
        DAI.approve(address(exerciseVault), TOKEN_1 *100);
        exerciseVault.donatePaymentToken(address(DAI), TOKEN_1 *100);
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

    function testExercise() public {

        vm.startPrank(address(owner));

        FLOW.approve(address(oFlowV3), TOKEN_1);
        oFlowV3.mint(address(owner2), TOKEN_1);

        washTrades();

        vm.startPrank(address(owner2));
        
        oFlowV3.approve(address(exerciseVault), TOKEN_1);

        uint256 daiBalanceBefore = DAI.balanceOf(address(exerciseVault));
        uint256 daiBalanceBeforeOwner2 = DAI.balanceOf(address(owner2));

        assertEq(exerciseVault.getAmountOfPaymentTokensAfterExercise(address(oFlowV3),address(FLOW),address(DAI),TOKEN_1),189903102678420429);
        exerciseVault.exercise(address(oFlowV3), TOKEN_1,0);

        vm.stopPrank();
        
        uint256 daiBalanceAfter = DAI.balanceOf(address(exerciseVault));
        uint256 daiBalanceAftereOwner2 = DAI.balanceOf(address(owner2));
        
        assertEq(daiBalanceAfter - daiBalanceBefore,9994900140969496);
        assertEq(daiBalanceAftereOwner2 - daiBalanceBeforeOwner2,189903102678420429);
    }

    function testOnlyOwneCanTakeTokensBack() public {
        vm.startPrank(address(owner2));
        vm.expectRevert();
        exerciseVault.inCaseTokensGetStuck(address(DAI), address(owner2));
        vm.stopPrank();
        
        vm.startPrank(address(owner));
        uint256 daiBalanceBeforeOwner = DAI.balanceOf(address(owner));
        exerciseVault.inCaseTokensGetStuck(address(DAI), address(owner));
        uint256 daiBalanceAftereOwner = DAI.balanceOf(address(owner));
        vm.stopPrank();

        assertEq(daiBalanceAftereOwner - daiBalanceBeforeOwner,100000000000000000000);
    }
}
// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";
import "contracts/GaugeV4.sol";
import "contracts/factories/GaugeFactoryV4.sol";

contract OptionTokenV3Test is BaseTest {
    GaugeFactoryV4 gaugeFactory;
    VotingEscrow escrow;
    Voter voter;
    BribeFactory bribeFactory;
    GaugeV4 gauge;

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
        
        escrow = new VotingEscrow(address(FLOW),address(flowDaiPair), address(artProxy), owners[0]);
        
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
    }

    function testGaugeLock() public {
        vm.startPrank(address(owner));
        washTrades();
        flowDaiPair.approve(address(gauge),1000);

        uint256 lpBalanceBefore = flowDaiPair.balanceOf(address(owner));
        gauge.depositWithLock(address(owner), 1, 7 * 86400);
        vm.warp(block.timestamp + 7 * 86400 + 1);
        gauge.withdraw(1);
        uint256 lpBalanceAfter = flowDaiPair.balanceOf(address(owner));
        vm.stopPrank();

        assertEq(gauge.balanceWithLock(address(owner)),0);
        assertEq(lpBalanceBefore - lpBalanceAfter, 0);
    }

    function testGaugeWithdrawWithLock() public {
        vm.startPrank(address(owner));
        washTrades();
        flowDaiPair.approve(address(gauge),1000);

        uint256 lpBalanceBefore = flowDaiPair.balanceOf(address(owner));
        gauge.depositWithLock(address(owner), 1, 7 * 86400);
        vm.expectRevert("The lock didn't expire");
        gauge.withdraw(1);
        uint256 lpBalanceAfter = flowDaiPair.balanceOf(address(owner));
        vm.stopPrank();

        assertEq(gauge.balanceWithLock(address(owner)),1);
        assertEq(lpBalanceBefore - lpBalanceAfter, 1);
    }

    function testGaugeLockAfterExpire() public {
        vm.startPrank(address(owner));
        washTrades();
        flowDaiPair.approve(address(gauge),1000);

        uint256 lpBalanceBefore = flowDaiPair.balanceOf(address(owner));
        gauge.depositWithLock(address(owner), 1, 7 * 86400);
        vm.warp(block.timestamp + 7 * 86400 + 1);
        gauge.depositWithLock(address(owner), 2, 7 * 86400);
        gauge.withdraw(1);
        uint256 lpBalanceAfter = flowDaiPair.balanceOf(address(owner));
        vm.stopPrank();

        assertEq(gauge.lockEnd(address(owner)),block.timestamp +  7 * 86400);
        assertEq(gauge.balanceWithLock(address(owner)),2);
        assertEq(lpBalanceBefore - lpBalanceAfter, 2);
    }

    function testGaugeLockExtendLock() public {
        vm.startPrank(address(owner));
        washTrades();
        flowDaiPair.approve(address(gauge),1000);

        uint256 lpBalanceBefore = flowDaiPair.balanceOf(address(owner));
        gauge.depositWithLock(address(owner), 1, 14 * 86400);
        vm.warp(block.timestamp + 7 * 86400 + 1);
        gauge.depositWithLock(address(owner), 2, 8 * 86400);
        uint256 lpBalanceAfter = flowDaiPair.balanceOf(address(owner));
        vm.stopPrank();

        assertEq(gauge.lockEnd(address(owner)),block.timestamp +  8 * 86400);
        assertEq(gauge.balanceWithLock(address(owner)),3);
        assertEq(lpBalanceBefore - lpBalanceAfter, 3);
    }

    function testAdminCanSetPairAndPaymentToken() public {
        address flowFraxPair = factory.createPair(
            address(FLOW),
            address(FRAX),
            false
        );
        vm.startPrank(address(owner));
        vm.expectEmit(true, true, false, false);
        emit SetPairAndPaymentToken(IPair(flowFraxPair), address(FRAX));
        oFlowV3.setPairAndPaymentToken(IPair(flowFraxPair), address(FRAX));
        vm.stopPrank();
    }

    function testNonAdminCannotSetPairAndPaymentToken() public {
        address flowFraxPair = factory.createPair(
            address(FLOW),
            address(FRAX),
            false
        );
        vm.startPrank(address(owner2));
        vm.expectRevert(OptionToken_NoAdminRole.selector);
        oFlowV3.setPairAndPaymentToken(IPair(flowFraxPair), address(FRAX));
        vm.stopPrank();
    }

    function testCannotSetIncorrectPairToken() public {
        address daiFraxPair = factory.createPair(
            address(DAI),
            address(FRAX),
            false
        );
        vm.startPrank(address(owner));
        vm.expectRevert(OptionToken_IncorrectPairToken.selector);
        oFlowV3.setPairAndPaymentToken(IPair(daiFraxPair), address(DAI));
        vm.stopPrank();
    }

    function testSetTreasury() public {
        vm.startPrank(address(owner));
        assertEq(oFlowV3.treasury(), address(owner));
        vm.expectEmit(true, false, false, false);
        emit SetTreasury(address(owner2),address(owner2));
        oFlowV3.setTreasury(address(owner2),address(owner2));
        assertEq(oFlowV3.treasury(), address(owner2));
        assertEq(oFlowV3.vmTreasury(), address(owner2));
        vm.stopPrank();
    }

    function testNonAdminCannotSetTreasury() public {
        vm.startPrank(address(owner2));
        vm.expectRevert(OptionToken_NoAdminRole.selector);
        oFlowV3.setTreasury(address(owner2),address(owner2));
        vm.stopPrank();
    }

    function testSetDiscount() public {
        vm.startPrank(address(owner));
        assertEq(oFlowV3.discount(), 99);
        vm.expectEmit(true, false, false, false);
        emit SetDiscount(50);
        oFlowV3.setDiscount(50);
        assertEq(oFlowV3.discount(), 50);
        vm.stopPrank();
    }

     function testSetMinLpLock() public {
        vm.startPrank(address(owner));
        assertEq(oFlowV3.lockDurationForMinLpDiscount(), 7 * 86400);
        oFlowV3.setLockDurationForMinLpDiscount(1 * 86400);
        assertEq(oFlowV3.lockDurationForMinLpDiscount(), 1 * 86400);
        assertEq(oFlowV3.getLockDurationForLpDiscount(oFlowV3.minLPDiscount()),1 * 86400);
        vm.stopPrank();
    }

    function testSetMinLPDiscount() public {
        vm.startPrank(address(owner));
        assertEq(oFlowV3.minLPDiscount(), 80);
        oFlowV3.setMinLPDiscount(70);
        assertEq(oFlowV3.minLPDiscount(), 70);
        vm.stopPrank();
    }

     function testSetMaxLPDiscount() public {
        vm.startPrank(address(owner));
        assertEq(oFlowV3.maxLPDiscount(), 20);
        oFlowV3.setMaxLPDiscount(10);
        assertEq(oFlowV3.maxLPDiscount(), 10);
        vm.stopPrank();
    }

    function testNonAdminCannotSetDiscount() public {
        vm.startPrank(address(owner2));
        vm.expectRevert(OptionToken_NoAdminRole.selector);
        oFlowV3.setDiscount(50);
        vm.stopPrank();
    }

    function testSetVeDiscount() public {
        vm.startPrank(address(owner));
        assertEq(oFlowV3.veDiscount(), 10);
        vm.expectEmit(true, false, false, false);
        emit SetVeDiscount(50);
        oFlowV3.setVeDiscount(50);
        assertEq(oFlowV3.veDiscount(), 50);
        vm.stopPrank();
    }

    function testNonAdminCannotSetVeDiscount() public {
        vm.startPrank(address(owner2));
        vm.expectRevert(OptionToken_NoAdminRole.selector);
        oFlowV3.setVeDiscount(50);
        vm.stopPrank();
    }

    function testCannotSetDiscountOutOfBoundry() public {
        vm.startPrank(address(owner));
        vm.expectRevert(OptionToken_InvalidDiscount.selector);
        oFlowV3.setDiscount(101);
        vm.expectRevert(OptionToken_InvalidDiscount.selector);
        oFlowV3.setDiscount(0);
        vm.stopPrank();
    }

    function testSetTwapPoints() public {
        vm.startPrank(address(owner));
        assertEq(oFlowV3.twapPoints(), 4);
        vm.expectEmit(true, false, false, false);
        emit SetTwapPoints(15);
        oFlowV3.setTwapPoints(15);
        assertEq(oFlowV3.twapPoints(), 15);
        vm.stopPrank();
    }

    function testNonAdminCannotSetTwapPoints() public {
        vm.startPrank(address(owner2));
        vm.expectRevert(OptionToken_NoAdminRole.selector);
        oFlowV3.setTwapPoints(15);
        vm.stopPrank();
    }

    function testCannotSetTwapPointsOutOfBoundry() public {
        vm.startPrank(address(owner));
        vm.expectRevert(OptionToken_InvalidTwapPoints.selector);
        oFlowV3.setTwapPoints(51);
        vm.expectRevert(OptionToken_InvalidTwapPoints.selector);
        oFlowV3.setTwapPoints(0);
        vm.stopPrank();
    }

    function testMintAndBurn() public {
        uint256 flowBalanceBefore = FLOW.balanceOf(address(owner));
        uint256 oFlowV3BalanceBefore = oFlowV3.balanceOf(address(owner));

        vm.startPrank(address(owner));
        FLOW.approve(address(oFlowV3), TOKEN_1);
        oFlowV3.mint(address(owner), TOKEN_1);
        vm.stopPrank();

        uint256 flowBalanceAfter = FLOW.balanceOf(address(owner));
        uint256 oFlowV3BalanceAfter = oFlowV3.balanceOf(address(owner));

        assertEq(flowBalanceBefore - flowBalanceAfter, TOKEN_1);
        assertEq(oFlowV3BalanceAfter - oFlowV3BalanceBefore, TOKEN_1);

        vm.startPrank(address(owner));
        oFlowV3.burn(TOKEN_1);
        vm.stopPrank();

        uint256 flowBalanceAfter_ = FLOW.balanceOf(address(owner));
        uint256 oFlowV3BalanceAfter_ = oFlowV3.balanceOf(address(owner));

        assertEq(flowBalanceAfter_ - flowBalanceAfter, TOKEN_1);
        assertEq(oFlowV3BalanceAfter - oFlowV3BalanceAfter_, TOKEN_1);
    }

    function testNonMinterCannotMint() public {
        vm.startPrank(address(owner2));
        FLOW.approve(address(oFlowV3), TOKEN_1);
        vm.expectRevert(OptionToken_NoMinterRole.selector);
        oFlowV3.mint(address(owner2), TOKEN_1);
        vm.stopPrank();
    }

    function testNonAdminCannotBurn() public {
        vm.startPrank(address(owner));
        FLOW.approve(address(oFlowV3), TOKEN_1);
        oFlowV3.mint(address(owner2), TOKEN_1);
        vm.stopPrank();

        vm.startPrank(address(owner2));
        vm.expectRevert(OptionToken_NoAdminRole.selector);
        oFlowV3.burn(TOKEN_1);
        vm.stopPrank();
    }

    function testPauseAndUnpause() public { 
        vm.startPrank(address(owner));

        FLOW.approve(address(oFlowV3), TOKEN_1);
        oFlowV3.mint(address(owner), TOKEN_1);

        washTrades();

        vm.expectEmit(true, false, false, false);
        emit PauseStateChanged(true);
        oFlowV3.pause();
        vm.expectRevert(OptionToken_Paused.selector);
        oFlowV3.exercise(TOKEN_1, TOKEN_1, address(owner));

        vm.expectEmit(true, false, false, false);
        emit PauseStateChanged(false);
        oFlowV3.unPause();
        DAI.approve(address(oFlowV3), TOKEN_100K);
        oFlowV3.exercise(TOKEN_1, TOKEN_1, address(owner));
        vm.stopPrank();
    }

    function testNonPauserCannotPause() public {
        vm.startPrank(address(owner2));
        vm.expectRevert(OptionToken_NoPauserRole.selector);
        oFlowV3.pause();
        vm.stopPrank();
    }

    function testNonAdminCannotUnpause() public {
        vm.startPrank(address(owner));
        oFlowV3.pause();
        vm.stopPrank();

        vm.startPrank(address(owner2));
        vm.expectRevert(OptionToken_NoAdminRole.selector);
        oFlowV3.unPause();
        vm.stopPrank();
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
        // mint Option token to owner 2
        oFlowV3.mint(address(owner2), TOKEN_1);

        oFlowV3.setTreasury(address(owner),address(owner3));
        washTrades();
        vm.stopPrank();

        uint256 flowBalanceBefore = FLOW.balanceOf(address(owner2));
        uint256 oFlowV3BalanceBefore = oFlowV3.balanceOf(address(owner2));
        uint256 daiBalanceBefore = DAI.balanceOf(address(owner2));
        uint256 treasuryDaiBalanceBefore = DAI.balanceOf(address(owner));
        uint256 treasuryVMDaiBalanceBefore = DAI.balanceOf(address(owner3));
        uint256 rewardGaugeDaiBalanceBefore = DAI.balanceOf(address(gauge));

        uint256 discountedPrice = oFlowV3.getDiscountedPrice(TOKEN_1);

        vm.startPrank(address(owner2));
        DAI.approve(address(oFlowV3), TOKEN_100K);
        vm.expectEmit(true, true, false, true); 
        emit Exercise(
            address(owner2),
            address(owner2),
            TOKEN_1,
            discountedPrice
        );
        oFlowV3.exercise(TOKEN_1, TOKEN_1, address(owner2));
        vm.stopPrank();

        uint256 flowBalanceAfter = FLOW.balanceOf(address(owner2));
        uint256 oFlowV3BalanceAfter = oFlowV3.balanceOf(address(owner2));
        uint256 daiBalanceAfter = DAI.balanceOf(address(owner2));
        uint256 treasuryDaiBalanceAfter = DAI.balanceOf(address(owner));
         uint256 treasuryVMDaiBalanceAfter = DAI.balanceOf(address(owner3));
        uint256 rewardGaugeDaiAfter = DAI.balanceOf(address(gauge));

        assertEq(flowBalanceAfter - flowBalanceBefore, TOKEN_1);
        assertEq(oFlowV3BalanceBefore - oFlowV3BalanceAfter, TOKEN_1);
        assertEq(daiBalanceBefore - daiBalanceAfter, discountedPrice);
        assertEq(
             (rewardGaugeDaiAfter - rewardGaugeDaiBalanceBefore) + (treasuryDaiBalanceAfter - treasuryDaiBalanceBefore) + (treasuryVMDaiBalanceAfter - treasuryVMDaiBalanceBefore),
             discountedPrice
        );
    }

    function testExerciseFewTimes() public {
        vm.startPrank(address(owner));

        uint256 amountOfExercise = 4;
        FLOW.approve(address(oFlowV3), TOKEN_1*amountOfExercise);
        // mint Option token to owner 2
        oFlowV3.mint(address(owner2), TOKEN_1*amountOfExercise);

        washTrades();
        vm.stopPrank();

        uint256 flowBalanceBefore = FLOW.balanceOf(address(owner2));
        uint256 oFlowV3BalanceBefore = oFlowV3.balanceOf(address(owner2));
        uint256 daiBalanceBefore = DAI.balanceOf(address(owner2));
        uint256 treasuryDaiBalanceBefore = DAI.balanceOf(address(owner));
        uint256 rewardGaugeDaiBalanceBefore = DAI.balanceOf(address(gauge));

        uint256 discountedPrice = oFlowV3.getDiscountedPrice(TOKEN_1);

        vm.startPrank(address(owner2));
        DAI.approve(address(oFlowV3), TOKEN_100K);
        vm.expectEmit(true, true, false, true); 
        emit Exercise(
            address(owner2),
            address(owner2),
            TOKEN_1,
            discountedPrice
        );
        oFlowV3.exercise(TOKEN_1, TOKEN_1, address(owner2));
        oFlowV3.exercise(TOKEN_1, TOKEN_1, address(owner2));
        oFlowV3.exercise(TOKEN_1, TOKEN_1, address(owner2));
        oFlowV3.exercise(TOKEN_1, TOKEN_1, address(owner2));

        vm.stopPrank();

        uint256 flowBalanceAfter = FLOW.balanceOf(address(owner2));
        uint256 oFlowV3BalanceAfter = oFlowV3.balanceOf(address(owner2));
        uint256 daiBalanceAfter = DAI.balanceOf(address(owner2));
        uint256 treasuryDaiBalanceAfter = DAI.balanceOf(address(owner));
        uint256 rewardGaugeDaiAfter = DAI.balanceOf(address(gauge));

        assertEq(flowBalanceAfter - flowBalanceBefore, TOKEN_1*amountOfExercise);
        assertEq(oFlowV3BalanceBefore - oFlowV3BalanceAfter, TOKEN_1*amountOfExercise);
        assertEq(daiBalanceBefore - daiBalanceAfter, discountedPrice*amountOfExercise);
        assertEq(
             (rewardGaugeDaiAfter - rewardGaugeDaiBalanceBefore) + (treasuryDaiBalanceAfter - treasuryDaiBalanceBefore),
             discountedPrice*amountOfExercise
        );

    }

    function testCannotExercisePastDeadline() public {
        vm.startPrank(address(owner));
        FLOW.approve(address(oFlowV3), TOKEN_1);
        oFlowV3.mint(address(owner), TOKEN_1);

        DAI.approve(address(oFlowV3), TOKEN_100K);
        vm.expectRevert(OptionToken_PastDeadline.selector);
        oFlowV3.exercise(TOKEN_1, TOKEN_1, address(owner), block.timestamp - 1);
        vm.stopPrank();
    }

    function testCannotExerciseWithSlippageTooHigh() public {
        vm.startPrank(address(owner));
        FLOW.approve(address(oFlowV3), TOKEN_1);
        oFlowV3.mint(address(owner), TOKEN_1);

        washTrades();
        uint256 discountedPrice = oFlowV3.getDiscountedPrice(TOKEN_1);

        DAI.approve(address(oFlowV3), TOKEN_100K);
        vm.expectRevert(OptionToken_SlippageTooHigh.selector);
        oFlowV3.exercise(TOKEN_1, discountedPrice - 1, address(owner));
        vm.stopPrank();
    }

    function testExerciseLp() public { 
        vm.startPrank(address(owner)); 
        FLOW.approve(address(oFlowV3), TOKEN_1);
        // mint Option token to owner 2
        oFlowV3.mint(address(owner2), TOKEN_1);

        washTrades();
        vm.stopPrank();
        uint256 flowBalanceBefore = FLOW.balanceOf(address(owner2));
        uint256 oFlowV3BalanceBefore = oFlowV3.balanceOf(address(owner2));
        uint256 daiBalanceBefore = DAI.balanceOf(address(owner2));
        uint256 treasuryDaiBalanceBefore = DAI.balanceOf(address(owner));
        uint256 rewardGaugeDaiBalanceBefore = DAI.balanceOf(address(gauge));

        (uint256 underlyingReserve, uint256 paymentReserve) = IRouter(router).getReserves(address(FLOW), address(DAI), false);
        uint256 paymentAmountToAddLiquidity = (TOKEN_1 * paymentReserve) /  underlyingReserve;

        uint256 discountedPrice = oFlowV3.getLpDiscountedPrice(TOKEN_1,20);

      
        vm.startPrank(address(owner2));
        DAI.approve(address(oFlowV3), TOKEN_100K);
        vm.expectEmit(true, true, false, true); 
        emit ExerciseLp(
            address(owner2),
            address(owner2),
            TOKEN_1,
            discountedPrice,
            1000000000999700046
        );

  
        oFlowV3.exerciseLp(TOKEN_1, TOKEN_1, address(owner2),20,block.timestamp);
        vm.stopPrank();

        uint256 flowBalanceAfter = FLOW.balanceOf(address(owner2));
        uint256 oFlowV3BalanceAfter = oFlowV3.balanceOf(address(owner2));
        uint256 daiBalanceAfter = DAI.balanceOf(address(owner2));
        uint256 treasuryDaiBalanceAfter = DAI.balanceOf(address(owner));
        uint256 rewardGaugeDaiAfter = DAI.balanceOf(address(gauge));

        assertEq(gauge.lockEnd(address(owner2)),block.timestamp + 52 * 7 * 86400);

        assertEq(flowBalanceAfter - flowBalanceBefore, 0);
        assertEq(oFlowV3BalanceBefore - oFlowV3BalanceAfter, TOKEN_1);
        assertEq(daiBalanceBefore - daiBalanceAfter, discountedPrice + paymentAmountToAddLiquidity);
        assertEq(
             (rewardGaugeDaiAfter - rewardGaugeDaiBalanceBefore) + (treasuryDaiBalanceAfter - treasuryDaiBalanceBefore),
             discountedPrice
        );
    }
}

// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";

contract FeesToBribesTest is BaseTest {
    VotingEscrow escrow;
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;
    ExternalBribe xbribe;

    function setUp() public {
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2e25;
        amounts[1] = 1e25;
        amounts[2] = 1e25;
        mintFlow(owners, amounts);

        VeArtProxy artProxy = new VeArtProxy();
        deployPairFactoryAndRouter();
        deployMainPairWithOwner(address(owner));
        
        escrow = new VotingEscrow(address(FLOW),address(flowDaiPair), address(artProxy), owners[0]);

        deployVoter();
        factory.setFee(true, 2); // 2 bps = 0.02%
        deployPairWithOwner(payable(address(owner)));
        mintPairFraxUsdcWithOwner(payable(address(owner)));
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

    function testNonPairFactoryOwnerCannotChangeFees() public {
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        owner2.setFee(address(factory), true, 2);
    }

    function testPairFactoryOwnerCannotSetFeeAboveMax() public {
        vm.expectRevert(abi.encodePacked("fee too high"));
        factory.setFee(true, 501);
    }

    function testPairFactoryOwnerCanChangeFeesAndClaim() public {
        factory.setFee(true, 3); // 3 bps = 0.03%

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), true);

        assertEq(
            router.getAmountsOut(USDC_1, routes)[1],
            pair.getAmountOut(USDC_1, address(USDC))
        );

        uint256[] memory assertedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(
            USDC_1,
            assertedOutput[1],
            routes,
            address(owner),
            block.timestamp
        );
    }

    function testNonPairFactoryOwnerCannotSetFeesOverrides() public {
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        vm.startPrank(address(owner2));
        factory.setFeesOverrides(address(pair), 21);
        vm.stopPrank();
    }

    function testPairFactoryOwnerCannotSetFeesOverridesAboveMax() public {
        vm.expectRevert(abi.encodePacked("fee too high"));
        factory.setFeesOverrides(address(pair), 501);
    }

    function testPairFactoryOwnerCanSetFeesOverridesAndClaim() public {
        factory.setFeesOverrides(address(pair), 30); // 30 bps = 0.3%

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), true);

        assertEq(
            router.getAmountsOut(USDC_1, routes)[1],
            pair.getAmountOut(USDC_1, address(USDC))
        );

        uint256[] memory assertedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(
            USDC_1,
            assertedOutput[1],
            routes,
            address(owner),
            block.timestamp
        );
    }

    function createLock() public {
        flowDaiPair.approve(address(escrow), 5e17);
        escrow.create_lock(5e17, FIFTY_TWO_WEEKS);
        vm.roll(block.number + 1); // fwd 1 block because escrow.balanceOfNFT() returns 0 in same block
        assertGt(escrow.balanceOfNFT(1), 495063075414519385);
        assertEq(flowDaiPair.balanceOf(address(escrow)), 5e17);
    }

    function testSwapAndClaimFees() public {
        createLock();
        vm.warp(block.timestamp + 1 weeks);

        voter.createGauge(address(pair), 0);
        address gaugeAddress = voter.gauges(address(pair));
        address xBribeAddress = voter.external_bribes(gaugeAddress);
        xbribe = ExternalBribe(xBribeAddress);

        Router.route[] memory routes = new Router.route[](1);
        routes[0] = Router.route(address(USDC), address(FRAX), true);

        assertEq(
            router.getAmountsOut(USDC_1, routes)[1],
            pair.getAmountOut(USDC_1, address(USDC))
        );

        uint256[] memory assertedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(
            USDC_1,
            assertedOutput[1],
            routes,
            address(owner),
            block.timestamp
        );

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        voter.vote(1, pools, weights);

        vm.warp(block.timestamp + 1 weeks);

        assertEq(USDC.balanceOf(address(xbribe)), 200); // 0.01% -> 0.02%
        uint256 b = USDC.balanceOf(address(owner));
        address[] memory rewards = new address[](1);
        rewards[0] = address(USDC);
        xbribe.getReward(1, rewards);
        assertGt(USDC.balanceOf(address(owner)), b);
    }
}

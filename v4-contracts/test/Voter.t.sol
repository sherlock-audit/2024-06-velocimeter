// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";

contract VoterTest is BaseTest {
    VotingEscrow escrow;
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;
    ExternalBribe xbribe;

    event Whitelisted(address indexed whitelister, address indexed token);
    event Blacklisted(address indexed blacklister, address indexed token);
    event WhitelistedForGaugeCreation(address indexed whitelister, address indexed token);
    event BlacklistedForGaugeCreation(address indexed blacklister, address indexed token);
    event BribeFactorySet(address indexed setter, address newBribeFatory);
    event ExternalBribeSet(address indexed setter, address indexed indexed gauge, address externalBribe);
    event FactoryAdded(address indexed setter, address indexed pairFactory, address indexed gaugeFactory);
    event FactoryReplaced(address indexed setter, address indexed pairFactory, address indexed gaugeFactory, uint256 pos);
    event FactoryRemoved(address indexed setter, uint256 indexed pos);

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
        deployPairWithOwner(address(owner));
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

    function testSetup() public {
        assertEq(voter.factories(0), address(factory));
        assertEq(voter.factoryLength(), 1);
        address[] memory factories = new address[](1);
        factories[0] = address(factory);
        assertEq(voter._factories(), factories);
        vm.expectRevert();
        voter.factories(1);
        assertEq(voter.isFactory(address(factory)), true);
        assertEq(voter.isFactory(address(0x01)), false);

        assertEq(voter.gaugeFactories(0), address(gaugeFactory));
        assertEq(voter.gaugeFactoriesLength(), 1);
        address[] memory gaugeFactories = new address[](1);
        gaugeFactories[0] = address(gaugeFactory);
        assertEq(voter._gaugeFactories(), gaugeFactories);
        vm.expectRevert();
        voter.gaugeFactories(1);
        assertEq(voter.isGaugeFactory(address(gaugeFactory)), true);
        assertEq(voter.isGaugeFactory(address(0x01)), false);
    }

    function testEmergencyCouncilCanSetBribeFactory() public {
        address newBribeFactory = address(0x02);
        vm.expectEmit(true, false, false, true);
        emit BribeFactorySet(address(this), newBribeFactory);
        voter.setBribeFactory(newBribeFactory);
        assertEq(voter.bribefactory(), newBribeFactory);
    }

    function testNonEmergencyCouncilCannotSetBribeFactory() public {
        address newBribeFactory = address(0x02);
        vm.startPrank(address(0x03));
        vm.expectRevert("not emergencyCouncil");
        voter.setBribeFactory(newBribeFactory);
        vm.stopPrank();
    }

    function testEmergencyCouncilCanRemoveFactory() public {
        vm.expectEmit(true, true, false, true);
        emit FactoryRemoved(address(this), 0);
        voter.removeFactory(0);
        assertEq(voter.factories(0), address(0));
        assertEq(voter.factoryLength(), 1);
        address[] memory factories = new address[](1);
        assertEq(voter._factories(), factories);
        assertEq(voter.isFactory(address(factory)), false);

        assertEq(voter.gaugeFactories(0), address(0));
        assertEq(voter.gaugeFactoriesLength(), 1);
        address[] memory gaugeFactories = new address[](1);
        assertEq(voter._gaugeFactories(), gaugeFactories);
        assertEq(voter.isGaugeFactory(address(gaugeFactory)), false);
    }

    function testNonEmergencyCouncilCannotRemoveFactory() public {
        vm.startPrank(address(0x03));
        vm.expectRevert("not emergencyCouncil");
        voter.removeFactory(0);
        vm.stopPrank();
    }

    function testCannotRemoveFactoryOutOfRange() public {
        vm.expectRevert("_pos out of range");
        voter.removeFactory(2);
    }

    function testEmergencyCouncilCanAddAndReplcaeFactory() public {
        address newPairFactory = address(0xef);
        address newGaugeFactory = address(0xdf);

        vm.expectEmit(true, true, true, true);
        emit FactoryAdded(address(this), newPairFactory, newGaugeFactory);
        voter.addFactory(newPairFactory, newGaugeFactory);
        assertEq(voter.factories(1), newPairFactory);
        assertEq(voter.factoryLength(), 2);
        address[] memory factories = new address[](2);
        factories[0] = address(factory);
        factories[1] = newPairFactory;
        assertEq(voter._factories(), factories);
        assertEq(voter.isFactory(address(newPairFactory)), true);
        assertEq(voter.isFactory(address(factory)), true);

        assertEq(voter.gaugeFactories(1), newGaugeFactory);
        assertEq(voter.gaugeFactoriesLength(), 2);
        address[] memory gaugeFactories = new address[](2);
        gaugeFactories[0] = address(gaugeFactory);
        gaugeFactories[1] = newGaugeFactory;
        assertEq(voter._gaugeFactories(), gaugeFactories);
        assertEq(voter.isGaugeFactory(address(newGaugeFactory)), true);
        assertEq(voter.isGaugeFactory(address(gaugeFactory)), true);

        vm.expectEmit(true, true, true, true);
        emit FactoryReplaced(address(this), newPairFactory, newGaugeFactory, 0);
        voter.replaceFactory(newPairFactory, newGaugeFactory, 0);
        assertEq(voter.factories(0), newPairFactory);
        assertEq(voter.factoryLength(), 2);
        factories[0] = newPairFactory;
        factories[1] = newPairFactory;
        assertEq(voter._factories(), factories);
        assertEq(voter.isFactory(address(newPairFactory)), true);
        assertEq(voter.isFactory(address(factory)), false);

        assertEq(voter.gaugeFactories(0), newGaugeFactory);
        assertEq(voter.gaugeFactoriesLength(), 2);
        gaugeFactories[0] = newGaugeFactory;
        gaugeFactories[1] = newGaugeFactory;
        assertEq(voter._gaugeFactories(), gaugeFactories);
        assertEq(voter.isGaugeFactory(address(newGaugeFactory)), true);
        assertEq(voter.isGaugeFactory(address(gaugeFactory)), false);
    }

    function testNonEmergencyCouncilCannotAddFactory() public {
        address newPairFactory = address(0xef);
        address newGaugeFactory = address(0xdf);

        vm.startPrank(address(0x03));
        vm.expectRevert("not emergencyCouncil");
        voter.addFactory(newPairFactory, newGaugeFactory);
        vm.stopPrank();
    }

    function testNonEmergencyCouncilCannotReplaceFactory() public {
        address newPairFactory = address(0xef);
        address newGaugeFactory = address(0xdf);

        vm.startPrank(address(0x03));
        vm.expectRevert("not emergencyCouncil");
        voter.replaceFactory(newPairFactory, newGaugeFactory, 0);
        vm.stopPrank();
    }

    function testCannotReplaceFactoryOutOfRange() public {
        address newPairFactory = address(0xef);
        address newGaugeFactory = address(0xdf);

        vm.expectRevert("_pos out of range");
        voter.replaceFactory(newPairFactory, newGaugeFactory, 2);
    }

    function createLock() public {
        flowDaiPair.approve(address(escrow), 5e17);
        escrow.create_lock(5e17, FIFTY_TWO_WEEKS);
        vm.roll(block.number + 1); // fwd 1 block because escrow.balanceOfNFT() returns 0 in same block
        assertGt(escrow.balanceOfNFT(1), 495063075414519385);
        assertEq(flowDaiPair.balanceOf(address(escrow)), 5e17);
    }

    function testCanSetExternalBribeAndClaimFeesFromNewBribe() public {
        createLock();
        vm.warp(block.timestamp + 1 weeks);

        voter.createGauge(address(pair), 0);
        address gaugeAddress = voter.gauges(address(pair));

        address[] memory rewards = new address[](2);
        rewards[0] = address(USDC);
        rewards[1] = address(FRAX);
        ExternalBribe newExternalBribe = new ExternalBribe(
            address(voter),
            rewards
        );
        vm.expectEmit(true, true, false, true);
        emit ExternalBribeSet(address(this), gaugeAddress, address(newExternalBribe));
        voter.setExternalBribeFor(gaugeAddress, address(newExternalBribe));

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

        assertEq(USDC.balanceOf(address(newExternalBribe)), 200); // 0.01% -> 0.02%
        uint256 b = USDC.balanceOf(address(owner));
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        newExternalBribe.getReward(1, tokens);
        assertGt(USDC.balanceOf(address(owner)), b);
    }

    function testNonEmergencyCouncilCannotSetExternalBribe() public {
        createLock();
        vm.warp(block.timestamp + 1 weeks);

        voter.createGauge(address(pair), 0);
        address gaugeAddress = voter.gauges(address(pair));

        address[] memory rewards = new address[](2);
        rewards[0] = address(USDC);
        rewards[1] = address(FRAX);
        ExternalBribe newExternalBribe = new ExternalBribe(
            address(voter),
            rewards
        );

        vm.startPrank(address(0x03));
        vm.expectRevert("not emergencyCouncil");
        voter.setExternalBribeFor(gaugeAddress, address(newExternalBribe));
        vm.stopPrank();
    }

    function testGovernorCanWhitelistTokens() public {
        assertFalse(voter.isWhitelisted(address(USDC)));
        vm.expectEmit(true, true, false, true);
        emit Whitelisted(address(this), address(USDC));
        voter.whitelist(address(USDC));
        assertTrue(voter.isWhitelisted(address(USDC)));
    }

    function testCannotWhitelistTokensAgain() public {
        voter.whitelist(address(USDC));
        vm.expectRevert();
        voter.whitelist(address(USDC));
    }

    function testNonGovernorCannotWhitelistTokens() public {
        vm.startPrank(address(owner2));
        vm.expectRevert();
        voter.whitelist(address(USDC));
        vm.stopPrank();
    }

    function testGovernorCanBlacklistTokens() public {
        voter.whitelist(address(USDC));
        assertTrue(voter.isWhitelisted(address(USDC)));
        vm.expectEmit(true, true, false, true);
        emit Blacklisted(address(this), address(USDC));
        voter.blacklist(address(USDC));
        assertFalse(voter.isWhitelisted(address(USDC)));
    }

    function testNonGovernorCannotBlacklistTokens() public {
        voter.whitelist(address(USDC));
        vm.startPrank(address(owner2));
        vm.expectRevert();
        voter.blacklist(address(USDC));
        vm.stopPrank();
    }

    function testCannotBlacklistTokensAgain() public {
        voter.whitelist(address(USDC));
        voter.blacklist(address(USDC));
        vm.expectRevert();
        voter.blacklist(address(USDC));
    }
}

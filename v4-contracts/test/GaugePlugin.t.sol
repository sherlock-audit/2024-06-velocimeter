pragma solidity 0.8.13;

import "./BaseTest.sol";

contract GaugePluginTest is BaseTest {
    VotingEscrow escrow;
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;
    event WhitelistedForGaugeCreation(
        address indexed whitelister,
        address indexed token
    );
    event BlacklistedForGaugeCreation(
        address indexed blacklister,
        address indexed token
    );

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
        escrow = new VotingEscrow(address(FLOW), address(flowDaiPair), address(artProxy), owners[0]);

        deployPairFactoryAndRouter();
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

        factory.setFee(true, 2); // 2 bps = 0.02%
        deployPairWithOwner(address(owner));
        mintPairFraxUsdcWithOwner(payable(address(owner)));
    }

    function testSetup() public {
      assertTrue(gaugePlugin.governor() == owners[0]);
      assertTrue(gaugePlugin.isWhitelistedForGaugeCreation(address(FLOW)));
      assertTrue(gaugePlugin.isWhitelistedForGaugeCreation(address(WETH)));
    }

    function testOwnerCanSetGovernor() public {
        gaugePlugin.setGovernor(address(0x01));
        assertEq(gaugePlugin.governor(), address(0x01));
    }

    function testNonOwnerCannotSetGovernor() public {
        vm.startPrank(address(owner2));
        vm.expectRevert();
        gaugePlugin.setGovernor(address(0x01));
        vm.stopPrank();
    }

    function testGovernorCanWhitelistTokensForGaugeCreation() public {
        assertFalse(gaugePlugin.isWhitelistedForGaugeCreation(address(USDC)));
        vm.expectEmit(true, true, false, true);
        emit WhitelistedForGaugeCreation(address(this), address(USDC));
        gaugePlugin.whitelistForGaugeCreation(address(USDC));
        assertTrue(gaugePlugin.isWhitelistedForGaugeCreation(address(USDC)));
    }

    function testCannotWhitelistTokensForGaugeCreationAgain() public {
        gaugePlugin.whitelistForGaugeCreation(address(USDC));
        vm.expectRevert();
        gaugePlugin.whitelistForGaugeCreation(address(USDC));
    }

    function testNonGovernorCannotWhitelistTokensForGaugeCreation() public {
        vm.startPrank(address(owner2));
        vm.expectRevert();
        gaugePlugin.whitelistForGaugeCreation(address(USDC));
        vm.stopPrank();
    }

    function testGovernorCanBlacklistTokensForGaugeCreation() public {
        gaugePlugin.whitelistForGaugeCreation(address(USDC));
        assertTrue(gaugePlugin.isWhitelistedForGaugeCreation(address(USDC)));
        vm.expectEmit(true, true, false, true);
        emit BlacklistedForGaugeCreation(address(this), address(USDC));
        gaugePlugin.blacklistForGaugeCreation(address(USDC));
        assertFalse(gaugePlugin.isWhitelistedForGaugeCreation(address(USDC)));
    }

    function testNonGovernorCannotBlacklistTokensForGaugeCreation() public {
        gaugePlugin.whitelistForGaugeCreation(address(USDC));
        vm.startPrank(address(owner2));
        vm.expectRevert();
        gaugePlugin.blacklistForGaugeCreation(address(USDC));
        vm.stopPrank();
    }

    function testCannotBlacklistTokensForGaugeCreationAgain() public {
        gaugePlugin.whitelistForGaugeCreation(address(USDC));
        gaugePlugin.blacklistForGaugeCreation(address(USDC));
        vm.expectRevert();
        gaugePlugin.blacklistForGaugeCreation(address(USDC));
    }

    function testNonGovernorCanCreateGaugeWithWhitelistedTokens() public {
        gaugePlugin.whitelistForGaugeCreation(address(USDC));
        vm.startPrank(address(owner2));
        voter.createGauge(address(pair), 0);
        vm.stopPrank();
    }

    function testNonGovernorCannotCreateGaugeWithNonWhitelistedTokens() public {
        vm.startPrank(address(owner2));
        vm.expectRevert("!whitelistedForGaugeCreation");
        voter.createGauge(address(pair), 0);
        vm.stopPrank();
    }
}

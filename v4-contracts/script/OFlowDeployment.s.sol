// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// Scripting tool
import {Script} from "../lib/forge-std/src/Script.sol";
import {IFlow} from "../contracts/interfaces/IFlow.sol";
import {IPair} from "../contracts/interfaces/IPair.sol";
import {Flow} from "../contracts/Flow.sol";
import {OptionTokenV4} from "../contracts/OptionTokenV4.sol";
import {GaugeFactoryV4} from "../contracts/factories/GaugeFactoryV4.sol";
import {ProxyGaugeFactory} from "../contracts/factories/ProxyGaugeFactory.sol";
import {BribeFactory} from "../contracts/factories/BribeFactory.sol";
import {PairFactory} from "../contracts/factories/PairFactory.sol";
import {Router} from "../contracts/Router.sol";
import {VotingEscrow} from "../contracts/VotingEscrow.sol";
import {Voter} from "../contracts/Voter.sol";
import {GaugePlugin} from 'contracts/GaugePlugin.sol';

contract OFlowDeployment is Script {

    // TODO: change these accounts!
    address private constant TEAM_MULTI_SIG =
        0x4983A0E6e221dFb2C864E311a88fA55963513D44;
    address private constant DEPLOYER =
        0x3b91Ca4D89B5156d456CbD0D6305F7f36B1517a4;
        

    // TODO: Set the amount
    uint private constant LOCKED_MINT_AMOUNT = 100_000e18;

    // TODO: Fill the address
    address private constant WETH = 0x6e47f8d48a01b44DF3fFF35d258A10A3AEdC114c;
    address private constant NEW_FLOW = 0x1724BC42f8bdDc9819D6BC8e01Ea82792131D9B4;
    address private constant NEW_PAIR_FACTORY = 0xeb1d84d6C8645bA3372C560Ae1989F05B176F3D8;
    address private constant NEW_GAUGE_FACTORY = 0xeb67881f34DF55D211E694070d48afE180B77689;
    address private constant NEW_GAUGE_PLUGIN = 0x9052385e624FC2907a22aDD19EC63eFd46c89e43;
    address private constant NEW_PROXY_GAUGE_FACTORY = 0x6Db82B7c6967370211A5d4Ff38a576D42c418147;
    address private constant NEW_VOTER = 0x74C9C4d495D5f09D28a9d34eDF79DB300B535121;
    address private constant NEW_VOTING_ESCROW = 0x2e88E6FE84934C69BC1bAA601435c732874f8ded;
    address payable private constant NEW_ROUTER = payable(0x8BF3A7040299A2dFAC154a1bA310d2E38e389916);
    address private constant NEW_MINTER = 0x9052385e624FC2907a22aDD19EC63eFd46c89e43;
    // address private constant NEW_GAUGE_PLUGIN = 0x6F3103a306D606e24B8c8CeBAA3Cf2d7847401a6;
    address private constant NEW_REWARDS_DISTRIBUTOR_WETH = 0x6a83589830e0c28B2E268a15cC61F3991BEedB01;
    address private constant NEW_REWARDS_DISTRIBUTOR_FLOW = 0x9753555829D421745F9F72caeEAd6a6DA32d11A1;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address pair = PairFactory(NEW_PAIR_FACTORY).getPair(
            NEW_FLOW,
            WETH,
            false
        );

        // Option to buy Flow
        OptionTokenV4 oFlow = new OptionTokenV4(
            "Option to buy BVM", // name
            "oBVM", // symbol
            TEAM_MULTI_SIG, // admin
            NEW_FLOW, // underlying token
            TEAM_MULTI_SIG,
            NEW_VOTER,
            NEW_ROUTER,
            true,
            false,
            false,
            0
        );

        oFlow.setPairAndPaymentToken(IPair(pair), WETH);

        oFlow.setRewardsAddress(NEW_REWARDS_DISTRIBUTOR_WETH);

        oFlow.grantRole(oFlow.ADMIN_ROLE(), NEW_GAUGE_FACTORY);
        oFlow.grantRole(oFlow.ADMIN_ROLE(), TEAM_MULTI_SIG);

        oFlow.setDiscount(80);
        oFlow.setMaxLPDiscount(0);
        oFlow.setMinLPDiscount(1);
        oFlow.setLockDurationForMaxLpDiscount(52 * 7 * 86400);
        oFlow.setLockDurationForMinLpDiscount((52 * 7 * 86400)-1);
        
        GaugeFactoryV4(NEW_GAUGE_FACTORY).setOFlow(address(oFlow));

        // Transfer gaugefactory ownership to MSIG (team)
        GaugeFactoryV4(NEW_GAUGE_FACTORY).transferOwnership(TEAM_MULTI_SIG);

        ProxyGaugeFactory(NEW_PROXY_GAUGE_FACTORY).deployGauge(NEW_REWARDS_DISTRIBUTOR_FLOW,pair, "veNFT");

        address[] memory whitelistedTokens = new address[](3);
        whitelistedTokens[0] = NEW_FLOW;
        whitelistedTokens[1] = WETH;
        whitelistedTokens[2] = address(oFlow);
        Voter(NEW_VOTER).initialize(whitelistedTokens, NEW_MINTER);

        // Create gauge for flowWftm pair
        Voter(NEW_VOTER).createGauge(pair, 1);

        // Set voter's emergency council
        Voter(NEW_VOTER).setEmergencyCouncil(TEAM_MULTI_SIG);

        // Set voter's governor
        Voter(NEW_VOTER).setGovernor(TEAM_MULTI_SIG);

        // Update gauge in Option Token contract
        oFlow.updateGauge();

        //lockdrop type of token
        // Option to buy Flow
        OptionTokenV4 oFlowLock = new OptionTokenV4(
            "Option to lock BVM", // name
            "oNFTBVM", // symbol
            TEAM_MULTI_SIG, // admin
            NEW_FLOW, // underlying token
            TEAM_MULTI_SIG,
            NEW_VOTER,
            NEW_ROUTER,
            true,
            false,
            true,
            86400 * 7 // 14 days
        );

        oFlowLock.grantRole(oFlowLock.ADMIN_ROLE(), TEAM_MULTI_SIG);

        oFlowLock.setPairAndPaymentToken(IPair(pair), WETH);
        oFlowLock.setMaxLPDiscount(0);
        oFlowLock.setMinLPDiscount(1);
        oFlowLock.setLockDurationForMaxLpDiscount(52 * 7 * 86400);
        oFlowLock.setLockDurationForMinLpDiscount((52 * 7 * 86400)-1);

        Flow(NEW_FLOW).approve(address(oFlowLock), LOCKED_MINT_AMOUNT);
        oFlowLock.mint(TEAM_MULTI_SIG, LOCKED_MINT_AMOUNT);
        GaugePlugin(NEW_GAUGE_PLUGIN).transferOwnership(TEAM_MULTI_SIG);

        vm.stopBroadcast();
    }
}
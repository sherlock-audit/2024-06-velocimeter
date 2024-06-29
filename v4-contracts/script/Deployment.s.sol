// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// Scripting tool
import {Script} from "../lib/forge-std/src/Script.sol";

import {Flow} from "../contracts/Flow.sol";
import {GaugeFactoryV4} from "../contracts/factories/GaugeFactoryV4.sol";
import {ProxyGaugeFactory} from "../contracts/factories/ProxyGaugeFactory.sol";
import {BribeFactory} from "../contracts/factories/BribeFactory.sol";
import {PairFactory} from "../contracts/factories/PairFactory.sol";
import {Router} from "../contracts/Router.sol";
import {GaugePlugin} from "../contracts/GaugePlugin.sol";
import {VelocimeterLibrary} from "../contracts/VelocimeterLibrary.sol";
import {VeArtProxy} from "../contracts/VeArtProxy.sol";
import {VotingEscrow} from "../contracts/VotingEscrow.sol";
import {RewardsDistributorV2} from "../contracts/RewardsDistributorV2.sol";
import {Voter} from "../contracts/Voter.sol";
import {Minter} from "../contracts/Minter.sol";
import {IERC20} from "../contracts/interfaces/IERC20.sol";
import {IPair} from "../contracts/interfaces/IPair.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract Deployment is Script {
    // token addresses
    // TODO: check token address
    address private constant WETH = 0x6e47f8d48a01b44DF3fFF35d258A10A3AEdC114c;

    // privileged accounts
    // TODO: change these accounts!
    address private constant TEAM_MULTI_SIG =
        0x4983A0E6e221dFb2C864E311a88fA55963513D44;
    address private constant TANK = 0x4983A0E6e221dFb2C864E311a88fA55963513D44;
    address private constant DEPLOYER =
        0x3b91Ca4D89B5156d456CbD0D6305F7f36B1517a4;
    // TODO: set the following variables
    uint private constant INITIAL_MINT_AMOUNT = 250_000e18;
    uint private constant LOCKED_MINT_AMOUNT = 100_000e18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Flow token
        Flow flow = new Flow(DEPLOYER, INITIAL_MINT_AMOUNT);

        // Gauge factory
        GaugeFactoryV4 gaugeFactory = new GaugeFactoryV4();
        ProxyGaugeFactory proxyFactory = new ProxyGaugeFactory(address(flow));

        // Bribe factory
        BribeFactory bribeFactory = new BribeFactory();

        // Pair factory
        PairFactory pairFactory = new PairFactory();
        pairFactory.setPause(true); 

        // Router
        Router router = new Router(address(pairFactory), WETH);

        flow.approve(address(router), 1e18);

        revert("UPDATE PRICE BEFORE RUN");

        router.addLiquidityETH{value: 3320000000000000000}(
            address(flow),
            false,
            1e18,
            0, // Conversion ratio
            0,
            DEPLOYER,
            block.timestamp + 1000
        );

        address pair = pairFactory.getPair(
            address(flow),
            WETH,
            false
        );

        pairFactory.setPausePair(pair, true);
        pairFactory.setPause(false); 

        // VelocimeterLibrary
        new VelocimeterLibrary(address(router));

        // VotingEscrow
        VotingEscrow votingEscrow = new VotingEscrow(
            address(flow),
            pair, // LP Token
            address(0),
            TEAM_MULTI_SIG
        );

        // Gauge Plugin
        GaugePlugin gaugePlugin = new GaugePlugin(
            address(flow),
            WETH,
            TEAM_MULTI_SIG
        );

        // Voter
        Voter voter = new Voter(
            address(votingEscrow),
            address(pairFactory),
            address(gaugeFactory),
            address(bribeFactory),
            address(gaugePlugin)
        );

        voter.addFactory( address(pairFactory), address(proxyFactory));

        // Set voter
        votingEscrow.setVoter(address(voter));
        pairFactory.setVoter(address(voter));
        IPair(pair).setVoter();

        // RewardsDistributors
        RewardsDistributorV2 rewardsDistributorWETH = new RewardsDistributorV2(
            address(votingEscrow),
            WETH
        );

        RewardsDistributorV2 rewardsDistributorFlow = new RewardsDistributorV2(
            address(votingEscrow),
            address(flow)
        );

        // Minter
        Minter minter = new Minter(
            address(voter),
            address(votingEscrow),
            address(rewardsDistributorFlow)
        );

        // Set rewards distributor's depositor to minter contract
        rewardsDistributorWETH.setDepositor(address(minter));
        rewardsDistributorFlow.setDepositor(address(minter));

        minter.addRewardsDistributor(address(rewardsDistributorWETH));

        flow.transfer(address(TEAM_MULTI_SIG), INITIAL_MINT_AMOUNT - LOCKED_MINT_AMOUNT - 1e18);

        // Set flow minter to contract
        flow.setMinter(address(minter));

        // Set pair factory pauser and tank
        pairFactory.setTank(TANK);

        // Set minter and voting escrow's team
        votingEscrow.setTeam(TEAM_MULTI_SIG);
        minter.setTeam(TEAM_MULTI_SIG);

        // Transfer pairfactory ownership to MSIG (team)
        pairFactory.transferOwnership(TEAM_MULTI_SIG);

        vm.stopBroadcast();
    }
}
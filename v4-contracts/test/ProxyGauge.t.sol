pragma solidity 0.8.13;

import "./BaseTest.sol";
import "contracts/factories/ProxyGaugeFactory.sol";
import "contracts/GaugeV4.sol";
import "contracts/factories/GaugeFactoryV4.sol";
import "contracts/veMastaBooster.sol";

contract ProxyGaugeTest is BaseTest {
    VotingEscrow escrow;
    ProxyGaugeFactory gaugeFactory;
    
    BribeFactory bribeFactory;
    Voter voter;
    ProxyGauge gauge;
    Minter minter;
    RewardsDistributor distributor;
    veMastaBooster booster;
    

    function setUp() public {
        vm.warp(block.timestamp + 1 weeks); 
        deployOwners();
        deployCoins();
        mintStables();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2 * TOKEN_1M; // use 1/2 for veNFT position
        amounts[1] = TOKEN_1M;
        mintFlow(owners, amounts);

        VeArtProxy artProxy = new VeArtProxy();
        deployPairFactoryAndRouter();
        deployMainPairWithOwner(address(owner));
        escrow = new VotingEscrow(address(FLOW),address(flowDaiPair), address(artProxy), owners[0]);

        deployPairFactoryAndRouter();

        gaugeFactory = new ProxyGaugeFactory(address(FLOW));
        GaugeFactoryV4 gaugeFactoryV4 = new GaugeFactoryV4();
        bribeFactory = new BribeFactory();
        gaugePlugin = new GaugePlugin(address(FLOW), address(WETH), owners[0]);
        voter = new Voter(address(escrow), address(factory), address(gaugeFactory), address(bribeFactory), address(gaugePlugin));
        factory.setVoter(address(voter));
        voter.addFactory(address(factory),address(gaugeFactoryV4));

        address[] memory tokens = new address[](4);
        tokens[0] = address(USDC);
        tokens[1] = address(FRAX);
        tokens[2] = address(DAI);
        tokens[3] = address(FLOW);
        escrow.setVoter(address(voter));

        flowDaiPair.approve(address(escrow), TOKEN_1);
        escrow.create_lock(TOKEN_1, FIFTY_TWO_WEEKS);

        distributor = new RewardsDistributor(address(escrow));
        minter = new Minter(address(voter), address(escrow), address(distributor));
        distributor.setDepositor(address(minter));
        FLOW.setMinter(address(minter));

        voter.initialize(tokens, address(minter));
        minter.startActivePeriod();

        flowDaiPair = Pair(
            factory.createPair(address(FLOW), address(DAI), false)
        );
        
        deployOptionTokenV3WithOwner(
            address(owner),
            address(gaugeFactoryV4),
            address(voter),
            address(escrow)
        );

        deployPairWithOwner(address(owner));

        GaugeV4(voter.createGauge(address(flowDaiPair), 1));
        oFlowV3.updateGauge();

        booster = new veMastaBooster(address(this),52 weeks,address(oFlowV3), address(voter),61 days);

        address newGauge = gaugeFactory.deployGauge(address(booster),address(0),"Test");
        address gaugeAddress = voter.createGauge(newGauge, 0);
        gauge = ProxyGauge(gaugeAddress);


        vm.warp(block.timestamp + 1);
    }

     function testDistributeToTheBooster() public {
        vm.warp(block.timestamp + 7 days);
        address[] memory pools = new address[](1);
        pools[0] = address(gauge);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        voter.vote(1, pools, weights);
        voter.distribute(); 
        assertEq(FLOW.balanceOf(address(booster)),1999999999999999999999);

     }
}
pragma solidity 0.8.13;

import "./BaseTest.sol";
import "contracts/veMastaBooster.sol";
import "contracts/GaugeV4.sol";
import "contracts/factories/GaugeFactoryV4.sol";

contract veMastaBoosterTest is BaseTest { // TODO needs to be decide if and what boster can give to users
    VotingEscrow escrow;
    GaugeFactoryV4 gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;
    veMastaBooster veMastaBoosterContract;
    ExternalBribe bribe;
    GaugeV4 gauge;

    function setUp() public {
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = TOKEN_1 * 1000;
        amounts[1] = TOKEN_1 * 1000;
        amounts[2] = TOKEN_1 * 1000;
        mintFlow(owners, amounts);

        VeArtProxy artProxy = new VeArtProxy();
        escrow = new VotingEscrow(address(FLOW),address(flowDaiPair), address(artProxy), owners[0]);

        deployPairFactoryAndRouter();
        deployVoter();
        factory.setFee(true, 2); // 2 bps = 0.02%
        deployPairWithOwner(address(owner));

        deployOptionTokenV4WithOwner(
            address(owner),
            address(gaugeFactory),
            address(voter),
            address(escrow)
        );
        gaugeFactory.setOFlow(address(oFlowV4));

        gauge = GaugeV4(voter.createGauge(address(flowDaiPair), 0));
        oFlowV4.updateGauge();
        bribe = ExternalBribe(voter.external_bribes(address(gauge)));
       
        veMastaBoosterContract = new veMastaBooster(address(owner),10000000,address(oFlowV4),address(voter),10000000);
        FLOW.approve(address(veMastaBoosterContract),TOKEN_1 * 10);
        veMastaBoosterContract.notifyRewardAmount(TOKEN_1 * 10);

        oFlowV4.grantRole(oFlowV4.MINTER_ROLE(), address(veMastaBoosterContract));

        voter.whitelist(address(oFlowV4));
    }

    function deployVoter() public {
        gaugeFactory = new GaugeFactoryV4();
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
    }

    // function testBoostedBuyAndBribe() public {
    //    DAI.approve(address(veMastaBoosterContract), TOKEN_1);
    //    uint256 flowAmount = router.getAmountOut(TOKEN_1, address(DAI), address(FLOW), false);
    //    uint256 daiBalanceBefore = DAI.balanceOf(address(owner));
    //    uint256 oTokenBalanceBeforeBribe = oFlowV4.balanceOf(address(bribe));
    //    uint256 maxNFT = escrow.currentTokenId(); 
       
    //     veMastaBoosterContract.boostedBuyAndBribe(TOKEN_1,1,address(flowDaiPair));
    
    //     uint256 daiBalanceAfter = DAI.balanceOf(address(owner));
    //      uint256 oTokenBalanceBeforeAfter = oFlowV4.balanceOf(address(bribe));
        
    //     assertEq(escrow.currentTokenId(),maxNFT + 1);
        
    //     (int128 amount,uint256 duration) =  escrow.locked(maxNFT + 1);

    //     assertEq(daiBalanceBefore - daiBalanceAfter, TOKEN_1);
    //     assertEq(oTokenBalanceBeforeAfter - oTokenBalanceBeforeBribe, 333311110370345678 * 2);
    //     assertEq(amount,333311110370345678);
    //     assertEq(duration,9676800);
    // }

    // function testBoostedBuyAndVeLock() public {
    //     veMastaBoosterContract.setVeMatchRate(50);
    //    DAI.approve(address(veMastaBoosterContract), TOKEN_1);
    //    uint256 flowAmount = router.getAmountOut(TOKEN_1, address(DAI), address(FLOW), false);
    //    uint256 daiBalanceBefore = DAI.balanceOf(address(owner));
    //    uint256 maxNFT = escrow.currentTokenId(); 
       
    //    veMastaBoosterContract.boostedBuyAndVeLock(TOKEN_1,1);
    
    //     uint256 daiBalanceAfter = DAI.balanceOf(address(owner));
        
    //     assertEq(escrow.currentTokenId(),maxNFT + 1);
        
    //     (int128 amount,uint256 duration) =  escrow.locked(maxNFT + 1);

    //     assertEq(daiBalanceBefore - daiBalanceAfter, TOKEN_1);
    //     assertEq(amount,999933331111037034);
    //     assertEq(duration,9676800);
    // }

    // function testBoostedBuyAndLPLock() public {
    //    veMastaBoosterContract.setLpMatchRate(50);
    //    gaugeFactory.addOTokenFor(address(gauge), address(veMastaBoosterContract));
    //    DAI.approve(address(veMastaBoosterContract), TOKEN_1);
    //    uint256 flowAmount = router.getAmountOut(TOKEN_1, address(DAI), address(FLOW), false);
    //    uint256 daiBalanceBefore = DAI.balanceOf(address(owner));
       
    //    veMastaBoosterContract.boostedBuyAndLPLock(TOKEN_1,1);
    
    //     uint256 daiBalanceAfter = DAI.balanceOf(address(owner));

    //     (uint amountA, uint amountB) = router.quoteRemoveLiquidity(address(DAI), address(FLOW), false, gauge.balanceWithLock(address(owner)));

    //     assertEq(daiBalanceBefore - daiBalanceAfter, TOKEN_1);
    //     assertEq(gauge.balanceWithLock(address(owner)),666674074156379514);
    //     assertEq(amountA,749999999999999998);
    //     assertEq(gauge.lockEnd(address(owner)),10000001);
    // }

}
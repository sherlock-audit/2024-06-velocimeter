pragma solidity 0.8.13;

import "./BaseTest.sol";
import "contracts/RewardsDistributorV2.sol";

contract RewardsDistributorV2Test is BaseTest {
    VotingEscrow escrow;
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;
    RewardsDistributorV2 distributor;
    Minter minter;

    function deployBase() public {
        vm.warp(block.timestamp + 1 weeks); // put some initial time in

        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e25;
        mintFlow(owners, amounts);

        VeArtProxy artProxy = new VeArtProxy();
        deployPairFactoryAndRouter();
        deployMainPairWithOwner(address(owner));
        escrow = new VotingEscrow(address(FLOW), address(flowDaiPair),address(artProxy), owners[0]);

        gaugeFactory = new GaugeFactory();
        bribeFactory = new BribeFactory();
        gaugePlugin = new GaugePlugin(address(FLOW), address(DAI), owners[0]);
        voter = new Voter(address(escrow), address(factory), address(gaugeFactory), address(bribeFactory),address(gaugePlugin));

        factory.setVoter(address(voter));
        deployPairWithOwner(address(owner));
        deployOptionTokenWithOwner(address(owner), address(gaugeFactory));
        gaugeFactory.setOFlow(address(oFlow));

        address[] memory tokens = new address[](2);
        tokens[0] = address(FRAX);
        tokens[1] = address(FLOW);
        flowDaiPair.approve(address(escrow), TOKEN_1);
        escrow.create_lock(TOKEN_1, FIFTY_TWO_WEEKS);
        distributor = new RewardsDistributorV2(address(escrow),address(DAI));

        minter = new Minter(address(voter), address(escrow), address(distributor));
        
        voter.initialize(tokens, address(minter));
        escrow.setVoter(address(voter));

        distributor.setDepositor(address(minter));
        FLOW.setMinter(address(minter));

        FLOW.approve(address(router), TOKEN_1);
        FRAX.approve(address(router), TOKEN_1);
        router.addLiquidity(address(FRAX), address(FLOW), false, TOKEN_1, TOKEN_1, 0, 0, address(owner), block.timestamp);

        address pair = router.pairFor(address(FRAX), address(FLOW), false);

        FLOW.approve(address(voter), 5 * TOKEN_100K);
        voter.createGauge(pair, 0);
        vm.roll(block.number + 1); // fwd 1 block because escrow.balanceOfNFT() returns 0 in same block
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(flowDaiPair.balanceOf(address(escrow)), TOKEN_1);

        address[] memory pools = new address[](1);
        pools[0] = pair;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        voter.vote(1, pools, weights);

    }

    function initializeVotingEscrow() public {
        deployBase();

        Minter.Claim[] memory claims = new Minter.Claim[](1);
        claims[0] = Minter.Claim({
            claimant: address(owner),
            amount: TOKEN_100K,
            lockTime: FIFTY_TWO_WEEKS
        });
        //minter.initialMintAndLock(claims, 2 * TOKEN_100K);
        FLOW.transfer(address(minter), TOKEN_100K);
        flowDaiPair.approve(address(escrow), TOKEN_1);
        escrow.create_lock(TOKEN_1,FIFTY_TWO_WEEKS);
        minter.startActivePeriod();

        assertEq(escrow.ownerOf(2), address(owner));
        assertEq(escrow.ownerOf(3), address(0));
        vm.roll(block.number + 1);
        assertEq(FLOW.balanceOf(address(minter)), 1 * TOKEN_100K);
    }

    function testMinterWeeklyDistribute() public {
        initializeVotingEscrow();

        minter.update_period();
        assertEq(minter.weekly_emission(), 2000e18);

        _elapseOneWeek();   

        minter.update_period();
        assertEq(distributor.claimable(1), 0);
        distributor.claim(1);
        assertEq(minter.weekly_emission(), 2000e18);

        DAI.transfer(address(distributor), 10*TOKEN_1);
        _elapseOneWeek();

        flowDaiPair.approve(address(escrow), TOKEN_1);

        minter.update_period();

        assertEq(escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2), escrow.totalSupply());

        uint256 weekly = minter.weekly_emission();

        console2.log(weekly);
        console2.log(minter.calculate_growth(weekly));
        console2.log(FLOW.totalSupply());
        console2.log(escrow.totalSupply());

        _elapseOneWeek();

        minter.update_period();

        uint256 share = (escrow.balanceOfNFT(1) * 10*TOKEN_1) /escrow.totalSupply();
        uint256 claimable = distributor.claimable(1);
        assertEq(claimable, share - 1);
        console2.log(distributor.claimable(1));
        distributor.claim(1);

        _elapseOneWeek();

        minter.update_period();
        console2.log(distributor.claimable(1));
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        distributor.claim_many(tokenIds);

        _elapseOneWeek();

        minter.update_period();
        console2.log(distributor.claimable(1));
        distributor.claim(1);

        _elapseOneWeek();

        minter.update_period();
        console2.log(distributor.claimable(1));
        distributor.claim_many(tokenIds);

        _elapseOneWeek();

        minter.update_period();
        console2.log(distributor.claimable(1));
        distributor.claim(1);
    }

    function _elapseOneWeek() private {
        vm.warp(block.timestamp + ONE_WEEK);
        vm.roll(block.number + 1);
    }
}
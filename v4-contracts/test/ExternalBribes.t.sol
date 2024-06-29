pragma solidity 0.8.13;

import './BaseTest.sol';

contract ExternalBribesTest is BaseTest {
    VotingEscrow escrow;
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    Voter voter;
    RewardsDistributor distributor;
    Minter minter;
    Gauge gauge;
    ExternalBribe xbribe;
    Gauge gauge2;
    ExternalBribe xbribe2;
    PairFactory pairFactory;

    function setUp() public {
        vm.warp(block.timestamp + 1 weeks); // put some initial time in

        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2e25;
        amounts[1] = 1e25;
        amounts[2] = 1e25;
        mintFlow(owners, amounts);
        mintLR(owners, amounts);
        VeArtProxy artProxy = new VeArtProxy();
        deployPairFactoryAndRouter();
        deployMainPairWithOwner(address(owner));
        deployMainPairWithOwner(address(owner2));
        deployMainPairWithOwner(address(owner3));
        
        escrow = new VotingEscrow(address(FLOW),address(flowDaiPair), address(artProxy), owners[0]);

        // deployVoter()
        gaugeFactory = new GaugeFactory();
        bribeFactory = new BribeFactory();
        gaugePlugin = new GaugePlugin(address(FLOW), address(WETH), owners[0]);
        voter = new Voter(address(escrow), address(factory), address(gaugeFactory), address(bribeFactory), address(gaugePlugin));

        escrow.setVoter(address(voter));
        // setVoter on pairFactory. factory defined in BaseTest and we know for sure that it is deployed because of deployPairFactoryAndRouter()
        factory.setVoter(address(voter));
        deployPairWithOwner(address(owner));
        deployOptionTokenWithOwner(address(owner), address(gaugeFactory));
        gaugeFactory.setOFlow(address(oFlow));

        distributor = new RewardsDistributor(address(escrow));
        minter = new Minter(address(voter), address(escrow), address(distributor));
        distributor.setDepositor(address(minter));
        FLOW.setMinter(address(minter));
        address[] memory tokens = new address[](5);
        tokens[0] = address(USDC);
        tokens[1] = address(FRAX);
        tokens[2] = address(DAI);
        tokens[3] = address(FLOW);
        tokens[4] = address(LR);
        voter.initialize(tokens, address(minter));

        minter.startActivePeriod();

        // USDC - FRAX stable
        gauge = Gauge(voter.createGauge(address(pair), 0));
        xbribe = ExternalBribe(gauge.external_bribe());

        gauge2 = Gauge(voter.createGauge(address(pair2), 0));
        xbribe2 = ExternalBribe(gauge2.external_bribe());

        // ve
        flowDaiPair.approve(address(escrow), TOKEN_1);
        escrow.create_lock(TOKEN_1, FIFTY_TWO_WEEKS);

        vm.startPrank(address(owner2));
        flowDaiPair.approve(address(escrow), TOKEN_1);
        escrow.create_lock(TOKEN_1, FIFTY_TWO_WEEKS);
        vm.warp(block.timestamp + 1);
        vm.stopPrank();


        vm.startPrank(address(owner3));
        flowDaiPair.approve(address(escrow), TOKEN_1);
        escrow.create_lock(TOKEN_1, FIFTY_TWO_WEEKS);
        vm.warp(block.timestamp + 1);
        vm.stopPrank();
    }

    function testCanClaimExternalBribe() public {
        // fwd half a week
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(xbribe)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // cannot claim
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        xbribe.getRewardForOwner(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, 0);

        // fwd half a week
        vm.warp(block.timestamp + 1 weeks / 2);

        // deliver bribe
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        xbribe.getRewardForOwner(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testCanClaimExternalBribeProRata() public {
        // fwd half a week
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(xbribe)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.startPrank(address(owner2));
        voter.vote(2, pools, weights);
        vm.stopPrank();

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // fwd half a week
        vm.warp(block.timestamp + 1 weeks / 2);

        // deliver bribe
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        xbribe.getRewardForOwner(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        xbribe.getRewardForOwner(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, TOKEN_1 / 2);
    }

    function testCanClaimExternalBribeStaggered() public {
        // fwd half a week
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(xbribe)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        // vote delayed
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(owner2));
        voter.vote(2, pools, weights);
        vm.stopPrank();

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // fwd
        vm.warp(block.timestamp + 1 weeks / 2);

        // deliver bribe
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        xbribe.getRewardForOwner(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertGt(post - pre, TOKEN_1 / 2); // 500172176312657261
        uint256 diff = post - pre;

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        xbribe.getRewardForOwner(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertLt(post - pre, TOKEN_1 / 2); // 499827823687342738
        uint256 diff2 = post - pre;

        assertEq(diff + diff2, TOKEN_1 - 1); // -1 for rounding
    }

function testBribesCanClaimOnlyOnce() public {
        // Epoch 0
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.startPrank(address(owner2));
        voter.vote(2, pools, weights);
        vm.stopPrank();

        // fwd half a week
        // Epoch flip
        // Epoch 1 starts
        vm.warp(block.timestamp + 1 weeks / 2);

        uint256 pre = LR.balanceOf(address(owner));
        console2.log("");
        console2.log("Epoch 1: BEFORE checking 1 in bribe");
        uint256 earned = xbribe.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        vm.startPrank(address(voter));
        // once
        xbribe.getRewardForOwner(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        // twice
        xbribe.getRewardForOwner(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1 / 2);

        // Middle of Epoch 1
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe2), TOKEN_1);
        xbribe2.notifyRewardAmount(address(LR), TOKEN_1);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools2 = new address[](1);
        pools2[0] = address(pair2);
        uint256[] memory weights2 = new uint256[](1);
        weights2[0] = 10000;
        voter.vote(1, pools2, weights2);


        vm.startPrank(address(owner2));
        voter.vote(2, pools2, weights2);
        vm.stopPrank();


        vm.startPrank(address(owner3));
        voter.vote(3, pools, weights);
        vm.stopPrank();

        // fwd half a week
        // Epoch flip
        // Epoch 2 starts
        vm.warp(block.timestamp + 1 weeks / 2);

        uint256 pre2 = LR.balanceOf(address(owner));
        console2.log("");
        console2.log("Epoch 2: BEFORE checking 1 in bribe2");
        uint256 earned2 = xbribe2.earned(address(LR), 1);
        assertEq(earned2, TOKEN_1 / 2);

        console2.log("");
        console2.log("Epoch 2: BEFORE checking 1 in bribe1");
        earned = xbribe.earned(address(LR), 1);
        assertEq(earned, 0);

        // rewards
        address[] memory rewards2 = new address[](1);
        rewards2[0] = address(LR);

        vm.startPrank(address(voter));
        // once
        xbribe2.getRewardForOwner(1, rewards2);
        uint256 post2 = LR.balanceOf(address(owner));
        // twice
        xbribe2.getRewardForOwner(1, rewards2);
        vm.stopPrank();

        uint256 post_post2 = LR.balanceOf(address(owner));
        assertEq(post_post2, post2);
        assertEq(post_post2 - pre2, TOKEN_1 / 2);

        continueEpoch2();
    }

    function continueEpoch2() public {
        // Middle of epoch 2
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        vm.startPrank(address(owner3));
        voter.vote(3, pools, weights);
        vm.stopPrank();

        epoch3();
    }

    function epoch3() public {
        // fwd half a week
        // Epoch flip
        // Epoch 3 starts
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);
    
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        vm.startPrank(address(owner3));
        voter.vote(3, pools, weights);
        vm.stopPrank();

        // not claiming epoch 3 bribes for NFT 3
        epoch4();
    }

    function epoch4() public {
        // fwd a week
        // Epoch flip
        // Epoch 4
        vm.warp(block.timestamp + 1 weeks);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        vm.startPrank(address(owner3));
        voter.reset(3);
        vm.stopPrank();

        // Middle of epoch 4
        vm.warp(block.timestamp + 1 weeks / 2);

        uint256 pre = LR.balanceOf(address(owner));
        console2.log("");
        console2.log("Epoch 4: BEFORE checking 1");
        uint256 earned = xbribe.earned(address(LR), 1);
        assertEq(earned, 0);
        console2.log("");
        console2.log("Epoch 4: BEFORE checking 2");
        earned = xbribe.earned(address(LR), 2);
        assertEq(earned, TOKEN_1 / 2);
        console2.log("");
        console2.log("Epoch 4: BEFORE checking 3");
        earned = xbribe.earned(address(LR), 3);
        assertEq(earned, TOKEN_1 * 3);

        epoch5();
    }

    function epoch5() public {
        // fwd half a week
        // Epoch flip
        // Epoch 5
        vm.warp(block.timestamp + 1 weeks / 2);

        uint256 pre = LR.balanceOf(address(owner));
        console2.log("");
        console2.log("Epoch 5: BEFORE checking 1");
        uint256 earned = xbribe.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);
        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        vm.startPrank(address(voter));
        // once
        xbribe.getRewardForOwner(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        // twice
        xbribe.getRewardForOwner(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1);
    }

    function testBribesCanClaimOnlyOnceArray() public {
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.startPrank(address(owner2));
        voter.vote(2, pools, weights);
        vm.stopPrank();

        // fwd half a week
        vm.warp(block.timestamp + 1 weeks / 2);

        uint256 pre = LR.balanceOf(address(owner));
        uint256 earned = xbribe.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        // rewards
        address[] memory rewards = new address[](2);
        rewards[0] = address(LR);
        rewards[1] = address(LR);

        vm.startPrank(address(voter));
        // once
        xbribe.getRewardForOwner(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        // twice
        xbribe.getRewardForOwner(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1 / 2);
    }

    function testBribesCanClaimIfVotesAreNotCasted() public {
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.startPrank(address(owner2));
        voter.vote(2, pools, weights);
        vm.stopPrank();

        // fwd half a week
        vm.warp(block.timestamp + 1 weeks / 2);

        uint256 pre = LR.balanceOf(address(owner));
        uint256 earned = xbribe.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        // rewards
        address[] memory rewards = new address[](2);
        rewards[0] = address(LR);
        rewards[1] = address(LR);

        vm.startPrank(address(voter));
        // once
        xbribe.getRewardForOwner(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        // twice
        xbribe.getRewardForOwner(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1 / 2);

        // Another Epoch
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // Not voting this epoch

        // fwd half a week
        vm.warp(block.timestamp + 1 weeks / 2);

        uint256 pre2 = LR.balanceOf(address(owner));
        uint256 earned2 = xbribe.earned(address(LR), 1);
        assertEq(earned2, TOKEN_1 / 2);

        // rewards
        address[] memory rewards2 = new address[](2);
        rewards2[0] = address(LR);
        rewards2[1] = address(LR);

        vm.startPrank(address(voter));
        // once
        xbribe.getRewardForOwner(1, rewards2);
        uint256 post2 = LR.balanceOf(address(owner));
        // twice
        xbribe.getRewardForOwner(1, rewards2);
        vm.stopPrank();

        uint256 post_post2 = LR.balanceOf(address(owner));
        assertEq(post_post2, post2);
        assertEq(post_post2 - pre2, TOKEN_1 / 2);
    }

    function testBribesCanClaimLeftOverRewardAfterBeingHandled() public {
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // fwd half a week
        uint epochTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        xbribe.handleLeftOverRewards(epochTimestamp, rewards);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.startPrank(address(owner2));
        voter.vote(2, pools, weights);
        vm.stopPrank();

        // fwd a week
        vm.warp(block.timestamp + 1 weeks);

        uint256 pre = LR.balanceOf(address(owner));
        uint256 earned = xbribe.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        vm.startPrank(address(voter));
        // once
        xbribe.getRewardForOwner(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        // twice
        xbribe.getRewardForOwner(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1 / 2);
    }

    function testBribesCanClaimLeftOverRewardAfterBeingHandledPlusAddingMoreBribes() public {
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // fwd half a week
        uint epochTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1 weeks / 2);

        // add more bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        xbribe.handleLeftOverRewards(epochTimestamp, rewards);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.startPrank(address(owner2));
        voter.vote(2, pools, weights);
        vm.stopPrank();

        // fwd a week
        vm.warp(block.timestamp + 1 weeks);

        uint256 pre = LR.balanceOf(address(owner));
        uint256 earned = xbribe.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        vm.startPrank(address(voter));
        // once
        xbribe.getRewardForOwner(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        // twice
        xbribe.getRewardForOwner(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1);
    }

    function testBribesCanClaimLeftOverRewardAfterBeingHandledAfterSeveralEpochs() public {
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // fwd half a week
        uint epochTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1 weeks / 2);

        // add more bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.startPrank(address(owner2));
        voter.vote(2, pools, weights);
        vm.stopPrank();

        // fwd a week
        vm.warp(block.timestamp + 3 weeks);

        xbribe.handleLeftOverRewards(epochTimestamp, rewards);

        vm.warp(block.timestamp + 1 weeks);

        uint256 pre = LR.balanceOf(address(owner));
        uint256 earned = xbribe.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        vm.startPrank(address(voter));
        // once
        xbribe.getRewardForOwner(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        // twice
        xbribe.getRewardForOwner(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1);
    }

    function testCannotCallHandleLeftOverRewardsWhenThereAreVotes() public {
        vm.warp(block.timestamp + 1 weeks / 2);

        // create a bribe
        LR.approve(address(xbribe), TOKEN_1);
        xbribe.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pair);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        // fwd half a week
        uint epochTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        vm.expectRevert("this epoch has votes");
        xbribe.handleLeftOverRewards(epochTimestamp, rewards);
    }
}

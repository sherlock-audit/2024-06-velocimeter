pragma solidity 0.8.13;

import "./BaseTest.sol";

contract KillGaugesTest is BaseTest {
  VotingEscrow escrow;
  GaugeFactory gaugeFactory;
  BribeFactory bribeFactory;
  Voter voter;
  RewardsDistributor distributor;
  Minter minter;
  TestStakingRewards staking;
  TestStakingRewards staking2;
  Gauge gauge;
  Gauge gauge2;

  event GaugeKilledTotally(address indexed gauge);
  event GaugePaused(address indexed gauge);
  event GaugeRestarted(address indexed gauge);

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

    flowDaiPair.approve(address(escrow), 100 * TOKEN_1);
    escrow.create_lock(100 * TOKEN_1, FIFTY_TWO_WEEKS);
    vm.roll(block.number + 1);


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
    distributor = new RewardsDistributor(address(escrow));

    minter = new Minter(address(voter), address(escrow), address(distributor));
    distributor.setDepositor(address(minter));
    FLOW.setMinter(address(minter));
    address[] memory tokens = new address[](4);
    tokens[0] = address(USDC);
    tokens[1] = address(FRAX);
    tokens[2] = address(DAI);
    tokens[3] = address(FLOW);
    voter.initialize(tokens, address(minter));

    FLOW.approve(address(gaugeFactory), 15 * TOKEN_100K);
    voter.createGauge(address(pair), 0);
    voter.createGauge(address(pair2), 0);

    staking = new TestStakingRewards(address(pair), address(FLOW));
    staking2 = new TestStakingRewards(address(pair2), address(FLOW));

    address gaugeAddress = voter.gauges(address(pair));
    gauge = Gauge(gaugeAddress);

    address gaugeAddress2 = voter.gauges(address(pair2));
    gauge2 = Gauge(gaugeAddress2);
  }

  function testEmergencyCouncilCanKillAndrestartGauges() public {
    address gaugeAddress = address(gauge);

    // emergency council is owner
    vm.expectEmit(true, false, false, true);
    emit GaugePaused(gaugeAddress);
    voter.pauseGauge(gaugeAddress);
    assertFalse(voter.isAlive(gaugeAddress));
    assertFalse(IPair(pair).hasGauge());

    vm.warp(block.timestamp + 1 weeks);

    address[] memory pools = new address[](1);
    pools[0] = address(pair);
    uint256[] memory weights = new uint256[](1);
    weights[0] = 10000;
    vm.expectRevert(abi.encodePacked("gauge already dead"));
    voter.vote(1, pools, weights);

    vm.expectEmit(true, false, false, true);
    emit GaugeRestarted(gaugeAddress);
    voter.restartGauge(gaugeAddress);
    assertTrue(voter.isAlive(gaugeAddress));
    assertTrue(IPair(pair).hasGauge());
  }

  function testEmergencyCouncilCanKillGaugesTotally() public {
    address gaugeAddress = address(gauge);

    assertTrue(voter.isAlive(gaugeAddress));
    assertTrue(IPair(pair).hasGauge());
    assertEq(voter.external_bribes(gaugeAddress), gauge.external_bribe());
    assertTrue(voter.isGauge(gaugeAddress));
    assertFalse(voter.gauges(address(pair)) == address(0));

    // emergency council is owner
    vm.expectEmit(true, false, false, true);
    emit GaugeKilledTotally(gaugeAddress);
    voter.killGaugeTotally(gaugeAddress);
    assertFalse(voter.isAlive(gaugeAddress));
    assertFalse(IPair(pair).hasGauge());
    assertEq(voter.external_bribes(gaugeAddress), address(0));
    assertFalse(voter.isGauge(gaugeAddress));
    assertTrue(voter.gauges(address(pair)) == address(0));
  }

  function testCanKillGaugesTotallyAndCreateAgain() public {
    address gaugeAddress = address(gauge);

    // emergency council is owner
    voter.killGaugeTotally(gaugeAddress);

    voter.createGauge(address(pair), 0);
    assertFalse(voter.gauges(address(pair)) == address(0));
  }

   function testKillGaugeIsAddedToArray() public {
    address gaugeAddress = address(gauge);

    // emergency council is owner
    voter.killGaugeTotally(gaugeAddress);

    assertEq(voter._killedGauges()[0],gaugeAddress);
  }

  function testFullyKilledGaugeCanWithdraw() public {
    USDC.approve(address(router), USDC_100K);
    FRAX.approve(address(router), TOKEN_100K);
    router.addLiquidity(address(FRAX), address(USDC), true, TOKEN_100K, USDC_100K, TOKEN_100K, USDC_100K, address(owner), block.timestamp);

    address gaugeAddress = address(gauge);

    uint256 supply = pair.balanceOf(address(owner));
    pair.approve(address(gauge), supply);
    gauge.deposit(supply, 1);

    voter.killGaugeTotally(gaugeAddress);

    gauge.withdrawToken(supply, 1); // should be allowed
  }

   function testCanStillDistroAllWithFullyKilledGauge() public {
    vm.warp(block.timestamp + ONE_WEEK * 2);
    vm.roll(block.number + 1);
    minter.update_period();
    voter.updateGauge(address(gauge));
    voter.updateGauge(address(gauge2));

    uint256 claimable = voter.claimable(address(gauge));
    console2.log(claimable);
    FLOW.approve(address(staking), claimable);
    staking.notifyRewardAmount(claimable);

    uint256 claimable2 = voter.claimable(address(gauge2));
    FLOW.approve(address(staking), claimable2);
    staking.notifyRewardAmount(claimable2);

    address[] memory gauges = new address[](2);
    gauges[0] = address(gauge);
    gauges[1] = address(gauge2);
    voter.updateFor(gauges);

    voter.killGaugeTotally(address(gauge));

    // should be able to claim from gauge2, just not from gauge
    voter.distribute(address(gauge));
  }


  function testFailCouncilCannotKillNonExistentGauge() public {
    voter.pauseGauge(address(0xDEAD));
  }

  function testFailNoOneElseCanKillGauges() public {
    address gaugeAddress = address(gauge);
    vm.prank(address(owner2));
    voter.pauseGauge(gaugeAddress);
  }

  function testKilledGaugeCannotDeposit() public {
    USDC.approve(address(router), USDC_100K);
    FRAX.approve(address(router), TOKEN_100K);
    router.addLiquidity(address(FRAX), address(USDC), true, TOKEN_100K, USDC_100K, TOKEN_100K, USDC_100K, address(owner), block.timestamp);

    address gaugeAddress = address(gauge);
    voter.pauseGauge(gaugeAddress);

    uint256 supply = pair.balanceOf(address(owner));
    pair.approve(address(gauge), supply);
    vm.expectRevert(abi.encodePacked(""));
    gauge.deposit(supply, 1);
  }

  function testKilledGaugeCanWithdraw() public {
    USDC.approve(address(router), USDC_100K);
    FRAX.approve(address(router), TOKEN_100K);
    router.addLiquidity(address(FRAX), address(USDC), true, TOKEN_100K, USDC_100K, TOKEN_100K, USDC_100K, address(owner), block.timestamp);

    address gaugeAddress = address(gauge);

    uint256 supply = pair.balanceOf(address(owner));
    pair.approve(address(gauge), supply);
    gauge.deposit(supply, 1);

    voter.pauseGauge(gaugeAddress);

    gauge.withdrawToken(supply, 1); // should be allowed
  }

  function testKilledGaugeCanUpdateButGoesToZero() public {
    vm.warp(block.timestamp + ONE_WEEK * 2);
    vm.roll(block.number + 1);
    minter.update_period();
    voter.updateGauge(address(gauge));
    uint256 claimable = voter.claimable(address(gauge));
    FLOW.approve(address(staking), claimable);
    staking.notifyRewardAmount(claimable);
    address[] memory gauges = new address[](1);
    gauges[0] = address(gauge);

    voter.pauseGauge(address(gauge));

    voter.updateFor(gauges);

    assertEq(voter.claimable(address(gauge)), 0);
  }

  function testKilledGaugeCanDistributeButGoesToZero() public {
    vm.warp(block.timestamp + ONE_WEEK * 2);
    vm.roll(block.number + 1);
    minter.update_period();
    voter.updateGauge(address(gauge));
    uint256 claimable = voter.claimable(address(gauge));
    FLOW.approve(address(staking), claimable);
    staking.notifyRewardAmount(claimable);
    address[] memory gauges = new address[](1);
    gauges[0] = address(gauge);
    voter.updateFor(gauges);

    voter.pauseGauge(address(gauge));

    assertEq(voter.claimable(address(gauge)), 0);
  }

  function testCanStillDistroAllWithKilledGauge() public {
    vm.warp(block.timestamp + ONE_WEEK * 2);
    vm.roll(block.number + 1);
    minter.update_period();
    voter.updateGauge(address(gauge));
    voter.updateGauge(address(gauge2));

    uint256 claimable = voter.claimable(address(gauge));
    console2.log(claimable);
    FLOW.approve(address(staking), claimable);
    staking.notifyRewardAmount(claimable);

    uint256 claimable2 = voter.claimable(address(gauge2));
    FLOW.approve(address(staking), claimable2);
    staking.notifyRewardAmount(claimable2);

    address[] memory gauges = new address[](2);
    gauges[0] = address(gauge);
    gauges[1] = address(gauge2);
    voter.updateFor(gauges);

    voter.pauseGauge(address(gauge));

    // should be able to claim from gauge2, just not from gauge
    voter.distro();
  }
}

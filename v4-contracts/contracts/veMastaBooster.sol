// SPDX-License-Identifier: MIT

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/interfaces/IVotingEscrow.sol";
import "contracts/interfaces/IVoter.sol";
import "contracts/interfaces/IRouter.sol";
import "contracts/interfaces/IPair.sol";
import "contracts/interfaces/IOptionToken.sol";
import "contracts/interfaces/IBribe.sol";
import "contracts/interfaces/IGauge.sol";
import "contracts/interfaces/IGaugeV4.sol";
import "contracts/interfaces/IProxyGaugeNotify.sol";

pragma solidity ^0.8.13;

contract veMastaBooster is Ownable,IProxyGaugeNotify {
    address public paymentToken;
    address public optionToken;
    address public router;
    address public gauge;
    address public pair;
    address public flow;
    address public voting_escrow;
    address public voter;
    uint256 public lpMatchRate = 20; // 20%
    uint256 public veMatchRate = 60; // 60%
    uint256 public bribeMatchRate = 50; // 50%
    
    uint256 public lpLockDuration;
    uint256 public maxLock;

    bool public boostLpPaused;
    bool public boostVePaused;
    bool public boostBribePaused;

    event Boosted(uint256 indexed _timestamp, uint256 _totalLocked, address _locker);
    event RewardsAdded(uint256 indexed _timestamp, uint256 _amount);
    event MatchRateChanged(uint256 indexed _timestamp, string _type, uint256 _newRate);
    event Pausings(uint256 indexed _timestamp, string _type, bool _paused);

    // need minter role for the oToken
    // need approval to deposit for lock to the maxing gauge
    constructor(address _team, uint256 _maxLock, address _optionToken,address _voter,uint256 _lpLockDuration) {
        _transferOwnership(_team);
        voter = _voter;
        voting_escrow = IVoter(voter)._ve();
        flow = IVotingEscrow(voting_escrow).baseToken();
        optionToken = _optionToken;
        paymentToken = IOptionToken(_optionToken).paymentToken();
        router = IOptionToken(_optionToken).router();
        gauge = IOptionToken(_optionToken).gauge();
        pair = IGauge(gauge).stake();
        maxLock = _maxLock;
        lpLockDuration = _lpLockDuration;
        giveAllowances();
    }
//VIEW FUNCTIONS
    function balanceOfFlow() public view returns (uint){
        return IERC20(flow).balanceOf(address(this));
    }
    function balanceOfOToken() public view returns (uint){
        return IERC20(optionToken).balanceOf(address(this));
    }
    function maxLpLockableAmount() public view returns (uint){
         uint256 flowBal = balanceOfFlow();
         uint256 amnt = flowBal * 100 / lpMatchRate;
         return amnt;
    }
    
    function maxVeLockableAmount() public view returns (uint){
         uint256 flowBal = balanceOfFlow();
         uint256 amnt = flowBal * 100 / veMatchRate;
         return amnt;
    }   
    function maxBribeAmount() public view returns (uint){
         uint256 flowBal = balanceOfFlow();
         uint256 amnt = flowBal * 100 / bribeMatchRate;
         return amnt;
    }
    function checkFlowBalanceEnoughForLP(uint256 _paymentAmount) public view returns (bool) {
        (uint256 toSpend,uint256 toLP,uint amountToLock) = getAmountsForLPLock(_paymentAmount);

        uint256 amount = IRouter(router).getAmountOut(toSpend, paymentToken, flow, false);

        return balanceOfFlow() >= amountToLock - amount;
    }

    function checkFlowBalanceEnoughForVE(uint256 _paymentAmount) public view returns (bool) {
        uint256 amount = IRouter(router).getAmountOut(_paymentAmount, paymentToken, flow, false);
        return balanceOfFlow() >= amount * veMatchRate  / 100;
    }
    function checkFlowBalanceEnoughForBribe(uint256 _paymentAmount) public view returns (bool) {
        uint256 amount = IRouter(router).getAmountOut(_paymentAmount, paymentToken, flow, false);
        return balanceOfFlow() >= amount * bribeMatchRate  / 100;
    }
    function getExpectedAmountForLP(uint256 _paymentAmount) external view returns (uint256,uint256) {
        uint256 amount = IRouter(router).getAmountOut(_paymentAmount, paymentToken, flow, false);

        (uint256 toSpend,uint256 toLP,uint amountToLock) = getAmountsForLPLock(_paymentAmount);

        return (amountToLock,toLP);
    }
    function getExpectedAmountForVE(uint256 _paymentAmount) external view returns (uint256) {
        uint256 amount = IRouter(router).getAmountOut(_paymentAmount, paymentToken, flow, false);
        return amount * veMatchRate  / 100;
    }
    function getExpectedAmountForBribe(uint256 _paymentAmount) external view returns (uint256) {
        uint256 amount = IRouter(router).getAmountOut(_paymentAmount, paymentToken, flow, false);
        return amount * bribeMatchRate  / 100;
    }

    function getAmountsForLPLock(uint256 _amount) public view returns (uint256,uint256,uint256) {
        uint256 toSpend = _amount / 2 -(_amount / 2 * lpMatchRate / 100);
        uint256 toLP = _amount - toSpend;

        (uint256 flowReserve, uint256 paymentReserve) = IRouter(router).getReserves(flow, paymentToken, false);
        uint256 amountToLock = (toLP * flowReserve) / paymentReserve;

        return (toSpend,toLP,amountToLock);
    }

        
//PUBLIC FUNCTIONS       
    function notifyRewardAmount(uint256 _amount) external {
        require(_amount > 0, 'need to add at least 1 FLOW');
        IERC20(flow).transferFrom(msg.sender, address(this), _amount);
        emit RewardsAdded(block.timestamp, _amount);
    }


// USER FUNCTIONS
    function boostedBuyAndVeLock(uint256 _amount, uint _minOut) public {
        require(!boostVePaused, 'this is paused');
        require(_amount > 0, 'need to lock at least 1 paymentToken');
        require(balanceOfFlow() > 0, 'no extra FLOW for boosting');
        IERC20(paymentToken).transferFrom(msg.sender, address(this), _amount);

        if (_minOut == 0) {
            _minOut = 1;
        }

        uint256 flowBefore = balanceOfFlow();
        IRouter(router).swapExactTokensForTokensSimple(_amount, _minOut, paymentToken, flow, false, address(this), block.timestamp);
        uint256 flowAfter = balanceOfFlow();
        uint256 flowResult = flowAfter - flowBefore;

        uint256 amountToLock = flowResult * veMatchRate  / 100 + flowResult;
        IVotingEscrow(voting_escrow).create_lock_for(amountToLock, maxLock, msg.sender);

        emit Boosted(block.timestamp, amountToLock, msg.sender);
    }
    function boostedBuyAndLPLock(uint256 _amount, uint _minOut) public {
        require(!boostLpPaused, 'this is paused');
        require(_amount > 0, 'need to lock at least 1 paymentToken');
        require(balanceOfFlow() > 0, 'no extra FLOW for boosting');
        
        uint256 paymentBalBefore = IERC20(paymentToken).balanceOf(address(this));
        IERC20(paymentToken).transferFrom(msg.sender, address(this), _amount);

        if (_minOut == 0) {
            _minOut = 1;
        }

        (uint256 toSpend,uint256 toLP,uint amountToLock) = getAmountsForLPLock(_amount);
        
        uint256 flowBefore = balanceOfFlow();
        IRouter(router).swapExactTokensForTokensSimple(toSpend, _minOut, paymentToken, flow, false, address(this), block.timestamp);
        uint256 flowAfter = balanceOfFlow();
        uint256 flowResult = flowAfter - flowBefore;

        IRouter(router).addLiquidity(flow, paymentToken, false, amountToLock, toLP, 1, 1, address(this), block.timestamp);
        uint256 lpBal = IERC20(pair).balanceOf(address(this));
        IGaugeV4(gauge).depositWithLock(msg.sender,lpBal,lpLockDuration);

        uint256 paymentBalAfter = IERC20(paymentToken).balanceOf(address(this));
        uint paymentLeftover = paymentBalAfter - paymentBalBefore;

        if(paymentLeftover > 0) {
             IERC20(paymentToken).transfer(msg.sender, paymentLeftover);
        }

        emit Boosted(block.timestamp, lpBal, msg.sender);
    }

    function boostedBuyAndBribe(uint256 _amount, uint _minOut,address _pool) public {
        require(!boostBribePaused, 'this is paused');
        require(_amount > 0, 'need to lock at least 1 paymentToken');
        require(balanceOfFlow() > 0, 'no extra FLOW for boosting');
        IERC20(paymentToken).transferFrom(msg.sender, address(this), _amount);

        if (_minOut == 0) {
            _minOut = 1;
        }

        uint256 flowBefore = balanceOfFlow();
        IRouter(router).swapExactTokensForTokensSimple(_amount, _minOut, paymentToken, flow, false, address(this), block.timestamp);
        uint256 flowAfter = balanceOfFlow();
        uint256 flowResult = flowAfter - flowBefore;

        uint256 oTokenBefore = balanceOfOToken();
        IOptionToken(optionToken).mint(address(this), flowResult);
        uint256 oTokenAfter = balanceOfOToken();

        uint256 oTokenResult = oTokenAfter - oTokenBefore;
        
        address poolGauge = IVoter(voter).gauges(_pool);

        require(IVoter(voter).isAlive(poolGauge), 'gauge not alive');

        address bribeGauge = IVoter(voter).external_bribes(poolGauge);

        IERC20(optionToken).approve(bribeGauge, oTokenResult);

        IBribe(bribeGauge).notifyRewardAmount(
                optionToken,
                oTokenResult
        );

        uint256 amountToLock = flowResult * bribeMatchRate  / 100;
        IVotingEscrow(voting_escrow).create_lock_for(amountToLock, maxLock, msg.sender);

        emit Boosted(block.timestamp, amountToLock, msg.sender);
    }

//OWNER FUNCTIONS
    function setLpMatchRate(uint256 _rate) external onlyOwner {
        require(_rate <= 100, 'cant give more than 1-1');
        lpMatchRate = _rate;  

        emit MatchRateChanged(block.timestamp, "LPBoost", _rate);    
    }
    function setVeMatchRate(uint256 _rate) external onlyOwner {
        require(_rate <= 100, 'cant give more than 1-1');
        veMatchRate = _rate;  

        emit MatchRateChanged(block.timestamp, "veBoost", _rate);      
    }  
    function setBribeMatchRate(uint256 _rate) external onlyOwner {
        require(_rate <= 100, 'cant give more than 1-1');
        bribeMatchRate = _rate;  

        emit MatchRateChanged(block.timestamp, "BribeBoost", _rate);      
    }
    function setPaymentToken(address _paymentToken) external onlyOwner {
        require(_paymentToken != address(0));
        paymentToken = _paymentToken;
    }
    function setRouter(address _router) external onlyOwner {
        require(_router != address(0));
        router = _router;
    }
    function setPair(address _pair) external onlyOwner {
        require(_pair != address(0));
        pair = _pair;
    }
    function setGauge(address _gauge) external onlyOwner {
        require(_gauge != address(0));
        gauge = _gauge;
    }
    function setOptionToken(address _optionToken) external onlyOwner {
        require(_optionToken != address(0));
        optionToken = _optionToken;
    }
    function setLPLockDuration(uint256 _lpLockDuration) external onlyOwner {
        lpLockDuration = _lpLockDuration;
    }       
    function pauseLPBoost(bool _tf) external onlyOwner {
        boostLpPaused = _tf;
        emit Pausings(block.timestamp, "LPBoost", _tf);
    }
    function pauseVeBoost(bool _tf) external onlyOwner {
        boostVePaused = _tf;
        emit Pausings(block.timestamp, "VeBoost", _tf);
    }
    function pauseBribeBoost(bool _tf) external onlyOwner {
        boostBribePaused = _tf;
        emit Pausings(block.timestamp, "BribeBoost", _tf);
    }
    function inCaseTokensGetStuck(address _token, address _to) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(_to, amount);
    }
    function giveAllowances() public onlyOwner {
        IERC20(flow).approve(voting_escrow, type(uint256).max);
        IERC20(flow).approve(router, type(uint256).max);
        IERC20(paymentToken).approve(router, type(uint256).max);
        IERC20(flow).approve(optionToken, type(uint256).max);
        IERC20(pair).approve(gauge, type(uint256).max);
    }
    function removeAllowances() public onlyOwner {
        IERC20(flow).approve(voting_escrow, 0);
        IERC20(flow).approve(router, 0);
        IERC20(paymentToken).approve(router, 0);
        IERC20(flow).approve(optionToken, 0);
        IERC20(pair).approve(gauge, type(uint256).max);
    }

}
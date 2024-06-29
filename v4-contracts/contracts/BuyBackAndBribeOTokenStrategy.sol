// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import 'contracts/interfaces/IERC20.sol';
import 'contracts/interfaces/IRouter.sol';
import 'contracts/interfaces/IBribe.sol';
import "contracts/interfaces/IOptionToken.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

// Bribes pay out rewards for a given pool based on the votes that were received from the user (goes hand in hand with Voter.vote())
contract BuyBackAndBribeOTokenStrategy is Ownable{
    address public treasury;
    address public bribeGauge;
    address public optionToken;
    address public router;
    address public paymentToken;
    address public underlyingToken;
    uint256 public ratio = 80; // actual % of how much wftm will swap for FVM

    constructor(address _treasury, address _bribeGauge,address _optionToken, address _router) {
        treasury = _treasury;
        router = _router;
        bribeGauge = _bribeGauge;
        optionToken = _optionToken;
        paymentToken = IOptionToken(optionToken).paymentToken();
        underlyingToken = IOptionToken(optionToken).underlyingToken();
        giveAllowances();
    }

    // ADMINS Set Functions
    function setTreasury(address _treasury) external onlyOwner {
        require (_treasury != address(0));
        treasury = _treasury;
    }
    function setBribeGauge(address _bribeGauge) external onlyOwner {
        require (_bribeGauge != address(0));
        bribeGauge = _bribeGauge;
    }
    function setRouter(address _router) external onlyOwner {
        require (_router != address(0));
        router = _router;
    }
    function setRatio(uint256 _ratio) external onlyOwner {
        ratio = _ratio;
    }
    
    // Public Functions
    function balanceOfUnderlyingToken() public view returns (uint){
        return IERC20(underlyingToken).balanceOf(address(this));
    }
    function balanceOfPaymentToken() public view returns (uint){
        return IERC20(paymentToken).balanceOf(address(this));
    }

    function balanceOfOToken() public view returns (uint){
        return IERC20(optionToken).balanceOf(address(this));
    }

    function disperse() public {
        uint256 paymentTokenBal = balanceOfPaymentToken();
        if (ratio > 0) {
            uint256 paymentTokenToSwap = paymentTokenBal * ratio / 100;

            IRouter(router).swapExactTokensForTokensSimple(paymentTokenToSwap, 1, paymentToken, underlyingToken, false, address(this), block.timestamp);
            
            paymentTokenBal = balanceOfPaymentToken();
            uint256 underlyingTokenBal = balanceOfUnderlyingToken();

            uint256 oTokenBefore = balanceOfOToken();
            IOptionToken(optionToken).mint(address(this), underlyingTokenBal);
            uint256 oTokenAfter = balanceOfOToken();
            uint256 oTokenResult = oTokenAfter - oTokenBefore;

            IERC20(optionToken).approve(bribeGauge, oTokenResult);

            IBribe(bribeGauge).notifyRewardAmount(
                optionToken,
                oTokenResult
            );

        }        
        IERC20(paymentToken).transfer(treasury, paymentTokenBal);
        
    }

    // Admin Safety Functions
    function inCaseTokensGetStuck(address _token, address _to) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(_to, amount);
    }
    function giveAllowances() public onlyOwner {
        IERC20(optionToken).approve(bribeGauge, type(uint256).max);
        IERC20(underlyingToken).approve(optionToken, type(uint256).max);
        IERC20(paymentToken).approve(router, type(uint256).max);
    }
    function removeAllowances() external onlyOwner {
        IERC20(optionToken).approve(bribeGauge, 0);
        IERC20(underlyingToken).approve(optionToken, 0);
        IERC20(paymentToken).approve(router, 0);
    }
}
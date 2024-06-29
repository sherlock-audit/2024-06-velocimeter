// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/interfaces/IVotingEscrow.sol";
import "contracts/interfaces/IRouter.sol";
import "contracts/interfaces/IPair.sol";
import "contracts/interfaces/IOptionToken.sol";

contract ExerciseVault is Ownable {
     event OTokenAdded(address indexed _oToken);
     event OTokenRemoved(address indexed _oToken);
     event Donated(uint256 indexed _timestamp, address indexed _paymentToken,uint256 _amount);
     event Exercise(address indexed _oToken,address indexed _from,uint256 _amount,uint256 _profit);

     address public router;
     
     mapping(address => bool) public isOToken;
     
     uint256 public fee = 500; // 5%

     constructor(address _router) {
        router = _router;
     }

     function getAmountOfPaymentTokensAfterExercise(address _oToken,address _underlyingToken,address _paymentToken,uint256 _amount) public view returns (uint256) {
         uint256 price = IOptionToken(_oToken).getDiscountedPrice(_amount);
         uint256 amoutAfterSell = IRouter(router).getAmountOut(_amount, _underlyingToken, _paymentToken, false);
         uint256 profit = amoutAfterSell - price;
         uint256 fee = (profit * fee ) / 10000;
         return profit - fee;
     }

     function exercise(address _oToken,uint256 _amount,uint _minOut) external {
        require(isOToken[_oToken],"Not a valid oToken");
        require(_amount > 0,"_amount < 0");

        if (_minOut == 0) {
            _minOut = 1;
        }
        
        IERC20(_oToken).transferFrom(msg.sender, address(this), _amount);

        address paymentToken = IOptionToken(_oToken).paymentToken();
        address underlyingToken = IOptionToken(_oToken).underlyingToken();

        uint256 paymentTokenBalanceBefore = IERC20(paymentToken).balanceOf(address(this));
        uint256 underlyingTokenBalanceBefore = IERC20(underlyingToken).balanceOf(address(this));
        uint256 price = IOptionToken(_oToken).getDiscountedPrice(_amount);

        require(paymentTokenBalanceBefore > price,"Not enough payment tokens");

        IOptionToken(_oToken).exercise(_amount, price, address(this));

        uint256 underlyingTokenBalanceAfter = IERC20(underlyingToken).balanceOf(address(this));
        uint256 ammountToSell = underlyingTokenBalanceAfter - underlyingTokenBalanceBefore;

        IERC20(underlyingToken).approve(router, ammountToSell);
        IRouter(router).swapExactTokensForTokensSimple(ammountToSell, _minOut, underlyingToken, paymentToken, false, address(this), block.timestamp);

        uint256 paymentTokenBalanceAfter = IERC20(paymentToken).balanceOf(address(this));

        require(paymentTokenBalanceAfter > paymentTokenBalanceBefore,"Not profitable excercise");

        uint256 profit =  paymentTokenBalanceAfter - paymentTokenBalanceBefore;
        uint256 fee = (profit * fee ) / 10000;
        uint256 profitAfterFee = profit - fee;

        IERC20(paymentToken).transfer(msg.sender, profitAfterFee);

        emit Exercise(_oToken,msg.sender,_amount,profitAfterFee);
     }

     function donatePaymentToken(address _paymentToken,uint256 _amount) public {
        require(_amount > 0, 'need to add at least 1');
        IERC20(_paymentToken).transferFrom(msg.sender, address(this), _amount);
        emit Donated(block.timestamp,_paymentToken, _amount);
    }

     function inCaseTokensGetStuck(address _token, address _to) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(_to, amount);
     }

    function addOToken(address _oToken) external onlyOwner{
        isOToken[_oToken] = true;
        address paymentToken = IOptionToken(_oToken).paymentToken();

        IERC20(paymentToken).approve(_oToken, type(uint256).max);

        emit OTokenAdded(_oToken);
    }

    function removeOToken(address _oToken) external onlyOwner{
        isOToken[_oToken] = false;

        address paymentToken = IOptionToken(_oToken).paymentToken();
        IERC20(paymentToken).approve(_oToken, 0);

        emit OTokenRemoved(_oToken);
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

}
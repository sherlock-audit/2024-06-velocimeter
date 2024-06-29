// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import 'contracts/interfaces/IBribe.sol';
import 'contracts/interfaces/IERC20.sol';
import 'contracts/interfaces/IProxyGaugeNotify.sol';
import 'contracts/interfaces/IGauge.sol';
import 'contracts/interfaces/IOptionToken.sol';
import 'contracts/interfaces/IVoter.sol';
import 'contracts/interfaces/IVotingEscrow.sol';

// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
contract ProxyGauge is IGauge {
    address public immutable flow;
    address public immutable notifyAddress;
    string public symbol;

    // simple re-entrancy check
    uint internal _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    constructor(address _flow,address _notifyAddress,string memory _symbol) {
        flow = _flow;
        notifyAddress = _notifyAddress;
        symbol = _symbol;
    }

    function notifyRewardAmount(address token, uint amount) external lock {
        require(token == flow);
        require(amount > 0);
        
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        amount = balanceAfter - balanceBefore;

        _safeApprove(flow, notifyAddress, amount);
        IProxyGaugeNotify(notifyAddress).notifyRewardAmount(amount);
    }

    function getReward(address account, address[] memory tokens) external {

    }

    function left(address token) external view returns (uint) {
        return 0;
    }

    function stake() external view returns (address) {
        return address(0);
    }

    function externalBribe() external returns (address) {
        return address(0);
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) =
        token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) =
        token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeApprove(address token, address spender, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) =
        token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}
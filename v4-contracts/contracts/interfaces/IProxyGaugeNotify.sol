pragma solidity 0.8.13;

interface IProxyGaugeNotify {
    function notifyRewardAmount(uint256 _amount) external; 
}

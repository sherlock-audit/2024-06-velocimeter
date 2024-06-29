pragma solidity 0.8.13;

interface IOptionTokenNotify {
    function notify(uint256 _amount) external; // after the transfer is done option token is doing the notfy call to the strategy
}
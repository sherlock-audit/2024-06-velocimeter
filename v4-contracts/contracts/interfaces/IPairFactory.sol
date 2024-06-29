pragma solidity 0.8.13;

interface IPairFactory {
    function allPairsLength() external view returns (uint);
    function isPair(address pair) external view returns (bool);
    function isPaused(address _pair) external view returns(bool);
    function pairCodeHash() external pure returns (bytes32);
    function getFee(address pair) external view returns (uint256);
    function getPair(address tokenA, address token, bool stable) external view returns (address);
    function getInitializable() external view returns (address, address, bool);
    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);
    function voter() external view returns (address);
    function tank() external view returns (address);
}

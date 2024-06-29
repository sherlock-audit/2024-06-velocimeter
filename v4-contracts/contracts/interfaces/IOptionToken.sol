pragma solidity 0.8.13;

interface IOptionToken {
    function mint(address _to, uint256 _amount) external;
    function exercise(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient
    ) external returns (uint256);
    function paymentToken() external returns (address);
    function underlyingToken() external returns (address);
    function router() external returns (address);
    function gauge() external returns (address);
    function getDiscountedPrice(uint256 _amount) external view returns (uint256);

}

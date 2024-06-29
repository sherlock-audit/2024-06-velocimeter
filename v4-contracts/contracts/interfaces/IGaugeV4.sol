pragma solidity 0.8.13;

interface IGaugeV4 {
    function left(address token) external view returns (uint);

    function notifyRewardAmount(address token, uint amount) external;

    function depositWithLock(
        address account,
        uint256 amount,
        uint256 _lockDuration
    ) external;

    function depositFor(address account, uint256 amount) external;
}

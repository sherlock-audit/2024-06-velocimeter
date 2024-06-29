pragma solidity ^0.8.13;

interface IGaugePlugin {
    function checkGaugeCreationAllowance(
        address,
        address,
        address
    ) external view returns (bool);

    function checkGaugePauseAllowance(
        address,
        address
    ) external view returns (bool);

    function checkGaugeRestartAllowance(
        address,
        address
    ) external view returns (bool);

    function checkGaugeKillAllowance(
        address,
        address
    ) external view returns (bool);
}

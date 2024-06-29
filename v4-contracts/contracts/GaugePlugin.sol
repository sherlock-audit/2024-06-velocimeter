// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "contracts/interfaces/IGaugePlugin.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract GaugePlugin is IGaugePlugin, Ownable {
    address public governor; // credibly neutral party similar to Curve's Emergency DAO
    mapping(address => bool) public isWhitelistedForGaugeCreation; // token => whitelist for permissionless gauge creation

    constructor(address flow, address weth, address _governor) {
        governor = _governor;
        isWhitelistedForGaugeCreation[flow] = true;
        isWhitelistedForGaugeCreation[weth] = true;
    }

    event WhitelistedForGaugeCreation(
        address indexed whitelister,
        address indexed token
    );
    event BlacklistedForGaugeCreation(
        address indexed blacklister,
        address indexed token
    );
    event GovernorSet(address indexed _newGovernor);

    function setGovernor(address _governor) public onlyOwner {
        governor = _governor;
        emit GovernorSet(_governor);
    }

    function whitelistForGaugeCreation(address _token) public {
        require(msg.sender == governor);
        _whitelistForGaugeCreation(_token);
    }

    function _whitelistForGaugeCreation(address _token) internal {
        require(!isWhitelistedForGaugeCreation[_token]);
        isWhitelistedForGaugeCreation[_token] = true;
        emit WhitelistedForGaugeCreation(msg.sender, _token);
    }

    function blacklistForGaugeCreation(address _token) public {
        require(msg.sender == governor);
        _blacklistForGaugeCreation(_token);
    }

    function _blacklistForGaugeCreation(address _token) internal {
        require(isWhitelistedForGaugeCreation[_token]);
        isWhitelistedForGaugeCreation[_token] = false;
        emit BlacklistedForGaugeCreation(msg.sender, _token);
    }

    function checkGaugeCreationAllowance(
        address caller,
        address tokenA,
        address tokenB
    ) external view returns (bool) {
        return
            isWhitelistedForGaugeCreation[tokenA] ||
            isWhitelistedForGaugeCreation[tokenB];
    }

    function checkGaugePauseAllowance(
        address caller,
        address gauge
    ) external view returns (bool) {
        return false;
    }

    function checkGaugeRestartAllowance(
        address caller,
        address gauge
    ) external view returns (bool) {
        return false;
    }

    function checkGaugeKillAllowance(
        address caller,
        address gauge
    ) external view returns (bool) {
        return false;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import 'contracts/interfaces/IGaugeFactory.sol';
import 'contracts/ProxyGauge.sol';
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract ProxyGaugeFactory is IGaugeFactory, Ownable {

    address public immutable flow;
    address[] public gauges;
    mapping(address => address) public isWhitelisted;

    constructor( address _flow) {
        flow = _flow;
    }
 
    function deployGauge(address _notifyAddress,address _pairAddress,string memory _symbol) external onlyOwner returns (address) {
        address last_gauge = address(new ProxyGauge(flow,_notifyAddress,_symbol));
        if(_pairAddress == address(0)) {
            _pairAddress = last_gauge;
        }
        isWhitelisted[_pairAddress] = last_gauge;
        return last_gauge;
    } 

    function createGauge(address _pool, address _external_bribe, address _ve, bool isPair, address[] memory allowedRewards) external returns (address) {
        require(isWhitelisted[_pool] != address(0),"!whitelisted");
        gauges.push(isWhitelisted[_pool]);
        return isWhitelisted[_pool];
    }

    function whitelist(address _gauge) external onlyOwner {
        isWhitelisted[_gauge] = _gauge;
    }

    function blacklist(address _gauge) external onlyOwner {
        isWhitelisted[_gauge] = address(0);
    }

}

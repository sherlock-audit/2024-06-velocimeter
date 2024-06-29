// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import 'contracts/interfaces/IGaugeFactory.sol';
import 'contracts/GaugeV4.sol';
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract GaugeFactoryV4 is IGaugeFactory, Ownable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    address public last_gauge;
    address public oFlow;

    event OFlowSet(address indexed _oFlow);
    event OFlowUpdatedFor(address indexed _gauge);
    event OTokenAddedFor(address indexed _gauge,address indexed _oToken);
    event OTokenRemovedFor(address indexed _gauge,address indexed _oToken);

    function createGauge(address _pool, address _external_bribe, address _ve, bool isPair, address[] memory allowedRewards) external returns (address) {
        last_gauge = address(new GaugeV4(_pool, _external_bribe, _ve, msg.sender, oFlow, address(this), isPair, allowedRewards));
        if (oFlow != address(0)) {
            IAccessControl(oFlow).grantRole(MINTER_ROLE, last_gauge);
        }
        return last_gauge;
    }

    function setOFlow(address _oFlow) external onlyOwner {
        oFlow = _oFlow;
        emit OFlowSet(_oFlow);
    }

    function updateOFlowFor(address _gauge) external onlyOwner {
        GaugeV4(_gauge).setOFlow(oFlow);
        emit OFlowUpdatedFor(_gauge);
    }

    function addOTokenFor(address _gauge,address _oToken) external onlyOwner{
        GaugeV4(_gauge).addOToken(_oToken);
        emit OTokenAddedFor(_gauge,_oToken);
    }

    function removeOTokenFor(address _gauge,address _oToken) external onlyOwner{
        GaugeV4(_gauge).removeOToken(_oToken);
        emit OTokenRemovedFor(_gauge,_oToken);
    }
}

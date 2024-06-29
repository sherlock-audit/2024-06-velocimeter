// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import 'contracts/interfaces/IPairFactory.sol';
import 'contracts/interfaces/IVoter.sol';
import 'contracts/Pair.sol';
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract PairFactory is IPairFactory, Ownable {

    bool public isPausedAll;
    mapping(address => bool) public isPausedOverride; 
    uint256 public stableFee;
    uint256 public volatileFee;
    uint256 public constant MAX_FEE = 500; // 5%
    address public voter;
    address public tank;
    address public deployer;

    mapping(address => mapping(address => mapping(bool => address))) public getPair;
    address[] public allPairs;
    mapping(address => bool) public isPair; // simplified check if its a pair, given that `stable` flag might not be available in peripherals
    mapping(address => uint256) public feesOverrides;

    address internal _temp0;
    address internal _temp1;
    bool internal _temp;

    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint);
    event VoterSet(address indexed setter, address indexed voter);
    event TankSet(address indexed setter, address indexed tank);
    event Paused(address indexed pauser, bool paused);
    event PausedPair(address indexed pauser,address pair, bool paused);

    event FeeSet(address indexed setter, bool stable, uint256 fee);

    constructor() {
        stableFee = 3; // 0.03%
        volatileFee = 25; // 0.25%
        deployer = msg.sender;
    }

    function setVoter(address _voter) external {
        require(voter == address(0), 'The voter has already been set.');
        // have to make sure that this can be set to the voter address during init script
        require(msg.sender == deployer, 'Not authorised to set voter.');
        voter = _voter;
        emit VoterSet(msg.sender, _voter);
    }

    function setTank(address _tank) external onlyOwner {
        tank = _tank;
        emit TankSet(msg.sender, _tank);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function setPause(bool _state) external onlyOwner {
        isPausedAll = _state;
        emit Paused(msg.sender, _state);
    }

    function setPausePair(address _pair,bool _state) external onlyOwner {
        isPausedOverride[_pair] = _state;
        emit PausedPair(msg.sender,_pair, _state);
    }

    function setFee(bool _stable, uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, 'fee too high');
        if (_stable) {
            stableFee = _fee;
        } else {
            volatileFee = _fee;
        }
        emit FeeSet(msg.sender, _stable, _fee);
    }

    function setFeesOverrides(address _pair, uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, "fee too high");
        feesOverrides[_pair] = _fee;
    }

    function isPaused(address _pair) external view returns(bool) {
        bool _paused = isPausedOverride[_pair];
        return isPausedAll || _paused;
    }

    function getFee(address _pair) public view returns(uint256) {
    	/// to get base fees, call `stableFee()` or `volatileFee()`
    	uint _fo = feesOverrides[_pair];
    	if( _fo != 0 ) {
    		return _fo;
    	} else {
    		return IPair(_pair).stable() ? stableFee : volatileFee;
    	}
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(Pair).creationCode);
    }

    function getInitializable() external view returns (address, address, bool) {
        return (_temp0, _temp1, _temp);
    }

    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair) {
        require(tokenA != tokenB, 'IA'); // Pair: IDENTICAL_ADDRESSES
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ZA'); // Pair: ZERO_ADDRESS
        require(getPair[token0][token1][stable] == address(0), 'PE'); // Pair: PAIR_EXISTS - single check is sufficient
        if (stable) {
            require(IVoter(voter).governor() == tx.origin, "not governor");
        }
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable)); // notice salt includes stable as well, 3 parameters
        (_temp0, _temp1, _temp) = (token0, token1, stable);
        pair = address(new Pair{salt:salt}());
        getPair[token0][token1][stable] = pair;
        getPair[token1][token0][stable] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        isPair[pair] = true;
        emit PairCreated(token0, token1, stable, pair, allPairs.length);
    }
}

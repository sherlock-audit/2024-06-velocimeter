// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IOptionToken.sol";

contract AirdropClaim is ReentrancyGuard {

    using SafeERC20 for IERC20;


    uint256 constant public PRECISION = 1000;
    uint256 public totalAirdrop;
    uint256 public totalToReceive;
    uint256 public totalWalletsIncluded;
    uint256 public totalWalletsClaimed;
    uint256 public totalVeFLOWClaimed;

    bool public seeded;
    
    address public owner;
    address public msig;
    address public optionToken;
    IERC20 public token;

    
    uint public constant LOCK = 52 * 7 * 86400;
    

    mapping(address => uint) public claimableAmount;
    mapping(address => bool) public userClaimed;

    modifier onlyOwner {
        require(msg.sender == owner, 'not owner');
        _;
    }

    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event Claimed(address _who, uint amount);
    event AirdropSet(uint walletAdded, uint walletTotal, uint veCHRAdded, uint veCHRTotal);


    constructor(address _token, address _optionToken, address _msig) {
        owner = msg.sender;
        token = IERC20(_token);
        optionToken = _optionToken;
        msig = _msig;
    }


    function deposit(uint256 amount) external {
        require(msg.sender == owner);
        token.safeTransferFrom(msg.sender, address(this), amount);
        totalAirdrop += amount;
        seeded = true;
        emit Deposit(amount);
    }

    function withdraw(uint256 amount, address _token) external {
        require(msg.sender == owner);
        IERC20(_token).safeTransfer(msig, amount);
        totalAirdrop -= amount;

        emit Withdraw(amount);
    }
    
    /* 
        OWNER FUNCTIONS
    */

    function setOwner(address _owner) external onlyOwner{
        require(_owner != address(0));
        owner = _owner;
    }

    /// @notice set user infromation for the airdrop claim
    /// @param _who who can receive the airdrop
    /// @param _amount the amount he can receive
    function setAirdropReceivers(address[] memory _who, uint256[] memory _amount) external onlyOwner {
        require(_who.length == _amount.length);

        uint _totalToReceive;
        for (uint i = 0; i < _who.length; i++) {
            claimableAmount[_who[i]] += _amount[i];
            _totalToReceive += _amount[i];
            userClaimed[_who[i]] = false;
        }
        totalToReceive += _totalToReceive;
        totalWalletsIncluded += _who.length;
        emit AirdropSet(_who.length,totalWalletsIncluded, _totalToReceive, totalToReceive);
        
    }



    function claim() external nonReentrant returns(uint _tokenId){

        // check user has airdrop available
        require(claimableAmount[msg.sender] != 0, "No airdrop available");

        uint amount = claimableAmount[msg.sender];
        claimableAmount[msg.sender] = 0;
        token.approve(optionToken, 0);
        token.approve(optionToken, amount);

        IOptionToken(optionToken).mint(msg.sender, amount);

        userClaimed[msg.sender] = true;
        totalWalletsClaimed += 1;
        totalVeFLOWClaimed += amount;

        emit Claimed(msg.sender, amount);
    }


    function claimable(address user) public view returns(uint _claimable){
        _claimable = claimableAmount[user];
    }
    
    
    function emergencyWithdraw(address _token, uint amount) onlyOwner external{
        IERC20(_token).safeTransfer(msig, amount);
        totalAirdrop -= amount;

        emit Withdraw(amount);
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

contract TestVotingEscrow {
    uint256 public totalSupply = 0;
    address public immutable lpToken;
    address public immutable baseToken;
    address immutable public owner;
    mapping(uint => uint) balances;
    mapping(uint => address) public ownerOf;
    constructor(address _lpToken,address _token) {
        lpToken = _lpToken;
        baseToken = _token;
        owner = msg.sender;
    }

    uint tokenId = 0;

    function create_lock(uint amount, uint) external {
        balances[++tokenId] = amount;
        ownerOf[tokenId] = msg.sender;
        totalSupply += amount;
    }

    function balanceOfNFT(uint) external view returns (uint) {
        return totalSupply;
    }

    function isApprovedOrOwner(address, uint) external pure returns (bool) {
        return true;
    }
}

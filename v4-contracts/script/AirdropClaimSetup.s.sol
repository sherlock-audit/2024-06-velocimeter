// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// Scripting tool
import {Script} from "../lib/forge-std/src/Script.sol";
import {IFlow} from "../contracts/interfaces/IFlow.sol";
import {AirdropClaim} from "../contracts/AirdropClaim.sol";

contract AirdropClaimSetup is Script {
    // TODO: set variables
    address private constant FLOW = address(0);
    address private constant TEAM_MULTI_SIG = address(0);
    address private constant AIRDROP_CLAIM_CONTRACT = address(0);
    uint private constant TOTAL_AIRDROP_AMOUNT = 0;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        IFlow(FLOW).approve(AIRDROP_CLAIM_CONTRACT, TOTAL_AIRDROP_AMOUNT);
        AirdropClaim(AIRDROP_CLAIM_CONTRACT).deposit(TOTAL_AIRDROP_AMOUNT);

        vm.stopBroadcast();
    }
}

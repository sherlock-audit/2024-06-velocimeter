// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// Scripting tool
import {Script} from "../lib/forge-std/src/Script.sol";
import {IFlow} from "../contracts/interfaces/IFlow.sol";
import {AirdropClaim} from "../contracts/AirdropClaim.sol";

contract AirdropClaimDeployment is Script {
    // TODO: set variables
    address private constant BVM = 0xd386a121991E51Eab5e3433Bf5B1cF4C8884b47a;
    address private constant OBVM = 0x762eb51D2e779EeEc9B239FFB0B2eC8262848f3E;
    address private constant TEAM_MULTI_SIG = 0xfA89A4C7F79Dc4111c116a0f01061F4a7D9fAb73;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // AirdropClaim
        AirdropClaim airdropClaim = new AirdropClaim(
            BVM,
            OBVM,
            TEAM_MULTI_SIG
        );

        //airdropClaim.setOwner(TEAM_MULTI_SIG);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// Scripting tool
import {Script} from "../lib/forge-std/src/Script.sol";
import {Minter} from "../contracts/Minter.sol";

contract StartActivePeriod is Script {
    // TODO: set variables
    address private constant MINTER_CONTRACT =
        0xAA28F5F63a9DC90640abF7F008726460127a4Da6;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        Minter(MINTER_CONTRACT).startActivePeriod();

        vm.stopBroadcast();
    }
}

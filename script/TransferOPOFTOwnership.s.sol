// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "../src/wHYPEOFT.sol";
import "../utils/L2Constants.sol";

// forge script script/TransferOPOFTOwnership.s.sol:TransferOPOFTOwnership --rpc-url $OPTIMISM_RPC --broadcast
contract TransferOPOFTOwnership is Script, L2Constants {

    function run() public {
        vm.startBroadcast();

        WHYPEOFT oft = WHYPEOFT(OFT_ADDRESS);

        oft.setDelegate(OP_CONTRACT_CONTROLLER);
        oft.transferOwnership(OP_CONTRACT_CONTROLLER);

        console.log("OFT new owner: %s", oft.owner());

        vm.stopBroadcast();
    }
}

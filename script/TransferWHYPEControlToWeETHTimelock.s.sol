// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "../utils/GnosisHelpers.sol";
import "../utils/L2Constants.sol";

interface IWHYPEAdapterControl {
    function owner() external view returns (address);
    function setDelegate(address delegate) external;
    function transferOwnership(address newOwner) external;
}

interface IEndpointDelegates {
    function delegates(address oapp) external view returns (address);
}

/**
 * @notice Generates and simulates the HyperEVM Safe bundle that moves WHYPE
 *         adapter ownership and LayerZero delegate control to the weETH timelock.
 *
 * forge script script/TransferWHYPEControlToWeETHTimelock.s.sol:TransferWHYPEControlToWeETHTimelock -vvv
 *
 *         HYPEREVM_RPC may override the default HyperEVM RPC.
 */
contract TransferWHYPEControlToWeETHTimelock is GnosisHelpers, L2Constants {
    string constant OUTPUT_PATH = "output/whype-control-transfer-hyperevm.json";

    function run() external {
        vm.createSelectFork(vm.envOr("HYPEREVM_RPC", HYPE_RPC_URL));
        require(
            keccak256(bytes(vm.toString(block.chainid))) == keccak256(bytes(HYPE_CHAIN_ID)),
            "RPC chain id does not match HyperEVM"
        );

        IWHYPEAdapterControl adapter = IWHYPEAdapterControl(OFT_ADAPTER_ADDRESS);
        IEndpointDelegates endpoint = IEndpointDelegates(HYPE_ENDPOINT);

        require(adapter.owner() == HYPE_LEGACY_CONTRACT_CONTROLLER, "Unexpected current owner");
        require(
            endpoint.delegates(OFT_ADAPTER_ADDRESS) == HYPE_LEGACY_CONTRACT_CONTROLLER, "Unexpected current delegate"
        );
        require(HYPE_CONTRACT_CONTROLLER.code.length > 0, "New controller has no code");

        bytes memory setDelegate =
            abi.encodeWithSelector(IWHYPEAdapterControl.setDelegate.selector, HYPE_CONTRACT_CONTROLLER);
        bytes memory transferOwnership =
            abi.encodeWithSelector(IWHYPEAdapterControl.transferOwnership.selector, HYPE_CONTRACT_CONTROLLER);

        string memory adapterHex = addressToHex(OFT_ADAPTER_ADDRESS);
        string memory bundle = string.concat(
            _getGnosisHeader(HYPE_CHAIN_ID, addressToHex(HYPE_LEGACY_CONTRACT_CONTROLLER)),
            _getGnosisTransaction(adapterHex, iToHex(setDelegate), "0", false),
            _getGnosisTransaction(adapterHex, iToHex(transferOwnership), "0", true)
        );

        vm.createDir("./output", true);
        vm.writeFile(OUTPUT_PATH, bundle);
        console.log("Bundle written to:", OUTPUT_PATH);

        executeGnosisTransactionBundle(OUTPUT_PATH);

        require(adapter.owner() == HYPE_CONTRACT_CONTROLLER, "Ownership transfer failed");
        require(endpoint.delegates(OFT_ADAPTER_ADDRESS) == HYPE_CONTRACT_CONTROLLER, "Delegate transfer failed");
        console.log("Ownership and delegate verification passed");
    }
}

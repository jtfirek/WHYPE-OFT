// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";
import "../src/wHYPEOFTAdapter.sol";

/**
 * @notice Generates a Gnosis Safe Transaction Builder JSON bundle for configuring
 *         the wHYPEOFTAdapter on HyperEVM to peer with the OP OFT, then simulates
 *         execution on fork.
 *
 * forge script script/ConfigureAdapterForOP.s.sol:ConfigureAdapterForOP \
 *   --rpc-url $HYPEREVM_RPC \
 *   -vvvv
 */
contract ConfigureAdapterForOP is GnosisHelpers, L2Constants {
    using OptionsBuilder for bytes;

    string constant OUTPUT_PATH = "output/hyperevm-adapter-op-config-bundle.json";
    string constant CHAIN_ID = "999";

    function run() external {
        address adapter = OFT_ADAPTER_ADDRESS;
        address opOFT = OFT_ADDRESS;
        uint32 opEid = OP_EID;

        address endpoint = HYPE_ENDPOINT;
        address sendLib = HYPE_SEND_302;
        address receiveLib = HYPE_RECEIVE_302;

        address safeAddress = HYPE_CONTRACT_CONTROLLER;

        // --- 1. setPeer calldata ---
        bytes memory setPeerData = abi.encodeWithSignature(
            "setPeer(uint32,bytes32)",
            opEid,
            bytes32(uint256(uint160(opOFT)))
        );

        // --- 2 & 3. setConfig calldata (send + receive) ---
        address[] memory requiredDVNs = new address[](3);
        requiredDVNs[0] = HYPE_BITGO_DVN;
        requiredDVNs[1] = HYPE_P2P_DVN;
        requiredDVNs[2] = HYPE_USDT0_DVN;

        for (uint i = 0; i < requiredDVNs.length - 1; i++) {
            for (uint j = 0; j < requiredDVNs.length - i - 1; j++) {
                if (requiredDVNs[j] > requiredDVNs[j + 1]) {
                    address temp = requiredDVNs[j];
                    requiredDVNs[j] = requiredDVNs[j + 1];
                    requiredDVNs[j + 1] = temp;
                }
            }
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 3,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(opEid, 2, abi.encode(ulnConfig));

        bytes memory setConfigSendData = abi.encodeWithSelector(
            IMessageLibManager.setConfig.selector,
            adapter,
            sendLib,
            params
        );

        bytes memory setConfigReceiveData = abi.encodeWithSelector(
            IMessageLibManager.setConfig.selector,
            adapter,
            receiveLib,
            params
        );

        // --- 4. setEnforcedOptions calldata ---
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](2);
        enforcedOptions[0] = EnforcedOptionParam({
            eid: opEid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        });
        enforcedOptions[1] = EnforcedOptionParam({
            eid: opEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        });

        bytes memory setEnforcedOptionsData = abi.encodeWithSelector(
            IOAppOptionsType3.setEnforcedOptions.selector,
            enforcedOptions
        );

        // --- Build Gnosis JSON bundle ---
        string memory safeHex = addressToHex(safeAddress);
        string memory adapterHex = addressToHex(adapter);
        string memory endpointHex = addressToHex(endpoint);

        string memory bundle = string.concat(
            _getGnosisHeader(CHAIN_ID, safeHex),
            _getGnosisTransaction(adapterHex, iToHex(setPeerData), "0", false),
            _getGnosisTransaction(endpointHex, iToHex(setConfigSendData), "0", false),
            _getGnosisTransaction(endpointHex, iToHex(setConfigReceiveData), "0", false),
            _getGnosisTransaction(adapterHex, iToHex(setEnforcedOptionsData), "0", true)
        );

        vm.writeFile(OUTPUT_PATH, bundle);
        console.log("Gnosis bundle written to:", OUTPUT_PATH);

        // --- Simulate execution on fork ---
        executeGnosisTransactionBundle(OUTPUT_PATH);

        // --- Verify ---
        bytes32 peer = wHYPEOFTAdapter(adapter).peers(opEid);
        require(
            peer == bytes32(uint256(uint160(opOFT))),
            "Peer not set correctly"
        );
        console.log("Verification passed: adapter peered to OP OFT");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";

/// @dev `delegates` lives on EndpointV2's MessageLibManager but is absent from ILayerZeroEndpointV2.
interface IEndpointDelegates {
    function delegates(address oapp) external view returns (address);
}

/**
 * @notice Replaces the BitGo DVN with the LayerZero Labs DVN in the WHYPE required-DVN
 *         set on every live pathway, leaving P2P and USDT0 (and the 15-confirmation,
 *         3-of-3 shape) untouched.
 *
 *         The WHYPE mesh is hub-and-spoke through the HyperEVM adapter: Ethereum and
 *         Optimism each peer only with HyperEVM, so the pathways are
 *         Ethereum <-> HyperEVM and Optimism <-> HyperEVM. Both the send and receive
 *         library configs are rewritten on each side of each pathway.
 *
 *         Produces one Safe Transaction Builder bundle per chain and simulates each on
 *         a fork of that chain, asserting the resulting on-chain ULN config.
 *
 * forge script script/SwapBitgoDvnForLzDvn.s.sol:SwapBitgoDvnForLzDvn -vvv
 *
 *         RPCs default to the ones in L2Constants and can be overridden with the
 *         ETHEREUM_RPC / OPTIMISM_RPC / HYPEREVM_RPC env vars.
 */
contract SwapBitgoDvnForLzDvn is GnosisHelpers, L2Constants {
    uint32 constant CONFIG_TYPE_ULN = 2;
    uint64 constant CONFIRMATIONS = 15;

    struct PathwaySwap {
        string name;
        string rpcUrl;
        string chainId;
        address safe;
        address endpoint;
        address oapp;
        address sendLib;
        address receiveLib;
        address retiredDvn;
        address replacementDvn;
        address[2] retainedDvns;
        uint32[] dstEids;
    }

    function run() external {
        vm.createDir("./output", true);

        _swap(_ethereum());
        _swap(_optimism());
        _swap(_hyperEVM());
    }

    /*//////////////////////////////////////////////////////////////
                            Per-chain inputs
    //////////////////////////////////////////////////////////////*/

    function _ethereum() internal view returns (PathwaySwap memory) {
        uint32[] memory dstEids = new uint32[](1);
        dstEids[0] = HYPE_EID;

        return PathwaySwap({
            name: "ethereum",
            rpcUrl: vm.envOr("ETHEREUM_RPC", DEPLOYMENT_RPC_URL),
            chainId: DEPLOYMENT_CHAIN_ID,
            safe: DEPLOYMENT_CONTRACT_CONTROLLER,
            endpoint: DEPLOYMENT_ENDPOINT,
            oapp: OFT_ADDRESS,
            sendLib: DEPLOYMENT_SEND_LIB_302,
            receiveLib: DEPLOYMENT_RECEIVE_LIB_302,
            retiredDvn: DEPLOYMENT_BITGO_DVN,
            replacementDvn: DEPLOYMENT_LAYERZERO_DVN,
            retainedDvns: [DEPLOYMENT_P2P_DVN, DEPLOYMENT_USDT0_DVN],
            dstEids: dstEids
        });
    }

    function _optimism() internal view returns (PathwaySwap memory) {
        uint32[] memory dstEids = new uint32[](1);
        dstEids[0] = HYPE_EID;

        return PathwaySwap({
            name: "optimism",
            rpcUrl: vm.envOr("OPTIMISM_RPC", OP_RPC_URL),
            chainId: OP_CHAIN_ID,
            safe: OP_CONTRACT_CONTROLLER,
            endpoint: OP_ENDPOINT,
            oapp: OFT_ADDRESS,
            sendLib: OP_SEND_302,
            receiveLib: OP_RECEIVE_302,
            retiredDvn: OP_BITGO_DVN,
            replacementDvn: OP_LAYERZERO_DVN,
            retainedDvns: [OP_P2P_DVN, OP_USDT0_DVN],
            dstEids: dstEids
        });
    }

    function _hyperEVM() internal view returns (PathwaySwap memory) {
        // The adapter is the hub: it holds a config for each spoke chain.
        uint32[] memory dstEids = new uint32[](2);
        dstEids[0] = DEPLOYMENT_EID;
        dstEids[1] = OP_EID;

        return PathwaySwap({
            name: "hyperevm",
            rpcUrl: vm.envOr("HYPEREVM_RPC", HYPE_RPC_URL),
            chainId: HYPE_CHAIN_ID,
            safe: HYPE_CONTRACT_CONTROLLER,
            endpoint: HYPE_ENDPOINT,
            oapp: OFT_ADAPTER_ADDRESS,
            sendLib: HYPE_SEND_302,
            receiveLib: HYPE_RECEIVE_302,
            retiredDvn: HYPE_BITGO_DVN,
            replacementDvn: HYPE_LAYERZERO_DVN,
            retainedDvns: [HYPE_P2P_DVN, HYPE_USDT0_DVN],
            dstEids: dstEids
        });
    }

    /*//////////////////////////////////////////////////////////////
                        Generate, simulate, verify
    //////////////////////////////////////////////////////////////*/

    function _swap(PathwaySwap memory swap) internal {
        vm.createSelectFork(swap.rpcUrl);
        require(
            keccak256(bytes(vm.toString(block.chainid))) == keccak256(bytes(swap.chainId)),
            "RPC chain id does not match the configured chain"
        );

        address[] memory requiredDvns = _sortedRequiredDvns(swap);

        _assertPreconditions(swap, requiredDvns);

        SetConfigParam[] memory params = new SetConfigParam[](swap.dstEids.length);
        bytes memory ulnConfig = abi.encode(
            UlnConfig({
                confirmations: CONFIRMATIONS,
                requiredDVNCount: 3,
                optionalDVNCount: 0,
                optionalDVNThreshold: 0,
                requiredDVNs: requiredDvns,
                optionalDVNs: new address[](0)
            })
        );
        for (uint256 i = 0; i < swap.dstEids.length; i++) {
            params[i] = SetConfigParam(swap.dstEids[i], CONFIG_TYPE_ULN, ulnConfig);
        }

        bytes memory setSendConfig =
            abi.encodeWithSelector(IMessageLibManager.setConfig.selector, swap.oapp, swap.sendLib, params);
        bytes memory setReceiveConfig =
            abi.encodeWithSelector(IMessageLibManager.setConfig.selector, swap.oapp, swap.receiveLib, params);

        string memory endpointHex = addressToHex(swap.endpoint);
        string memory bundle = string.concat(
            _getGnosisHeader(swap.chainId, addressToHex(swap.safe)),
            _getGnosisTransaction(endpointHex, iToHex(setSendConfig), "0", false),
            _getGnosisTransaction(endpointHex, iToHex(setReceiveConfig), "0", true)
        );

        string memory outputPath = string.concat("output/whype-dvn-swap-", swap.name, ".json");
        vm.writeFile(outputPath, bundle);
        console.log("Bundle written to:", outputPath);

        executeGnosisTransactionBundle(outputPath);

        _assertPostconditions(swap, requiredDvns);
        console.log("Verification passed for:", swap.name);
    }

    /// @dev The ULN rejects unsorted required DVN arrays with LZ_ULN_Unsorted().
    function _sortedRequiredDvns(PathwaySwap memory swap) internal pure returns (address[] memory) {
        address[] memory dvns = new address[](3);
        dvns[0] = swap.retainedDvns[0];
        dvns[1] = swap.retainedDvns[1];
        dvns[2] = swap.replacementDvn;

        for (uint256 i = 0; i < dvns.length - 1; i++) {
            for (uint256 j = 0; j < dvns.length - i - 1; j++) {
                if (dvns[j] > dvns[j + 1]) {
                    address temp = dvns[j];
                    dvns[j] = dvns[j + 1];
                    dvns[j + 1] = temp;
                }
            }
        }

        return dvns;
    }

    /// @dev Guards against generating a bundle from stale assumptions about the live config.
    function _assertPreconditions(PathwaySwap memory swap, address[] memory requiredDvns) internal view {
        require(
            IEndpointDelegates(swap.endpoint).delegates(swap.oapp) == swap.safe,
            "Safe is not the OApp delegate"
        );
        require(swap.replacementDvn.code.length > 0, "Replacement DVN has no code");

        for (uint256 i = 0; i < swap.dstEids.length; i++) {
            _requireContainsDvn(swap, swap.sendLib, swap.dstEids[i], swap.retiredDvn, true);
            _requireContainsDvn(swap, swap.receiveLib, swap.dstEids[i], swap.retiredDvn, true);
            _requireContainsDvn(swap, swap.sendLib, swap.dstEids[i], swap.replacementDvn, false);
            _requireContainsDvn(swap, swap.receiveLib, swap.dstEids[i], swap.replacementDvn, false);

            // The retained DVNs must survive the swap untouched.
            for (uint256 j = 0; j < requiredDvns.length; j++) {
                if (requiredDvns[j] == swap.replacementDvn) continue;
                _requireContainsDvn(swap, swap.sendLib, swap.dstEids[i], requiredDvns[j], true);
                _requireContainsDvn(swap, swap.receiveLib, swap.dstEids[i], requiredDvns[j], true);
            }
        }
    }

    function _assertPostconditions(PathwaySwap memory swap, address[] memory requiredDvns) internal view {
        for (uint256 i = 0; i < swap.dstEids.length; i++) {
            _requireUlnConfig(swap, swap.sendLib, swap.dstEids[i], requiredDvns);
            _requireUlnConfig(swap, swap.receiveLib, swap.dstEids[i], requiredDvns);
        }
    }

    function _requireUlnConfig(
        PathwaySwap memory swap,
        address lib,
        uint32 dstEid,
        address[] memory requiredDvns
    ) internal view {
        UlnConfig memory config = _readUlnConfig(swap, lib, dstEid);

        require(config.confirmations == CONFIRMATIONS, "Unexpected confirmations");
        require(config.requiredDVNCount == 3, "Unexpected required DVN count");
        require(config.optionalDVNCount == 0, "Unexpected optional DVN count");
        require(config.optionalDVNThreshold == 0, "Unexpected optional DVN threshold");
        require(config.requiredDVNs.length == requiredDvns.length, "Unexpected required DVN length");
        for (uint256 i = 0; i < requiredDvns.length; i++) {
            require(config.requiredDVNs[i] == requiredDvns[i], "Unexpected required DVN");
        }
    }

    function _requireContainsDvn(
        PathwaySwap memory swap,
        address lib,
        uint32 dstEid,
        address dvn,
        bool expected
    ) internal view {
        UlnConfig memory config = _readUlnConfig(swap, lib, dstEid);

        bool found;
        for (uint256 i = 0; i < config.requiredDVNs.length; i++) {
            if (config.requiredDVNs[i] == dvn) found = true;
        }
        require(found == expected, expected ? "Expected DVN missing from live config" : "Unexpected DVN already live");
    }

    function _readUlnConfig(PathwaySwap memory swap, address lib, uint32 dstEid)
        internal
        view
        returns (UlnConfig memory)
    {
        bytes memory raw =
            ILayerZeroEndpointV2(swap.endpoint).getConfig(swap.oapp, lib, dstEid, CONFIG_TYPE_ULN);
        return abi.decode(raw, (UlnConfig));
    }
}

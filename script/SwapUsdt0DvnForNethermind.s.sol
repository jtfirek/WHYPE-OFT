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

interface IOwnable {
    function owner() external view returns (address);
}

interface ITimelockBatch {
    function PROPOSER_ROLE() external view returns (bytes32);
    function EXECUTOR_ROLE() external view returns (bytes32);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function getMinDelay() external view returns (uint256);
    function isOperation(bytes32 id) external view returns (bool);
    function isOperationPending(bytes32 id) external view returns (bool);
    function isOperationReady(bytes32 id) external view returns (bool);
    function isOperationDone(bytes32 id) external view returns (bool);
    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external pure returns (bytes32);
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external payable;
}

/**
 * @notice Replaces the USDT0 DVN with the Nethermind DVN in the WHYPE required-DVN set on
 *         every live pathway. The required set becomes P2P, LayerZero Labs and Nethermind
 *         (3-of-3, sorted), confirmations stay at 15, and optionalDVNCount is stored as
 *         NIL (255) so the pathway never inherits optional DVNs from the LayerZero default.
 *
 *         The WHYPE mesh is hub-and-spoke through the HyperEVM adapter, so the pathways are
 *         Ethereum <-> HyperEVM and Optimism <-> HyperEVM. Both the send and receive library
 *         configs are rewritten on each side, one setConfig call per (remote eid, library).
 *
 *         Owner and LayerZero delegate are the timelocks on every chain, so each chain gets two
 *         Safe Transaction Builder bundles: scheduleBatch and executeBatch on the timelock, with
 *         identical targets, values, payloads, predecessor and salt. Each pair is simulated on a
 *         fork as the real Safe: executeBatch must revert one second before the delay and
 *         succeed at the delay, then the resulting ULN config is asserted.
 *
 * forge script script/SwapUsdt0DvnForNethermind.s.sol:SwapUsdt0DvnForNethermind -vvv
 *
 *         RPCs default to the ones in L2Constants and can be overridden with the
 *         ETHEREUM_RPC / OPTIMISM_RPC / HYPEREVM_RPC env vars.
 */
contract SwapUsdt0DvnForNethermind is GnosisHelpers, L2Constants {
    uint32 constant CONFIG_TYPE_ULN = 2;
    uint64 constant CONFIRMATIONS = 15;
    uint8 constant REQUIRED_DVN_COUNT = 3;
    uint8 constant NIL_DVN_COUNT = type(uint8).max;

    bytes32 constant PREDECESSOR = bytes32(0);
    bytes32 constant SALT = keccak256("WHYPE: replace USDT0 DVN with Nethermind");

    struct PathwaySwap {
        string name;
        string rpcUrl;
        string chainId;
        address safe;
        address timelock;
        uint256 delay;
        address endpoint;
        address oapp;
        address sendLib;
        address receiveLib;
        address retiredDvn;
        address replacementDvn;
        address[2] retainedDvns;
        uint32[] dstEids;
    }

    struct Batch {
        address[] targets;
        uint256[] values;
        bytes[] payloads;
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
            safe: L1_TIMELOCK_SAFE,
            timelock: L1_TIMELOCK,
            delay: L1_TIMELOCK_MIN_DELAY,
            endpoint: DEPLOYMENT_ENDPOINT,
            oapp: OFT_ADDRESS,
            sendLib: DEPLOYMENT_SEND_LIB_302,
            receiveLib: DEPLOYMENT_RECEIVE_LIB_302,
            retiredDvn: DEPLOYMENT_USDT0_DVN,
            replacementDvn: DEPLOYMENT_NETHERMIND_DVN,
            retainedDvns: [DEPLOYMENT_P2P_DVN, DEPLOYMENT_LAYERZERO_DVN],
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
            safe: L2_TIMELOCK_SAFE,
            timelock: L2_TIMELOCK,
            delay: L2_TIMELOCK_MIN_DELAY,
            endpoint: OP_ENDPOINT,
            oapp: OFT_ADDRESS,
            sendLib: OP_SEND_302,
            receiveLib: OP_RECEIVE_302,
            retiredDvn: OP_USDT0_DVN,
            replacementDvn: OP_NETHERMIND_DVN,
            retainedDvns: [OP_P2P_DVN, OP_LAYERZERO_DVN],
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
            safe: L2_TIMELOCK_SAFE,
            timelock: L2_TIMELOCK,
            delay: L2_TIMELOCK_MIN_DELAY,
            endpoint: HYPE_ENDPOINT,
            oapp: OFT_ADAPTER_ADDRESS,
            sendLib: HYPE_SEND_302,
            receiveLib: HYPE_RECEIVE_302,
            retiredDvn: HYPE_USDT0_DVN,
            replacementDvn: HYPE_NETHERMIND_DVN,
            retainedDvns: [HYPE_P2P_DVN, HYPE_LAYERZERO_DVN],
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
        console.log("Fork:", swap.name, "block", block.number);

        address[] memory requiredDvns = _sortedRequiredDvns(swap);

        _assertPreconditions(swap, requiredDvns);

        Batch memory batch = _buildBatch(swap, requiredDvns);
        ITimelockBatch timelock = ITimelockBatch(swap.timelock);

        bytes memory scheduleData = abi.encodeCall(
            ITimelockBatch.scheduleBatch,
            (batch.targets, batch.values, batch.payloads, PREDECESSOR, SALT, swap.delay)
        );
        bytes memory executeData = abi.encodeCall(
            ITimelockBatch.executeBatch, (batch.targets, batch.values, batch.payloads, PREDECESSOR, SALT)
        );

        string memory schedulePath = _writeBundle(swap, "schedule", scheduleData);
        string memory executePath = _writeBundle(swap, "execute", executeData);

        bytes32 id = timelock.hashOperationBatch(batch.targets, batch.values, batch.payloads, PREDECESSOR, SALT);
        console.log("Timelock operation id:", vm.toString(id));
        require(!timelock.isOperation(id), "Operation already exists on the timelock");

        executeGnosisTransactionBundle(schedulePath);
        require(timelock.isOperationPending(id), "scheduleBatch did not register the operation");

        uint256 readyAt = block.timestamp + swap.delay;
        vm.warp(readyAt - 1);
        require(!timelock.isOperationReady(id), "Operation ready before the delay");
        _requireBundleReverts(executePath);

        vm.warp(readyAt);
        require(timelock.isOperationReady(id), "Operation not ready at the delay");
        executeGnosisTransactionBundle(executePath);
        require(timelock.isOperationDone(id), "executeBatch did not complete the operation");

        _assertPostconditions(swap, requiredDvns);
        console.log("Verification passed for:", swap.name);
    }

    function _buildBatch(PathwaySwap memory swap, address[] memory requiredDvns)
        internal
        pure
        returns (Batch memory batch)
    {
        bytes memory ulnConfig = abi.encode(
            UlnConfig({
                confirmations: CONFIRMATIONS,
                requiredDVNCount: REQUIRED_DVN_COUNT,
                optionalDVNCount: NIL_DVN_COUNT,
                optionalDVNThreshold: 0,
                requiredDVNs: requiredDvns,
                optionalDVNs: new address[](0)
            })
        );

        uint256 count = swap.dstEids.length * 2;
        batch.targets = new address[](count);
        batch.values = new uint256[](count);
        batch.payloads = new bytes[](count);

        address[2] memory libs = [swap.sendLib, swap.receiveLib];
        uint256 k;
        for (uint256 i = 0; i < swap.dstEids.length; i++) {
            SetConfigParam[] memory params = new SetConfigParam[](1);
            params[0] = SetConfigParam(swap.dstEids[i], CONFIG_TYPE_ULN, ulnConfig);
            for (uint256 l = 0; l < libs.length; l++) {
                batch.targets[k] = swap.endpoint;
                batch.payloads[k] =
                    abi.encodeWithSelector(IMessageLibManager.setConfig.selector, swap.oapp, libs[l], params);
                k++;
            }
        }
    }

    function _writeBundle(PathwaySwap memory swap, string memory action, bytes memory data)
        internal
        returns (string memory outputPath)
    {
        string memory bundle = string.concat(
            _getGnosisHeader(swap.chainId, addressToHex(swap.safe)),
            _getGnosisTransaction(addressToHex(swap.timelock), iToHex(data), "0", true)
        );
        outputPath = string.concat("output/whype-usdt0-to-nethermind-", swap.name, "-", action, ".json");
        vm.writeFile(outputPath, bundle);
        console.log("Bundle written to:", outputPath);
    }

    function _requireBundleReverts(string memory transactionPath) internal {
        string memory json = vm.readFile(transactionPath);
        address safe = vm.parseJsonAddress(json, ".safeAddress");
        address to = vm.parseJsonAddress(json, ".transactions[0].to");
        bytes memory data = vm.parseJsonBytes(json, ".transactions[0].data");

        vm.prank(safe);
        (bool success,) = to.call(data);
        require(!success, "executeBatch succeeded before the timelock delay");
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
        ITimelockBatch timelock = ITimelockBatch(swap.timelock);
        require(IEndpointDelegates(swap.endpoint).delegates(swap.oapp) == swap.timelock, "Timelock is not the delegate");
        require(IOwnable(swap.oapp).owner() == swap.timelock, "Timelock is not the owner");
        require(timelock.hasRole(timelock.PROPOSER_ROLE(), swap.safe), "Safe is not a timelock proposer");
        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), swap.safe), "Safe is not a timelock executor");
        require(timelock.getMinDelay() == swap.delay, "Unexpected timelock delay");
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
            _requireContainsDvn(swap, swap.sendLib, swap.dstEids[i], swap.retiredDvn, false);
            _requireContainsDvn(swap, swap.receiveLib, swap.dstEids[i], swap.retiredDvn, false);
        }
    }

    function _requireUlnConfig(
        PathwaySwap memory swap,
        address lib,
        uint32 dstEid,
        address[] memory requiredDvns
    ) internal view {
        // Effective config: endpoint.getConfig resolves NIL (255) to an optional count of 0.
        UlnConfig memory config = _readUlnConfig(swap, lib, dstEid);
        require(config.confirmations == CONFIRMATIONS, "Unexpected confirmations");
        require(config.requiredDVNCount == REQUIRED_DVN_COUNT, "Unexpected required DVN count");
        require(config.optionalDVNCount == 0, "Unexpected effective optional DVN count");
        require(config.optionalDVNThreshold == 0, "Unexpected optional DVN threshold");
        require(config.optionalDVNs.length == 0, "Unexpected optional DVNs");
        require(config.requiredDVNs.length == requiredDvns.length, "Unexpected required DVN length");
        for (uint256 i = 0; i < requiredDvns.length; i++) {
            require(config.requiredDVNs[i] == requiredDvns[i], "Unexpected required DVN");
        }

        // Stored config: the NIL sentinel is only visible on the library itself.
        UlnConfig memory stored = UlnBase(lib).getAppUlnConfig(swap.oapp, dstEid);
        require(stored.confirmations == CONFIRMATIONS, "Unexpected stored confirmations");
        require(stored.requiredDVNCount == REQUIRED_DVN_COUNT, "Unexpected stored required DVN count");
        require(stored.optionalDVNCount == NIL_DVN_COUNT, "Stored optional DVN count is not NIL");
        require(stored.optionalDVNThreshold == 0, "Unexpected stored optional DVN threshold");
        require(stored.optionalDVNs.length == 0, "Unexpected stored optional DVNs");
        require(stored.requiredDVNs.length == requiredDvns.length, "Unexpected stored required DVN length");
        for (uint256 i = 0; i < requiredDvns.length; i++) {
            require(stored.requiredDVNs[i] == requiredDvns[i], "Unexpected stored required DVN");
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
        require(found == expected, expected ? "Expected DVN missing from config" : "Unexpected DVN in config");
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

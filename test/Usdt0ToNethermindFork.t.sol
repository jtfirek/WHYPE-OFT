// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {
    ILayerZeroEndpointV2,
    MessagingFee,
    MessagingReceipt,
    Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IReceiveUlnE2 } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/interfaces/IReceiveUlnE2.sol";
import { UlnBase, UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

import "../utils/L2Constants.sol";

/// @dev Worker fees accrue inside the send library and are withdrawn later, so this is
///      where a DVN getting hired for a packet actually shows up.
interface ISendLibFeesNethermind {
    function fees(address worker) external view returns (uint256);
}

interface ITimelockOperations {
    function isOperationPending(bytes32 id) external view returns (bool);
    function isOperationDone(bytes32 id) external view returns (bool);
    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external pure returns (bytes32);
}

/**
 * @notice Fork tests for the USDT0 -> Nethermind DVN swap.
 *
 *         For every live WHYPE pathway this replays the literal scheduleBatch and executeBatch
 *         bundles from output/ as the proposer Safe, checks the timelock delay is enforced, and
 *         then drives a full OFT bridge in both directions against the resulting config:
 *
 *         - outbound: quoteSend + send, which prices and pays every DVN in the new required
 *           set. Nethermind must be paid and USDT0 must not.
 *         - inbound: the old set (P2P, LayerZero Labs, USDT0) verifying a packet is no longer
 *           enough to commit it; Nethermind's verification completes it and lzReceive delivers.
 *
 * forge test --match-path test/Usdt0ToNethermindFork.t.sol --skip DeployConfigureOFT.s.sol -vv
 */
contract Usdt0ToNethermindForkTest is Test, L2Constants {
    uint8 constant PACKET_VERSION = 1;
    uint64 constant CONFIRMATIONS = 15;
    uint32 constant CONFIG_TYPE_ULN = 2;
    uint8 constant NIL_DVN_COUNT = type(uint8).max;
    uint256 constant BRIDGE_AMOUNT = 1e18;

    struct Ctx {
        string name;
        string rpcUrl;
        string schedulePath;
        string executePath;
        address safe;
        address timelock;
        uint256 delay;
        uint32 localEid;
        address endpoint;
        address oapp;
        address token;
        bool isAdapter;
        address sendLib;
        address receiveLib;
        address usdt0Dvn;
        address nethermindDvn;
        address lzDvn;
        address p2pDvn;
    }

    /*//////////////////////////////////////////////////////////////
                                  Tests
    //////////////////////////////////////////////////////////////*/

    function test_Ethereum_To_HyperEVM() public {
        Ctx memory ctx = _ethereum();
        _applyThroughTimelock(ctx, 2);
        _assertSwapped(ctx, HYPE_EID);
        _outbound(ctx, HYPE_EID);
        _inbound(ctx, HYPE_EID, OFT_ADAPTER_ADDRESS);
    }

    function test_Optimism_To_HyperEVM() public {
        Ctx memory ctx = _optimism();
        _applyThroughTimelock(ctx, 2);
        _assertSwapped(ctx, HYPE_EID);
        _outbound(ctx, HYPE_EID);
        _inbound(ctx, HYPE_EID, OFT_ADAPTER_ADDRESS);
    }

    function test_HyperEVM_To_Ethereum() public {
        Ctx memory ctx = _hyperEVM();
        _applyThroughTimelock(ctx, 4);
        _assertSwapped(ctx, DEPLOYMENT_EID);
        _assertSwapped(ctx, OP_EID);
        _outbound(ctx, DEPLOYMENT_EID);
        _inbound(ctx, DEPLOYMENT_EID, OFT_ADDRESS);
    }

    function test_HyperEVM_To_Optimism() public {
        Ctx memory ctx = _hyperEVM();
        _applyThroughTimelock(ctx, 4);
        _assertSwapped(ctx, DEPLOYMENT_EID);
        _assertSwapped(ctx, OP_EID);
        _outbound(ctx, OP_EID);
        _inbound(ctx, OP_EID, OFT_ADDRESS);
    }

    /*//////////////////////////////////////////////////////////////
                             Per-chain context
    //////////////////////////////////////////////////////////////*/

    function _ethereum() internal view returns (Ctx memory) {
        return Ctx({
            name: "ethereum",
            rpcUrl: vm.envOr("ETHEREUM_RPC", DEPLOYMENT_RPC_URL),
            schedulePath: "output/whype-usdt0-to-nethermind-ethereum-schedule.json",
            executePath: "output/whype-usdt0-to-nethermind-ethereum-execute.json",
            safe: L1_TIMELOCK_SAFE,
            timelock: L1_TIMELOCK,
            delay: L1_TIMELOCK_MIN_DELAY,
            localEid: DEPLOYMENT_EID,
            endpoint: DEPLOYMENT_ENDPOINT,
            oapp: OFT_ADDRESS,
            token: OFT_ADDRESS,
            isAdapter: false,
            sendLib: DEPLOYMENT_SEND_LIB_302,
            receiveLib: DEPLOYMENT_RECEIVE_LIB_302,
            usdt0Dvn: DEPLOYMENT_USDT0_DVN,
            nethermindDvn: DEPLOYMENT_NETHERMIND_DVN,
            lzDvn: DEPLOYMENT_LAYERZERO_DVN,
            p2pDvn: DEPLOYMENT_P2P_DVN
        });
    }

    function _optimism() internal view returns (Ctx memory) {
        return Ctx({
            name: "optimism",
            rpcUrl: vm.envOr("OPTIMISM_RPC", OP_RPC_URL),
            schedulePath: "output/whype-usdt0-to-nethermind-optimism-schedule.json",
            executePath: "output/whype-usdt0-to-nethermind-optimism-execute.json",
            safe: L2_TIMELOCK_SAFE,
            timelock: L2_TIMELOCK,
            delay: L2_TIMELOCK_MIN_DELAY,
            localEid: OP_EID,
            endpoint: OP_ENDPOINT,
            oapp: OFT_ADDRESS,
            token: OFT_ADDRESS,
            isAdapter: false,
            sendLib: OP_SEND_302,
            receiveLib: OP_RECEIVE_302,
            usdt0Dvn: OP_USDT0_DVN,
            nethermindDvn: OP_NETHERMIND_DVN,
            lzDvn: OP_LAYERZERO_DVN,
            p2pDvn: OP_P2P_DVN
        });
    }

    function _hyperEVM() internal view returns (Ctx memory) {
        return Ctx({
            name: "hyperevm",
            rpcUrl: vm.envOr("HYPEREVM_RPC", HYPE_RPC_URL),
            schedulePath: "output/whype-usdt0-to-nethermind-hyperevm-schedule.json",
            executePath: "output/whype-usdt0-to-nethermind-hyperevm-execute.json",
            safe: L2_TIMELOCK_SAFE,
            timelock: L2_TIMELOCK,
            delay: L2_TIMELOCK_MIN_DELAY,
            localEid: HYPE_EID,
            endpoint: HYPE_ENDPOINT,
            oapp: OFT_ADAPTER_ADDRESS,
            token: WRAPPED_HYPE_ADDRESS,
            isAdapter: true,
            sendLib: HYPE_SEND_302,
            receiveLib: HYPE_RECEIVE_302,
            usdt0Dvn: HYPE_USDT0_DVN,
            nethermindDvn: HYPE_NETHERMIND_DVN,
            lzDvn: HYPE_LAYERZERO_DVN,
            p2pDvn: HYPE_P2P_DVN
        });
    }

    /*//////////////////////////////////////////////////////////////
                          Timelock replay
    //////////////////////////////////////////////////////////////*/

    /// @dev Forks the chain and replays both bundles as the Safe, around the timelock delay.
    function _applyThroughTimelock(Ctx memory ctx, uint256 expectedSetConfigCalls) internal {
        vm.createSelectFork(ctx.rpcUrl);

        (address scheduleTo, bytes memory scheduleData) = _readSingleTx(ctx, ctx.schedulePath);
        (address executeTo, bytes memory executeData) = _readSingleTx(ctx, ctx.executePath);
        assertEq(scheduleTo, ctx.timelock, "schedule target is not the timelock");
        assertEq(executeTo, ctx.timelock, "execute target is not the timelock");

        bytes32 id = _operationId(ctx, scheduleData, executeData, expectedSetConfigCalls);

        vm.prank(ctx.safe);
        (bool ok,) = scheduleTo.call(scheduleData);
        assertTrue(ok, "scheduleBatch reverted");
        assertTrue(ITimelockOperations(ctx.timelock).isOperationPending(id), "operation not pending");

        uint256 readyAt = block.timestamp + ctx.delay;
        vm.warp(readyAt - 1);
        vm.prank(ctx.safe);
        (ok,) = executeTo.call(executeData);
        assertFalse(ok, "executeBatch succeeded before the delay");

        vm.warp(readyAt);
        vm.prank(ctx.safe);
        (ok,) = executeTo.call(executeData);
        assertTrue(ok, "executeBatch reverted after the delay");
        assertTrue(ITimelockOperations(ctx.timelock).isOperationDone(id), "operation not done");
    }

    function _readSingleTx(Ctx memory ctx, string memory path) internal view returns (address to, bytes memory data) {
        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonAddress(json, ".safeAddress"), ctx.safe, "unexpected Safe");
        assertEq(vm.parseJsonUint(json, ".chainId"), block.chainid, "unexpected chain id");
        assertFalse(vm.keyExistsJson(json, ".transactions[1]"), "bundle has more than one transaction");
        assertEq(vm.parseJsonUint(json, ".transactions[0].value"), 0, "unexpected value");
        to = vm.parseJsonAddress(json, ".transactions[0].to");
        data = vm.parseJsonBytes(json, ".transactions[0].data");
    }

    /// @dev Decodes both calls and checks executeBatch carries the operation scheduleBatch queued.
    function _operationId(
        Ctx memory ctx,
        bytes memory scheduleData,
        bytes memory executeData,
        uint256 expectedSetConfigCalls
    ) internal view returns (bytes32) {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads,
            bytes32 predecessor,
            bytes32 salt,
            uint256 delay
        ) = abi.decode(_stripSelector(scheduleData), (address[], uint256[], bytes[], bytes32, bytes32, uint256));
        assertEq(delay, ctx.delay, "scheduled delay is not the timelock minimum");
        assertEq(targets.length, expectedSetConfigCalls, "unexpected number of setConfig calls");
        for (uint256 i = 0; i < targets.length; i++) {
            assertEq(targets[i], ctx.endpoint, "batch target is not the endpoint");
            assertEq(values[i], 0, "batch value is not zero");
        }

        bytes memory expectedExecute = abi.encodeWithSignature(
            "executeBatch(address[],uint256[],bytes[],bytes32,bytes32)", targets, values, payloads, predecessor, salt
        );
        assertEq(keccak256(executeData), keccak256(expectedExecute), "executeBatch does not match scheduleBatch");

        return ITimelockOperations(ctx.timelock).hashOperationBatch(targets, values, payloads, predecessor, salt);
    }

    function _stripSelector(bytes memory data) internal pure returns (bytes memory args) {
        args = new bytes(data.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = data[i + 4];
        }
    }

    function _assertSwapped(Ctx memory ctx, uint32 remoteEid) internal view {
        address[3] memory expected = _sorted(ctx.p2pDvn, ctx.lzDvn, ctx.nethermindDvn);

        address[2] memory libs = [ctx.sendLib, ctx.receiveLib];
        for (uint256 l = 0; l < libs.length; l++) {
            UlnConfig memory config = _ulnConfig(ctx, libs[l], remoteEid);
            assertEq(config.confirmations, CONFIRMATIONS, "confirmations changed");
            assertEq(config.requiredDVNCount, 3, "required count changed");
            assertEq(config.optionalDVNCount, 0, "effective optional count not zero");
            assertEq(config.optionalDVNThreshold, 0, "optional threshold changed");
            assertEq(config.requiredDVNs.length, 3, "required length changed");
            for (uint256 i = 0; i < 3; i++) {
                assertEq(config.requiredDVNs[i], expected[i], "unexpected required DVN");
                assertTrue(config.requiredDVNs[i] != ctx.usdt0Dvn, "USDT0 still present");
            }

            UlnConfig memory stored = UlnBase(libs[l]).getAppUlnConfig(ctx.oapp, remoteEid);
            assertEq(stored.optionalDVNCount, NIL_DVN_COUNT, "stored optional count is not NIL");
            assertEq(stored.optionalDVNThreshold, 0, "stored optional threshold not zero");
            assertEq(stored.optionalDVNs.length, 0, "stored optional DVNs not empty");
            assertEq(stored.confirmations, CONFIRMATIONS, "stored confirmations changed");
            assertEq(stored.requiredDVNCount, 3, "stored required count changed");
            for (uint256 i = 0; i < 3; i++) {
                assertEq(stored.requiredDVNs[i], expected[i], "unexpected stored required DVN");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 Outbound
    //////////////////////////////////////////////////////////////*/

    /// @dev Prices and sends a real OFT transfer, which exercises every DVN in the new set.
    function _outbound(Ctx memory ctx, uint32 remoteEid) internal {
        address bridger = makeAddr("bridger");

        if (ctx.isAdapter) {
            deal(ctx.token, bridger, BRIDGE_AMOUNT);
            vm.prank(bridger);
            IERC20(ctx.token).approve(ctx.oapp, BRIDGE_AMOUNT);
        } else {
            deal(ctx.token, bridger, BRIDGE_AMOUNT, true);
        }

        SendParam memory sendParam = SendParam({
            dstEid: remoteEid,
            to: _toBytes32(bridger),
            amountLD: BRIDGE_AMOUNT,
            minAmountLD: BRIDGE_AMOUNT,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = IOFT(ctx.oapp).quoteSend(sendParam, false);
        assertGt(fee.nativeFee, 0, "quote returned zero native fee");
        console.log("[%s -> %s] native fee (wei):", ctx.name, vm.toString(remoteEid), fee.nativeFee);

        vm.deal(bridger, fee.nativeFee);
        uint256 balanceBefore = IERC20(ctx.token).balanceOf(bridger);

        ISendLibFeesNethermind lib = ISendLibFeesNethermind(ctx.sendLib);
        uint256 nethermindBefore = lib.fees(ctx.nethermindDvn);
        uint256 lzBefore = lib.fees(ctx.lzDvn);
        uint256 p2pBefore = lib.fees(ctx.p2pDvn);
        uint256 usdt0Before = lib.fees(ctx.usdt0Dvn);

        vm.prank(bridger);
        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) =
            IOFT(ctx.oapp).send{ value: fee.nativeFee }(sendParam, fee, bridger);

        assertTrue(receipt.guid != bytes32(0), "no guid returned");
        assertEq(oftReceipt.amountSentLD, BRIDGE_AMOUNT, "wrong amount sent");
        assertEq(IERC20(ctx.token).balanceOf(bridger), balanceBefore - BRIDGE_AMOUNT, "tokens not debited");

        assertGt(lib.fees(ctx.nethermindDvn), nethermindBefore, "Nethermind DVN was not paid");
        assertGt(lib.fees(ctx.lzDvn), lzBefore, "LayerZero Labs DVN was not paid");
        assertGt(lib.fees(ctx.p2pDvn), p2pBefore, "P2P DVN was not paid");
        assertEq(lib.fees(ctx.usdt0Dvn), usdt0Before, "USDT0 DVN was still paid");
    }

    /*//////////////////////////////////////////////////////////////
                                  Inbound
    //////////////////////////////////////////////////////////////*/

    /// @dev Drives the receive path end to end: DVN verification, commit, then delivery.
    function _inbound(Ctx memory ctx, uint32 remoteEid, address remotePeer) internal {
        address recipient = makeAddr("recipient");
        bytes32 sender = _toBytes32(remotePeer);

        uint64 nonce = ILayerZeroEndpointV2(ctx.endpoint).inboundNonce(ctx.oapp, remoteEid, sender) + 1;
        bytes32 guid = keccak256(abi.encodePacked("whype-usdt0-to-nethermind", ctx.localEid, remoteEid, nonce));

        // OFT message with no compose: sendTo (bytes32) ++ amountSD (uint64), shared decimals are 6.
        uint64 amountSD = uint64(BRIDGE_AMOUNT / 1e12);
        bytes memory message = abi.encodePacked(_toBytes32(recipient), amountSD);

        bytes memory header =
            abi.encodePacked(PACKET_VERSION, nonce, remoteEid, sender, ctx.localEid, _toBytes32(ctx.oapp));
        assertEq(header.length, 81, "malformed packet header");

        bytes32 payloadHash = keccak256(abi.encodePacked(guid, message));

        // The old set must no longer be sufficient.
        _verifyAs(ctx, ctx.p2pDvn, header, payloadHash);
        _verifyAs(ctx, ctx.lzDvn, header, payloadHash);
        _verifyAs(ctx, ctx.usdt0Dvn, header, payloadHash);
        vm.expectRevert(bytes4(keccak256("LZ_ULN_Verifying()")));
        IReceiveUlnE2(ctx.receiveLib).commitVerification(header, payloadHash);

        // Adding Nethermind completes the new set.
        _verifyAs(ctx, ctx.nethermindDvn, header, payloadHash);
        IReceiveUlnE2(ctx.receiveLib).commitVerification(header, payloadHash);

        uint256 balanceBefore = IERC20(ctx.token).balanceOf(recipient);
        ILayerZeroEndpointV2(ctx.endpoint).lzReceive(
            Origin({ srcEid: remoteEid, sender: sender, nonce: nonce }), ctx.oapp, guid, message, ""
        );
        assertEq(IERC20(ctx.token).balanceOf(recipient), balanceBefore + BRIDGE_AMOUNT, "tokens not delivered");
    }

    function _verifyAs(Ctx memory ctx, address dvn, bytes memory header, bytes32 payloadHash) internal {
        vm.prank(dvn);
        IReceiveUlnE2(ctx.receiveLib).verify(header, payloadHash, CONFIRMATIONS);
    }

    /*//////////////////////////////////////////////////////////////
                                 Helpers
    //////////////////////////////////////////////////////////////*/

    function _ulnConfig(Ctx memory ctx, address lib, uint32 remoteEid) internal view returns (UlnConfig memory) {
        bytes memory raw = ILayerZeroEndpointV2(ctx.endpoint).getConfig(ctx.oapp, lib, remoteEid, CONFIG_TYPE_ULN);
        return abi.decode(raw, (UlnConfig));
    }

    function _sorted(address a, address b, address c) internal pure returns (address[3] memory out) {
        out = [a, b, c];
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2 - i; j++) {
                if (out[j] > out[j + 1]) {
                    address tmp = out[j];
                    out[j] = out[j + 1];
                    out[j + 1] = tmp;
                }
            }
        }
    }

    function _toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}

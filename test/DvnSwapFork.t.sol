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
import { UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

import "../utils/L2Constants.sol";

/// @dev Worker fees accrue inside the send library and are withdrawn later, so this is
///      where a DVN getting hired for a packet actually shows up.
interface ISendLibFees {
    function fees(address worker) external view returns (uint256);
}

/**
 * @notice Fork tests for the BitGo -> LayerZero Labs DVN swap.
 *
 *         For every live WHYPE pathway this executes the generated Safe bundle on a fork
 *         of the real chain and then drives a full OFT bridge in both directions against
 *         the resulting config:
 *
 *         - outbound: quoteSend + send, which prices and pays every DVN in the new
 *           required set. A DVN that is not configured for the destination would make
 *           the quote or the send revert here.
 *         - inbound: the new DVN set verifies a packet on the receive library,
 *           commitVerification lands it on the endpoint, and lzReceive delivers the
 *           tokens. This is asserted to fail first when only the OLD set (including
 *           BitGo) has verified, proving the receive side now genuinely requires the
 *           LayerZero Labs DVN.
 *
 * forge test --match-path test/DvnSwapFork.t.sol --skip DeployConfigureOFT.s.sol -vv
 */
contract DvnSwapForkTest is Test, L2Constants {
    uint8 constant PACKET_VERSION = 1;
    uint64 constant CONFIRMATIONS = 15;
    uint32 constant CONFIG_TYPE_ULN = 2;
    uint256 constant BRIDGE_AMOUNT = 1e18;

    struct Ctx {
        string name;
        string rpcUrl;
        string bundlePath;
        uint32 localEid;
        address endpoint;
        address oapp;
        address token;
        bool isAdapter;
        address sendLib;
        address receiveLib;
        address bitgoDvn;
        address lzDvn;
        address p2pDvn;
        address usdt0Dvn;
    }

    /*//////////////////////////////////////////////////////////////
                                  Tests
    //////////////////////////////////////////////////////////////*/

    function test_Ethereum_To_HyperEVM() public {
        Ctx memory ctx = _ethereum();
        _applyBundle(ctx);
        _assertSwapped(ctx, HYPE_EID);
        _outbound(ctx, HYPE_EID);
        _inbound(ctx, HYPE_EID, OFT_ADAPTER_ADDRESS);
    }

    function test_Optimism_To_HyperEVM() public {
        Ctx memory ctx = _optimism();
        _applyBundle(ctx);
        _assertSwapped(ctx, HYPE_EID);
        _outbound(ctx, HYPE_EID);
        _inbound(ctx, HYPE_EID, OFT_ADAPTER_ADDRESS);
    }

    function test_HyperEVM_To_Ethereum() public {
        Ctx memory ctx = _hyperEVM();
        _applyBundle(ctx);
        _assertSwapped(ctx, DEPLOYMENT_EID);
        _outbound(ctx, DEPLOYMENT_EID);
        _inbound(ctx, DEPLOYMENT_EID, OFT_ADDRESS);
    }

    function test_HyperEVM_To_Optimism() public {
        Ctx memory ctx = _hyperEVM();
        _applyBundle(ctx);
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
            bundlePath: "output/whype-dvn-swap-ethereum.json",
            localEid: DEPLOYMENT_EID,
            endpoint: DEPLOYMENT_ENDPOINT,
            oapp: OFT_ADDRESS,
            token: OFT_ADDRESS,
            isAdapter: false,
            sendLib: DEPLOYMENT_SEND_LIB_302,
            receiveLib: DEPLOYMENT_RECEIVE_LIB_302,
            bitgoDvn: DEPLOYMENT_BITGO_DVN,
            lzDvn: DEPLOYMENT_LAYERZERO_DVN,
            p2pDvn: DEPLOYMENT_P2P_DVN,
            usdt0Dvn: DEPLOYMENT_USDT0_DVN
        });
    }

    function _optimism() internal view returns (Ctx memory) {
        return Ctx({
            name: "optimism",
            rpcUrl: vm.envOr("OPTIMISM_RPC", OP_RPC_URL),
            bundlePath: "output/whype-dvn-swap-optimism.json",
            localEid: OP_EID,
            endpoint: OP_ENDPOINT,
            oapp: OFT_ADDRESS,
            token: OFT_ADDRESS,
            isAdapter: false,
            sendLib: OP_SEND_302,
            receiveLib: OP_RECEIVE_302,
            bitgoDvn: OP_BITGO_DVN,
            lzDvn: OP_LAYERZERO_DVN,
            p2pDvn: OP_P2P_DVN,
            usdt0Dvn: OP_USDT0_DVN
        });
    }

    function _hyperEVM() internal view returns (Ctx memory) {
        return Ctx({
            name: "hyperevm",
            rpcUrl: vm.envOr("HYPEREVM_RPC", HYPE_RPC_URL),
            bundlePath: "output/whype-dvn-swap-hyperevm.json",
            localEid: HYPE_EID,
            endpoint: HYPE_ENDPOINT,
            oapp: OFT_ADAPTER_ADDRESS,
            token: WRAPPED_HYPE_ADDRESS,
            isAdapter: true,
            sendLib: HYPE_SEND_302,
            receiveLib: HYPE_RECEIVE_302,
            bitgoDvn: HYPE_BITGO_DVN,
            lzDvn: HYPE_LAYERZERO_DVN,
            p2pDvn: HYPE_P2P_DVN,
            usdt0Dvn: HYPE_USDT0_DVN
        });
    }

    /*//////////////////////////////////////////////////////////////
                            Bundle application
    //////////////////////////////////////////////////////////////*/

    /// @dev Forks the chain and replays the generated Safe bundle as the Safe itself.
    function _applyBundle(Ctx memory ctx) internal {
        vm.createSelectFork(ctx.rpcUrl);

        string memory json = vm.readFile(ctx.bundlePath);
        address safe = vm.parseJsonAddress(json, ".safeAddress");

        for (uint256 i = 0; vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(i), "]")); i++) {
            string memory base = string.concat(".transactions[", vm.toString(i), "]");
            address to = vm.parseJsonAddress(json, string.concat(base, ".to"));
            uint256 value = vm.parseJsonUint(json, string.concat(base, ".value"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(base, ".data"));

            vm.prank(safe);
            (bool ok,) = to.call{ value: value }(data);
            assertTrue(ok, "bundle transaction reverted");
        }
    }

    function _assertSwapped(Ctx memory ctx, uint32 remoteEid) internal view {
        address[3] memory expected = _sorted(ctx.p2pDvn, ctx.usdt0Dvn, ctx.lzDvn);

        address[2] memory libs = [ctx.sendLib, ctx.receiveLib];
        for (uint256 l = 0; l < libs.length; l++) {
            UlnConfig memory config = _ulnConfig(ctx, libs[l], remoteEid);

            assertEq(config.confirmations, CONFIRMATIONS, "confirmations changed");
            assertEq(config.requiredDVNCount, 3, "required count changed");
            assertEq(config.optionalDVNCount, 0, "optional count changed");
            assertEq(config.optionalDVNThreshold, 0, "optional threshold changed");
            assertEq(config.requiredDVNs.length, 3, "required length changed");

            for (uint256 i = 0; i < 3; i++) {
                assertEq(config.requiredDVNs[i], expected[i], "unexpected required DVN");
                assertTrue(config.requiredDVNs[i] != ctx.bitgoDvn, "BitGo still present");
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

        uint256 lzDvnBefore = ISendLibFees(ctx.sendLib).fees(ctx.lzDvn);
        uint256 p2pDvnBefore = ISendLibFees(ctx.sendLib).fees(ctx.p2pDvn);
        uint256 usdt0DvnBefore = ISendLibFees(ctx.sendLib).fees(ctx.usdt0Dvn);
        uint256 bitgoDvnBefore = ISendLibFees(ctx.sendLib).fees(ctx.bitgoDvn);

        vm.prank(bridger);
        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) =
            IOFT(ctx.oapp).send{ value: fee.nativeFee }(sendParam, fee, bridger);

        assertTrue(receipt.guid != bytes32(0), "no guid returned");
        assertEq(oftReceipt.amountSentLD, BRIDGE_AMOUNT, "wrong amount sent");
        assertEq(IERC20(ctx.token).balanceOf(bridger), balanceBefore - BRIDGE_AMOUNT, "tokens not debited");

        assertGt(ISendLibFees(ctx.sendLib).fees(ctx.lzDvn), lzDvnBefore, "LayerZero Labs DVN was not paid");
        assertGt(ISendLibFees(ctx.sendLib).fees(ctx.p2pDvn), p2pDvnBefore, "P2P DVN was not paid");
        assertGt(ISendLibFees(ctx.sendLib).fees(ctx.usdt0Dvn), usdt0DvnBefore, "USDT0 DVN was not paid");
        assertEq(ISendLibFees(ctx.sendLib).fees(ctx.bitgoDvn), bitgoDvnBefore, "BitGo DVN was still paid");
    }

    /*//////////////////////////////////////////////////////////////
                                  Inbound
    //////////////////////////////////////////////////////////////*/

    /// @dev Drives the receive path end to end: DVN verification, commit, then delivery.
    function _inbound(Ctx memory ctx, uint32 remoteEid, address remotePeer) internal {
        address recipient = makeAddr("recipient");
        bytes32 sender = _toBytes32(remotePeer);

        uint64 nonce = ILayerZeroEndpointV2(ctx.endpoint).inboundNonce(ctx.oapp, remoteEid, sender) + 1;
        bytes32 guid = keccak256(abi.encodePacked("whype-dvn-swap", ctx.localEid, remoteEid, nonce));

        // OFT message with no compose: sendTo (bytes32) ++ amountSD (uint64), shared decimals are 6.
        uint64 amountSD = uint64(BRIDGE_AMOUNT / 1e12);
        bytes memory message = abi.encodePacked(_toBytes32(recipient), amountSD);

        bytes memory header = abi.encodePacked(
            PACKET_VERSION, nonce, remoteEid, sender, ctx.localEid, _toBytes32(ctx.oapp)
        );
        assertEq(header.length, 81, "malformed packet header");

        bytes32 payloadHash = keccak256(abi.encodePacked(guid, message));

        // The old set must no longer be sufficient.
        _verifyAs(ctx, ctx.p2pDvn, header, payloadHash);
        _verifyAs(ctx, ctx.usdt0Dvn, header, payloadHash);
        _verifyAs(ctx, ctx.bitgoDvn, header, payloadHash);
        vm.expectRevert(bytes4(keccak256("LZ_ULN_Verifying()")));
        IReceiveUlnE2(ctx.receiveLib).commitVerification(header, payloadHash);

        // Adding the LayerZero Labs DVN completes the new set.
        _verifyAs(ctx, ctx.lzDvn, header, payloadHash);
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
        bytes memory raw =
            ILayerZeroEndpointV2(ctx.endpoint).getConfig(ctx.oapp, lib, remoteEid, CONFIG_TYPE_ULN);
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

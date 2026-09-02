// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import "../utils/GnosisHelpers.sol";
import "../utils/L2Constants.sol";

interface IWHYPEOAppControl {
    function owner() external view returns (address);
    function peers(uint32 eid) external view returns (bytes32);
    function setPeer(uint32 eid, bytes32 peer) external;
    function setDelegate(address delegate) external;
    function transferOwnership(address newOwner) external;
}

interface IEndpointDelegates {
    function delegates(address oapp) external view returns (address);
}

interface IMessageLibManager {
    function setSendLibrary(address oapp, uint32 eid, address newLib) external;
    function setReceiveLibrary(address oapp, uint32 eid, address newLib, uint256 gracePeriod) external;
    function getSendLibrary(address sender, uint32 eid) external view returns (address);
    function isDefaultSendLibrary(address sender, uint32 eid) external view returns (bool);
    function getReceiveLibrary(address receiver, uint32 eid) external view returns (address lib, bool isDefault);
}

interface ITimelock {
    function getMinDelay() external view returns (uint256);
}

/**
 * @notice Generates and simulates three Safe bundles that:
 *         - remove Scroll as a peer on Ethereum and HyperEVM;
 *         - pin send and receive libraries for every remaining peer;
 *         - move Ethereum WHYPE control to the ether.fi L1 timelock; and
 *         - move Optimism and HyperEVM WHYPE control to the ether.fi L2 timelock.
 *
 * forge script script/UpdateWHYPEPeersAndOwnership.s.sol:UpdateWHYPEPeersAndOwnership -vvv
 *
 * RPCs may be overridden with ETHEREUM_RPC, OPTIMISM_RPC, and HYPEREVM_RPC.
 */
contract UpdateWHYPEPeersAndOwnership is GnosisHelpers, L2Constants {
    uint256 constant L1_TIMELOCK_DELAY = 2 days;
    uint256 constant L2_TIMELOCK_DELAY = 3 days;

    struct Call {
        address target;
        bytes data;
    }

    function run() external {
        vm.createDir("./output", true);

        _updateEthereum();
        _updateOptimism();
        _updateHyperEVM();
    }

    function _updateEthereum() internal {
        _selectFork(vm.envOr("ETHEREUM_RPC", DEPLOYMENT_RPC_URL), DEPLOYMENT_CHAIN_ID);
        _assertControl(DEPLOYMENT_ENDPOINT, OFT_ADDRESS, DEPLOYMENT_LEGACY_CONTRACT_CONTROLLER);
        require(
            IWHYPEOAppControl(OFT_ADDRESS).peers(SCROLL_EID) == _toBytes32(OFT_ADDRESS),
            "Unexpected Ethereum -> Scroll peer"
        );
        _assertDefaultLibraries(
            DEPLOYMENT_ENDPOINT, OFT_ADDRESS, HYPE_EID, DEPLOYMENT_SEND_LIB_302, DEPLOYMENT_RECEIVE_LIB_302
        );
        _assertTimelock(DEPLOYMENT_CONTRACT_CONTROLLER, L1_TIMELOCK_DELAY);

        Call[] memory calls = new Call[](5);
        calls[0] = _setSendLibrary(DEPLOYMENT_ENDPOINT, OFT_ADDRESS, HYPE_EID, DEPLOYMENT_SEND_LIB_302);
        calls[1] = _setReceiveLibrary(DEPLOYMENT_ENDPOINT, OFT_ADDRESS, HYPE_EID, DEPLOYMENT_RECEIVE_LIB_302);
        calls[2] = Call(OFT_ADDRESS, _clearPeer(SCROLL_EID));
        calls[3] = Call(
            OFT_ADDRESS, abi.encodeWithSelector(IWHYPEOAppControl.setDelegate.selector, DEPLOYMENT_CONTRACT_CONTROLLER)
        );
        calls[4] = Call(
            OFT_ADDRESS,
            abi.encodeWithSelector(IWHYPEOAppControl.transferOwnership.selector, DEPLOYMENT_CONTRACT_CONTROLLER)
        );

        _writeAndExecute(
            DEPLOYMENT_CHAIN_ID, DEPLOYMENT_LEGACY_CONTRACT_CONTROLLER, calls, "output/whype-update-ethereum.json"
        );

        require(IWHYPEOAppControl(OFT_ADDRESS).peers(SCROLL_EID) == bytes32(0), "Scroll peer not cleared");
        _assertPinnedLibraries(
            DEPLOYMENT_ENDPOINT, OFT_ADDRESS, HYPE_EID, DEPLOYMENT_SEND_LIB_302, DEPLOYMENT_RECEIVE_LIB_302
        );
        _assertControl(DEPLOYMENT_ENDPOINT, OFT_ADDRESS, DEPLOYMENT_CONTRACT_CONTROLLER);
    }

    function _updateOptimism() internal {
        _selectFork(vm.envOr("OPTIMISM_RPC", OP_RPC_URL), OP_CHAIN_ID);
        _assertControl(OP_ENDPOINT, OFT_ADDRESS, OP_LEGACY_CONTRACT_CONTROLLER);
        require(IWHYPEOAppControl(OFT_ADDRESS).peers(SCROLL_EID) == bytes32(0), "Unexpected Optimism peer");
        _assertDefaultLibraries(OP_ENDPOINT, OFT_ADDRESS, HYPE_EID, OP_SEND_302, OP_RECEIVE_302);
        _assertTimelock(OP_CONTRACT_CONTROLLER, L2_TIMELOCK_DELAY);

        Call[] memory calls = new Call[](4);
        calls[0] = _setSendLibrary(OP_ENDPOINT, OFT_ADDRESS, HYPE_EID, OP_SEND_302);
        calls[1] = _setReceiveLibrary(OP_ENDPOINT, OFT_ADDRESS, HYPE_EID, OP_RECEIVE_302);
        calls[2] =
            Call(OFT_ADDRESS, abi.encodeWithSelector(IWHYPEOAppControl.setDelegate.selector, OP_CONTRACT_CONTROLLER));
        calls[3] = Call(
            OFT_ADDRESS, abi.encodeWithSelector(IWHYPEOAppControl.transferOwnership.selector, OP_CONTRACT_CONTROLLER)
        );

        _writeAndExecute(OP_CHAIN_ID, OP_LEGACY_CONTRACT_CONTROLLER, calls, "output/whype-update-optimism.json");

        require(IWHYPEOAppControl(OFT_ADDRESS).peers(SCROLL_EID) == bytes32(0), "Optimism peer changed");
        _assertPinnedLibraries(OP_ENDPOINT, OFT_ADDRESS, HYPE_EID, OP_SEND_302, OP_RECEIVE_302);
        _assertControl(OP_ENDPOINT, OFT_ADDRESS, OP_CONTRACT_CONTROLLER);
    }

    function _updateHyperEVM() internal {
        _selectFork(vm.envOr("HYPEREVM_RPC", HYPE_RPC_URL), HYPE_CHAIN_ID);
        _assertControl(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, HYPE_LEGACY_CONTRACT_CONTROLLER);
        require(
            IWHYPEOAppControl(OFT_ADAPTER_ADDRESS).peers(SCROLL_EID) == _toBytes32(OFT_ADDRESS),
            "Unexpected HyperEVM -> Scroll peer"
        );
        _assertDefaultLibraries(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, DEPLOYMENT_EID, HYPE_SEND_302, HYPE_RECEIVE_302);
        _assertDefaultLibraries(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, OP_EID, HYPE_SEND_302, HYPE_RECEIVE_302);
        _assertTimelock(HYPE_CONTRACT_CONTROLLER, L2_TIMELOCK_DELAY);

        Call[] memory calls = new Call[](7);
        calls[0] = _setSendLibrary(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, DEPLOYMENT_EID, HYPE_SEND_302);
        calls[1] = _setReceiveLibrary(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, DEPLOYMENT_EID, HYPE_RECEIVE_302);
        calls[2] = _setSendLibrary(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, OP_EID, HYPE_SEND_302);
        calls[3] = _setReceiveLibrary(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, OP_EID, HYPE_RECEIVE_302);
        calls[4] = Call(OFT_ADAPTER_ADDRESS, _clearPeer(SCROLL_EID));
        calls[5] = Call(
            OFT_ADAPTER_ADDRESS,
            abi.encodeWithSelector(IWHYPEOAppControl.setDelegate.selector, HYPE_CONTRACT_CONTROLLER)
        );
        calls[6] = Call(
            OFT_ADAPTER_ADDRESS,
            abi.encodeWithSelector(IWHYPEOAppControl.transferOwnership.selector, HYPE_CONTRACT_CONTROLLER)
        );

        _writeAndExecute(HYPE_CHAIN_ID, HYPE_LEGACY_CONTRACT_CONTROLLER, calls, "output/whype-update-hyperevm.json");

        require(IWHYPEOAppControl(OFT_ADAPTER_ADDRESS).peers(SCROLL_EID) == bytes32(0), "Scroll peer not cleared");
        _assertPinnedLibraries(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, DEPLOYMENT_EID, HYPE_SEND_302, HYPE_RECEIVE_302);
        _assertPinnedLibraries(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, OP_EID, HYPE_SEND_302, HYPE_RECEIVE_302);
        _assertControl(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, HYPE_CONTRACT_CONTROLLER);
    }

    function _writeAndExecute(string memory chainId, address safe, Call[] memory calls, string memory outputPath)
        internal
    {
        string memory bundle = _getGnosisHeader(chainId, addressToHex(safe));

        for (uint256 i = 0; i < calls.length; i++) {
            bundle = string.concat(
                bundle,
                _getGnosisTransaction(addressToHex(calls[i].target), iToHex(calls[i].data), "0", i == calls.length - 1)
            );
        }

        vm.writeFile(outputPath, bundle);
        console.log("Bundle written to:", outputPath);
        executeGnosisTransactionBundle(outputPath);
    }

    function _selectFork(string memory rpcUrl, string memory expectedChainId) internal {
        vm.createSelectFork(rpcUrl);
        require(
            keccak256(bytes(vm.toString(block.chainid))) == keccak256(bytes(expectedChainId)), "RPC chain id mismatch"
        );
    }

    function _assertControl(address endpoint, address oapp, address expected) internal view {
        require(IWHYPEOAppControl(oapp).owner() == expected, "Unexpected owner");
        require(IEndpointDelegates(endpoint).delegates(oapp) == expected, "Unexpected delegate");
    }

    function _assertTimelock(address timelock, uint256 expectedDelay) internal view {
        require(timelock.code.length > 0, "Timelock has no code");
        require(ITimelock(timelock).getMinDelay() == expectedDelay, "Unexpected timelock delay");
    }

    function _assertDefaultLibraries(address endpoint, address oapp, uint32 eid, address sendLib, address receiveLib)
        internal
        view
    {
        IMessageLibManager manager = IMessageLibManager(endpoint);
        require(manager.getSendLibrary(oapp, eid) == sendLib, "Unexpected default send library");
        require(manager.isDefaultSendLibrary(oapp, eid), "Send library already pinned");
        (address configuredReceiveLib, bool isDefault) = manager.getReceiveLibrary(oapp, eid);
        require(configuredReceiveLib == receiveLib, "Unexpected default receive library");
        require(isDefault, "Receive library already pinned");
    }

    function _assertPinnedLibraries(address endpoint, address oapp, uint32 eid, address sendLib, address receiveLib)
        internal
        view
    {
        IMessageLibManager manager = IMessageLibManager(endpoint);
        require(manager.getSendLibrary(oapp, eid) == sendLib, "Send library pin failed");
        require(!manager.isDefaultSendLibrary(oapp, eid), "Send library still default");
        (address configuredReceiveLib, bool isDefault) = manager.getReceiveLibrary(oapp, eid);
        require(configuredReceiveLib == receiveLib, "Receive library pin failed");
        require(!isDefault, "Receive library still default");
    }

    function _setSendLibrary(address endpoint, address oapp, uint32 eid, address sendLib)
        internal
        pure
        returns (Call memory)
    {
        return Call(endpoint, abi.encodeWithSelector(IMessageLibManager.setSendLibrary.selector, oapp, eid, sendLib));
    }

    function _setReceiveLibrary(address endpoint, address oapp, uint32 eid, address receiveLib)
        internal
        pure
        returns (Call memory)
    {
        return Call(
            endpoint, abi.encodeWithSelector(IMessageLibManager.setReceiveLibrary.selector, oapp, eid, receiveLib, 0)
        );
    }

    function _clearPeer(uint32 eid) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IWHYPEOAppControl.setPeer.selector, eid, bytes32(0));
    }

    function _toBytes32(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }
}

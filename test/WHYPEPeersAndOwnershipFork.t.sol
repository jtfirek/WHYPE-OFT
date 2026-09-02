// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import "../utils/L2Constants.sol";

interface IWHYPEOAppFork {
    function owner() external view returns (address);
    function peers(uint32 eid) external view returns (bytes32);
}

interface IEndpointDelegatesFork {
    function delegates(address oapp) external view returns (address);
}

contract WHYPEPeersAndOwnershipForkTest is Test, L2Constants {
    address constant ETHEREUM_WEETH_OAPP = 0xcd2eb13D6831d4602D80E5db9230A57596CDCA63;
    address constant OPTIMISM_WEETH_OAPP = 0x5A7fACB970D094B6C7FF1df0eA68D99E6e73CBFF;
    address constant HYPEREVM_WEETH_OAPP = 0xA3D68b74bF0528fdD07263c60d6488749044914b;

    function test_Ethereum_RemovesScrollAndTransfersControl() public {
        vm.createSelectFork(vm.envOr("ETHEREUM_RPC", DEPLOYMENT_RPC_URL));

        _assertControl(DEPLOYMENT_ENDPOINT, OFT_ADDRESS, DEPLOYMENT_LEGACY_CONTRACT_CONTROLLER);
        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(SCROLL_EID), _toBytes32(OFT_ADDRESS));

        _applyBundle("output/whype-update-ethereum.json", DEPLOYMENT_LEGACY_CONTRACT_CONTROLLER, OFT_ADDRESS, 3);

        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(SCROLL_EID), bytes32(0));
        _assertControl(DEPLOYMENT_ENDPOINT, OFT_ADDRESS, DEPLOYMENT_CONTRACT_CONTROLLER);
        _assertMatchesWeETH(DEPLOYMENT_ENDPOINT, OFT_ADDRESS, ETHEREUM_WEETH_OAPP);
    }

    function test_Optimism_TransfersControlAndRemainsDisconnectedFromScroll() public {
        vm.createSelectFork(vm.envOr("OPTIMISM_RPC", OP_RPC_URL));

        _assertControl(OP_ENDPOINT, OFT_ADDRESS, OP_LEGACY_CONTRACT_CONTROLLER);
        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(SCROLL_EID), bytes32(0));

        _applyBundle("output/whype-update-optimism.json", OP_LEGACY_CONTRACT_CONTROLLER, OFT_ADDRESS, 2);

        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(SCROLL_EID), bytes32(0));
        _assertControl(OP_ENDPOINT, OFT_ADDRESS, OP_CONTRACT_CONTROLLER);
        _assertMatchesWeETH(OP_ENDPOINT, OFT_ADDRESS, OPTIMISM_WEETH_OAPP);
    }

    function test_HyperEVM_RemovesScrollAndTransfersControl() public {
        vm.createSelectFork(vm.envOr("HYPEREVM_RPC", HYPE_RPC_URL));

        _assertControl(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, HYPE_LEGACY_CONTRACT_CONTROLLER);
        assertEq(IWHYPEOAppFork(OFT_ADAPTER_ADDRESS).peers(SCROLL_EID), _toBytes32(OFT_ADDRESS));

        _applyBundle("output/whype-update-hyperevm.json", HYPE_LEGACY_CONTRACT_CONTROLLER, OFT_ADAPTER_ADDRESS, 3);

        assertEq(IWHYPEOAppFork(OFT_ADAPTER_ADDRESS).peers(SCROLL_EID), bytes32(0));
        _assertControl(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, HYPE_CONTRACT_CONTROLLER);
        _assertMatchesWeETH(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, HYPEREVM_WEETH_OAPP);
    }

    function _applyBundle(string memory path, address expectedSafe, address expectedTarget, uint256 expectedCount)
        internal
    {
        string memory json = vm.readFile(path);
        address safe = vm.parseJsonAddress(json, ".safeAddress");
        assertEq(safe, expectedSafe, "unexpected sender Safe");

        uint256 transactionCount;
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(i), "]")); i++) {
            string memory base = string.concat(".transactions[", vm.toString(i), "]");
            address to = vm.parseJsonAddress(json, string.concat(base, ".to"));
            uint256 value = vm.parseJsonUint(json, string.concat(base, ".value"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(base, ".data"));

            assertEq(to, expectedTarget, "unexpected transaction target");
            assertEq(value, 0, "unexpected transaction value");

            vm.prank(safe);
            (bool ok,) = to.call{value: value}(data);
            assertTrue(ok, "bundle transaction reverted");
            transactionCount++;
        }

        assertEq(transactionCount, expectedCount, "unexpected transaction count");
    }

    function _assertControl(address endpoint, address oapp, address expected) internal view {
        assertEq(IWHYPEOAppFork(oapp).owner(), expected, "unexpected owner");
        assertEq(IEndpointDelegatesFork(endpoint).delegates(oapp), expected, "unexpected delegate");
    }

    function _assertMatchesWeETH(address endpoint, address whype, address weeth) internal view {
        assertEq(IWHYPEOAppFork(whype).owner(), IWHYPEOAppFork(weeth).owner(), "owner does not match weETH");
        assertEq(
            IEndpointDelegatesFork(endpoint).delegates(whype),
            IEndpointDelegatesFork(endpoint).delegates(weeth),
            "delegate does not match weETH"
        );
    }

    function _toBytes32(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }
}

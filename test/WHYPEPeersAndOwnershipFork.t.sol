// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import "../utils/L2Constants.sol";

interface IWHYPEOAppFork {
    function owner() external view returns (address);
    function totalSupply() external view returns (uint256);
    function peers(uint32 eid) external view returns (bytes32);
}

interface IEndpointDelegatesFork {
    function delegates(address oapp) external view returns (address);
}

contract WHYPEPeersAndOwnershipForkTest is Test, L2Constants {
    function test_Ethereum_RemovesScrollAndTransfersControl() public {
        vm.createSelectFork(vm.envOr("ETHEREUM_RPC", DEPLOYMENT_RPC_URL));

        _assertControl(DEPLOYMENT_ENDPOINT, OFT_ADDRESS, DEPLOYMENT_LEGACY_CONTRACT_CONTROLLER);
        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(SCROLL_EID), _toBytes32(OFT_ADDRESS));

        _applyBundle("output/whype-update-ethereum.json", DEPLOYMENT_LEGACY_CONTRACT_CONTROLLER, OFT_ADDRESS, 3);

        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(SCROLL_EID), bytes32(0));
        _assertControl(DEPLOYMENT_ENDPOINT, OFT_ADDRESS, DEPLOYMENT_CONTRACT_CONTROLLER);
    }

    function test_Optimism_TransfersControlAndRemainsDisconnectedFromScroll() public {
        vm.createSelectFork(vm.envOr("OPTIMISM_RPC", OP_RPC_URL));

        _assertControl(OP_ENDPOINT, OFT_ADDRESS, OP_LEGACY_CONTRACT_CONTROLLER);
        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(SCROLL_EID), bytes32(0));

        _applyBundle("output/whype-update-optimism.json", OP_LEGACY_CONTRACT_CONTROLLER, OFT_ADDRESS, 2);

        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(SCROLL_EID), bytes32(0));
        _assertControl(OP_ENDPOINT, OFT_ADDRESS, OP_CONTRACT_CONTROLLER);
    }

    function test_HyperEVM_RemovesScrollAndTransfersControl() public {
        vm.createSelectFork(vm.envOr("HYPEREVM_RPC", HYPE_RPC_URL));

        _assertControl(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, HYPE_LEGACY_CONTRACT_CONTROLLER);
        assertEq(IWHYPEOAppFork(OFT_ADAPTER_ADDRESS).peers(SCROLL_EID), _toBytes32(OFT_ADDRESS));

        _applyBundle("output/whype-update-hyperevm.json", HYPE_LEGACY_CONTRACT_CONTROLLER, OFT_ADAPTER_ADDRESS, 3);

        assertEq(IWHYPEOAppFork(OFT_ADAPTER_ADDRESS).peers(SCROLL_EID), bytes32(0));
        _assertControl(HYPE_ENDPOINT, OFT_ADAPTER_ADDRESS, HYPE_CONTRACT_CONTROLLER);
    }

    function test_Scroll_RemovesAllPeersWithOutstandingSupply() public {
        vm.createSelectFork(vm.envOr("SCROLL_RPC", SCROLL_RPC_URL));

        _assertControl(SCROLL_ENDPOINT, OFT_ADDRESS, SCROLL_CONTRACT_CONTROLLER);
        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(DEPLOYMENT_EID), _toBytes32(OFT_ADDRESS));
        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(HYPE_EID), _toBytes32(OFT_ADAPTER_ADDRESS));

        uint256 supplyBefore = IWHYPEOAppFork(OFT_ADDRESS).totalSupply();
        assertGt(supplyBefore, 0, "expected outstanding Scroll supply");

        _applyBundle("output/whype-update-scroll.json", SCROLL_CONTRACT_CONTROLLER, OFT_ADDRESS, 2);

        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(DEPLOYMENT_EID), bytes32(0));
        assertEq(IWHYPEOAppFork(OFT_ADDRESS).peers(HYPE_EID), bytes32(0));
        assertEq(IWHYPEOAppFork(OFT_ADDRESS).totalSupply(), supplyBefore, "Scroll supply changed");
        _assertControl(SCROLL_ENDPOINT, OFT_ADDRESS, SCROLL_CONTRACT_CONTROLLER);
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

    function _toBytes32(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }
}

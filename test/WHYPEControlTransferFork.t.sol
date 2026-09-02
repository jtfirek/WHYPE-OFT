// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import "../utils/L2Constants.sol";

interface IWHYPEAdapterControlFork {
    function owner() external view returns (address);
    function setDelegate(address delegate) external;
    function transferOwnership(address newOwner) external;
}

interface IEndpointDelegatesFork {
    function delegates(address oapp) external view returns (address);
}

/**
 * @notice Executes the generated WHYPE control-transfer bundle on a HyperEVM fork
 *         and verifies both controls match the live weETH OFT.
 *
 * forge test --match-path test/WHYPEControlTransferFork.t.sol -vv
 */
contract WHYPEControlTransferForkTest is Test, L2Constants {
    string constant BUNDLE_PATH = "output/whype-control-transfer-hyperevm.json";
    address constant WEETH_OFT_ADDRESS = 0xA3D68b74bF0528fdD07263c60d6488749044914b;

    function test_WHYPEControlMatchesWeETH() public {
        vm.createSelectFork(vm.envOr("HYPEREVM_RPC", HYPE_RPC_URL));

        IWHYPEAdapterControlFork adapter = IWHYPEAdapterControlFork(OFT_ADAPTER_ADDRESS);
        IEndpointDelegatesFork endpoint = IEndpointDelegatesFork(HYPE_ENDPOINT);

        assertEq(adapter.owner(), HYPE_LEGACY_CONTRACT_CONTROLLER, "unexpected initial owner");
        assertEq(
            endpoint.delegates(OFT_ADAPTER_ADDRESS), HYPE_LEGACY_CONTRACT_CONTROLLER, "unexpected initial delegate"
        );

        _applyBundle();

        address weETHOwner = IWHYPEAdapterControlFork(WEETH_OFT_ADDRESS).owner();
        address weETHDelegate = endpoint.delegates(WEETH_OFT_ADDRESS);

        assertEq(weETHOwner, HYPE_CONTRACT_CONTROLLER, "configured controller does not match weETH owner");
        assertEq(adapter.owner(), weETHOwner, "WHYPE owner does not match weETH");
        assertEq(endpoint.delegates(OFT_ADAPTER_ADDRESS), weETHDelegate, "WHYPE delegate does not match weETH");
    }

    function _applyBundle() internal {
        string memory json = vm.readFile(BUNDLE_PATH);
        address safe = vm.parseJsonAddress(json, ".safeAddress");
        assertEq(safe, HYPE_LEGACY_CONTRACT_CONTROLLER, "unexpected sender Safe");

        uint256 transactionCount;
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(i), "]")); i++) {
            string memory base = string.concat(".transactions[", vm.toString(i), "]");
            address to = vm.parseJsonAddress(json, string.concat(base, ".to"));
            uint256 value = vm.parseJsonUint(json, string.concat(base, ".value"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(base, ".data"));

            assertEq(to, OFT_ADAPTER_ADDRESS, "unexpected transaction target");
            assertEq(value, 0, "unexpected transaction value");

            vm.prank(safe);
            (bool ok,) = to.call{value: value}(data);
            assertTrue(ok, "bundle transaction reverted");
            transactionCount++;
        }

        assertEq(transactionCount, 2, "unexpected transaction count");
    }
}

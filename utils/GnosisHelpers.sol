// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract GnosisHelpers is Script {

    function executeGnosisTransactionBundle(string memory transactionPath) public {
        string memory json = vm.readFile(transactionPath);

        address safeAddress = vm.parseJsonAddress(json, ".safeAddress");
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat(".transactions[", Strings.toString(i), "]")); i++) {
            address to = vm.parseJsonAddress(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].to"));
            uint256 value = vm.parseJsonUint(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].value"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(string.concat(".transactions[", Strings.toString(i)), "].data"));

            vm.prank(safeAddress);
            (bool success,) = address(to).call{value: value}(data);
            require(success, "Transaction failed");
        }
    }

    function _getGnosisHeader(string memory chainId, string memory safeAddress) internal pure returns (string memory) {
        return string.concat('{"chainId":"', chainId, '","safeAddress":"', safeAddress, '","meta": { "txBuilderVersion": "1.16.5" }, "transactions": [');
    }

    function _getGnosisTransaction(string memory to, string memory data, string memory value, bool isLast) internal pure returns (string memory) {
        string memory suffix = isLast ? ']}' : ',';
        return string.concat('{"to":"', to, '","value":"', value, '","data":"', data, '"}', suffix);
    }

    function iToHex(bytes memory buffer) public pure returns (string memory) {
        bytes memory converted = new bytes(buffer.length * 2);
        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }

    function addressToHex(address addr) public pure returns (string memory) {
        return iToHex(abi.encodePacked(addr));
    }
}

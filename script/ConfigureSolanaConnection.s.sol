// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

import "../utils/L2Constants.sol";
import "../utils/GnosisHelpers.sol";

// forge script script/ConfigureSolanaConnection.s.sol:ConfigureSolanaConnection
contract ConfigureSolanaConnection is Script, L2Constants, GnosisHelpers {
    using OptionsBuilder for bytes;

    /*//////////////////////////////////////////////////////////////
                            SOLANA CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    // Solana EID and Peer Address
    uint32 constant SOLANA_EID = 30168;
    bytes32 constant SOLANA_PEER = 0x8d6b09beda705dba0621aa53db6f864d4fc60f40deefb7f41faa83c14663c6c9;
    
    // Ethereum LayerZero Addresses
    address constant ETH_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant ETH_SEND_302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address constant ETH_RECEIVE_302 = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;
    address constant ETH_P2P_DVN = 0x06559EE34D85a88317Bf0bfE307444116c631b67;
    address constant ETH_USDT0_DVN = 0x3b0531eB02Ab4aD72e7a531180beeF9493a00dD2;
    address constant ETH_NETHERMIND_DVN = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;
    address constant ETH_GNOSIS_SAFE = 0x0E556b9aff11195d8bf35F98134BC76B9b6b14C3;
    
    // HyperEVM DVNs (Nethermind only - others are in L2Constants)
    address constant HYPE_NETHERMIND_DVN = 0x8E49eF1DfAe17e547CA0E7526FfDA81FbaCA810A;
    
    // Enforced Options
    uint128 constant SOLANA_GAS = 143000;
    
    // Gnosis Safe Addresses
    address constant HYPE_GNOSIS_SAFE = HYPE_CONTRACT_CONTROLLER; // 0xaBEEd16B15a18930595A85D96e435Ad2DF8ba8e4

    /*//////////////////////////////////////////////////////////////
                        TRANSACTION DATA STRINGS
    //////////////////////////////////////////////////////////////*/
    
    string setPeerDataString;
    string setEnforcedOptionsString;

    function run() public {
        console.log("Initializing Solana connection configuration...");
        _initialize();

        console.log("Building transaction batch for Ethereum");
        string memory EthereumJson = _buildEthereumTransactions();
        vm.writeJson(EthereumJson, "./output/ethereum-solana.json");

        console.log("Building transaction batch for HyperEVM");
        string memory HyperEVMJson = _buildHyperEVMTransactions();
        vm.writeJson(HyperEVMJson, "./output/hyperevm-solana.json");

        console.log("Transaction bundles generated successfully!");
    }

    function _initialize() internal {
        // Encode setPeer transaction data
        bytes memory setPeerData = abi.encodeWithSignature("setPeer(uint32,bytes32)", SOLANA_EID, SOLANA_PEER);
        setPeerDataString = iToHex(setPeerData);

        // Encode setEnforcedOptions transaction data
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](1);
        enforcedOptions[0] = EnforcedOptionParam({
            eid: SOLANA_EID,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(SOLANA_GAS, 0)
        });
        bytes memory setEnforcedOptionsData = abi.encodeWithSignature("setEnforcedOptions((uint32,uint16,bytes)[])", enforcedOptions);
        setEnforcedOptionsString = iToHex(setEnforcedOptionsData);
    }

    function _buildEthereumTransactions() internal view returns (string memory) {
        // Get hex strings for addresses
        string memory oftString = iToHex(abi.encodePacked(OFT_ADDRESS));
        string memory endpointString = iToHex(abi.encodePacked(ETH_ENDPOINT));
        
        string memory json = _getGnosisHeader("1", ETH_GNOSIS_SAFE);

        // Set peer to Solana
        json = string.concat(json, _getGnosisTransaction(oftString, setPeerDataString, false));
        
        // Set enforced options for Solana
        json = string.concat(json, _getGnosisTransaction(oftString, setEnforcedOptionsString, false));

        // Configure send library DVNs
        string memory setConfigSendData = iToHex(
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])", 
                OFT_ADDRESS, 
                ETH_SEND_302, 
                _getEthereumDVNConfig()
            )
        );
        json = string.concat(json, _getGnosisTransaction(endpointString, setConfigSendData, false));

        // Configure receive library DVNs
        string memory setConfigReceiveData = iToHex(
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])", 
                OFT_ADDRESS, 
                ETH_RECEIVE_302, 
                _getEthereumDVNConfig()
            )
        );
        json = string.concat(json, _getGnosisTransaction(endpointString, setConfigReceiveData, true));

        return json;
    }

    function _buildHyperEVMTransactions() internal view returns (string memory) {
        // Get hex strings for addresses
        string memory oftAdapterString = iToHex(abi.encodePacked(OFT_ADAPTER_ADDRESS));
        string memory endpointString = iToHex(abi.encodePacked(HYPE_ENDPOINT));
        
        string memory json = _getGnosisHeader("998", HYPE_GNOSIS_SAFE);

        // Set peer to Solana
        json = string.concat(json, _getGnosisTransaction(oftAdapterString, setPeerDataString, false));
        
        // Set enforced options for Solana
        json = string.concat(json, _getGnosisTransaction(oftAdapterString, setEnforcedOptionsString, false));

        // Configure send library DVNs
        string memory setConfigSendData = iToHex(
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])", 
                OFT_ADAPTER_ADDRESS, 
                HYPE_SEND_302, 
                _getHyperEVMDVNConfig()
            )
        );
        json = string.concat(json, _getGnosisTransaction(endpointString, setConfigSendData, false));

        // Configure receive library DVNs
        string memory setConfigReceiveData = iToHex(
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])", 
                OFT_ADAPTER_ADDRESS, 
                HYPE_RECEIVE_302, 
                _getHyperEVMDVNConfig()
            )
        );
        json = string.concat(json, _getGnosisTransaction(endpointString, setConfigReceiveData, true));

        return json;
    }

    function _getEthereumDVNConfig() internal pure returns (SetConfigParam[] memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](3);
        
        // Sort DVNs to prevent LZ_ULN_Unsorted() errors
        requiredDVNs[0] = ETH_P2P_DVN;
        requiredDVNs[1] = ETH_USDT0_DVN;
        requiredDVNs[2] = ETH_NETHERMIND_DVN;
        
        _sortDVNs(requiredDVNs);

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 3,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(SOLANA_EID, 2, abi.encode(ulnConfig));

        return params;
    }

    function _getHyperEVMDVNConfig() internal pure returns (SetConfigParam[] memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](3);
        
        // Sort DVNs to prevent LZ_ULN_Unsorted() errors
        requiredDVNs[0] = HYPE_P2P_DVN;
        requiredDVNs[1] = HYPE_USDT0_DVN;
        requiredDVNs[2] = HYPE_NETHERMIND_DVN;
        
        _sortDVNs(requiredDVNs);

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 3,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(SOLANA_EID, 2, abi.encode(ulnConfig));

        return params;
    }

    function _sortDVNs(address[] memory dvns) internal pure {
        for (uint i = 0; i < dvns.length - 1; i++) {
            for (uint j = 0; j < dvns.length - i - 1; j++) {
                if (dvns[j] > dvns[j + 1]) {
                    address temp = dvns[j];
                    dvns[j] = dvns[j + 1];
                    dvns[j + 1] = temp;
                }
            }
        }
    }
}


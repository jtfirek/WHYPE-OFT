// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

import "../utils/L2Constants.sol";
import "../interfaces/ICreate3Deployer.sol";

import "../src/wHYPEOFT.sol";

// forge script script/DeployConfigureOPOFT.s.sol:DeployOPOFTScript --rpc-url $OPTIMISM_RPC --broadcast
contract DeployOPOFTScript is Script, L2Constants {
    using OptionsBuilder for bytes;

    ICreate3Deployer private CREATE3 = ICreate3Deployer(L2_CREATE3_DEPLOYER);

    EnforcedOptionParam[] public enforcedOptions;

    OFT oftDeployment;

    function run() public {
        vm.startBroadcast();

        deployOFT();

        configurePeer();
        configureEnforcedOptions();
        configureDVN();

        vm.stopBroadcast();
    }

    function runUpdateEnforcedOptions() public {
        oftDeployment = OFT(OFT_ADDRESS);

        vm.startBroadcast();

        _appendEnforcedOptions(HYPE_EID);
        oftDeployment.setEnforcedOptions(enforcedOptions);

        vm.stopBroadcast();
    }

    function deployOFT() internal {
        console.log("Deploying OFT contract on Optimism...");

        bytes memory implCreationCode = abi.encodePacked(type(WHYPEOFT).creationCode, abi.encode(TOKEN_NAME, TOKEN_SYMBOL, OP_ENDPOINT, msg.sender));

        address oftDeploymentAddress = CREATE3.deployCreate3(keccak256("WHYPE"), implCreationCode);
        require(oftDeploymentAddress == OFT_ADDRESS, "OFT deployment address mismatch");

        oftDeployment = OFT(oftDeploymentAddress);
    }

    function configurePeer() internal {
        console.log("Configuring peers...");

        oftDeployment.setPeer(HYPE_EID, bytes32(uint256(uint160(OFT_ADAPTER_ADDRESS))));
    }

    function configureDVN() internal {
        console.log("Configuring DVNs...");

        _setDVN(HYPE_EID);
    }

    function configureEnforcedOptions() internal {
        console.log("Configuring enforced options...");

        _appendEnforcedOptions(HYPE_EID);

        oftDeployment.setEnforcedOptions(enforcedOptions);
    }

    function _setDVN(uint32 dstEid) public {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](3);

        requiredDVNs[0] = OP_BITGO_DVN;
        requiredDVNs[1] = OP_P2P_DVN;
        requiredDVNs[2] = OP_USDT0_DVN;

        for (uint i = 0; i < requiredDVNs.length - 1; i++) {
            for (uint j = 0; j < requiredDVNs.length - i - 1; j++) {
                if (requiredDVNs[j] > requiredDVNs[j + 1]) {
                    address temp = requiredDVNs[j];
                    requiredDVNs[j] = requiredDVNs[j + 1];
                    requiredDVNs[j + 1] = temp;
                }
            }
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 3,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(dstEid, 2, abi.encode(ulnConfig));
        ILayerZeroEndpointV2(OP_ENDPOINT).setConfig(OFT_ADDRESS, OP_SEND_302, params);
        ILayerZeroEndpointV2(OP_ENDPOINT).setConfig(OFT_ADDRESS, OP_RECEIVE_302, params);
    }

    function _appendEnforcedOptions(uint32 dstEid) internal {
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        }));
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        }));
    }
}

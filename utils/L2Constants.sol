// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

    struct ConfigPerChain {
        string RPC_URL;
        string CHAIN_ID;

        uint32 EID;
        address ENDPOINT;
        address SEND_302;
        address RECEIVE_302;
        address BITGO_DVN;
        address P2P_DVN;
        address USDT0_DVN;
        address[3] LZ_DVN;
        address GNOSIS_SAFE;
    }

contract L2Constants {

    /*//////////////////////////////////////////////////////////////
                        OFT Deployment Parameters
    //////////////////////////////////////////////////////////////*/

    // General chain constants
    string constant DEPLOYMENT_RPC_URL = "";
    string constant DEPLOYMENT_CHAIN_ID = "";
    
    // LayerZero addresses
    uint32 constant DEPLOYMENT_EID = 0;
    address constant DEPLOYMENT_ENDPOINT = address(0);
    address constant DEPLOYMENT_SEND_LIB_302 = address(0);
    address constant DEPLOYMENT_RECEIVE_LIB_302 = address(0);

    address constant DEPLOYMENT_BITGO_DVN = address(0);
    address constant DEPLOYMENT_P2P_DVN = address(0);
    address constant DEPLOYMENT_USDT0_DVN = address(0);
    address[3] DEPLOYMENT_LZ_DVN = [address(0), address(0), address(0)];

    address constant DEPLOYMENT_CONTRACT_CONTROLLER = address(0);
    /*//////////////////////////////////////////////////////////////
                    
    //////////////////////////////////////////////////////////////*/

    address constant OFT_ADDRESS = 0xd83E3d560bA6F05094d9D8B3EB8aaEA571D1864E;
   
    address constant L2_CREATE3_DEPLOYER = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    
    // OFT Token Constants
    string constant TOKEN_NAME = "Wrapped HYPE";
    string constant TOKEN_SYMBOL = "wHYPE";
    
    // Hyperliquid Constants
    string constant HYPE_RPC_URL = "https://rpc.hyperliquid.xyz/evm";
    uint32 constant HYPE_EID = 30367;
    address constant WRAPPED_HYPE_ADDRESS = 0x5555555555555555555555555555555555555555;
    address constant HYPE_ENDPOINT = 0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9;
    address constant HYPE_CONTRACT_CONTROLLER = 0xaBEEd16B15a18930595A85D96e435Ad2DF8ba8e4;

    address constant OFT_ADAPTER_ADDRESS = 0x2B7E48511ea616101834f09945c11F7d78D9136d;

    address constant HYPE_SEND_302 = 0xfd76d9CB0Bac839725aB79127E7411fe71b1e3CA;
    address constant HYPE_RECEIVE_302 = 0x7cacBe439EaD55fa1c22790330b12835c6884a91;
    address constant HYPE_BITGO_DVN = 0xf55E9dAef79eeC17F76e800F059495F198ef8348;
    address constant HYPE_P2P_DVN = 0xC7423626016bc40375458bc0277F28681EC91C8e;
    address constant HYPE_USDT0_DVN = 0xaE016a939935D6fe6185900d4c7C7C9b27366caC;
    address[3] HYPE_DVN = [0xf55E9dAef79eeC17F76e800F059495F198ef8348, 0xC7423626016bc40375458bc0277F28681EC91C8e, 0xaE016a939935D6fe6185900d4c7C7C9b27366caC];

    
    // Construct an array of all the chains that are currently supported
    ConfigPerChain[] public Chains;
    constructor () {

    }

    ConfigPerChain ETHEREUM = ConfigPerChain({
        RPC_URL: "https://gateway.tenderly.co/public/mainnet",
        CHAIN_ID: "1",
        EID: 30101,
        ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1,
        RECEIVE_302: 0xc02Ab410f0734EFa3F14628780e6e695156024C2,

        BITGO_DVN: 0xc9ca319f6Da263910fd9B037eC3d817A814ef3d8,
        P2P_DVN: 0x06559EE34D85a88317Bf0bfE307444116c631b67,
        USDT0_DVN: 0x3b0531eB02Ab4aD72e7a531180beeF9493a00dD2,
        LZ_DVN: [0xc9ca319f6Da263910fd9B037eC3d817A814ef3d8, 0x06559EE34D85a88317Bf0bfE307444116c631b67, 0x3b0531eB02Ab4aD72e7a531180beeF9493a00dD2],
        GNOSIS_SAFE: 0x0E556b9aff11195d8bf35F98134BC76B9b6b14C3
    });
}

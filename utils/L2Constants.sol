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
    }

contract L2Constants {

    /*//////////////////////////////////////////////////////////////
                        OFT Deployment Parameters
    //////////////////////////////////////////////////////////////*/

    // General chain constants
    string constant DEPLOYMENT_RPC_URL = "https://gateway.tenderly.co/public/mainnet";
    string constant DEPLOYMENT_CHAIN_ID = "1";
    
    // LayerZero addresses
    uint32 constant DEPLOYMENT_EID = 30101;
    address constant DEPLOYMENT_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant DEPLOYMENT_SEND_LIB_302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address constant DEPLOYMENT_RECEIVE_LIB_302 = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;

    address constant DEPLOYMENT_BITGO_DVN = 0xc9ca319f6Da263910fd9B037eC3d817A814ef3d8;
    address constant DEPLOYMENT_P2P_DVN = 0x06559EE34D85a88317Bf0bfE307444116c631b67;
    address constant DEPLOYMENT_USDT0_DVN = 0x3b0531eB02Ab4aD72e7a531180beeF9493a00dD2;
    address constant DEPLOYMENT_LAYERZERO_DVN = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    address[3] DEPLOYMENT_LZ_DVN = [0xc9ca319f6Da263910fd9B037eC3d817A814ef3d8, 0x06559EE34D85a88317Bf0bfE307444116c631b67, 0x3b0531eB02Ab4aD72e7a531180beeF9493a00dD2];

    address constant DEPLOYMENT_CONTRACT_CONTROLLER = 0x0E556b9aff11195d8bf35F98134BC76B9b6b14C3;
    /*//////////////////////////////////////////////////////////////
                    
    //////////////////////////////////////////////////////////////*/

    address constant OFT_ADDRESS = 0xd83E3d560bA6F05094d9D8B3EB8aaEA571D1864E;
   
    address constant L2_CREATE3_DEPLOYER = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    
    // OFT Token Constants
    string constant TOKEN_NAME = "Wrapped HYPE";
    string constant TOKEN_SYMBOL = "WHYPE";
    
    // Hyperliquid Constants
    string constant HYPE_RPC_URL = "https://rpc.hyperliquid.xyz/evm";
    string constant HYPE_CHAIN_ID = "999";
    uint32 constant HYPE_EID = 30367;
    address constant WRAPPED_HYPE_ADDRESS = 0x5555555555555555555555555555555555555555;
    address constant HYPE_ENDPOINT = 0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9;
    address constant HYPE_LEGACY_CONTRACT_CONTROLLER = 0xaBEEd16B15a18930595A85D96e435Ad2DF8ba8e4;
    address constant HYPE_CONTRACT_CONTROLLER = 0xf27128a5b064e8d97EDaa60D24bFa2FD1eeC26eB;

    address constant OFT_ADAPTER_ADDRESS = 0x2B7E48511ea616101834f09945c11F7d78D9136d;

    address constant HYPE_SEND_302 = 0xfd76d9CB0Bac839725aB79127E7411fe71b1e3CA;
    address constant HYPE_RECEIVE_302 = 0x7cacBe439EaD55fa1c22790330b12835c6884a91;
    address constant HYPE_BITGO_DVN = 0xf55E9dAef79eeC17F76e800F059495F198ef8348;
    address constant HYPE_P2P_DVN = 0xC7423626016bc40375458bc0277F28681EC91C8e;
    address constant HYPE_USDT0_DVN = 0xaE016a939935D6fe6185900d4c7C7C9b27366caC;
    address constant HYPE_LAYERZERO_DVN = 0xc097ab8CD7b053326DFe9fB3E3a31a0CCe3B526f;
    address[3] HYPE_DVN = [0xf55E9dAef79eeC17F76e800F059495F198ef8348, 0xC7423626016bc40375458bc0277F28681EC91C8e, 0xaE016a939935D6fe6185900d4c7C7C9b27366caC];

    // Optimism Constants
    string constant OP_RPC_URL = "https://mainnet.optimism.io";
    string constant OP_CHAIN_ID = "10";

    uint32 constant OP_EID = 30111;
    address constant OP_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant OP_SEND_302 = 0x1322871e4ab09Bc7f5717189434f97bBD9546e95;
    address constant OP_RECEIVE_302 = 0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063;

    address constant OP_BITGO_DVN = 0xF24Dc834039a1E39F6b99A51Df05Df9c91e35b2d;
    address constant OP_P2P_DVN = 0x539008c98B17803A273eDf98aBA2d4414Ee3f4D7;
    address constant OP_USDT0_DVN = 0x947Bb89919d1E5996d6C46223626AC2E97BcF8A3;
    address constant OP_LAYERZERO_DVN = 0x6A02D83e8d433304bba74EF1c427913958187142;
    address[3] OP_DVN = [0xF24Dc834039a1E39F6b99A51Df05Df9c91e35b2d, 0x539008c98B17803A273eDf98aBA2d4414Ee3f4D7, 0x947Bb89919d1E5996d6C46223626AC2E97BcF8A3];

    address constant OP_CONTRACT_CONTROLLER = 0x0E556b9aff11195d8bf35F98134BC76B9b6b14C3;

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
        LZ_DVN: [0xc9ca319f6Da263910fd9B037eC3d817A814ef3d8, 0x06559EE34D85a88317Bf0bfE307444116c631b67, 0x3b0531eB02Ab4aD72e7a531180beeF9493a00dD2]
    });

    ConfigPerChain OPTIMISM = ConfigPerChain({
        RPC_URL: "https://mainnet.optimism.io",
        CHAIN_ID: "10",
        EID: 30111,
        ENDPOINT: 0x1a44076050125825900e736c501f859c50fE728c,
        SEND_302: 0x1322871e4ab09Bc7f5717189434f97bBD9546e95,
        RECEIVE_302: 0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063,
        BITGO_DVN: 0xF24Dc834039a1E39F6b99A51Df05Df9c91e35b2d,
        P2P_DVN: 0x539008c98B17803A273eDf98aBA2d4414Ee3f4D7,
        USDT0_DVN: 0x947Bb89919d1E5996d6C46223626AC2E97BcF8A3,
        LZ_DVN: [0xF24Dc834039a1E39F6b99A51Df05Df9c91e35b2d, 0x539008c98B17803A273eDf98aBA2d4414Ee3f4D7, 0x947Bb89919d1E5996d6C46223626AC2E97BcF8A3]
    });
}

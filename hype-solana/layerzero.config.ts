import { EndpointId } from '@layerzerolabs/lz-definitions'
import { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { getEnforcedOptions, getMultisigAddress, getOptionalDVNs, getRequiredDVNs } from './consts/wire'
import { getOftStoreAddress } from './tasks/solana'

// Define all contracts
const CONTRACTS: OmniPointHardhat[] = [
    {
        eid: EndpointId.ETHEREUM_V2_MAINNET,
        contractName: 'wHYPEOFT',
        address: '0xd83E3d560bA6F05094d9D8B3EB8aaEA571D1864E',
    },
    {
        eid: EndpointId.HYPERLIQUID_V2_MAINNET,
        contractName: 'wHYPEOFTAdapter',
        address: '0x2B7E48511ea616101834f09945c11F7d78D9136d',
    },
    { eid: EndpointId.SOLANA_V2_MAINNET, address: getOftStoreAddress(EndpointId.SOLANA_V2_MAINNET) },
]

// Generate all possible connections
const generateConnections = async () => {
    const connections = []

    // Generate all directional pairs first (including both directions)
    const pairs = []
    for (let i = 0; i < CONTRACTS.length; i++) {
        for (let j = 0; j < CONTRACTS.length; j++) {
            if (i !== j) {
                // Skip self-connections
                pairs.push([CONTRACTS[i], CONTRACTS[j]]) // from -> to
            }
        }
    }

    // Iterate through all directional pairs
    for (const [from, to] of pairs) {
        connections.push({
            from,
            to,
            config: {
                enforcedOptions: getEnforcedOptions(to.eid),
                sendConfig: {
                    ulnConfig: {
                        requiredDVNs: getRequiredDVNs(from.eid),
                        optionalDVNs: getOptionalDVNs(from.eid),
                        optionalDVNThreshold: 0,
                    },
                },
                receiveConfig: {
                    ulnConfig: {
                        requiredDVNs: getRequiredDVNs(from.eid),
                        optionalDVNs: getOptionalDVNs(from.eid),
                        optionalDVNThreshold: 0,
                    },
                },
            },
        })
    }

    return connections
}

export default async function () {
    const connections = await generateConnections()

    return {
        contracts: CONTRACTS.map((contract) => ({
            contract,
            config: {
                owner: getMultisigAddress(contract.eid),
                delegate: getMultisigAddress(contract.eid),
            },
        })),
        connections,
    }
}

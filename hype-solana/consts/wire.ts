import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { OAppEnforcedOption } from '@layerzerolabs/toolbox-hardhat'

export const DVNS = {
    P2P: {
        [EndpointId.HYPERLIQUID_V2_MAINNET]: '0xc7423626016bc40375458bc0277f28681ec91c8e',
        [EndpointId.ETHEREUM_V2_MAINNET]: '0x06559ee34d85a88317bf0bfe307444116c631b67',
        [EndpointId.SOLANA_V2_MAINNET]: '29EKzmCscUg8mf4f5uskwMqvu2SXM8hKF1gWi1cCBoKT',
    } as Partial<Record<EndpointId, string>>,
    USDT0: {
        [EndpointId.HYPERLIQUID_V2_MAINNET]: '0xae016a939935d6fe6185900d4c7c7c9b27366cac',
        [EndpointId.ETHEREUM_V2_MAINNET]: '0x3b0531eb02ab4ad72e7a531180beef9493a00dd2',
        [EndpointId.SOLANA_V2_MAINNET]: 'JBt34GkVns6VSoP2dCPpViW28eqE4GNgKaoZPRP63wZs',
    } as Partial<Record<EndpointId, string>>,
    NETHERMIND: {
        [EndpointId.HYPERLIQUID_V2_MAINNET]: '0x8e49ef1dfae17e547ca0e7526ffda81fbaca810a',
        [EndpointId.ETHEREUM_V2_MAINNET]: '0xa59ba433ac34d2927232918ef5b2eaafcf130ba5',
        [EndpointId.SOLANA_V2_MAINNET]: 'GPjyWr8vCotGuFubDpTxDxy9Vj1ZeEN4F2dwRmFiaGab',
    } as Partial<Record<EndpointId, string>>,
}

// Define enforced options per specific endpoint ID
export const ENFORCED_OPTIONS: Partial<Record<EndpointId, OAppEnforcedOption[]>> = {
    // Mainnet
    [EndpointId.HYPERLIQUID_V2_MAINNET]: [
        { msgType: 1, optionType: ExecutorOptionType.LZ_RECEIVE, gas: 100000, value: 0 },
    ],
    [EndpointId.ETHEREUM_V2_MAINNET]: [
        { msgType: 1, optionType: ExecutorOptionType.LZ_RECEIVE, gas: 100000, value: 0 },
    ],
    [EndpointId.SOLANA_V2_MAINNET]: [
        { msgType: 1, optionType: ExecutorOptionType.LZ_RECEIVE, gas: 143000, value: 2442960 },
    ],
}

export const MULTISIGS: Partial<Record<EndpointId, string>> = {
    // Mainnet addresses
    [EndpointId.HYPERLIQUID_V2_MAINNET]: 'TODO',
    [EndpointId.ETHEREUM_V2_MAINNET]: 'TODO',
    [EndpointId.SOLANA_V2_MAINNET]: 'TODO',
} as const

// Helper functions
export const getRequiredDVNs = (eid: EndpointId): string[] => {
    return [DVNS.P2P[eid], DVNS.USDT0[eid], DVNS.NETHERMIND[eid]].filter(Boolean) as string[]
}

export const getOptionalDVNs = (eid: EndpointId): string[] => {
    return [] as string[]
}

export const getEnforcedOptions = (eid: EndpointId): OAppEnforcedOption[] => {
    return ENFORCED_OPTIONS[eid] ?? [{ msgType: 1, optionType: ExecutorOptionType.LZ_RECEIVE, gas: 80000, value: 0 }]
}

export const getMultisigAddress = (eid: EndpointId): string => {
    const address = MULTISIGS[eid]

    if (!address || address === 'TODO' || address === '0x0000000000000000000000000000000000000000') {
        throw new Error(
            `Multisig address not configured for endpoint ${eid}. Please update MULTISIGS in consts/wire.ts`
        )
    }

    return address
}

# Configuration Scripts

## ConfigureSolanaConnection.s.sol

Generates Gnosis Safe transaction bundles to connect WHYPE OFT deployments on Ethereum and HyperEVM to Solana.

### Configuration

The script configures:
- **Peer connection** to Solana OFT
- **Enforced options** for Solana cross-chain messages (143k gas)
- **DVN configuration** using P2P, USDT0, and Nethermind DVNs
- **UlnConfig** with 3 required DVNs and 15 block confirmations

### Usage

```bash
# Generate transaction bundles
forge script script/ConfigureSolanaConnection.s.sol:ConfigureSolanaConnection

# Output files will be created in:
# - ./output/ethereum-solana.json
# - ./output/hyperevm-solana.json
```

### Transaction Bundles

Each bundle includes transactions to:
1. Set Solana as a peer (`setPeer`)
2. Configure enforced options for Solana messages
3. Set DVN configuration for send library
4. Set DVN configuration for receive library

Import the generated JSON files into Gnosis Safe transaction builder to execute.


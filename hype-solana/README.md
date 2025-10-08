# Solana HYPE OFT

Run `pnpm install` to get dependencies.

To wire Solana -> evm chains, set up the desired configurations within `consts/wire.ts` and `layerzero.config.ts`. See existing chains for reference. Then  run:

```
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts --ci --skip-connections-from-eids < evm eids >
```

For example:

```
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts --ci --skip-connections-from-eids 30101,30367
```

To transfer ownership on Solana, ensure the `MULTISIGS` object is updated within the `consts/wire.ts` file, then run:

```
npx hardhat lz:ownable:transfer-ownership --oapp-config layerzero.config.ts --ci
```

To transfer upgrade authority of the solana program, run:

```
solana program set-upgrade-authority [FLAGS] [OPTIONS] <PROGRAM_ADDRESS> --new-upgrade-authority <NEW_UPGRADE_AUTHORITY> --skip-new-upgrade-authority-signer-check
```
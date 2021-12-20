# Coral Marketplace Core
This project has been created using the [Hardhat-reef-template](https://github.com/reef-defi/hardhat-reef-template).

## Contract addresses
| | Marketplace contract | NFT contract | Loan contract |
|---|---|---|---|
|__Mainnet__|[TODO](https://reefscan.com/contract/TODO)|[TODO](https://reefscan.com/contract/TODO)|[TODO](https://reefscan.com/contract/TODO)|
| __Testnet__ |[TODO](https://testnet.reefscan.com/contract/TODO)|[TODO](https://testnet.reefscan.com/contract/TODO)|[TODO](https://testnet.reefscan.com/contract/TODO)|

## Installing
Install all dependencies with `yarn`.

## Deploy contracts
Deploy in testnet:
```bash
yarn hardhat run scripts/deploy.js
```

Deploy in mainnet:
```bash
yarn hardhat run scripts/deploy.js --network reef_mainnet
```

## Run tests
```bash
yarn test
```

## Use account seeds
In order to use your Reef account to deploy the contracts or run the tests, you have to rename the _seeds.example.json_ file to _seeds.json_ and write your set your seed words there.

## License
Distributed under the MIT License. See [LICENSE](LICENSE) for more information.

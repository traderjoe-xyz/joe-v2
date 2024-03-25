# [Joe V2: Liquidity Book](https://github.com/traderjoe-xyz/joe-v2)

This repository contains the Liquidity Book contracts, as well as tests and deploy scripts.

- The [LBPair](./src/LBPair.sol) is the contract that contains all the logic of the actual pair for swaps, adds, removals of liquidity and fee claiming. This contract should never be deployed directly, and the factory should always be used for that matter.

- The [LBToken](./src/LBToken.sol) is the contract that is used to calculate the shares of a user. The LBToken is a new token standard that is similar to ERC-1155, but without any callbacks (for safety reasons) and any functions or variables relating to ERC-721.

- The [LBFactory](./src/LBFactory.sol) is the contract used to deploy the different pairs and acts as a registry for all the pairs already created. There are also privileged functions such as setting the parameters of the fees, the flashloan fee, setting the pair implementation, set if a pair should be ignored by the quoter and add new presets. Unless the `creationUnlocked` is `true`, only the owner of the factory can create pairs.

- The [LBRouter](./src/LBRouter.sol) is the main contract that user will interact with as it adds security checks. Most users shouldn't interact directly with the pair.

- The [LBQuoter](./src/LBQuoter.sol) is a contract that is used to return the best route of all those given. This should be used before a swap to get the best return on a swap.

For more information, go to the [documentation](https://docs.traderjoexyz.com/) and the [whitepaper](https://github.com/traderjoe-xyz/LB-Whitepaper/blob/main/Joe%20v2%20Liquidity%20Book%20Whitepaper.pdf).

## Install foundry

Foundry documentation can be found [here](https://book.getfoundry.sh/forge/index.html).

### On Linux and macOS

Open your terminal and type in the following command:

```
curl -L https://foundry.paradigm.xyz | bash
```

This will download foundryup. Then install Foundry by running:

```
foundryup
```

To update foundry after installation, simply run `foundryup` again, and it will update to the latest Foundry release.
You can also revert to a specific version of Foundry with `foundryup -v $VERSION`.

### On Windows

If you use Windows, you need to build from source to get Foundry.

Download and run `rustup-init` from [rustup.rs](https://rustup.rs/). It will start the installation in a console.

After this, run the following to build Foundry from source:

```
cargo install --git https://github.com/foundry-rs/foundry foundry-cli anvil --bins --locked
```

To update from source, run the same command again.

## Install dependencies

To install dependencies, run the following to install dependencies:

```
forge install
```

___

## Tests

To run tests, run the following command:

```
forge test
```

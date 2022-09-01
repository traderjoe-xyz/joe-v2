# DexV2
DexV2 POC, VERY PRIVATE, DO NOT SHARE OUTSIDE OF TRADERJOE
Unlicensed.

## Use Foundry
Install foundry and git submodules
```
curl -L https://foundry.paradigm.xyz | bash
foundryup
forge install
```

Usage
```
forge build
forge test
```

Documentation can be found [here](https://book.getfoundry.sh/forge/index.html)

## Deploy on a forked network
After preparing your `.env` file:
```
anvil --fork-url=https://api.avax-test.network/ext/bc/C/rpc

source .env
forge script --rpc-url=$ANVIL_URL --private-key=$PRIVATE_KEY script/deploy-core.s.sol --broadcast
```
Enter the contract addresses on the script and then run:
```
forge script --rpc-url=$ANVIL_URL --private-key=$PRIVATE_KEY script/deploy-playground.s.sol --broadcast
```

## Documentation
### Prices
The current price of a LBPair is determined by its current active bin. This can be fetched using `getReservesAndId()`. You can then calculate the corresponding price using `getPriceFromId(activeBin, pairBinStep)` from the `BinHelper` contract library or using this method from the joe sdk: 
```
public static getPriceFromId(id: number, binStep: number): number {
    return (1 + binStep / 20_000) ** (id - 8388608)
  }
```

Price is expressed with 36 decimals.

### Swap
The LBRouter contract manages swaps using both V1 and V2 pairs. In addition to the token route, you will need to specify which pair you want to go through in order to go from one token to another, as you can have several pairs with different bin steps for the same pair of tokens. `binStep = 0` represents the V1 pair.

First, approve the LBRouter on your input token. You can then use `swapExactTokensForTokens` for example:
```
function swapExactTokensForTokens(
    uint256 _amountIn,
    uint256 _amountOutMin,
    uint256[] memory _pairBinSteps,
    IERC20[] memory _tokenPath,
    address _to,
    uint256 _deadline
) 
```

Using Solidity, you can build the `pairBinSteps` and `tokenPath` this way:
```
IERC20[] memory tokenPath = new IERC20[](2);
tokenPath[0] = usdt;
tokenPath[1] = usdc;
uint256[] memory pairVersions = new uint256[](1);
pairVersions[0] = 1;
```
This will swap usdt for usdc using the LBpair with `binStep=1`

You can estimate the outcome of this swap using:
```
function getSwapOut(
    ILBPair _LBPair,
    uint256 _amountIn,
    bool _swapForY
)
```
To know which token is tokenY, call:
```
function getLBPairInfo(
    IERC20 _tokenA,
    IERC20 _tokenB,
    uint256 _binStep
) 
```
> *Note that when the two tokens of the pair can be interchanged, they are called tokenA and tokenB. When not, it is specified tokenY or tokenX.*

Swaps examples can be found in the `LBRouter.Swaps.t.sol` test contract

### Adding liquidity
Adding liquidity into a LBpair introduces two kinds of slippage: *price slippage* and *amount slippage*. All the necessary inputs to add liquidity are packed in a single struct:
```
struct LiquidityParameters {
    IERC20 tokenX;
    IERC20 tokenY;
    uint256 binStep;
    uint256 amountX;
    uint256 amountY;
    uint256 amountXMin;
    uint256 amountYMin;
    uint256 activeIdDesired;
    uint256 idSlippage;
    int256[] deltaIds;
    uint256[] distributionX;
    uint256[] distributionY;
    address to;
    uint256 deadline;
}
```

As you can see, you will need to know which token of the pair is token X and which one is token Y. `distributionX` and `distributionY` are representing the proportion of the corresponding token that will be put in the bin specified in the `deltaIds` array. `deltaIds` are relative to the current active bin, that can move within the boundaries defined by `idSlippage`. The sum of `distributionX` must be either 0 (no token X deposited) or 100e18 (100%). Same for `distributionY`.

`deltaId = 0` means that you are depositing in the current active bin. You can deposit both X and Y in this bin only. Strictly negative `deltaIds` correspond to Y bins, `distributionX` amounts will be null. Strictly positive `deltaIds` correspond to X bins, `distributionY` amounts will be null.

An example building deltaIds and distribution arrays can be found on the `spreadLiquidityForRouter` function in the `TestHelper.sol` contract. This function prepares a deposit of the same amount of token Y and X equally distributed.

### Removing Liquidity
To remove liquidity, you must first know where your liquidity is. First, fetch the total number of bins you deposited liquidity in using `userPositionNb`. You can then loop on all your bin and fetch your position (bin number) using `userPositionAt` and then `balanceOf`. 
To convert your bin position to a token amount, apply a cross product using your balance, the total supply of that bin and the total amount of token in the same bin.
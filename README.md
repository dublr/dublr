<img alt="Dublr Logo" height="300" width = "300" src="https://raw.githubusercontent.com/dublr/dublr/main/icon.png">

# The Dublr Token

## tl;dr

[Dublr](https://github.com/dublr/dublr) is a smart contract token that implements several token standards (ERC20, ERC777, ERC1363, ERC4524, EIP2612). It has its own built-in distributed exchange (so it is both a token and a DEX). Supply is generated on-demand by minting, with a mint price that grows exponentially.

## Short overview

Dublr (ticker: DUBLR) is a new smart contract token for the Ethereum blockchain. Dublr has some very unique features:

* Dublr is a token smart contract that is compatible with many different token APIs (ERC20, ERC777, ERC1363, ERC4524, and EIP2612 permits), making it maximally flexible and useful. [OmniToken](contracts/main/OmniToken) is the foundation that provides this broad API compatibility.
* Dublr is also its own built-in decentralized exchange or DEX (sell-side only), meaning that sellers can list Dublr tokens for sale, and buyers can buy Dublr tokens, using the Dublr contract itself. (Because Dublr implements ERC20, it can also be traded on all other centralized and decentralized exchanges.)
* The supply of DUBLR tokens is created by on-demand minting at the current _mint price_ (in ETH per DUBLR), when demand exceeds supply below the mint price, rather than via ICO or airdrop.
* The maximum value of the DUBLR/ETH exchange rate is fixed by the current mint price. The actual price at which Dublr tokens can be bought is the minimum out of the current mint price and the price of the cheapest sell order currently listed on the built-in DEX.
* The mint price grows exponentially over time, with a doubling period of 90 days (hence the name, "Dublr"), setting an upper envelope to how fast the _maximum_ price of DUBLR can grow, equivalent to 0.77% compound interest per day.

## Longer overview

**Supported token APIs:** Dublr builds on the [OmniToken](contracts/main/OmniToken) library, which supports a wide range of APIs for:
  * safe sending of ERC20-compatible tokens (to prevent the irretrievable loss of tokens when they are sent to the wrong address);
  * safe granting of 3rd party spending allowances (to counter a well-known "double allowance spend" vulnerability of ERC20);
  * time-limited allowances (so that forgotten allowances don't render a wallet vulnerable to being drained);
  * the granting of allowances via signed permits; and
  * recipient/sender/spender notification after a transfer is complete, and spender notification after an allowance is granted.

**Buying tokens:** Dublr token supply is not created and distributed the usual way, via ICO or airdrop, but rather buyers can simply call the payable `buy()` function on [the Dublr contract](contracts/main/Dublr#buying-api) with any amount of ETH, and the maximum number of Dublr tokens that can be bought or minted for that price will be placed in the buyer's DUBLR wallet. Token supply grows as needed to meet demand.

**Selling tokens:** The built-in DEX can be used to list Dublr tokens for sale by calling `sell(price, amount)` on [the Dublr contract](contracts/main/Dublr#selling-api). As long as the list price of the tokens is below the mint price, a buyer may buy these tokens when calling `buy()`. Tokens are bought in increasing order of list price, until sell orders are exhausted or the mint price is reached. Once the mint price is reached, new tokens are minted for buyers with the remaining buyer's balance, increasing the total supply of tokens, rather than filling more expensive sell orders.

**Mint price:** The mint price doubles every 90 days, equivalent to a compound interest rate for the _maximum_ price a coin may be sold for of 0.77% per day. The mint price increases exponentially at this rate over 30 doubling periods (7.5 years). The mint price puts a hard cap on how fast the price of Dublr tokens may grow, increasing total supply as needed to meet the demand, to keep tokens selling at the mint price or below. After 30 doubling periods, minting is permanently disabled, fixing the total supply forever. However, minting will probably stop long before the 30th doubling period due to the mint price eventually becoming exorbitant.

**No promise of profits by the issuer:** No profit or return is guaranteed, promised, or predicted if DUBLR tokens are purchased. It is impossible to predict actual market behavior, and DUBLR tokens can sell at any price. See [Legal Agreement and Disclaimers](LEGAL.md).

**Security:** Dublr is tightly secured against security vulnerabilities, via:

* OmniToken's strong [security model](contracts/main/OmniToken#erc20-extensions-and-deviations-from-standards-to-increase-security)
* Dublr's implementation of reentrancy protection via the [Checks-Effects-Interactions](https://blog.openzeppelin.com/reentrancy-after-istanbul/) pattern
* reentrancy locks
* extensive unit testing

## Quick Start

### Setting up MetaMask

1. Install the MetaMask app or Chrome extension, and follow its directions to create a wallet.
1. Fund your wallet by copying your wallet address from MetaMask and sending an ETH balance there.
1. Tap/click on "Don't see your token? Import tokens", then choose "Custom token".
1. Enter the Dublr contract address: `TODO`, the token symbol (DUBLR), and the token precision (18).

### Buying Dublr tokens

1. On the MetaMask app: open the MetaMask browser (open the "hamburger menu", the three-line button at top left, then tap "Browser"). If you are using a desktop browser with the MetaMask extension, you can just browse directly to the following URL.
1. Open the Etherscan page for the Dublr contract: `TODO`.
1. Make sure you're on the "Contract" tab. Tap "Write".
1. Tap/click "Connect to Web3" then "MetaMask" to connect your MetaMask wallet to EtherScan. You should now see a green dot in Etherscan indicating that your wallet is connected.
1. Find the "buy" function, and tap/click to open the parameter list. Fill in how much ETH you want to use to buy Dublr tokens in the "payableAmount" box. Tap/click "Write" to purchase Dublr tokens.
  * Note: In the early days of Dublr, you probably want to call `buy()` to get the best possible price on DUBLR tokens, whether bought or minted. Later, if the market price for DUBLR tokens becomes much lower than the (exponentially growing) mint price as a result of a strong increase in supply of tokens sold significantly below the mint price, then you may want to call `buy(/* allowMinting = */ false)` instead of `buy()` in order to disable minting, so that the ETH amount that you send doesn't end up minting DUBLR tokens for an exorbitant price.
1. If you already imported the DUBLR as a custom token, then you should see your tokens appear in your MetaMask wallet summary screen.

Because Dublr implements the ERC20 API, Dublr tokens may also be able to be bought on an ERC20-compatible external decentralized exchange (DEX) such as UniSwap, if there is liquidity on the exchange. However, ensure that you are getting a good price, relative to the price of Dublr tokens on Dublr's built-in DEX. Use the "Read" tab to call `mintPrice` to determine the current mint price, and call `cheapestSellOrder` or `allSellOrders` to see orders in Dublr's own order book.

### Selling Dublr tokens

1. Open the Etherscan page for the Dublr contract again, as above.
1. Make sure you're on the "Contract" tab. Tap/click "Read".
1. Connect your Web3 wallet (MetaMask) if it's not already connected.
1. Find the `mintPrice` function, and tap/click "Read" to read the current mint price. Use this to decide on a sell price.
1. Tap/click "Write". Find the `sell` function, and tap/click to open the parameter list.
1. Fill in `priceETHPerDUBLR_x1e9` as the sell price, in ETH per DUBLR, multiplied by `10^9` (1 billion).  For example, to sell at a price of `0.005`, `priceETHPerDUBLR_x1e9` should be `5000000`.
1. Fill in `amountDUBLRWEI` with the number of Dublr tokens you want to want to list for sale, in DUBLR wei (where 1 DUBLR == `10^18` DUBLR wei).
1. Tap/click "Write" to list these tokens for sale.

Any existing sell order will be canceled automatically before listing the new order. While a sell order is listed, `amountDUBLRWEI` tokens will be deducted from your wallet balance. If the sell order is canceled, any unsold tokens will be returned to your wallet balance.

Your sell order can be canceled at any time by calling the "Write" function `cancelMySellOrder`.

Alternatively, Dublr tokens can be sold or provided as liquidity on an ERC20-compatible external decentralized exchange (DEX) such as UniSwap.

### Sending/spending Dublr tokens:

Use your MetaMask wallet to send tokens to another wallet.

For more advanced usage, you can use any dapp, contract, or commandline library or API that supports the [ERC20, ERC777, ERC1363, or ERC4524 APIs](contracts/main/OmniToken) to send, spend, or use Dublr tokens, or to approve token spenders.

## Contract info

* The Dublr smart contract is deployed at address: `TODO`
* The Dublr contract was deployed on `TODO date`, starting the clock on the [mint price schedule](contracts/main/Dublr#getting-the-current-mint-price).
* The initial mint price is 0.000005 ETH per DUBLR (`initialMintPriceETHPerDUBLR_x1e9 == 5000`).
* Owner/deployer's initial mint amount: 2B DUBLR (10k ETH equiv at 0.000005 ETH per DUBLR). All other supply is minted on demand.
* The source code of the Dublr smart contract can be verified to be the same as the source code in this GitHub repository using Etherscan. `TODO`

## Fees

The market maker fee (subtracted from the sale price of sellers' tokens, i.e. deducted from the ETH amount sent from buyer to seller) is 0.15% of the sell order price. This fee is less than the sum of the market maker fee (0.1%) plus the market taker fee (an additional 0.1%) charged by Binance's for their non-VIP trading tier (0.2% total fees per trade) and half the size of Uniswap's fees (0.3%).

Additionally, all ETH value used to mint new tokens via the `buy()` function are charged as a minting fee, which is an irreversible exchange of ETH for DUBLR.

Fees are sent to the owner/creator of the Dublr contract. Fees are charged irreversibly, as the cost of services performed by the Dublr smart contract, and no refunds will be given.

The value in ETH of any purchased tokens can only be reclaimed by selling the Dublr tokens on the built-in DEX, or on another DEX such as UniSwap. Selling tokens may incur losses, as the exchange rate fluctuates due to market forces. No promise of increase in value or return on investment, and no promise of avoidance of loss or damage, is made or implied by the owner/creator of the Dublr contract. (See next section.)

# LEGAL AGREEMENT AND DISCLAIMERS

By electing to mint, buy, sell, gift, transmit, store, or otherwise use Dublr tokens (collectively, by using the Dublr token, or by using any functionality implemented by the Dublr smart contract), you agree to all terms of the [Legal Agreement and Disclaimers](LEGAL.md).

# Author

Dublr was created by Hiroshi Yamamoto, and is made available under the [MIT license](LICENSE).

虎穴に入らずんば虎子を得ず。

For updates on the Dublr smart contract and DUBLR token, follow [@DublrToken](https://twitter.com/DublrToken) on Twitter.


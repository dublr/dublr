<img alt="Dublr Logo" height="300" width = "300" src="https://raw.githubusercontent.com/dublr/dublr/main/icon.png">

# The Dublr Token and the Dublr Decentralized Exchange (DEX)

## Short overview

Dublr is a fungible token smart contract that implements the ERC20 token standard, along with several extensions to make token sending safer and more secure (ERC1363, ERC4524, EIP2612), and a number of other ERC20 extensions to mitigate ERC20 allowance exploit issues.

Furthermore, Dublr contains its own built-in decentralized exchange (DEX) for decentralized finance (DeFi), so it is both a token and a DEX. Supply is generated on-demand by minting, with a mint price that grows exponentially.

The Dublr DEX is accessible at [https://dublr.github.io/](https://dublr.github.io/) . Dublr is deployed on Polygon mainnet, therefore DUBLR tokens must be bought with Polygon MATIC (not ERC20-wrapped MATIC tokens on the Ethereum network).

![image](https://user-images.githubusercontent.com/97215152/197721148-51498198-6c94-4407-9a75-59c8b1484ee3.png)

## Long overview

**Supported token APIs:** Dublr builds on the [OmniToken](contracts/main/OmniToken) library, which supports a wide range of APIs for:
  * sending/using tokens using the ERC20 API;
  * safe sending of ERC20-compatible tokens (to prevent the irretrievable loss of tokens when they are sent to the wrong address);
  * safe granting of 3rd party spending allowances (to counter a well-known "double allowance spend" vulnerability of ERC20);
  * time-limited allowances (so that forgotten allowances don't render a wallet vulnerable to being drained);
  * the granting of allowances via signed permits using the EIP2612 permitting standard; and
  * recipient notification after a transfer is complete using the ERC1363 and ERC4524 API, and spender notification after an allowance is granted using the ERC1363 API.

**Buying/selling tokens:** Dublr token supply is not created and distributed the usual way, via ICO or airdrop, but rather Dublr has its own built-in decentralized exchange or DEX (sell-side only). Sellers can list Dublr tokens for sale, and buyers can buy Dublr tokens, using the Dublr contract itself. Token supply grows automatically as needed, by minting new tokens to meet demand, when there is insufficient supply of tokens for sale to meet buyer demand below the mint price.

**Mint price:** The price at which new tokens are minted doubles every 90 days, equivalent to a compound interest rate for the maximum price a coin may be sold for of 0.77% per day. The mint price increases exponentially at this rate over 30 doubling periods (7.5 years). The mint price puts a hard cap on how fast the price of Dublr tokens may grow.

**Security:** Dublr is tightly secured against security vulnerabilities, via:

* Third-party security audits by two companies: Omniscia and SolidProof.
* Static analysis, using SolHint and Slither.
* Extensive unit testing.
* OmniToken's strong [security model](contracts/main/OmniToken#erc20-extensions-and-deviations-from-standards-to-increase-security), with particularly close attention paid to protection against reentrancy attacks via the [Checks-Effects-Interactions](https://blog.openzeppelin.com/reentrancy-after-istanbul/) pattern, and via reentrancy locks.

## Quick Start

* Set up a cryptocurrency wallet (e.g. MetaMask or Coinbase Wallet), and fund it with MATIC. You may need to enable experimental networks under advanced settings to be able to switch your wallet to the Polygon Mainnet network.
* Visit the Dublr dapp at [https://dublr.github.io/](https://dublr.github.io/).
* Buying: click on the Buy tab, decide how much MATIC to spend on Dublr tokens, accept the terms and conditions, and click "Buy DUBLR tokens".
  * Slippage protection is implemented to ensure you end up with close to as many tokens as you expected, preventing frontrunning attacks.
  * Once you have DUBLR tokens in your ERC20-compatible wallet, you can send DUBLR tokens to another wallet address at any time, using the send functionality of the wallet.

![image](https://user-images.githubusercontent.com/97215152/197721752-cd8a6e66-e2b8-4b6f-86a0-57dd40567c7a.png)

* Selling: click on the Sell tab, decide how many DUBLR tokens to sell and at what price, accept the terms and conditions, and click "List DUBLR tokens for sale".
  * Only one sell order may be listed at a time for a given wallet. Listing another sell order will cancel the active sell order.
  * You can choose to cancel your currently-active sell order under the Sell tab anytime before the order is bought by a buyer.

![image](https://user-images.githubusercontent.com/97215152/197722095-439aa9fb-a858-4acf-ab32-b941a5f1ed52.png)

* You can view the depth chart and the orderbook in the Orderbook tab.

Note that there is no guarantee of sufficient demand or liquidity on the buy side of any decentralized or centralized exchange, including the Dublr DEX, to be able to sell DUBLR at any given price. Therefore, there is no guarantee whatsoever of profit from trading Dublr tokens. See the full [Legal Agreement and Disclaimers](https://github.com/dublr/dublr/blob/main/LEGAL.md) for more information.

## Contract info

Dublr contract deployment details:

* Address: Polygon mainnet address [`0x3D739A2db4F42632ca090a7a6713a9A62DB994C0`](https://polygonscan.com/token/0x3D739A2db4F42632ca090a7a6713a9A62DB994C0).
* Deployed from git commit: [`eb50917365bbbb0d948efe656610c5abe06aa3d8`](https://github.com/dublr/dublr/tree/eb50917365bbbb0d948efe656610c5abe06aa3d8).
* The source code of the Dublr smart contract can be [verified to be the same as the source code in this GitHub repository using PolygonScan](https://polygonscan.com/address/0x3D739A2db4F42632ca090a7a6713a9A62DB994C0#code).
* Deployment date: 2022-10-14, 22:06 UTC (this starts the clock on the [mint price schedule](contracts/main/Dublr#getting-the-current-mint-price)).
* Initial mint price: is `0.0005` MATIC per DUBLR (`initialMintPriceNWCPerDUBLR_x1e9 == 500000`).
* Supply:
  * Initial amount of DUBLR minted by the creator of Dublr: `0 DUBLR` (the creator of Dublr owns no DUBLR tokens, in order for DUBLR to not be considered a security).
  * All supply is minted on demand, when the demand for DUBLR tokens exceeds the supply of DUBLR tokens for sale below the mint price.

The Dublr smart contract is intentionally deployed as a *non-proxied contract*, so the code is not changeable or upgradeable by the creator of Dublr after deployment. This decision was made in order to increase the security of the deployed Dublr smart contract (since it cannot be changed after deployment). The decision was made only after thorough an enormous amount of development effort, testing, correctness proofs, and internal auditing, and only after two extensive third-party security audits were passed. Non-proxied contracts are far more secure than proxied contracts, as long as the code has passed extensive unit testing and thorough third-party security audits, because they can continue to operate in a trustless way.

## Fees

**Buyer fees:** There are no market taker fees for buying tokens listed on the built-in DEX. All MATIC that is spent to mint new tokens is collected as a nonrefundable minting fee.

**Seller fees:** A nonrefundable market maker fee of 0.15% is subtracted from the MATIC amount transferred from the buyer to the seller when tokens are bought. This fee is lower than most DEX fees, e.g. 0.3% for Uniswap, and lower than the total fee for most centralized exchange fees, e.g. 0.2% for Binance (0.1% market maker fee plus 0.1% market taker fee).

# LEGAL AGREEMENT AND DISCLAIMERS

**Disclaimers for US SEC compliance:** The name "Dublr" describes only the growth of the mint price, not the profitability of DUBLR tokens, or the growth of any fair market value of DUBLR tokens. The growth of the mint price sets a hard <i>upper</i> bound on how fast the price of DUBLR can grow relative to ETH, enforced by increasing total supply of tokens to meet demand whenever the demand outstrips the supply of tokens for sale below the mint price. There is no <i>lower</i> bound on price, and minting is an inherently deflationary activity, so there are no guarantees or promises, express or implied, about the profitability of purchasing DUBLR tokens. The purchasing, sale, and use of DUBLR tokens is entirely at the purchaser's own risk. DUBLR tokens may not be able to be sold without incurring loss, or may not be able to be sold at all if there is insufficient demand. Collected fees will not be used to fund ongoing development, marketing, or any other action beneficial to DUBLR token holders, and cannot be used to fund ongoing maintenance or improvement of the Dublr smart contract code, since no changes can be made to the deployed Dublr contract code after deployment. Therefore, any MATIC spent to mint or sell DUBLR tokens does not constitute investment in a common enterprise. By buying, selling, or using DUBLR tokens, you signify that you agree to the full Dublr [Legal Agreement and Disclaimers](https://github.com/dublr/dublr/blob/main/LEGAL.md).

# Author

Dublr was created by Hiroshi Yamamoto, and is made available under the [MIT license](LICENSE).

虎穴に入らずんば虎子を得ず。

For non-promotional (informational-only) updates on the Dublr smart contract and DUBLR token, follow [@DublrToken](https://twitter.com/DublrToken) on Twitter.


# Dublr API

[Dublr](https://github.com/dublr/dublr) is a fungible token smart contract that implements several token standards. It has its own built-in distributed exchange (so it is both a token and a DEX). Supply is generated on-demand by minting, with a mint price that grows exponentially.

The token standards implemented by Dublr (ERC20, ERC1363, ERC4524, EIP2612) are described in the documentation for the underlying [OmniToken library](../OmniToken).

The DEX functionality of Dublr is documented below.

## Selling API

### Getting the current mint price

```
function mintPrice() public view returns (uint256 mintPriceNWCPerDUBLR_x1e9);
```

Returns the current mint price, in NWC per DUBLR (multiplied by 1e9, i.e. in fixed-point representation with the decimal point shifted right 9 places). NWC stands for "network currency", which is the currency of the network which the Dublr contract is deployed on (MATIC for Polygon, ETH for Ethereum, etc.).

This mint price should be consulted in determining what price to use to sell tokens at. If a sell order is priced above the mint price, there is no way for a buyer to buy tokens in the sell order until the mint price rises above the sell order price.

Dublr uses a polynomial approximation to the exponential function, so the doubling is not quite precise. The mint price schedule is as follows. Mint prices are shown as fractional decimals below rather than in fixed point, e.g. if `mintPriceNWCPerDUBLR_x1e9 == 5000`, then the mint price is shown as `0.000005000`.

| Days since Dublr contract creation | Mint price (NWC per DUBLR) |
| ---: | ---: |
| 0 | 0.000005000 |
| 90 | 0.000009997 |
| 180 | 0.000019981 |
| 270 | 0.000039915 |
| 360 | 0.000079700 |
| 450 | 0.000159066 |
| 540 | 0.000317315 |
| 630 | 0.000632707 |
| 720 | 0.001260991 |
| 810 | 0.002512004 |
| 900 | 0.005001804 |
| 990 | 0.009954800 |
| 1080 | 0.019803274 |
| 1170 | 0.039376907 |
| 1260 | 0.078260991 |
| 1350 | 0.155471118 |
| 1440 | 0.308712220 |
| 1530 | 0.612715781 |
| 1620 | 1.215527059 |
| 1710 | 2.410304001 |
| 1800 | 4.777270726 |
| 1890 | 9.464331323 |
| 1980 | 18.741389513 |
| 2070 | 37.095045996 |
| 2160 | 73.389200218 |
| 2250 | 145.128065282 |
| 2340 | 286.862348030 |
| 2430 | 566.759774746 |
| 2520 | 1119.251364127 |
| 2610 | 2209.328547933 |
| 2700 | 4359.098693581 |
| >=2701 | 0.000000000 |

The mint price is returned as `0` after 30 doubling periods (90 days each) from the creation of the Dublr contract, and minting is disabled after this time (i.e. after ~7.5 years total), fixing the total supply forever.

The initial mint price is NWC per DUBLR is 0.000005, meaning that initially, 1/0.000005 == 200000 DUBLR tokens are minted for every NWC token spent by a buyer. If you spent 1 NWC wei right after the Dublr contract is launched, you would end up with 200000 DUBLR wei (both tokens use the same equivalence of 1 token = `10^18` wei), and ninety days later, after the mint price has doubled once, spending another 1 NWC on minting would cause only roughly 100000 DUBLR tokens to be minted. (See [Disclaimers](https://github.com/dublr/dublr/blob/main/LEGAL.md) re. non-monetary-equivalence of DUBLR tokens.)

However, minting will also cease when the supply of tokens listed for sale in the built-in DEX, at a price below the current mint price, exceeds buyer demand. This will happen once the minting price becomes exorbitant relative to the market price.

### Listing tokens for sale

```
function sell(uint256 priceNWCPerDUBLR_x1e9, uint256 amountDUBLRWEI) external;
```

Lists `amountDUBLRWEI` DUBLR tokens (measured in DUBLR wei, where 1 DUBLR = `10^18` DUBLR wei) for sale, at a price of `priceNWCPerDUBLR_x1e9 * 10^-9` NWC tokens per DUBLR token.

When tokens are listed for sale, `amountDUBLRWEI` tokens are deducted from the seller's balance. The listed tokens are returned to the seller's balance if the seller cancels the order. The listed tokens are moved to the buyer's balance if a buyer buys the order. Buyers may buy part or all of an active sell order.

A caller may have only one active sell order at a time. If a seller already has an existing sell order, and they call `sell` again, the existing sell order will automatically be canceled via `cancelMySellOrder()` before the new order is placed.

If `sellOrder.priceNWCPerDUBLR_x1e9 < mintPrice()` then it is possible for a buyer to buy the sell order, as long as there aren't any cheaper sell orders listed in the orderbook (orders are bought in increasing order of price).

Note that if you list tokens for sale, the address from which you call `sell(price, amount)` MUST be able to accept NWC payments upon sale of the listed tokens -- in other words, the seller address must be a regular wallet (an Externally-Owned Account or EOA), or it must be a contract that has a `payable` function that is triggered on an empty data payload (`receieve` or `fallback`). If the seller address is a contract and it rejects NWC payment by either not defining one of these functions, or the function reverts, then the payment is considered forfeited, because if the Dublr DEX allowed sellers to revert any buyer's transaction, this would allow the seller to execute a denial of service attack, preventing buyers from using the DEX.

Note that a market maker fee of 0.15% is subtracted from the NWC order amount sent to the seller, when a buyer buys a sell order that is listed on the built-in decentralized exchange (DEX).

### Getting caller's current sell order

```
function mySellOrder() external view returns (uint256 priceNWCPerDUBLR_x1e9, uint256 amountDUBLRWEI);
```

Returns the price and amount of the caller's current sell order.

### Reading the orderbook

```
function orderBookSize() external view returns (uint256 numEntries);
```

Returns the number of orders in the orderbook.

```
function cheapestSellOrder() external view returns (uint256 priceNWCPerDUBLR_x1e9, uint256 amountDUBLRWEI);
```

Returns the price and amount of the cheapest sell order of all orders in the orderbook.

```
struct PriceAndAmount {
    uint256 priceNWCPerDUBLR_x1e9;
    uint256 amountDUBLRWEI;
}

function allSellOrders() external view returns (PriceAndAmount[] memory priceAndAmountOfSellOrders);
```

Returns all sell orders in the orderbook, in min-heap order (a partial ordering, not a total order) by price.

### Canceling caller's current sell order

```
function cancelMySellOrder() public;
```

Cancels the caller's current sell order, and returns any unsold tokens in the sell order back to the seller's balance.

## Buying API

```
function buy() external payable;

function buy(bool allowMinting) external payable;
```

Buys as many tokens as can be afforded given the payable NWC value of the function call. Sell orders are purchased in increasing order of price, until the current mint price is reached, at which point any remaining NWC balance is used to mint tokens at the current mint price. Optionally, minting can be disabled by calling `buy(false)`.

If a buyer buys DUBLR tokens from a sell order, the DUBLR tokens are transferred from the orderbook to the buyer, and the NWC equivalent is transferred from the buyer to the seller, minus market maker fees (effectively charged to the seller, not the buyer).

Because change is given if the buyer sends an NWC amount that is not a whole multiple of the token price, the buyer must be able to receive NWC payments. In other words, the buyer account must either be a non-contract wallet (an EOA), or a contract that implements one of the payable `receive()` or `fallback()` functions to receive payment.

Note that a large number of sell orders could be bought with a single call to `buy`, which may cause the block gas limit to be hit. If this happens, the only way to buy tokens is to reduce the NWC amount sent, and buy the desired amount in multiple transactions.

For coins that are minted, the full NWC amount sent by the buyer is collected as a minting fee, and exchanged for DUBLR tokens.

## Owner API

The owner/deployer of the Dublr contract may also call the following methods to disable/enable features and/or cancel all sell orders in case of emergency (e.g. if a vulnerability is found):

```
function _owner_setMinSellOrderValueNWCWEI(uint256 value) external ownerOnly;

function _owner_enableSelling(bool enable) external ownerOnly;

function _owner_enableBuying(bool enable) external ownerOnly;

function _owner_enableMinting(bool enable) external ownerOnly;

function _owner_cancelAllSellOrders() external ownerOnly;
```

## Legal agreement

By using the Dublr API, you confirm that the Dublr token ("DUBLR") is not considered an unregistered or illegal security, and that the Dublr smart contract is not considered an unregistered or illegal exchange, by the laws of any legal jurisdiction in which you hold or use Dublr tokens.

In some jurisdictions, such as the United States, any use, transfer, or sale of a token is a taxable event. It is your responsibility to record the purchase price and sale price in NWC or your local currency equivalent for each use, transfer, or sale of DUBLR tokens you own, and to pay the taxes due.

By using Dublr, you agree to the full [Legal Agreement and Disclaimers for Dublr and OmniToken](https://github.com/dublr/dublr/blob/main/LEGAL.md).


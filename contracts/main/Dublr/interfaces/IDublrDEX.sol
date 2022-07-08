// SPDX-License-Identifier: MIT

// The Dublr token (symbol: DUBLR), with a built-in distributed exchange for buying/selling tokens.
// By Hiroshi Yamamoto.
// 虎穴に入らずんば虎子を得ず。
//
// Officially hosted at: https://github.com/dublr/dublr

pragma solidity 0.8.15;

/**
 * @title IDublrDex
 * @dev Dublr distributed exchange interface.
 * @author Hiroshi Yamamoto
 */
interface IDublrDEX {

    // -----------------------------------------------------------------------------------------------------------------
    // Events

    /**
     * @notice Emitted when a seller's tokens are listed for sale.
     *
     * @param seller The account of the seller of the listed tokens.
     * @param priceETHPerDUBLR_x1e9 The list price of the tokens, in ETH per DUBLR (multiplied by `10^9`).
     * @param amountDUBLRWEI The number of tokens listed for sale.
     */
    event ListSell(address indexed seller, uint256 priceETHPerDUBLR_x1e9, uint256 amountDUBLRWEI);

    /**
     * @notice Emitted when a sell order is canceled.
     *
     * @param seller The account of the token seller in the canceled listing.
     * @param priceETHPerDUBLR_x1e9 The price tokens were listed for, in ETH per DUBLR (multiplied by `10^9`).
     * @param amountDUBLRWEI The number of tokens that were listed for sale.
     */
    event CancelSell(address indexed seller, uint256 priceETHPerDUBLR_x1e9, uint256 amountDUBLRWEI);

    /**
     * @notice Emitted when the a sell order is partially or fully purchased by a buyer.
     *
     * @dev When amountRemainingInOrderDUBLR reaches 0, the sell order is removed from the orderbook.
     *
     * @param buyer The buyer account.
     * @param seller The seller account.
     * @param priceETHPerDUBLR_x1e9 The price tokens were listed for, in ETH per DUBLR (multiplied by `10^9`).
     * @param amountBoughtDUBLRWEI The number of DUBLR tokens (in DUBLR wei, where 1 DUBLR == `10^18` DUBLR wei)
     *          that were transferred from the seller to the buyer.
     * @param amountRemainingInOrderDUBLRWEI The number of DUBLR tokens (in DUBLR wei) remaining in the order.
     * @param amountSentToSellerETHWEI The amount of ETH (in wei) transferred from the buyer to the seller.
     * @param amountChargedToBuyerETHWEI The amount of ETH (in wei) charged to the buyer, including fees.
     */
    event Buy(address indexed buyer, address indexed seller,
            uint256 priceETHPerDUBLR_x1e9, uint256 amountBoughtDUBLRWEI, uint256 amountRemainingInOrderDUBLRWEI,
            uint256 amountSentToSellerETHWEI, uint256 amountChargedToBuyerETHWEI);

    /**
     * @notice Emitted when a buyer calls `buy()`, and there are no sell orders listed below the mint price,
     * leading to new tokens being minted for the buyer.
     *
     * @param buyer The account to mint tokens for.
     * @param priceETHPerDUBLR_x1e9 The current mint price, in ETH per DUBLR (multiplied by `10^9`).
     * @param amountSpentETHWEI The amount of ETH that was spent by the buyer to mint tokens.
     * @param amountMintedDUBLRWEI The number of tokens that were minted for the buyer.
     */
    event Mint(address indexed buyer, uint256 priceETHPerDUBLR_x1e9, uint256 amountSpentETHWEI,
            uint256 amountMintedDUBLRWEI);

    /**
     * @notice Emitted when 90% of the supplied buyer's ETH balance has been expended on buying sell orders
     */
    event OutOfGasForBuyingSellOrders(address indexed buyer, uint256 buyOrderRemainingETHWEI, uint256 totBoughtDUBLRWEI);

    /**
     * @notice Emitted to return any change to the buyer from a `buy()` call, where the provided ETH amount was
     * not a whole multiple of the token price.
     *
     * @param buyer The buyer account.
     * @param refundedETHWEI The amount of ETH (in wei) that was refunded to the buyer.
     */
    event RefundChange(address indexed buyer, uint256 refundedETHWEI);

    /**
     * @notice Emitted when an ETH payment could not be sent to a seller for any reason. These payments
     * are considered forfeited as per the documentation on the `sell(...)` function.
     *
     * @param seller The seller account to which an attempt was made to send an ETH payment.
     * @param amountETHWEI The amount of ETH (in wei) that the Dublr contract attempted to send.
     * @param data Any data returned by the failed payable call (may contain revert reason information).
     */
    event Unpayable(address indexed seller, uint256 amountETHWEI, bytes data);

    // -----------------------------------------------------------------------------------------------------------------
    // Public functions for interacting with order book

    /**
     * @notice The number of sell orders in the order book.
     *
     * @return numEntries The number of entries in the order book.
     */
    function orderBookSize() external view returns (uint256 numEntries);

    /**
     * @notice The price of the cheapest sell order in the order book for any user.
     *
     * @dev If there are no current sell orders, reverts.
     *
     * @return priceETHPerDUBLR_x1e9 The price of DUBLR tokens in the cheapest sell order, in ETH per DUBLR
     *          (multiplied by `10^9`).
     * @return amountDUBLRWEI the number of DUBLR tokens for sale, in DUBLR wei (1 DUBLR = 10^18 DUBLR wei).
     */
    function cheapestSellOrder() external view returns (uint256 priceETHPerDUBLR_x1e9, uint256 amountDUBLRWEI);

    /**
     * @notice The current sell order in the order book for the caller.
     *
     * @dev If the caller has no current sell order, reverts.
     *
     * @return priceETHPerDUBLR_x1e9 The price of DUBLR tokens in the caller's current sell order, in ETH per DUBLR
     *          (multiplied by `10^9`).
     * @return amountDUBLRWEI the number of DUBLR tokens for sale, in DUBLR wei (1 DUBLR = `10^18` DUBLR wei).
     */
    function mySellOrder() external view returns (uint256 priceETHPerDUBLR_x1e9, uint256 amountDUBLRWEI);

    /**
     * @notice Cancel the caller's current sell order in the orderbook.
     *
     * @dev Restores the amount of the caller's sell order back to the seller's token balance.
     *
     * If the caller has no current sell order, reverts.
     */
    function cancelMySellOrder() external;
    
    /**
     * @dev The price and amount of a sell order in the orderbook.
     *
     * @param priceETHPerDUBLR_x1e9 The price of DUBLR tokens in the caller's current sell order, in ETH per DUBLR
     *          (multiplied by `10^9`).
     * @param amountDUBLRWEI the number of DUBLR tokens for sale, in DUBLR wei (1 DUBLR = `10^18` DUBLR wei).
     */
    struct PriceAndAmount {
        // Tuples are not a first-class type in Solidity, so need to use a struct to return an array of tuples
        uint256 priceETHPerDUBLR_x1e9;
        uint256 amountDUBLRWEI;
    }

    /**
     * @notice Get all sell orders in the orderbook.
     * 
     * @dev Note that the orders are returned in min-heap order by price, and not in increasing order by price.
     *
     * @return priceAndAmountOfSellOrders A list of all sell orders in the orderbook, in min-heap order by price.
     * Each list item is a tuple consisting of the price of each token in ETH per DUBLR (multiplied by `10^9`),
     * and the number of tokens for sale.
     */
    function allSellOrders() external view
            // Returning an array requires ABI encoder v2, which is the default in Solidity >=0.8.0.
            returns (PriceAndAmount[] memory priceAndAmountOfSellOrders);

    // -----------------------------------------------------------------------------------------------------------------
    // Selling

    /** 
     * @notice List DUBLR tokens for sale in the orderbook.
     *
     * @dev List some amount of the caller's DUBLR token balance for sale. This may be canceled any time before the
     * tokens are purchased by a buyer. If tokens from the order are bought by a buyer, the ETH value of the purchased
     * tokens are sent to the seller, minus a market maker fee of 0.15%.
     *
     * During the time that tokens are listed for sale, the amount of the sell order is deducted from the token
     * balance of the seller, to prevent double-spending. The amount is returned to the seller's token balance if
     * the sell order is later canceled.
     *
     * If there is already a sell order in the order book for this sender, then that old order is automatically
     * canceled before the new order is placed (there may only be one order per seller in the order book at one
     * time).
     *
     * Note that the equivalent ETH amount of the order must be greater than the gas supplied to run this sell
     * function, to ensure that the order size is not unreasonably small (small orders cost buyers a lot of gas
     * relative to the number of tokens they buy). The equivalent ETH amount of the order can be calculated as:
     * `uint256 amountETHWEI = amountDUBLRWEI * priceETHPerDUBLR_x1e9 / 1e9` . If `amountETHWEI` is not greater
     * than the gas amount supplied to call the `sell()` function, then the transaction will revert with
     * "Order value too small". Note that gas is normally specified in Gwei, so you need to multiply the gas
     * value by 1e9 to convert to wei before making this comparison.
     *
     * @notice Because payment for the sale of tokens is sent to the seller when the tokens are sold, the seller
     * account must be able to receive ETH payments. In other words, the seller account must either be a non-contract
     * wallet (an Externally-Owned Account or EOA), or a contract that implements one of the payable `receive()`
     * or `fallback()` functions, in order to receive payment. If sending ETH to the seller fails because the
     * seller account is a non-payable contract, then the ETH from the sale of tokens is forfeited.
     *
     * @notice By calling this function, you confirm that the Dublr token is not considered an unregistered or illegal
     * security, and that the Dublr smart contract is not considered an unregistered or illegal exchange, by
     * the laws of any legal jurisdiction in which you hold or use the Dublr token.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is a taxable
     * event. It is your responsibility to record the purchase price and sale price in ETH or your local currency
     * equivalent for each use, transfer, or sale of DUBLR tokens you own, and to pay the taxes due.
     *
     * @param priceETHPerDUBLR_x1e9 the price to list the tokens for sale at, in ETH per DUBLR token, multiplied
     *          by `10^9`.
     * @param amountDUBLRWEI the number of DUBLR tokens to sell, in units of DUBLR wei (1 DUBLR == `10^18` DUBLR wei).
     *          Must be less than or equal to the caller's balance. Additionally,
     *          `amountETHWEI = amountDUBLRWEI * priceETHPerDUBLR_x1e9 / 1e9` must be greater than the
     *          ETH value of gas supplied to run the function, to ensure the order size is not tiny.
     */
    function sell(uint256 priceETHPerDUBLR_x1e9, uint256 amountDUBLRWEI) external;
    
    // -----------------------------------------------------------------------------------------------------------------
    // Buying

    /**
     * @notice Buy the cheapest DUBLR tokens available, for the equivalent value of the ETH `payableAmount`/`value`
     * sent with the transaction.
     *
     * @dev A payable function that exchanges the ETH value attached to the transaction for DUBLR tokens.
     *
     * Buys tokens listed for sale, if any sell orders are listed below the mint price and `allowBuying == true`.
     * Sell orders are purchased in increasing order of price, until the supplied ETH amount runs out or the mint price
     * is reached. Then this function will mint new tokens at the current mint price with the remaining ETH balance, if
     * `allowMinting == true`, increasing total supply.
     *
     * At least `minimumTokensToBuyOrMintDUBLRWEI` DUBLR tokens must be either purchased from sell orders or minted,
     * otherwise the transaction will revert with "Too much slippage". You can determine how many coins you expect
     * to receive for a given ETH payable amount, by examining the order book (call `allSellOrders()` to get all
     * orderbook entries, and then sort them in increasing order of price).
     *
     * A maximum of 90% of the supplied gas may be used to buy sell orders from the built-in DEX (to prevent
     * gas exhaustion DoS attacks). If this gas limit is reached, buying will stop with the order partially filled,
     * an `OutOfGasForBuyingSellOrders` event will be emitted to signify that the order was only partially filled,
     * the unspent ETH balance will be returned to the buyer, and a `RefundChange` event will be emitted to inform
     * the buyer of the refund. (Note that `minimumTokensToBuyOrMintDUBLRWEI` tokens must still be bought in this
     * partially-filled order, otherwise the transaction will instead revert with "Out of gas".)
     *
     * Change is also refunded to the buyer if the buyer sends an ETH amount that is not a whole multiple of the token
     * price, and a `RefundChange` event is emitted. The buyer must be able to receive refunded ETH payments for the
     * `buy()` function to succed: the buyer account must either be a non-contract wallet (an EOA), or a contract
     * that implements one of the payable `receive()` or `fallback()` functions to receive payment.
     *
     * @notice By calling this function, you confirm that the Dublr token is not considered an unregistered or illegal
     * security, and that the Dublr smart contract is not considered an unregistered or illegal exchange, by
     * the laws of any legal jurisdiction in which you hold or use the Dublr token.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is a taxable
     * event. It is your responsibility to record the purchase price and sale price in ETH or your local currency
     * equivalent for each use, transfer, or sale of DUBLR tokens you own, and to pay the taxes due.
     *
     * @param minimumTokensToBuyOrMintDUBLRWEI The minimum number of tokens (in DUBLR wei, i.e. 10^-18 DUBLR) that the
     *      provided (payable) ETH value should buy, in order to prevent slippage. If at least this total number is not
     *      bought or minted by the time all ETH funds of the transaction have been expended, then the transaction is
     *      reverted and the full provided ETH amount is refunded (minus gas spent, since this is not refundable).
     *      This mechanism attempts to protect the user from any drastic and unfavorable price changes while their
     *      transaction is pending.
     * @param allowBuying If `true`, allow the buying of any tokens listed for sale below the mint price.
     * @param allowMinting If `true`, allow the minting of new tokens at the current mint price.
     */
    function buy(uint256 minimumTokensToBuyOrMintDUBLRWEI, bool allowBuying, bool allowMinting) external payable;
}


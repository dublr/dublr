// SPDX-License-Identifier: MIT

// The Dublr token (symbol: DUBLR), with a built-in distributed exchange for buying/selling tokens.
// By Hiroshi Yamamoto.
// 虎穴に入らずんば虎子を得ず。
//
// Officially hosted at: https://github.com/dublr/dublr

pragma solidity 0.8.17;

/**
 * @title IDublrDex
 * @dev Dublr distributed exchange interface.
 * @author Hiroshi Yamamoto
 */
interface IDublrDEX {

    // Note that NWC is used to denote the symbol of the network currency (ETH for Ethereum, MATIC for Polygon, etc.)

    // -----------------------------------------------------------------------------------------------------------------
    // Events

    /**
     * @notice Emitted when a seller's tokens are listed for sale.
     *
     * @param seller The account of the seller of the listed tokens.
     * @param priceNWCPerDUBLR_x1e9 The list price of the tokens, in NWC per DUBLR (multiplied by `10^9`),
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     * @param amountDUBLRWEI The number of tokens listed for sale.
     */
    event ListSellOrder(address indexed seller, uint256 priceNWCPerDUBLR_x1e9, uint256 amountDUBLRWEI);

    /**
     * @notice Emitted when a sell order is canceled.
     *
     * @param seller The account of the token seller in the canceled listing.
     * @param priceNWCPerDUBLR_x1e9 The price tokens were listed for, in NWC per DUBLR (multiplied by `10^9`),
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     * @param amountDUBLRWEI The number of tokens that were listed for sale.
     */
    event CancelSellOrder(address indexed seller, uint256 priceNWCPerDUBLR_x1e9, uint256 amountDUBLRWEI);

    /**
     * @notice Emitted when the a sell order is partially or fully purchased by a buyer.
     *
     * @dev When amountRemainingInOrderDUBLR reaches 0, the sell order is removed from the orderbook.
     *
     * @param buyer The buyer account.
     * @param seller The seller account.
     * @param priceNWCPerDUBLR_x1e9 The price tokens were listed for, in NWC per DUBLR (multiplied by `10^9`),
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     * @param amountBoughtDUBLRWEI The number of DUBLR tokens (in DUBLR wei, where 1 DUBLR == `10^18` DUBLR wei)
     *          that were transferred from the seller to the buyer.
     * @param amountRemainingInOrderDUBLRWEI The number of DUBLR tokens (in DUBLR wei) remaining in the order.
     * @param amountSentToSellerNWCWEI The amount of NWC (in wei) transferred from the buyer to the seller,
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     * @param amountChargedToBuyerNWCWEI The amount of NWC (in wei) charged to the buyer, including fees,
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     */
    event BuySellOrder(address indexed buyer, address indexed seller,
            uint256 priceNWCPerDUBLR_x1e9, uint256 amountBoughtDUBLRWEI, uint256 amountRemainingInOrderDUBLRWEI,
            uint256 amountSentToSellerNWCWEI, uint256 amountChargedToBuyerNWCWEI);

    /**
     * @notice Emitted when a buyer calls `buy()`, and there are no sell orders listed below the mint price,
     * leading to new tokens being minted for the buyer.
     *
     * @param buyer The account to mint tokens for.
     * @param priceNWCPerDUBLR_x1e9 The current mint price, in NWC per DUBLR (multiplied by `10^9`),
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     * @param amountSpentNWCWEI The amount of NWC that was spent by the buyer to mint tokens,
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     * @param amountMintedDUBLRWEI The number of tokens that were minted for the buyer.
     */
    event Mint(address indexed buyer, uint256 priceNWCPerDUBLR_x1e9, uint256 amountSpentNWCWEI,
            uint256 amountMintedDUBLRWEI);

    /**
     * @notice Emitted to return any change to the buyer from a `buy()` call, where the provided amount of
     * network currency was not a whole multiple of the token price.
     *
     * @param buyer The buyer account.
     * @param refundedNWCWEI The amount of NWC (in wei) that was refunded to the buyer,
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     */
    event RefundChange(address indexed buyer, uint256 refundedNWCWEI);

    /**
     * @notice Emitted when a payment in network currency could not be sent to a seller for any reason.
     * These payments are considered forfeited as per the documentation on the `sell(...)` function.
     *
     * @param seller The seller account to which an attempt was made to send a network currency payment.
     * @param amountNWCWEI The amount of NWC (in wei) that the Dublr contract attempted to send,
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     * @param data Any data returned by the failed payable call (may contain revert reason information).
     */
    event Unpayable(address indexed seller, uint256 amountNWCWEI, bytes data);

    // -----------------------------------------------------------------------------------------------------------------
    // Static call values
    
    /**
     * @dev Results of all statically-callable functions in a single call, used to reduce the number of RPC calls
     * in the style of MultiCall.
     */
    struct StaticCallValues {
        bool buyingEnabled;
        bool sellingEnabled;
        bool mintingEnabled;
        uint256 blockGasLimit;
        uint256 balanceNWCWEI;
        uint256 balanceDUBLRWEI;
        uint256 mintPriceNWCPerDUBLR_x1e9;
        uint256 maxPriceNWCPerDUBLR_x1e9;
        uint256 minSellOrderValueNWCWEI;
        PriceAndAmount mySellOrder;
        PriceAndAmount[] allSellOrders;
    }

    /**
     * @notice Get results of all statically-callable functions in a single call, to reduce the number of RPC calls.
     *
     * @return values The results of the statically-callable functions of the contract.
     */
    function getStaticCallValues() external returns (StaticCallValues memory values);

    // -----------------------------------------------------------------------------------------------------------------
    // Mint price
            
    /**
     * @notice The current mint price, in NWC per DUBLR (multiplied by `10^9`),
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     *
     * @dev Returns the current mint price for this token. Calls to `buy()` will buy tokens for sale
     * rather than minting new tokens, if there are tokens listed below the current mint price.
     *
     * The mint price grows exponentially, doubling every 90 days for 30 doubling periods, and then minting
     * is disabled. In practice, minting may no longer be triggered long before that time, if the supply
     * of coins for sale below the mint price exceeds demand.
     *
     * @return mintPriceNWCPerDUBLR_x1e9 The current mint price, in NWC per DUBLR, multiplied by `10^9`,
     *              or zero if the minting time period has ended (after 30 doubling periods),
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     */
    function mintPrice() external view returns (uint256 mintPriceNWCPerDUBLR_x1e9);

    // -----------------------------------------------------------------------------------------------------------------
    // Minimum sell order value

    /**
     * @notice The NWC value (in wei, == 10^-18 NWC) of the minimum sell order that may be listed for sale via `sell()`,
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     *
     * @return The NWC value of the minimum sell order,
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     */
    function minSellOrderValueNWCWEI() external returns (uint256);

    // -----------------------------------------------------------------------------------------------------------------
    // Public functions for interacting with order book
    
    /**
     * @dev The price and amount of a sell order in the orderbook.
     *
     * @param priceNWCPerDUBLR_x1e9 The price of DUBLR tokens in the caller's current sell order, in NWC per DUBLR
     *          (multiplied by `10^9`),
     *      where NWC is the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     * @param amountDUBLRWEI the number of DUBLR tokens for sale, in DUBLR wei (1 DUBLR = `10^18` DUBLR wei).
     */
    struct PriceAndAmount {
        // Tuples are not a first-class type in Solidity, so need to use a struct to return an array of tuples
        uint256 priceNWCPerDUBLR_x1e9;
        uint256 amountDUBLRWEI;
    }

    /**
     * @notice The number of sell orders in the order book.
     *
     * @return numEntries The number of entries in the order book.
     */
    function orderBookSize() external view returns (uint256 numEntries);

    /**
     * @notice The price of the cheapest sell order in the order book for any user.
     *
     * @return priceAndAmountOfSellOrder The price of DUBLR tokens in the cheapest sell order, in network currency per DUBLR
     *      (multiplied by `10^9`), and the number of DUBLR tokens for sale, in DUBLR wei (1 DUBLR = 10^18 DUBLR wei).
     *      Both values are 0 if the orderbook is empty.
     */
    function cheapestSellOrder() external view returns (PriceAndAmount memory priceAndAmountOfSellOrder);

    /**
     * @notice The current sell order in the order book for the caller, or (0, 0) if none.
     *
     * @return priceAndAmountOfSellOrder The price of DUBLR tokens in the caller's sell order, in network currency per DUBLR
     *      (multiplied by `10^9`), and the number of DUBLR tokens for sale, in DUBLR wei (1 DUBLR = 10^18 DUBLR wei).
     *      Both values are 0 if the caller has no sell order.
     */
    function mySellOrder() external view returns (PriceAndAmount memory priceAndAmountOfSellOrder);

    /**
     * @notice Cancel the caller's current sell order in the orderbook.
     *
     * @dev Restores the amount of the caller's sell order back to the seller's token balance.
     *
     * If the caller has no current sell order, reverts.
     */
    function cancelMySellOrder() external;

    /**
     * @notice Get all sell orders in the orderbook.
     * 
     * @dev Note that the orders are returned in min-heap order by price, and not in increasing order by price.
     *
     * @return priceAndAmountOfSellOrders A list of all sell orders in the orderbook, in min-heap order by price.
     * Each list item is a tuple consisting of the price of each token in network currency per DUBLR
     * (multiplied by `10^9`), and the number of tokens for sale.
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
     * tokens are purchased by a buyer. If tokens from the order are bought by a buyer, the NWC value of the purchased
     * tokens are sent to the seller, minus a market maker fee of 0.15%.
     * NWC represents the network currency (ETH for Ethereum, MATIC for Polygon, etc.).
     *
     * During the time that tokens are listed for sale, the amount of the sell order is deducted from the token
     * balance of the seller, to prevent double-spending. The amount is returned to the seller's token balance if
     * the sell order is later canceled.
     *
     * If there is already a sell order in the order book for this sender, then that old order is automatically
     * canceled before the new order is placed (there may only be one order per seller in the order book at one
     * time).
     *
     * Note that the equivalent NWC amount of the order must be at least `minSellOrderValueNWCWEI`, to ensure
     * that the order size is not unreasonably small (small orders cost buyers a lot of gas relative to the number
     * of tokens they buy). The equivalent NWC amount of the order can be calculated as:
     * `uint256 amountNWCWEI = amountDUBLRWEI * priceNWCPerDUBLR_x1e9 / 1e9` . If `amountNWCWEI` is not at least
     * `minSellOrderValueNWCWEI`, then the transaction will revert with "Order value too small".
     *
     * @notice Because payment for the sale of tokens is sent to the seller when the tokens are sold, the seller
     * account must be able to receive NWC payments. In other words, the seller account must either be a non-contract
     * wallet (an Externally-Owned Account or EOA), or a contract that implements one of the payable `receive()`
     * or `fallback()` functions, in order to receive payment. If sending NWC to the seller fails because the
     * seller account is a non-payable contract, then the NWC from the sale of tokens is forfeited.
     *
     * @notice By calling this function, you confirm that the Dublr token is not considered an unregistered or illegal
     * security, and that the Dublr smart contract is not considered an unregistered or illegal exchange, by
     * the laws of any legal jurisdiction in which you hold or use the Dublr token.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is a taxable
     * event. It is your responsibility to record the purchase price and sale price in NWC or your local currency
     * equivalent for each use, transfer, or sale of DUBLR tokens you own, and to pay the taxes due.
     *
     * @notice The creator and deployer of Dublr makes no claims, guarantees, or promises, express or implied, about the
     * profitability, utility, fitness for any purpose, or redeemability for fiat value of any purchased DUBLR tokens.
     * Fees collected for the sale or minting of DUBLR tokens are not used to fund any ongoing development of the
     * Dublr smart contract, and the Dublr smart contract runs autonomously on the blockchain without any intervention,
     * therefore the Dublr smart contract represents no common enterprise. By purchasing DUBLR tokens, you agree to
     * abide by all applicable laws, you assume all liability and risk for your actions, and you agree to all terms and
     * conditions in the Legal Agreement and Disclaimers for Dublr and OmniToken:
     * https://github.com/dublr/dublr/blob/main/LEGAL.md
     *
     * @param priceNWCPerDUBLR_x1e9 the price to list the tokens for sale at, in NWC per DUBLR token, multiplied
     *          by `10^9`.
     * @param amountDUBLRWEI the number of DUBLR tokens to sell, in units of DUBLR wei (1 DUBLR == `10^18` DUBLR wei).
     *          Must be less than or equal to the caller's balance. Additionally,
     *          `amountNWCWEI = amountDUBLRWEI * priceNWCPerDUBLR_x1e9 / 1e9` must be greater than
     *          the value of `minSellOrderValueNWCWEI()`, to ensure trivial orders don't waste gas.
     */
    function sell(uint256 priceNWCPerDUBLR_x1e9, uint256 amountDUBLRWEI) external;
    
    // -----------------------------------------------------------------------------------------------------------------
    // Buying

    /**
     * @notice Buy the cheapest DUBLR tokens available, for the equivalent value of the NWC `payableAmount`/`value`
     * sent with the transaction.
     *
     * @dev A payable function that exchanges the NWC value attached to the transaction for DUBLR tokens.
     * (NWC represents the network currency (ETH for Ethereum, MATIC for Polygon, etc.).)
     *
     * Buys tokens listed for sale, if any sell orders are listed below the mint price and `allowBuying == true`.
     * Sell orders are purchased in increasing order of price, until the supplied NWC amount runs out or the mint price
     * is reached. Then this function will mint new tokens at the current mint price with the remaining NWC balance, if
     * `allowMinting == true`, increasing total supply.
     *
     * At least `minimumTokensToBuyOrMintDUBLRWEI` DUBLR tokens must be either purchased from sell orders or minted,
     * otherwise the transaction will revert with "Too much slippage". You can determine how many coins you expect
     * to receive for a given NWC payable amount, by examining the order book (call `allSellOrders()` to get all
     * orderbook entries, and then sort them in increasing order of price).
     *
     * Change is also refunded to the buyer if the buyer sends an NWC amount that is not a whole multiple of the token
     * price, and a `RefundChange` event is emitted. The buyer must be able to receive refunded NWC payments for the
     * `buy()` function to succed: the buyer account must either be a non-contract wallet (an EOA), or a contract
     * that implements one of the payable `receive()` or `fallback()` functions to receive payment.
     *
     * For very large buy amounts with many small sell orders listed on the DEX, the amount of gas required to run the
     * transaction may exceed the block gas limit. In this case, the only way to buy tokens is to reduce the NWC amount
     * that is sent.
     *
     * @notice By calling this function, you confirm that the Dublr token is not considered an unregistered or illegal
     * security, and that the Dublr smart contract is not considered an unregistered or illegal exchange, by
     * the laws of any legal jurisdiction in which you hold or use the Dublr token.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is a taxable
     * event. It is your responsibility to record the purchase price and sale price in NWC or your local currency
     * equivalent for each use, transfer, or sale of DUBLR tokens you own, and to pay the taxes due.
     *
     * @notice The creator and deployer of Dublr makes no claims, guarantees, or promises, express or implied, about the
     * profitability, utility, fitness for any purpose, or redeemability for fiat value of any purchased DUBLR tokens.
     * Fees collected for the sale or minting of DUBLR tokens are not used to fund any ongoing development of the
     * Dublr smart contract, and the Dublr smart contract runs autonomously on the blockchain without any intervention,
     * therefore the Dublr smart contract represents no common enterprise. By purchasing DUBLR tokens, you agree to
     * abide by all applicable laws, you assume all liability and risk for your actions, and you agree to all terms and
     * conditions in the Legal Agreement and Disclaimers for Dublr and OmniToken:
     * https://github.com/dublr/dublr/blob/main/LEGAL.md
     *
     * @param minimumTokensToBuyOrMintDUBLRWEI The minimum number of tokens (in DUBLR wei, i.e. 10^-18 DUBLR) that the
     *      provided (payable) NWC value should buy, in order to prevent slippage. If at least this total number is not
     *      bought or minted by the time all NWC funds of the transaction have been expended, then the transaction is
     *      reverted and the full provided NWC amount is refunded (minus gas spent, since this is not refundable).
     *      This mechanism attempts to protect the user from any drastic and unfavorable price changes while their
     *      transaction is pending.
     * @param allowBuying If `true`, allow the buying of any tokens listed for sale below the mint price.
     * @param allowMinting If `true`, allow the minting of new tokens at the current mint price.
     */
    function buy(uint256 minimumTokensToBuyOrMintDUBLRWEI, bool allowBuying, bool allowMinting) external payable;
}


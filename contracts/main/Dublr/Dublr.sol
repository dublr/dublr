// SPDX-License-Identifier: MIT

// The Dublr token (symbol: DUBLR), with a built-in distributed exchange for buying/selling tokens.
// By Hiroshi Yamamoto.
// 虎穴に入らずんば虎子を得ず。
//
// Officially hosted at: https://github.com/dublr/dublr

pragma solidity 0.8.17;

import "./DublrInternal.sol";
import "./interfaces/IDublrDEX.sol";

/**
 * @title Dublr
 * @dev The Dublr token and distributed exchange
 * @author Hiroshi Yamamoto
 */
contract Dublr is DublrInternal, IDublrDEX {

    // Note that NWC is used to denote the symbol of the network currency (ETH for Ethereum, MATIC for Polygon, etc.)

    // -----------------------------------------------------------------------------------------------------------------
    // Constructor

    /**
     * @dev Constructor.
     * @param initialMintPrice_NWCPerDUBLR_x1e9 the numerator of the initial price of DUBLR in
     *          NWC per DUBLR token, multiplied by 1e9 (as a fixed point representation).
     * @param initialMintAmountDUBLR the one-time number of DUBLR tokens to mint for the owner on creation
     *          of the contract.
     */
    constructor(uint256 initialMintPrice_NWCPerDUBLR_x1e9, uint256 initialMintAmountDUBLR)
            OmniToken("Dublr", "DUBLR", "1", initialMintAmountDUBLR) {
        require(initialMintPrice_NWCPerDUBLR_x1e9 > 0, "Bad arg");
        
        // Record initial timestamp
        // solhint-disable-next-line not-rely-on-time
        initialMintTimestamp = block.timestamp;
        
        // Record initial mint price at contract creation time
        initialMintPriceNWCPerDUBLR_x1e9 = initialMintPrice_NWCPerDUBLR_x1e9;
        
        // Calculate maximum valid price for sell orders (prevents DoS via numerical overflow)
        maxPriceNWCPerDUBLR_x1e9 = initialMintPriceNWCPerDUBLR_x1e9 * MAX_SELL_ORDER_PRICE_FACTOR;

        // Register DUBLR token via ERC1820
        registerInterfaceViaERC1820("DUBLRToken", true);
        
        // Register IDublrDEX interface via ERC165
        registerInterfaceViaERC165(type(IDublrDEX).interfaceId, true);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Static call values

    /**
     * @notice Get results of all statically-callable functions in a single call, to reduce the number of RPC calls.
     *
     * @return values The results of the statically-callable functions of the contract.
     */
    function getStaticCallValues() external view
            override(IDublrDEX) returns (StaticCallValues memory values) {
        return StaticCallValues({
            buyingEnabled: buyingEnabled,
            sellingEnabled: sellingEnabled,
            mintingEnabled: mintingEnabled,
            blockGasLimit: block.gaslimit,
            balanceNWCWEI: msg.sender.balance,
            balanceDUBLRWEI: balanceOf[msg.sender],
            mintPriceNWCPerDUBLR_x1e9: mintPrice(),
            maxPriceNWCPerDUBLR_x1e9: maxPriceNWCPerDUBLR_x1e9,
            minSellOrderValueNWCWEI: minSellOrderValueNWCWEI,
            mySellOrder: mySellOrder(),
            allSellOrders: allSellOrders()
        });
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Minimum sell order value (mitigates DEX DoS attacks by sellers)

    /**
     * @notice The network currency value (in wei, == 10^-18 NWC) of the minimum sell order that may be listed for sale
     *      via `sell()`. Assumes the network currency has 10^18 wei per currency unit.
     */
    uint256 public override(IDublrDEX) minSellOrderValueNWCWEI = 0.01 ether;

    /**
     * @notice Only callable by the owner/deployer of the contract.
     *
     * @dev Set the network currency value (in wei, == 10^-18 NWC) of the minimum sell order that may be listed for sale
     *      via a call to `sell()`.
     * @param minValueNWCWEI The minimum network currency value of a sell order
     *      (orders of smaller value will be rejected).
     */
    function _owner_setMinSellOrderValueNWCWEI(uint256 minValueNWCWEI) external ownerOnly {
        minSellOrderValueNWCWEI = minValueNWCWEI;
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Determine the current mint price, based on block timestamp

    /**
     * @notice The current mint price, in network currency per DUBLR, multiplied by `10^9`.
     *
     * @dev Returns the current mint price for this token. Calls to `buy()` will buy tokens for sale
     * rather than minting new tokens, if there are tokens listed below the current mint price.
     *
     * The mint price grows exponentially, doubling every 90 days for 30 doubling periods, and then minting
     * is disabled. In practice, minting may no longer be triggered long before that time, if the supply
     * of coins for sale below the mint price exceeds demand.
     *
     * @return mintPriceNWCPerDUBLR_x1e9 The current mint price, in network currency per DUBLR, multiplied by `10^9`,
     *              or zero if the minting time period has ended (after 30 doubling periods).
     */
    function mintPrice() public view override(IDublrDEX) returns (uint256 mintPriceNWCPerDUBLR_x1e9) {
        // This is only a polynomial approximation of 2^t, so the doubling is not quite precise.
        // Factor increase in mint price during 1st doubling period: 1.999528
        // Factor increase in mint price during 30th doubling period: 1.973042
        // Factor increase in mint price between initial mint price and price after 30th
        //     doubling period: 871819739 (0.87 billion, i.e. 19% less than 1<<30)

        // N.B. daily compound interest rate == exp(ln(2) / DOUBLING_PERIOD_DAYS)
        // == 1.00773 if DOUBLING_PERIOD_DAYS == 90 (compound interest rate is 0.77% per day)

        // Use the block timestamp as an estimate of the current time. It is possible for miners to spoof
        // this timestamp, but it must be greater than the parent block timestamp (according to the Ethereum
        // yellowpaper), and most clients reject timestamps more than 15 seconds in the future.
        // The mint price grows by only 0.77% per day, so adding 15 seconds won't change the value of the
        // mint price by much (up to 0.003%). Also, setting the timestamp ahead of the real time results
        // in a higher price, which is only disadvantageous for a would-be attacker. Therefore, using the
        // block timestamp is not problematic here.
        // solhint-disable-next-line not-rely-on-time
        uint256 t = block.timestamp - initialMintTimestamp;
        if (t > MAX_DOUBLING_TIME_SEC) {
            return 0;
        }

        // Given an exponential function that doubles as x increments by 1
        //
        //     p = 2**x
        //
        // then to rewrite this in base e, we have
        //
        //     p = e**(ln(2) x)
        //
        // since
        //
        //     e**y = 2  =>  y == ln(2)
        //
        // Therefore the factor increase in mint price since the contract was deployed is given by
        //
        //     p = e**(ln(2) t / DOUBLING_PERIOD_SEC)
        //
        // where t is time since the constructor was called, in seconds.
        //
        // Exponentiation may be approximated by a polynomial:
        //
        //     exp(x) = lim{n->inf} (1 + x/n)**n
        //
        // (we use n = 1024 for a reasonable approximation that is not too costly).
        //
        // The factor increase in price can therefore be approximated by
        //
        //     p = (1 + ln(2) t / DOUBLING_PERIOD_SEC)**1024
        //
        // This approximation is accurate to within 3% per doubling period, with the biggest error
        // at the latest (30th) doubling period.

        // None of these calculations can overflow, so use unchecked math
        unchecked {
            // Convert the value (ln(2) * t / DOUBLING_PERIOD_SEC) to fixed point
            // Max value: ln(2) * FIXED_POINT * NUM_DOUBLING_PERIODS
            uint256 x = LN2_FIXED_POINT * t / DOUBLING_PERIOD_SEC;
            // x = (1 + x/1024) in fixed point
            x = FIXED_POINT + x / 1024;
            // x = x**1024
            // Obtained via 10 iterations, since x**(2**10) == x**1024
            // Max value of x is smaller than 2^30 times the original value of x.
            for (uint256 i = 0; i < 10; ) {
                // slither-disable-next-line divide-before-multiply
                x = x * x / FIXED_POINT;
                ++i;
            }
            // x is now an estimate of p, the factor increase in price, in fixed point.
            // Multiply x by the initial mint price to get the current mint price in fixed point,
            // then convert back from fixed point.
            // Max value before division still stays within uint256 range for all reasonable
            // values of initialMintPriceNWCPerDUBLR_x1e9.
            return x * initialMintPriceNWCPerDUBLR_x1e9 / FIXED_POINT;
        }
    }
    
    // -----------------------------------------------------------------------------------------------------------------
    // Public functions for interacting with order book

    /**
     * @notice The number of sell orders in the order book.
     *
     * @return numEntries The number of entries in the order book.
     */
    function orderBookSize() external view override(IDublrDEX) returns (uint256 numEntries) {
        return orderBook.length;
    }

    /**
     * @notice The price of the cheapest sell order in the order book for any user.
     *
     * @return priceAndAmountOfSellOrder The price of DUBLR tokens in the cheapest sell order,
     *      in network currency per DUBLR (multiplied by `10^9`), and the number of DUBLR tokens
     *      for sale, in DUBLR wei (1 DUBLR = 10^18 DUBLR wei).
     *      Both values are 0 if the orderbook is empty.
     */
    function cheapestSellOrder() external view override(IDublrDEX)
            returns (PriceAndAmount memory priceAndAmountOfSellOrder) {
        if (orderBook.length == 0) {
            // Orderbook is empty
            return PriceAndAmount({
                priceNWCPerDUBLR_x1e9: 0,
                amountDUBLRWEI: 0
            });
        } else {
            Order storage order = orderBook[0];
            return PriceAndAmount({
                priceNWCPerDUBLR_x1e9: order.priceNWCPerDUBLR_x1e9,
                amountDUBLRWEI: order.amountDUBLRWEI
            });
        }
    }

    /**
     * @notice The current sell order in the order book for the caller, or (0, 0) if none.
     *
     * @return priceAndAmountOfSellOrder The price of DUBLR tokens in the caller's sell order,
     *      in network currency per DUBLR (multiplied by `10^9`), and the number of DUBLR tokens
     *      for sale, in DUBLR wei (1 DUBLR = 10^18 DUBLR wei).
     *      Both values are 0 if the caller has no sell order.
     */
    function mySellOrder() public view override(IDublrDEX)
            returns (PriceAndAmount memory priceAndAmountOfSellOrder) {
        uint256 heapIdxPlusOne = sellerToHeapIdxPlusOne[msg.sender];
        if (heapIdxPlusOne == 0) {
            // Caller has no sell order
            return PriceAndAmount({
                priceNWCPerDUBLR_x1e9: 0,
                amountDUBLRWEI: 0
            });
        } else {
            uint256 heapIdx;
            unchecked { heapIdx = heapIdxPlusOne - 1; }  // Save gas
            
            // Peek at the order in the heap without removing it
            Order storage order = orderBook[heapIdx];
            assert(order.seller == msg.sender);  // Sanity check
            
            return PriceAndAmount({
                priceNWCPerDUBLR_x1e9: order.priceNWCPerDUBLR_x1e9,
                amountDUBLRWEI: order.amountDUBLRWEI
            });
        }
    }

    /**
     * @notice Cancel the caller's current sell order in the orderbook.
     *
     * @dev Restores the remaining (unfulfilled) amount of the caller's sell order back to the seller's
     * token balance. If the caller has no current sell order, does nothing.
     */
    function cancelMySellOrder() public override(IDublrDEX)
            // Modified with stateUpdater for reentrancy protection
            stateUpdater {
        // Determine the heap index of the sender's current sell order, if any
        uint256 heapIdxPlusOne = sellerToHeapIdxPlusOne[msg.sender];
        if (heapIdxPlusOne > 0) {
            uint256 heapIdx;
            unchecked { heapIdx = heapIdxPlusOne - 1; }  // Save gas

            // Remove the order from the heap
            Order memory order = heapRemove(heapIdx);
            assert(order.seller == msg.sender);  // Sanity check

            // Add the order amount of the canceled sell order back into the seller's balance
            balanceOf[order.seller] += order.amountDUBLRWEI;

            emit CancelSellOrder(order.seller, order.priceNWCPerDUBLR_x1e9, order.amountDUBLRWEI);
        }
    }

    /**
     * @notice Get all sell orders in the orderbook.
     * 
     * @dev Note that the orders are returned in min-heap order by price, and not in increasing order by price.
     *
     * @return priceAndAmountOfSellOrders A list of all sell orders in the orderbook, in min-heap order by price.
     * Each list item is a tuple consisting of the price of each token in network currency per DUBLR
     * (multiplied by `10^9`), and the number of tokens for sale.
     */
    function allSellOrders() public view override(IDublrDEX)
            // Returning an array requires ABI encoder v2, which is the default in Solidity >=0.8.0.
            returns (PriceAndAmount[] memory priceAndAmountOfSellOrders) {
        priceAndAmountOfSellOrders = new PriceAndAmount[](orderBook.length);
        uint256 len = orderBook.length;
        for (uint256 i = 0; i < len; ) {
            Order storage order = orderBook[i];
            priceAndAmountOfSellOrders[i] = PriceAndAmount({
                    priceNWCPerDUBLR_x1e9: order.priceNWCPerDUBLR_x1e9,
                    amountDUBLRWEI: order.amountDUBLRWEI});
            unchecked { ++i; }  // Save gas
        }
    }

    /**
     * @notice Only callable by the owner/deployer of the contract.
     *
     * @dev Cancel all sell orders (in case of emergency).
     * Restores the remaining (unfulfilled) amount of each sell order back to the respective seller's token balance.
     */
    function _owner_cancelAllSellOrders() external
            // Modified with stateUpdater for reentrancy protection
            stateUpdater ownerOnly {
        while (orderBook.length > 0) {
            uint256 heapIdx;
            unchecked { heapIdx = orderBook.length - 1; }  // Save gas
            Order storage order = orderBook[heapIdx];
            balanceOf[order.seller] += order.amountDUBLRWEI;
            delete sellerToHeapIdxPlusOne[order.seller];
            orderBook.pop();
            emit CancelSellOrder(order.seller, order.priceNWCPerDUBLR_x1e9, order.amountDUBLRWEI);
        }
    }

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
    function sell(uint256 priceNWCPerDUBLR_x1e9, uint256 amountDUBLRWEI) external override(IDublrDEX)
            // Modified with stateUpdater for reentrancy protection
            stateUpdater {
        require(sellingEnabled, "Selling disabled");
        require(priceNWCPerDUBLR_x1e9 > 0 && amountDUBLRWEI > 0
                // Make sure prices aren't exorbitant, to prevent DoS attacks where a seller triggers integer overflow
                // for other users.
                && priceNWCPerDUBLR_x1e9 <= maxPriceNWCPerDUBLR_x1e9, "Bad arg");
                
        // To mitigate DoS attacks, we have to prevent sellers from listing lots of very small sell orders
        // from different addresses, by making it costly to do this. We require that the total amount of the
        // sell order in NWC be greater than a specified minimum amount.
        require(dublrToNWCRoundDown(priceNWCPerDUBLR_x1e9, amountDUBLRWEI) >= minSellOrderValueNWCWEI,
                "Order value too small");

        // Cancel existing order, if there is one, before placing new sell order
        address seller = msg.sender;
        uint256 heapIdxPlusOne = sellerToHeapIdxPlusOne[seller];
        if (heapIdxPlusOne > 0) {
            cancelMySellOrder();
        }

        // Remove sell amount from sender's balance, to prevent spending of amount while order is in orderbook
        // (this amount will be restored to account balance if order is canceled)
        require(amountDUBLRWEI <= balanceOf[seller], "Insufficient balance");
        unchecked { balanceOf[seller] -= amountDUBLRWEI; }  // Save gas by using unchecked

        // Add sell order to heap
        heapInsert(Order({
                seller: msg.sender,
                // solhint-disable-next-line not-rely-on-time
                timestamp: block.timestamp,
                priceNWCPerDUBLR_x1e9: priceNWCPerDUBLR_x1e9,
                amountDUBLRWEI: amountDUBLRWEI}));

        emit ListSellOrder(seller, priceNWCPerDUBLR_x1e9, amountDUBLRWEI);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Buying

    /** @dev The amount of change to give to a seller. */
    struct SellerPayment {
        address seller;
        uint256 amountNWCWEI;
    } 

    /**
     * @dev Amount in NWC to send to sellers. This will be cleared at the end of each buy() call, it is only
     * held in storage rather than memory because Solidity does not support dynamic arrays in memory.
     */
    SellerPayment[] private sellerPaymentsTemp;

    /**
     * @dev Buy sell orders and then mint new tokens. Updates state of the contract, but does not call external
     * contracts (i.e. does not call `sendNWC`).
     *
     * @param minimumTokensToBuyOrMintDUBLRWEI The minimum number of tokens (in DUBLR wei, i.e. 10^-18 DUBLR) that the
     *      provided (payable) NWC value should buy, in order to prevent slippage. If at least this total number is not
     *      bought or minted by the time all NWC funds of the transaction have been expended, then the transaction is
     *      reverted and the full provided NWC amount is refunded (minus gas spent, since this is not refundable).
     *      This mechanism attempts to protect the user from any drastic and unfavorable price changes while their
     *      transaction is pending.
     * @param allowBuying If `true`, allow the buying of any tokens listed for sale below the mint price.
     * @param allowMinting If `true`, allow the minting of new tokens at the current mint price.
     * @return amountToRefundToBuyerNWCWEI The amount of unspent NWC to refund to the buyer.
     * @return sellerPayments The amount(s) of NWC to send to the sellers.
     */
    function _buy_stateUpdater(uint256 minimumTokensToBuyOrMintDUBLRWEI, bool allowBuying, bool allowMinting)
            // Modified with stateUpdater for reentrancy protection
            private stateUpdater
            returns (uint256 amountToRefundToBuyerNWCWEI, SellerPayment[] memory sellerPayments) {
        // The buyer is the caller
        address buyer = msg.sender;

        // Get the NWC value sent to this function in units of NWC wei
        uint256 buyOrderRemainingNWCWEI = msg.value;

        // Keep track of total tokens bought or minted
        uint256 totBoughtOrMintedDUBLRWEI = 0;

        // Calculate the mint price -- the price is 0 if minting has finished
        // (MAX_DOUBLING_TIME_SEC seconds or more after contract deployment, mintPrice() will return 0)
        uint256 mintPriceNWCPerDUBLR_x1e9 = mintPrice();

        // Amount of NWC to refund to (buyer, and amounts to send to sellers at end of transaction
        assert(sellerPaymentsTemp.length == 0);  // Sanity check

        // Buying sell orders: -----------------------------------------------------------------------------------------

        bool skipMinting = false;
        Order memory ownSellOrder;
        while (
                // If buyingEnabled is false (set by owner) or allowBuying is false (set by caller), skip over the
                // buying stage. This allows exchange function to be shut down or disabled if necessary without
                // affecting minting.
                buyingEnabled && allowBuying
                // Iterate through orders in increasing order of priceNWCPerDUBLR_x1e9, until we run out of NWC,
                // or until we run out of orders.
                && buyOrderRemainingNWCWEI > 0 && orderBook.length > 0) {

            // Find the lowest-priced order (this is a memory copy, because heapRemove(0) may be called below)
            Order memory sellOrder = orderBook[0];

            // Skip buying own sell order, if present
            if (sellOrder.seller == buyer) {
                ownSellOrder = sellOrder;
                heapRemove(0);
                continue;
            }

            // Stop iterating through sell orders once the order price is above the current mint price.
            if (mintPriceNWCPerDUBLR_x1e9 > 0
                    && sellOrder.priceNWCPerDUBLR_x1e9 > mintPriceNWCPerDUBLR_x1e9) {
                break;
            }
            
            // Calculate number of tokens to buy, and the price including fees: ----------------------------------------

            uint256 amountToBuyDUBLRWEI;
            {
                // Determine how many whole DUBLR can be purchased with the buyer's remaining NWC balance,
                // at the current price of this order. (Whole DUBLR => round down.)
                uint256 amountBuyerCanAffordAtSellOrderPrice_asDUBLRWEI =
                        nwcToDUBLRRoundDown(sellOrder.priceNWCPerDUBLR_x1e9, buyOrderRemainingNWCWEI);

                if (amountBuyerCanAffordAtSellOrderPrice_asDUBLRWEI == 0) {
                    // The amount of DUBLR that the buyer can afford at the sell order price is less than 1 token,
                    // so the buyer can't continue buying orders (order prices in the rest of the order book, and
                    // the mint price, have to be at least as high as the current price). Stop going through order
                    // book, and refunded remaining NWC balance to the buyer as change.
                    // The minting price must be higher than the current order, so minting will not be
                    // triggered either.
                    skipMinting = true;
                    break;
                }

                // The number of DUBLR tokens to buy from the sell order is the minimum of the order's
                // amountDUBLRWEI (it's only possible to buy a maximum of amountDUBLRWEI tokens from this
                // order) and amountBuyerCanAffordAtSellOrderPrice_asDUBLRWEI (the buyer can't buy more
                // tokensthan they can afford)
                amountToBuyDUBLRWEI = min(sellOrder.amountDUBLRWEI, amountBuyerCanAffordAtSellOrderPrice_asDUBLRWEI);
            }

            // Given the whole number of DUBLR tokens to be purchased, calculate the NWC amount to charge buyer,
            // and deduct the market maker fee from the amount to send the seller.
            // Round up amount to charge buyer and round down amount to send seller to nearest 1 NWC wei.
            uint256 amountToChargeBuyerNWCWEI = dublrToNWCRoundUpClamped(
                    sellOrder.priceNWCPerDUBLR_x1e9, amountToBuyDUBLRWEI,
                    // Clamping shouldn't be needed, but to guarantee safe rounding up,
                    // clamp amount to available balance
                    buyOrderRemainingNWCWEI);
            // Invariant: amountToChargeBuyerNWCWEI <= buyOrderRemainingNWCWEI

            // Convert the number of DUBLR tokens bought into an NWC balance to send to seller, after subtracting
            // the trading fee.
            uint256 amountToSendToSellerNWCWEI =
                    dublrToNWCLessMarketMakerFee(sellOrder.priceNWCPerDUBLR_x1e9, amountToBuyDUBLRWEI);

            // Transfer DUBLR from sell order to buyer: ----------------------------------------------------------------

            // Subtract the DUBLR amount from the seller's order balance
            // (modify `orderBook[0]` in storage, not the `sellOrder` copy in memory)
            uint256 sellOrderRemainingDUBLRWEI =
                    // Note that the following expression has a side effect: `-=`. The orderbook entry's
                    // remaining amount is modified in-place. The corresponding field of the in-memory copy,
                    // `sellOrder.amountDUBLRWEI`, is not used below the following line, so it doesn't matter
                    // that the storage version and the in-memory copy differ after this point.
                    (orderBook[0].amountDUBLRWEI -= amountToBuyDUBLRWEI);
                    
            // Remove `orderBook[0]` from the orderbook when its remaining balance reaches zero
            if (sellOrderRemainingDUBLRWEI == 0) {
                heapRemove(0);
            }
            
            // Deposit the DUBLR amount into the buyer's account
            balanceOf[buyer] += amountToBuyDUBLRWEI;

            // Keep track of total tokens bought or minted
            totBoughtOrMintedDUBLRWEI += amountToBuyDUBLRWEI;

            // Transfer NWC from buyer to seller: ----------------------------------------------------------------------

            // Record the amount of NWC to be sent to the seller (there may be several sellers involved in one buy)
            if (amountToSendToSellerNWCWEI > 0) {
                sellerPaymentsTemp.push(
                        SellerPayment({seller: sellOrder.seller, amountNWCWEI: amountToSendToSellerNWCWEI}));
            }

            // Deduct amount spent on tokens from the sell order from the remaining NWC balance of buyer
            unchecked { buyOrderRemainingNWCWEI -= amountToChargeBuyerNWCWEI; }  // Save gas (see invariant above)
            
            // Fees to send to owner: ----------------------------------------------------------------------------------
            
            // Fees to send to owner are (amountToChargeBuyerNWCWEI - amountToSendToSellerNWCWEI).
            // We don't need to actually calculate this or store it anywhere, because we can calculate how much NWC is
            // left over from `msg.value` after sellers have been paid and buyer has received change.

            // Emit Dublr BuySellOrder event
            emit BuySellOrder(buyer, sellOrder.seller,
                    sellOrder.priceNWCPerDUBLR_x1e9, amountToBuyDUBLRWEI,
                    sellOrderRemainingDUBLRWEI, amountToSendToSellerNWCWEI, amountToChargeBuyerNWCWEI);
        }

        // If own sell order was skipped, add it back into the orderbook
        if (ownSellOrder.amountDUBLRWEI > 0) {
            heapInsert(ownSellOrder);
        }

        // Minting: ----------------------------------------------------------------------------------------------------

        // If the buyer's NWC balance is still greater than zero after there are no more sell orders below the
        // mint price, switch to minting
        if (
            // Only mint if minting is enabled by owner and is allowed by the caller
            mintingEnabled && allowMinting && !skipMinting
            // If mint price is 0, then the minting period has finished
            && mintPriceNWCPerDUBLR_x1e9 > 0
            // Only mint if there is a remaining NWC balance
            && buyOrderRemainingNWCWEI > 0) {

            // Mint DUBLR tokens into buyer's account: -----------------------------------------------------------------

            // Convert the amount remaining of the buy order from NWC to DUBLR.
            // Round down to the nearest whole DUBLR wei.
            uint256 amountToMintDUBLRWEI = nwcToDUBLRRoundDown(
                    mintPriceNWCPerDUBLR_x1e9, buyOrderRemainingNWCWEI);
                    
            // Convert the whole number of DUBLR wei to mint back into NWC wei to spend on minting.
            // Round up to the nearest 1 NWC wei.
            uint256 amountToMintNWCWEI = dublrToNWCRoundUpClamped(
                    mintPriceNWCPerDUBLR_x1e9, amountToMintDUBLRWEI,
                    // Clamping shouldn't be needed, but to guarantee safe rounding up,
                    // clamp amount to available balance
                    buyOrderRemainingNWCWEI);
            // Invariant: amountToMintNWCWEI <= buyOrderRemainingNWCWEI

            // Only mint if the number of DUBLR tokens to mint is at least 1
            if (amountToMintDUBLRWEI > 0) {
                // Mint this number of DUBLR tokens for buyer (msg.sender).
                // Call the `_mint_stateUpdater` version rather than the `_mint` version to ensure that the minting
                // function cannot call out to external contracts, so that Checks-Effects-Interactions is followed
                // (since we're still updating state).
                _mint_stateUpdater(buyer, buyer, amountToMintDUBLRWEI);

                // Keep track of total tokens bought or minted
                totBoughtOrMintedDUBLRWEI += amountToMintDUBLRWEI;

                // Deduct NWC amount spent on minting
                unchecked { buyOrderRemainingNWCWEI -= amountToMintNWCWEI; }  // Save gas (see invariant above)

                // Emit Dublr Mint event (provides more useful info than other mint events)
                emit Mint(buyer, mintPriceNWCPerDUBLR_x1e9, amountToMintNWCWEI, amountToMintDUBLRWEI);
            }
        }
        
        // Refund unspent balance: -------------------------------------------------------------------------------------
        
        // If the remaining NWC balance is greater than zero, it could not all be spent -- refund to buyer
        if (buyOrderRemainingNWCWEI > 0) {
            amountToRefundToBuyerNWCWEI = buyOrderRemainingNWCWEI;  // Return param
            // Emit RefundChange event
            emit RefundChange(buyer, buyOrderRemainingNWCWEI);
            // All remaining NWC is used up.
            buyOrderRemainingNWCWEI = 0;
        } else {
            amountToRefundToBuyerNWCWEI = 0;  // Return param
        }
        
        // Protect against slippage: -----------------------------------------------------------------------------------
        
        // Require that the number of tokens bought or minted met or exceeded the minimum purchase amount
        require(totBoughtOrMintedDUBLRWEI >= minimumTokensToBuyOrMintDUBLRWEI, "Too much slippage");

        // Finalize state: ---------------------------------------------------------------------------------------------

        // In order to prevent the opportunity for reentrancy attacks, a copy of the sellerPaymentsTemp array
        // is made in order to ensure sellerPaymentsTemp is emptied before any sendNWC call to external contracts
        // (otherwise looping through the sellerPaymentsTemp array to send payments to sellers would mix state
        // updates with calling external contracts, breaking the Checks-Effects-Interactions pattern).
        uint256 numSellers = sellerPaymentsTemp.length;
        sellerPayments = new SellerPayment[](numSellers);  // Return param
        for (uint256 i = 0; i < numSellers; ) {
            sellerPayments[i] = sellerPaymentsTemp[i];
            unchecked { ++i; }  // Save gas
        }
        delete sellerPaymentsTemp;  // Clear storage array, so that it is always clear at the end of buy()
    }

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
    function buy(uint256 minimumTokensToBuyOrMintDUBLRWEI, bool allowBuying, bool allowMinting)
            public payable override(IDublrDEX) {

        require(msg.value > 0, "Zero payment");

        // CHECKS / EFFECTS / EVENTS:
        
        (uint256 amountToRefundToBuyerNWCWEI, SellerPayment[] memory sellerPayments) =
                _buy_stateUpdater(minimumTokensToBuyOrMintDUBLRWEI, allowBuying, allowMinting);

        // INTERACTIONS:

        // Transfer NWC from buyer to seller, and NWC fees to owner (`sendNWC` is an `extCaller` function)
        
        // Send any pending NWC payments to sellers
        uint256 totalSentToSellersAndBuyerNWCWEI = 0;
        uint256 numSellers = sellerPayments.length;
        for (uint256 i = 0; i < numSellers; ) {
            SellerPayment memory sellerPayment = sellerPayments[i];
            // By attempting to send with `errorMessageOnFail == ""`, if sending fails, then instead of reverting,
            // sendNWC will return false. We need to catch this case, because otherwise, a seller could execute
            // a DoS on the DEX by refusing to accept NWC payments, since every buy attempt would fail. Due to
            // Checks-Effects-Interactions, we can't go back at this point and just cancel the seller's order
            // -- all state has to have already been finalized. We also can't cancel the buy order, because
            // this is not the buyer's fault. Therefore, it is the seller's responsibility to ensure that they
            // can receive NWC payments, and as noted in the documentation for the `sell` function, if they
            // can't or won't accept NWC payment, they forfeit the payment.
            (bool success, bytes memory returnData) =
                    sendNWC(sellerPayment.seller, sellerPayment.amountNWCWEI, /* errorMessageOnFail = */ "");
            if (success) {
                // sellerPayment.amountNWCWEI was sent to seller
                totalSentToSellersAndBuyerNWCWEI += sellerPayment.amountNWCWEI;
            } else {
                // if (!success), then payment is forfeited and sent to owner, because seller does not accept
                // NWC, and we must prevent seller from being able to attack the exchange by causing all `buy()`
                // calls to revert. Log this case.
                // (Disable Slither static analyzer warning, there is no way to emit this event before all
                // external function calls are made)
                // slither-disable-next-line reentrancy-events
                emit Unpayable(sellerPayment.seller, sellerPayment.amountNWCWEI, returnData);
            }
            unchecked { ++i; }  // Save gas
        }
        
        // Refund any unspent NWC back to buyer. Reverts if the buyer does not accept payment. (This is different than
        // the behavior when a seller does not accept payment, because a buyer not accepting payment cannot
        // shut down the whole exchange.)
        sendNWC(/* buyer = */ msg.sender, amountToRefundToBuyerNWCWEI, "Can't refund change");
        totalSentToSellersAndBuyerNWCWEI += amountToRefundToBuyerNWCWEI;
        
        // Send any remaining NWC (trading fees + minting fees) to owner
        sendNWC(_owner, address(this).balance, "Can't pay owner");
    }
}


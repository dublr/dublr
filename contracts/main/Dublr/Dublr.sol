// SPDX-License-Identifier: MIT

// The Dublr token (symbol: DUBLR), with a built-in distributed exchange for buying/selling tokens.
// By Hiroshi Yamamoto.
// 虎穴に入らずんば虎子を得ず。
//
// Officially hosted at: https://github.com/dublr/dublr

pragma solidity 0.8.15;

import "./DublrInternal.sol";
import "./interfaces/IDublrDEX.sol";

/**
 * @title Dublr
 * @dev The Dublr token and distributed exchange
 * @author Hiroshi Yamamoto
 */
contract Dublr is DublrInternal, IDublrDEX {

    // -----------------------------------------------------------------------------------------------------------------
    // Constructor

    /**
     * @dev Constructor.
     * @param initialMintPrice_ETHPerDUBLR_x1e9 the numerator of the initial price of DUBLR in
     *          ETH per DUBLR token, multiplied by 1e9 (as a fixed point representation).
     * @param initialMintAmountDUBLR the one-time number of DUBLR tokens to mint for the owner on creation
     *          of the contract.
     */
    constructor(uint256 initialMintPrice_ETHPerDUBLR_x1e9, uint256 initialMintAmountDUBLR)
            OmniToken("Dublr", "DUBLR", "1", new address[](0), initialMintAmountDUBLR) {
        require(initialMintPrice_ETHPerDUBLR_x1e9 > 0, "Zero price");
        
        // Record timestamp and initial mint price at contract creation time
        initialMintPriceETHPerDUBLR_x1e9 = initialMintPrice_ETHPerDUBLR_x1e9;
        // solhint-disable-next-line not-rely-on-time
        initialMintTimestamp = block.timestamp;

        // Register DUBLR token via ERC1820
        registerInterfaceViaERC1820("DUBLRToken", true);
        
        // Register IDublrDEX interface via ERC165
        registerInterfaceViaERC165(type(IDublrDEX).interfaceId, true);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Determine the current mint price, based on block timestamp

    /**
     * @notice The current mint price, in ETH per DUBLR (multiplied by `10^9`).
     *
     * @dev Returns the current mint price for this token. Calls to `buy()` will buy tokens for sale
     * rather than minting new tokens, if there are tokens listed below the current mint price.
     *
     * The mint price grows exponentially, doubling every 90 days for 30 doubling periods, and then minting
     * is disabled. In practice, minting may no longer be triggered long before that time, if the supply
     * of coins for sale below the mint price exceeds demand.
     *
     * @return mintPriceETHPerDUBLR_x1e9 The current mint price, in ETH per DUBLR, multiplied by `10^9`,
     *              or zero if the minting time period has ended (after 30 doubling periods).
     */
    function mintPrice() public view returns (uint256 mintPriceETHPerDUBLR_x1e9) {
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
        
        // Convert the value (ln(2) * t / DOUBLING_PERIOD_SEC) to fixed point
        uint256 x = LN2_FIXED_POINT * t / DOUBLING_PERIOD_SEC;
        // x = 1 + x/1024
        x = FIXED_POINT + x / 1024;
        // x = x**1024
        // Obtained via 10 iterations, since x**(2**10) == x**1024
        for (uint256 i = 0; i < 10; ) {
            // slither-disable-next-line divide-before-multiply
            x = x * x / FIXED_POINT;
            unchecked { ++i; }  // Save gas
        }
        // x is now an estimate of p, the factor increase in price, in fixed point.
        // Multiply x by the initial mint price to get the current mint price in fixed point,
        // then convert back from fixed point
        return x * initialMintPriceETHPerDUBLR_x1e9 / FIXED_POINT;
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
     * @dev If there are no current sell orders, reverts.
     *
     * @return priceETHPerDUBLR_x1e9 The price of DUBLR tokens in the cheapest sell order, in ETH per DUBLR
     *          (multiplied by `10^9`).
     * @return amountDUBLRWEI the number of DUBLR tokens for sale, in DUBLR wei (1 DUBLR = 10^18 DUBLR wei).
     */
    function cheapestSellOrder() external view override(IDublrDEX)
            returns (uint256 priceETHPerDUBLR_x1e9, uint256 amountDUBLRWEI) {
        require(orderBook.length > 0, "No sell order");
        Order storage order = orderBook[0];
        return (order.priceETHPerDUBLR_x1e9, order.amountDUBLRWEI);
    }

    /**
     * @notice The current sell order in the order book for the caller.
     *
     * @dev If the caller has no current sell order, reverts.
     *
     * @return priceETHPerDUBLR_x1e9 The price of DUBLR tokens in the caller's current sell order, in ETH per DUBLR
     *          (multiplied by `10^9`).
     * @return amountDUBLRWEI the number of DUBLR tokens for sale, in DUBLR wei (1 DUBLR = `10^18` DUBLR wei).
     */
    function mySellOrder() external view override(IDublrDEX)
            returns (uint256 priceETHPerDUBLR_x1e9, uint256 amountDUBLRWEI) {
        uint256 heapIdxPlusOne = sellerToHeapIdxPlusOne[msg.sender];
        require(heapIdxPlusOne > 0, "No sell order");
        uint256 heapIdx;
        unchecked { heapIdx = heapIdxPlusOne - 1; }  // Save gas
        
        // Peek at the order in the heap without removing it
        Order storage order = orderBook[heapIdx];
        assert(order.seller == msg.sender);  // Sanity check
        
        return (order.priceETHPerDUBLR_x1e9, order.amountDUBLRWEI);
    }

    /**
     * @notice Cancel the caller's current sell order in the orderbook.
     *
     * @dev Restores the remaining (unfulfilled) amount of the caller's sell order back to the seller's
     * token balance. If the caller has no current sell order, reverts.
     */
    function cancelMySellOrder() public override(IDublrDEX)
            // Modified with stateUpdater for reentrancy protection
            stateUpdater {
        // Determine the heap index of the sender's current sell order, if any
        uint256 heapIdxPlusOne = sellerToHeapIdxPlusOne[msg.sender];
        require(heapIdxPlusOne > 0, "No sell order");
        uint256 heapIdx;
        unchecked { heapIdx = heapIdxPlusOne - 1; }  // Save gas

        // Remove the order from the heap
        Order memory order = heapRemove(heapIdx);
        assert(order.seller == msg.sender);  // Sanity check

        // Add the order amount of the canceled sell order back into the seller's balance
        balanceOf[order.seller] += order.amountDUBLRWEI;

        emit CancelSell(order.seller, order.priceETHPerDUBLR_x1e9, order.amountDUBLRWEI);
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
    function allSellOrders() external view override(IDublrDEX)
            // Returning an array requires ABI encoder v2, which is the default in Solidity >=0.8.0.
            returns (PriceAndAmount[] memory priceAndAmountOfSellOrders) {
        require(orderBook.length > 0, "No sell order");
        priceAndAmountOfSellOrders = new PriceAndAmount[](orderBook.length);
        uint256 len = orderBook.length;
        for (uint256 i = 0; i < len; ) {
            Order storage order = orderBook[i];
            priceAndAmountOfSellOrders[i] = PriceAndAmount({
                    priceETHPerDUBLR_x1e9: order.priceETHPerDUBLR_x1e9,
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
            emit CancelSell(order.seller, order.priceETHPerDUBLR_x1e9, order.amountDUBLRWEI);
        }
    }

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
     * Note that the equivalent ETH amount of the order must be at least `minSellOrderValueETHWEI`, to ensure
     * that the order size is not unreasonably small (small orders cost buyers a lot of gas relative to the number
     * of tokens they buy). The equivalent ETH amount of the order can be calculated as:
     * `uint256 amountETHWEI = amountDUBLRWEI * priceETHPerDUBLR_x1e9 / 1e9` . If `amountETHWEI` is not at least
     * `minSellOrderValueETHWEI`, then the transaction will revert with "Order value too small".
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
    function sell(uint256 priceETHPerDUBLR_x1e9, uint256 amountDUBLRWEI) external override(IDublrDEX)
            // Modified with stateUpdater for reentrancy protection
            stateUpdater {
        require(sellingEnabled, "Selling disabled");
        require(priceETHPerDUBLR_x1e9 > 0 && amountDUBLRWEI > 0, "Bad arg");

        // To mitigate DoS attacks, we have to prevent sellers from listing lots of very small sell orders from different
        // addresses, by making it costly to do this. We require that the total amount of the sell order in ETH be greater
        // than a specified minimum amount.
        require(dublrToEthRoundDown(priceETHPerDUBLR_x1e9, amountDUBLRWEI) >= minSellOrderValueETHWEI,
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
                priceETHPerDUBLR_x1e9: priceETHPerDUBLR_x1e9,
                amountDUBLRWEI: amountDUBLRWEI}));

        emit ListSell(seller, priceETHPerDUBLR_x1e9, amountDUBLRWEI);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Buying

    /** @dev The amount of change to give to a seller. */
    struct SellerPayment {
        address seller;
        uint256 amountETHWEI;
    } 

    /**
     * @dev Amount in ETH to send to sellers. This will be cleared at the end of each buy() call, it is only
     * held in storage rather than memory because Solidity does not support dynamic arrays in memory.
     */
    SellerPayment[] private amountToSendToSellers;

    /**
     * @dev Buy sell orders and then mint new tokens. Updates state of the contract, but does not call external
     * contracts (i.e. does not call `sendETH`).
     *
     * @param minimumTokensToBuyOrMintDUBLRWEI The minimum number of tokens (in DUBLR wei, i.e. 10^-18 DUBLR) that the
     *      provided (payable) ETH value should buy, in order to prevent slippage. If at least this total number is not
     *      bought or minted by the time all ETH funds of the transaction have been expended, then the transaction is
     *      reverted and the full provided ETH amount is refunded (minus gas spent, since this is not refundable).
     *      This mechanism attempts to protect the user from any drastic and unfavorable price changes while their
     *      transaction is pending.
     * @param allowBuying If `true`, allow the buying of any tokens listed for sale below the mint price.
     * @param allowMinting If `true`, allow the minting of new tokens at the current mint price.
     * @return amountToRefundToBuyerETHWEI The amount of ETH to refund to the buyer.
     * @return amountToSendToSellersCopy The amount(s) of ETH to send to the sellers.
     */
    function _buy(uint256 minimumTokensToBuyOrMintDUBLRWEI, bool allowBuying, bool allowMinting)
            // Modified with stateUpdater for reentrancy protection
            private stateUpdater
            returns (uint256 amountToRefundToBuyerETHWEI, SellerPayment[] memory amountToSendToSellersCopy) {
        uint256 initialGas = gasleft();

        // Up to 70% of the gas can be used for buying sell orders, leaving a minimum of 30% of the gas for
        // the rest of this function, including minting. (Buying sell orders is an expensive operation, since
        // it can involve manipulating the heap, potentially removing the root node of the heap for many
        // separate sell orders.)
        // Buying sell orders will terminate when the amount of gas remaining falls below buySellOrderMinGasLimit,
        // to prevent a DoS (gas exhaustion) attack on the exchange. Instead, if the remaining gas falls below
        // this limit, buying of sell orders will stop, and an OutOfGasForBuyingSellOrders event will be emitted.
        // The transaction may still revert if the provided gas is simply too low to run this function.
        uint256 buySellOrdersMinGasLimit = initialGas * 3 / 10;

        // The buyer is the caller
        address buyer = msg.sender;

        // Get the ETH value sent to this function in units of ETH wei
        uint256 buyOrderRemainingETHWEI = msg.value;

        // Keep track of total tokens bought or minted
        uint256 totBoughtOrMintedDUBLRWEI = 0;

        // Calculate the mint price -- the price is 0 if minting has finished
        // (MAX_DOUBLING_TIME_SEC seconds or more after contract deployment, mintPrice() will return 0)
        uint256 mintPriceETHPerDUBLR_x1e9 = mintPrice();

        // Amount of ETH to refund to (buyer, and amounts to send to sellers at end of transaction
        amountToRefundToBuyerETHWEI = 0;  // Return param
        assert(amountToSendToSellers.length == 0);  // Sanity check

        // Buying sell orders: -----------------------------------------------------------------------------------------

        bool ranOutOfGasForBuyingSellOrders = false;
        while (
                // If buyingEnabled is false (set by owner) or allowBuying is false (set by caller), skip over the
                // buying stage. This allows exchange function to be shut down or disabled if necessary without
                // affecting minting.
                buyingEnabled && allowBuying
                // Iterate through orders in increasing order of priceETHPerDUBLR_x1e9, until we run out of ETH,
                // or until we run out of orders.
                && buyOrderRemainingETHWEI > 0 && orderBook.length > 0) {

            // Find the lowest-priced order (this is a memory copy, because heapRemove(0) may be called below)
            Order memory sellOrder = orderBook[0];

            // Stop iterating through sell orders once the order price is above the current mint price.
            if (mintPriceETHPerDUBLR_x1e9 > 0
                    && sellOrder.priceETHPerDUBLR_x1e9 > mintPriceETHPerDUBLR_x1e9) {
                break;
            }
            
            // Calculate number of tokens to buy, and the price including fees: ----------------------------------------

            uint256 amountToBuyDUBLRWEI;
            {
                // Determine how many whole DUBLR can be purchased with the buyer's remaining ETH balance,
                // at the current price of this order. (Whole DUBLR => round down.)
                uint256 amountBuyerCanAffordAtSellOrderPrice_asDUBLRWEI =
                        ethToDublrRoundDown(sellOrder.priceETHPerDUBLR_x1e9, buyOrderRemainingETHWEI);

                if (amountBuyerCanAffordAtSellOrderPrice_asDUBLRWEI == 0) {
                    // The amount of DUBLR that the buyer can afford at the sell order price is less than 1 token,
                    // so the buyer can't continue buying orders (order prices in the rest of the order book, and
                    // the mint price, have to be at least as high as the current price). Stop going through order
                    // book, and refunded remaining ETH balance to the buyer as change.
                    if (buyOrderRemainingETHWEI > 0) {
                        amountToRefundToBuyerETHWEI += buyOrderRemainingETHWEI;
                        // Emit RefundChange event
                        emit RefundChange(buyer, buyOrderRemainingETHWEI);
                        // The minting price must be higher than the current order, so minting will not be
                        // triggered either.
                        buyOrderRemainingETHWEI = 0;
                    }
                    break;
                }

                // The number of DUBLR tokens to buy from the sell order is the minimum of the order's
                // amountDUBLRWEI (it's only possible to buy a maximum of amountDUBLRWEI tokens from this
                // order) and amountBuyerCanAffordAtSellOrderPrice_asDUBLRWEI (the buyer can't buy more
                // tokensthan they can afford)
                amountToBuyDUBLRWEI = min(sellOrder.amountDUBLRWEI, amountBuyerCanAffordAtSellOrderPrice_asDUBLRWEI);
            }

            // Given the whole number of DUBLR tokens to be purchased, calculate the ETH amount to charge buyer,
            // and deduct the market maker fee from the amount to send the seller.
            // Round up amount to charge buyer and round down amount to send seller to nearest 1 ETH wei.
            uint256 amountToChargeBuyerETHWEI = dublrToEthRoundUpClamped(
                    sellOrder.priceETHPerDUBLR_x1e9, amountToBuyDUBLRWEI,
                    // Clamping shouldn't be needed, but to guarantee safe rounding up,
                    // clamp amount to available balance
                    buyOrderRemainingETHWEI);
            // Invariant: amountToChargeBuyerETHWEI <= buyOrderRemainingETHWEI

            // Convert the number of DUBLR tokens bought into an ETH balance to send to seller, after subtracting
            // the trading fee.
            uint256 amountToSendToSellerETHWEI =
                    dublrToEthLessMarketMakerFee(sellOrder.priceETHPerDUBLR_x1e9, amountToBuyDUBLRWEI);

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

            // Transfer ETH from buyer to seller: ----------------------------------------------------------------------

            // Record the amount of ETH to be sent to the seller (there may be several sellers involved in one buy)
            if (amountToSendToSellerETHWEI > 0) {
                amountToSendToSellers.push(
                        SellerPayment({seller: sellOrder.seller, amountETHWEI: amountToSendToSellerETHWEI}));
            }

            // Deduct from the remaining ETH balance of buyer's buy order
            unchecked { buyOrderRemainingETHWEI -= amountToChargeBuyerETHWEI; }  // Save gas (see invariant above)
            
            // Fees to send to owner: ----------------------------------------------------------------------------------
            
            // Fees to send to owner are (amountToChargeBuyerETHWEI - amountToSendToSellerETHWEI).
            // We don't need to actually calculate this or store it anywhere, because we can calculate how much ETH is
            // left over from `msg.value` after sellers have been paid and buyer has received change.

            // Emit Dublr Buy event
            emit Buy(buyer, sellOrder.seller,
                    sellOrder.priceETHPerDUBLR_x1e9, amountToBuyDUBLRWEI,
                    sellOrderRemainingDUBLRWEI, amountToSendToSellerETHWEI, amountToChargeBuyerETHWEI);

            if (gasleft() < buySellOrdersMinGasLimit) {
                // Ran out of gas for buying sell orders --  prevent uncontrolled resource consumption DoS attacks.
                // See: https://swcregistry.io/docs/SWC-128

                // Record that we ran out of gas so we can revert with an appropriate message if necessary                
                ranOutOfGasForBuyingSellOrders = true;

                // Emit event
                emit OutOfGasForBuyingSellOrders(buyer, buyOrderRemainingETHWEI, totBoughtOrMintedDUBLRWEI);
                
                // Stop processing sell orders, and also do not fall through to minting (since there may be a big
                // jump in price between the current order's sell price and the mint price). The remaining ETH
                // balance must be refunded as-is.
                
                // Refund the rest of the remaining ETH to the buyer
                amountToRefundToBuyerETHWEI += buyOrderRemainingETHWEI;
                // Emit RefundChange event
                emit RefundChange(buyer, buyOrderRemainingETHWEI);
                // Stop processing sell orders, and do not mint anything
                buyOrderRemainingETHWEI = 0;
                break;
            }
        }

        // Minting: ----------------------------------------------------------------------------------------------------

        // If the buyer's ETH balance is still greater than zero after there are no more sell orders below the
        // mint price, switch to minting
        if (
            // Only mint if minting is enabled by owner and is allowed by the caller
            mintingEnabled && allowMinting
            // If mint price is 0, then the minting period has finished
            && mintPriceETHPerDUBLR_x1e9 > 0
            // Only mint if there is a remaining ETH balance
            && buyOrderRemainingETHWEI > 0) {

            // Mint DUBLR tokens into buyer's account: -----------------------------------------------------------------

            // Convert the amount remaining of the buy order from ETH to DUBLR.
            // Round down to the nearest whole DUBLR wei.
            uint256 amountToMintDUBLRWEI = ethToDublrRoundDown(
                    mintPriceETHPerDUBLR_x1e9, buyOrderRemainingETHWEI);
                    
            // Convert the whole number of DUBLR wei to mint back into ETH wei to spend on minting.
            // Round up to the nearest 1 ETH wei.
            uint256 amountToMintETHWEI = dublrToEthRoundUpClamped(
                    mintPriceETHPerDUBLR_x1e9, amountToMintDUBLRWEI,
                    // Clamping shouldn't be needed, but to guarantee safe rounding up,
                    // clamp amount to available balance
                    buyOrderRemainingETHWEI);
            // Invariant: amountToMintETHWEI <= buyOrderRemainingETHWEI

            // Only mint if the number of DUBLR tokens to mint is at least 1
            if (amountToMintDUBLRWEI > 0) {
                // Mint this number of DUBLR tokens for buyer (msg.sender).
                // Call the `_mint_stateUpdater` version rather than the `_mint` version to ensure that the minting function
                // cannot call out to external contracts, so that Checks-Effects-Interactions is followed (since
                // we're still updating state).
                _mint_stateUpdater(buyer, buyer, amountToMintDUBLRWEI, "", "");

                // Keep track of total tokens bought or minted
                totBoughtOrMintedDUBLRWEI += amountToMintDUBLRWEI;

                // Emit Dublr Mint event (provides more useful info than other mint events)
                emit Mint(buyer, mintPriceETHPerDUBLR_x1e9, amountToMintETHWEI, amountToMintDUBLRWEI);
                
                // Minting fee is 100% of amount spent to mint coins, i.e. amountToMintETHWEI.
                // We don't need to actually calculate this or store it anywhere, because we can calculate
                // how much ETH is left over from msg.value after buyer and sellers have been paid.
            }

            // Refund change to buyer for any fractional remainder (ETH worth less than 1 DUBLR): ----------------------

            // Calculate how much change to give for the last fractional ETH value that is worth less than 1 DUBLR
            // (amountToMintETHWEI is clamped above to a max of buyOrderRemainingETHWEI)
            unchecked { buyOrderRemainingETHWEI -= amountToMintETHWEI; }  // Save gas (see invariant above)
        }
        
        // Refund unspent balance: -------------------------------------------------------------------------------------
        
        // If the remaining ETH balance is greater than zero, it could not all be spent -- refund to buyer
        if (buyOrderRemainingETHWEI > 0) {
            amountToRefundToBuyerETHWEI += buyOrderRemainingETHWEI;
            // Emit RefundChange event
            emit RefundChange(buyer, buyOrderRemainingETHWEI);
            // All remaining ETH is used up.
            buyOrderRemainingETHWEI = 0;
        }
        
        // Protect against slippage: -----------------------------------------------------------------------------------
        
        // Require that the number of tokens bought or minted met or exceeded the minimum purchase amount
        require(totBoughtOrMintedDUBLRWEI >= minimumTokensToBuyOrMintDUBLRWEI,
                // If buyer ran out of gas for buying sell orders, then this should be reported rather than that
                // there was too much slippage.
                ranOutOfGasForBuyingSellOrders ? "Out of gas" : "Too much slippage");

        // Finalize state: ---------------------------------------------------------------------------------------------

        // In order to prevent the opportunity for reentrancy attacks, a copy of the amountToSendToSellers array
        // is made in order to ensure amountToSendToSellers is emptied before any sendETH call to external contracts
        // (otherwise looping through the amountToSendToSellers array to send payments to sellers would mix state
        // updates with calling external contracts, breaking the Checks-Effects-Interactions pattern).
        uint256 numSellers = amountToSendToSellers.length;
        amountToSendToSellersCopy = new SellerPayment[](numSellers);  // Return param
        for (uint256 i = 0; i < numSellers; ) {
            amountToSendToSellersCopy[i] = amountToSendToSellers[i];
            unchecked { ++i; }  // Save gas
        }
        delete amountToSendToSellers;  // Clear storage array, so that it is always clear at the end of buy()
    }

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
     * A maximum of 70% of the supplied gas may be used to buy sell orders from the built-in DEX (to prevent
     * gas exhaustion DoS attacks). If this gas limit is reached, buying will stop with the order partially filled,
     * an `OutOfGasForBuyingSellOrders` event will be emitted to signify that the order was only partially filled,
     * the unspent ETH balance will be returned to the buyer, and a `RefundChange` event will be emitted to inform
     * the buyer of the refund. (Note that `minimumTokensToBuyOrMintDUBLRWEI` tokens must still be bought in this
     * partially-filled order, otherwise the transaction will instead revert with "Out of gas".)
     * The transaction may also revert with gas exhaustion if the provided gas is simply too low to run this function.
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
    function buy(uint256 minimumTokensToBuyOrMintDUBLRWEI, bool allowBuying, bool allowMinting)
            public payable override(IDublrDEX) {

        require(msg.value > 0, "Zero payment");

        // CHECKS / EFFECTS / EVENTS:
        
        (uint256 amountToRefundToBuyerETHWEI, SellerPayment[] memory amountToSendToSellersCopy) =
                _buy(minimumTokensToBuyOrMintDUBLRWEI, allowBuying, allowMinting);

        // INTERACTIONS:

        // Transfer ETH from buyer to seller, and ETH fees to owner (`sendETH` is an `extCaller` function)
        
        // Send any pending ETH payments to sellers
        uint256 totalSentToSellersAndBuyerETHWEI = 0;
        uint256 numSellers = amountToSendToSellersCopy.length;
        for (uint256 i = 0; i < numSellers; ) {
            SellerPayment memory sellerPayment = amountToSendToSellersCopy[i];
            // By attempting to send with `errorMessageOnFail == ""`, if sending fails, then instead of reverting,
            // sendETH will return false. We need to catch this case, because otherwise, a seller could execute
            // a DoS on the DEX by refusing to accept ETH payments, since every buy attempt would fail. Due to
            // Checks-Effects-Interactions, we can't go back at this point and just cancel the seller's order
            // -- all state has to have already been finalized. We also can't cancel the buy order, because
            // this is not the buyer's fault. Therefore, it is the seller's responsibility to ensure that they
            // can receive ETH payments, and as noted in the documentation for the `sell` function, if they
            // can't or won't accept ETH payment, they forfeit the payment.
            (bool success, bytes memory returnData) =
                    sendETH(sellerPayment.seller, sellerPayment.amountETHWEI, /* errorMessageOnFail = */ "");
            if (success) {
                // sellerPayment.amountETHWEI was sent to seller
                totalSentToSellersAndBuyerETHWEI += sellerPayment.amountETHWEI;
            } else {
                // if (!success), then payment is forfeited and sent to owner, because seller does not accept
                // ETH, and we must prevent seller from being able to attack the exchange by causing all `buy()`
                // calls to revert. Log this case.
                // (Disable Slither static analyzer warning, there is no way to emit this event before all
                // external function calls are made)
                // slither-disable-next-line reentrancy-events
                emit Unpayable(sellerPayment.seller, sellerPayment.amountETHWEI, returnData);
            }
            unchecked { ++i; }  // Save gas
        }
        
        // Refund any unspent ETH back to buyer. Reverts if the buyer does not accept payment. (This is different than
        // the behavior when a seller does not accept payment, because a buyer not accepting payment cannot
        // shut down the whole exchange.)
        sendETH(/* buyer = */ msg.sender, amountToRefundToBuyerETHWEI, "Can't refund change");
        totalSentToSellersAndBuyerETHWEI += amountToRefundToBuyerETHWEI;
        
        // Send any remaining ETH (trading fees + minting fees) to owner
        sendETH(_owner, address(this).balance, "Can't pay owner");
    }
}


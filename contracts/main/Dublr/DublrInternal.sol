// SPDX-License-Identifier: MIT

// The Dublr token (symbol: DUBLR), with a built-in distributed exchange for buying/selling tokens.
// By Hiroshi Yamamoto.
// 虎穴に入らずんば虎子を得ず。
//
// Officially hosted at: https://github.com/dublr/dublr

pragma solidity 0.8.17;

import "../OmniToken/OmniToken.sol";

/**
 * @title DublrInternal
 * @dev Utility functions for the Dublr token and distributed exchange.
 * @author Hiroshi Yamamoto
 */
abstract contract DublrInternal is OmniToken {

    // Note that NWC is used to denote the symbol of the network currency (ETH for Ethereum, MATIC for Polygon, etc.)

    // -----------------------------------------------------------------------------------------------------------------
    // API enablement (needed in case a security issue is discovered with one of the APIs after the contract is created)

    /** @notice true if minting is enabled. */
    bool public mintingEnabled = true;

    /** @notice true if buying is enabled on the built-in distributed exchange. */
    bool public buyingEnabled = true;

    /** @notice true if selling is enabled on the built-in distributed exchange. */
    bool public sellingEnabled = true;

    /**
     * @notice Only callable by the owner/deployer of the contract.
     *
     * @dev Enable or disable minting.
     */
    function _owner_enableMinting(bool enable) external ownerOnly { mintingEnabled = enable; }

    /**
     * @notice Only callable by the owner/deployer of the contract.
     *
     * @dev Enable or disable selling on the built-in distributed exchange.
     */
    function _owner_enableSelling(bool enable) external ownerOnly { sellingEnabled = enable; }

    /**
     * @notice Only callable by the owner/deployer of the contract.
     *
     * @dev Enable or disable buying on the built-in distributed exchange.
     * `_owner_enableBuying(false)` disables buying but not minting, so `buy()` will still work
     * unless minting is also disabled.
     */
    function _owner_enableBuying(bool enable) external ownerOnly { buyingEnabled = enable; }

    // -----------------------------------------------------------------------------------------------------------------
    // Constants

    /** @dev Mint price doubling period: 90 days. */
    uint256 internal constant DOUBLING_PERIOD_DAYS = 90;

    /** @dev Doublings per year = 4.05 ~= 4 => mint price increase factor per year = ~2^4 = ~16. */
    uint256 internal constant DOUBLING_PERIOD_SEC = DOUBLING_PERIOD_DAYS * 24 * 60 * 60;

    /**
     * @dev Num doubling periods: 30 (7.5 years * 4 doublings per year) => max mint price increase factor is
     * 2^30 = ~1B, although minting should end organically before then due to increased supply of sell orders
     * below the mint price. (See forward-looking statement disclaimer in README.md .)
     */
    uint256 internal constant NUM_DOUBLING_PERIODS = 30;

    /** @dev The number of seconds during which the mint price continues to double. */
    uint256 internal constant MAX_DOUBLING_TIME_SEC = DOUBLING_PERIOD_SEC * NUM_DOUBLING_PERIODS;

    /** @dev The value of 1 for fixed point calculation of number of doublings over time. */
    uint256 internal constant FIXED_POINT = 1 << 30;

    /** @dev The value of ln(2)*FIXED_POINT == ln(2)*(1<<30). */
    uint256 internal constant LN2_FIXED_POINT = 0x2c5c85fe;

    /**
     * @notice The maximum price a sell order can be listed for, as a ratio compared to the initial mint price.
     * 1e15 => price can be 1 million billion times higher than the initial mint price. The mint price increases
     * ~1 billion times during 30 doubling periods, so this allows a maximum further growth of 1 million times.
     * The reason for the limit is to prevent sellers being able to trigger DoS for other users by causing
     * integer overflow when price is multiplied by amount, etc.
     */
    uint256 internal constant MAX_SELL_ORDER_PRICE_FACTOR = 1e15;

    /**
     * @dev One minus the trading fee of 0.15%, multiplied by (1<<30), = floor((1 - 0.0015) * (1 << 30)).
     * The network currency amount of an order is multiplied by this to determine how much to send to sellers
     * after fees are subtracted.
     */
    uint256 public sellerPaymentFractionFixedPoint = 0x3FE76C8B;

    /**
     * @notice Only callable by the owner of the contract.
     *
     * @dev Sets the trading fee.
     * 
     * @param paymentFractionFixedPoint One minus the trading fee, multiplied by (1<<30).
     * For example, for a trading fee of 0.15%, the value should be floor((1 - 0.0015) * (1 << 30))
     * = 0x3FE76C8B.
     */
    function _owner_setSellerPaymentFractionFixedPoint(uint256 paymentFractionFixedPoint)
            public ownerOnly {
        sellerPaymentFractionFixedPoint = paymentFractionFixedPoint;
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Minting values set by the constructor

    /** @dev The timestamp when the constructor was called. */
    uint256 internal initialMintTimestamp;

    /**
     * @dev The initial price of 1 DUBLR in network currency, multiplied by 1e9 (i.e. as a fixed point number),
     * when the contract constructor was called.
     */
    uint256 internal initialMintPriceNWCPerDUBLR_x1e9;

    /**
     * @notice The maximum price that DUBLR tokens can be listed for (to prevent numerical overflow),
     * multiplied by 1e9 (i.e. as a fixed point number).
     */
    uint256 public maxPriceNWCPerDUBLR_x1e9;

    // -----------------------------------------------------------------------------------------------------------------
    // The distributed exchange orderbook

    /** @dev An orderbook entry (for a sell order). */
    struct Order {
        address seller;
        uint256 timestamp;
        uint256 priceNWCPerDUBLR_x1e9;
        uint256 amountDUBLRWEI;
    }

    /** @dev The heap (to enforce increasing order of price for orderbook entry removal). */
    Order[] internal orderBook;

    /**
     * @dev The order book: mapping from address to (heap index + 1) if there is a current active sell order
     * for this address in the heap. (Need to add one because heap storage starts at index 0, but zero values
     * cannot be disambiguated from non-existence in a mapping.)
     *
     * The use of this mapping guarantees O(log N) removal time for removing an order by address.
     *
     * This data structure only allows us to have zero orders or one order per address at any given time.
     * It would be significantly more complex to create an orderbook where each user can have multiple active
     * orders at any given time, and still keep all order book access to O(log N) time.
     */
    mapping(address => uint256) internal sellerToHeapIdxPlusOne;

    // -----------------------------------------------------------------------------------------------------------------
    // Orderbook heap management functions

    /**
     * @dev Compare two orderbook entries, first by price, then (as a tiebreaker) by timestamp.
     * This is used to ensure that the cheapest orders are sold first, and when there is a tie,
     * the oldest order is sold first. (Does not compare amount, only compares price and timestamp.)
     *
     * @return diff -1 if order0 < order1, 0 if order0 == order1, 1 if order0 > order1, according to
     *         the above criteria.
     */
    function compare(Order memory order0, Order memory order1) private pure returns (int diff) {
        return order0.priceNWCPerDUBLR_x1e9 < order1.priceNWCPerDUBLR_x1e9 ? int(-1)
               : order0.priceNWCPerDUBLR_x1e9 > order1.priceNWCPerDUBLR_x1e9 ? int(1)
               : order0.timestamp < order1.timestamp ? int(-1)
               : int(1);
    }

    /**
     * @dev Set an entry in the orderbook min-heap, also updating the seller-to-heap-index mapping
     * sellerToHeapIdxPlusOne[order.seller].
     *
     * @param heapIdx The position to set the order.
     * @param order The order to set at the position.
     */
    function setOrder(uint256 heapIdx, Order memory order) private {
        assert(heapIdx <= orderBook.length);  // Sanity check
        if (heapIdx == orderBook.length) {
            orderBook.push(order);
        } else {
            orderBook[heapIdx] = order;
        }
        sellerToHeapIdxPlusOne[order.seller] = heapIdx + 1;
    }

    /**
     * @dev Standard up-heap algorithm for moving an order up a heap into its correct position.
     * (Heap is a min-heap, ordered by priceNWCPerDUBLR_x1e9, then by timestamp.)
     *
     * @param orderToMove The order to bubble up the heap
     * @param startHeapIdx The heap index to start bubbling up the heap from. (The order at this index
     * is ignored -- it is treated as a "hole".)
     */
    function upHeap(Order memory orderToMove, uint256 startHeapIdx) private {
        uint256 i = startHeapIdx;
        while (i > 0) {
            uint256 parentI;
            unchecked { parentI = (i - 1) / 2; }  // Save gas by using unchecked
            Order memory parentOrder = orderBook[parentI];
            if (compare(parentOrder, orderToMove) <= 0) {
                // Stop moving up heap once the parent order has a smaller value than the order to be inserted
                break;
            }
            // Move parent order down into position `i`, leaving a "hole" where the parent was
            setOrder(i, parentOrder);
            // Move up the heap
            i = parentI;
        }
        // Overwrite the "hole" at the final position with orderToMove
        setOrder(i, orderToMove);
    }

    /**
     * @dev Standard down-heap algorithm for moving an order down a heap into its correct position.
     * (Heap is a min-heap, ordered by priceNWCPerDUBLR_x1e9, then by timestamp.)
     *
     * @param orderToMove The order to percolate down the heap
     * @param startHeapIdx The heap index to start percolating down the heap from. (The order at this index
     * is ignored -- it is treated as a "hole".)
     */
    function downHeap(Order memory orderToMove, uint256 startHeapIdx) private {
        uint256 i = startHeapIdx;
        while (true) {
            // Get the index of the left and right child
            uint256 leftI;
            unchecked { leftI = 2 * i + 1; }  // Save gas (it would be impossibly expensive to ever cause overflow)
            if (leftI >= orderBook.length) {
                // Stop when node has no children
                break;
            }
            uint256 rightI;
            unchecked { rightI = leftI + 1; }  // Save gas
            // Choose child with lower priceNWCPerDUBLR_x1e9 (or older child, if children have same price)
            // -- this preserves the min-heap property relative to the other child, if the child with
            // a lower price or older order timestamp is moved up to the parent position
            uint256 smallerChildI = rightI < orderBook.length && compare(orderBook[rightI], orderBook[leftI]) < 0
                    ? rightI : leftI;
            Order memory smallerChildOrder = orderBook[smallerChildI];
            if (compare(orderToMove, smallerChildOrder) < 0) {
                // Stop when the correct insertion point for orderToMove is found
                break;
            }
            // Insertion point for orderToMove has not yet been found -- move child up into empty
            // parent position (this leaves child entry empty), as parent for next iteration)
            setOrder(i, smallerChildOrder);
            // Move to child entry
            i = smallerChildI;
        }
        // Overwrite the "hole" in the heap at the final position with orderToMove
        setOrder(i, orderToMove);
    }

    /**
     * @dev Insert a new sell order into the orderbook min-heap.
     *
     * @param order The sell order to insert into the heap.
     */
    function heapInsert(Order memory order) internal {
        // Insert order at the end of the heap, then bubble up into correct position
        upHeap(order, orderBook.length);
    }

    /**
     * @dev Remove an entry from the orderbook min-heap by index.
     *
     * (Min-heap is ordered by priceNWCPerDUBLR_x1e9, then by timestamp.)
     *
     * @param heapIdx The index of the heap entry to remove and return.
     * @return removedOrder The order at the given heap index.
     */
    function heapRemove(uint256 heapIdx) internal returns (Order memory removedOrder) {
        assert(orderBook.length > 0 && heapIdx < orderBook.length);  // Sanity check
        // Set element to be removed as return value
        removedOrder = orderBook[heapIdx];
        // After removing this order, there are no other orders for the seller (sellers can have only one
        // sell order at a given time)
        delete sellerToHeapIdxPlusOne[removedOrder.seller];
        // Last element in heap must be inserted into the space vacated by deletion of removedOrder,
        // then moved into position via down-heap (percolate down) operation
        uint256 lastOrderIdx;
        unchecked { lastOrderIdx = orderBook.length - 1; }  // Checked by assert above
        Order memory lastOrder = orderBook[lastOrderIdx];
        // Remove lastOrder from the end of the array
        orderBook.pop();
        // if (heapIdx == lastOrderIdx), then removed order is at end of array (i.e. removedOrder == lastOrder)
        // -- just return the removed order
        if (heapIdx != lastOrderIdx) {
            // Otherwise determine whether lastOrder needs to be bubbled up the heap or percolated down the heap
            // from the hole vacated by removedOrder
            if (heapIdx > 0 && compare(lastOrder, orderBook[(heapIdx - 1) / 2]) < 0) {
                // removedOrder had a parent (wasn't the root node of the heap), and lastOrder has a value
                // less than removedOrder's parent's value, so run up-heap algorithm
                upHeap(lastOrder, heapIdx);
            } else {
                // Otherwise (if removedOrder was at the root of the heap or lastOrder has a value greater than
                // or equal to removedOrder's parent's value), then run down-heap algorithm
                downHeap(lastOrder, heapIdx);
            }
        }
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Math functions
    
    /** @dev Return the minimum of two values. */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    
    /** The fixed point multiplier for priceNWCPerDUBLR_x1e9 prices (i.e. 1e9). */
    uint256 internal constant PRICE_FIXED_POINT_MULTIPLIER = 1e9;
    
    /**
     * @dev Convert DUBLR to network currency, rounding up, then clamping the result to a given max value.
     *
     * @param priceNWCPerDUBLR_x1e9 The price in network currency per DUBLR, multiplied by 1e9.
     * @param dublrAmt The amount of DUBLR to convert to NWC.
     * @param maxNWCAmt The max amount of NWC to clamp the return value to.
     * @return equivNWCAmt the NWC-equivalent value of dublrAmt at the given price.
     */
    function dublrToNWCRoundUpClamped(uint256 priceNWCPerDUBLR_x1e9, uint256 dublrAmt, uint256 maxNWCAmt)
            internal pure returns (uint256 equivNWCAmt) {
        uint256 nwcAmt = (dublrAmt * priceNWCPerDUBLR_x1e9 + PRICE_FIXED_POINT_MULTIPLIER - 1)
                / PRICE_FIXED_POINT_MULTIPLIER;
        return nwcAmt < maxNWCAmt ? nwcAmt : maxNWCAmt;
    }
    
    /**
     * @dev Convert DUBLR to network currency, rounding down.
     *
     * @param priceNWCPerDUBLR_x1e9 The price in network currency per DUBLR, multiplied by 1e9.
     * @param dublrAmt The amount of DUBLR to convert to network currency.
     * @return equivNWCAmt the network-currency-equivalent value of dublrAmt at the given price.
     */
    function dublrToNWCRoundDown(uint256 priceNWCPerDUBLR_x1e9, uint256 dublrAmt)
            internal pure returns (uint256 equivNWCAmt) {
        return dublrAmt * priceNWCPerDUBLR_x1e9 / PRICE_FIXED_POINT_MULTIPLIER;
    }
    
    /**
     * @dev Convert DUBLR to network currency, subtracting market maker fee, and rounding to nearest 1 NWC.
     *
     * @param priceNWCPerDUBLR_x1e9 The price in NWC per DUBLR, multiplied by 1e9.
     * @param dublrAmt The amount of DUBLR to convert to NWC.
     * @return equivNWCAmt the network-currency-equivalent value of dublrAmt at the given price,
     *      less market maker fee.
     */
    function dublrToNWCLessMarketMakerFee(uint256 priceNWCPerDUBLR_x1e9, uint256 dublrAmt)
            internal pure returns (uint256 equivNWCAmt) {
        // Round to nearest 1 NWC
        uint256 denom = PRICE_FIXED_POINT_MULTIPLIER * FIXED_POINT;
        return (dublrAmt * priceNWCPerDUBLR_x1e9 * sellerPaymentFractionFixedPoint + denom / 2) / denom;
    }
    
    /**
     * @dev Convert network currency to DUBLR, rounding down.
     *
     * @param priceNWCPerDUBLR_x1e9 The price in network currency per DUBLR, multiplied by 1e9.
     * @param nwcAmt The amount of network currency to convert to DUBLR.
     * @return equivDUBLRAmt the DUBLR-equivalent value of nwcAmt at the given price.
     */
    function nwcToDUBLRRoundDown(uint256 priceNWCPerDUBLR_x1e9, uint256 nwcAmt)
            internal pure returns (uint256 equivDUBLRAmt) {
        return nwcAmt * PRICE_FIXED_POINT_MULTIPLIER / priceNWCPerDUBLR_x1e9;
    }
}


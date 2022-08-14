// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

/**
 * @dev An approval receiver, as "sort of defined by" ERC677 (it is discussed in the comments),
 * and as implemented by AnySwap V2 tokens.
 */
interface IERC677ApprovalReceiver {
    function onTokenApproval(address holder, uint amount, bytes calldata data) external returns (bool success);
}


// SPDX-License-Identifier: MIT

/**
 * @title ERC1363Spender interface
 * @dev Interface for any contract that wants to support `approveAndCall`
 *  from ERC1363 token contracts.
 */

pragma solidity 0.8.17;

import './IERC165.sol';

/*
 * @dev The ERC-165 identifier for this interface is 0x7b04a2d0.
 * 0x7b04a2d0 === bytes4(keccak256("onApprovalReceived(address,uint256,bytes)"))
 */
interface IERC1363Spender is IERC165 {
    /**
     * @notice Handle the approval of ERC1363 tokens
     * @dev Any ERC1363 smart contract calls this function on the recipient
     * after an `approve`. This function MAY throw to revert and reject the
     * approval. Return of other than the magic value MUST result in the
     * transaction being reverted.
     * Note: the token contract address is always the message sender.
     * @param holder address The address which called `approveAndCall` function
     * @param amount uint256 The number of tokens to be spent
     * @param data bytes Additional data with no specified format
     * @return `bytes4(keccak256("onApprovalReceived(address,uint256,bytes)"))` (0x7b04a2d0) unless reverting
     */
    function onApprovalReceived(address holder, uint256 amount, bytes memory data) external returns (bytes4);
}

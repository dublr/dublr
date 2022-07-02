// SPDX-License-Identifier: MIT

/**
 * @title ERC1363Receiver interface
 * @dev Interface for any contract that wants to support `transferAndCall` or `transferFromAndCall`
 *  from ERC1363 token contracts.
 */

pragma solidity 0.8.15;

import '../main/OmniToken/interfaces/IERC165.sol';

interface IERC1363Receiver is IERC165 {
    /*
     * Note: the ERC-165 identifier for this interface is 0x88a7ca5c.
     * 0x88a7ca5c === bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)"))
     */

    /**
     * @notice Handle the receipt of ERC1363 tokens
     * @dev Any ERC1363 smart contract calls this function on the recipient after a `transfer` or a `transferFrom`.
     *        This function MAY throw to revert and reject the transfer. Return of other than the magic value MUST
     *        result in the transaction being reverted. Note: the token contract address is always the message sender.
     * @param operator address The address which called `transferAndCall` or `transferFromAndCall` function.
     * @param sender address The address which are token transferred from.
     * @param value uint256 The amount of tokens transferred.
     * @param data bytes Additional data with no specified format.
     * @return `bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)"))` (0x88a7ca5c) unless reverting.
     */
    function onTransferReceived(address operator, address sender, uint256 value, bytes memory data)
            external returns (bytes4);
}

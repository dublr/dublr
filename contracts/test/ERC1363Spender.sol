// SPDX-License-Identifier: MIT

/**
 * @title ERC1363Spender interface
 * @dev Interface for any contract that wants to support `approveAndCall`
 *  from ERC1363 token contracts.
 */

pragma solidity 0.8.16;

import "../main/OmniToken/interfaces/IERC1363Spender.sol";
import "../main/Dublr/Dublr.sol";

contract ERC1363Spender is IERC1363Spender {
    uint256 public callCount;
    
    /** @dev Determine whether or not this contract supports a given interface. (This is the ERC165 API.) */
    function supportsInterface(bytes4 interfaceId) external pure override(IERC165) returns (bool) {
        return interfaceId == 0x01ffc9a7 ? true // Required by ERC165 (the ERC165 interfaceId itself)
        : interfaceId == 0xffffffff ? false  // Required by ERC165
        // Only one interface function is supported (0x7b04a2d0)
        : interfaceId == ERC1363Spender.onApprovalReceived.selector;
    }

   /**
     * @notice Handle the approval of ERC1363 tokens
     * @dev Any ERC1363 smart contract calls this function on the recipient
     * after an `approve`. This function MAY throw to revert and reject the
     * approval. Return of other than the magic value MUST result in the
     * transaction being reverted.
     * Note: the token contract address is always the message sender.
     * @return `bytes4(keccak256("onApprovalReceived(address,uint256,bytes)"))` (0x7b04a2d0) unless reverting
     */
    function onApprovalReceived(address, uint256, bytes memory)
            external override(IERC1363Spender) returns (bytes4) {
        callCount++;
        return ERC1363Spender.onApprovalReceived.selector;
    }
    
    // Insecure send function, only for testing
    function send(address payable dublrContract, address from, address to, uint256 amount) external {
        // This is a security vulnerability, but this contract is only for a unit test
        // slither-disable-next-line arbitrary-send-erc20
        require(Dublr(dublrContract).transferFrom(from, to, amount));
    }
}


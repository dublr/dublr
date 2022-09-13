// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../main/OmniToken/interfaces/IERC1363Receiver.sol";

/**
 * @title ERC1363Receiver interface
 * @dev Interface for any contract that wants to support `transferAndCall` or `transferFromAndCall`
 *  from ERC1363 token contracts.
 */
contract ERC1363Receiver is IERC1363Receiver {
    uint256 public callCount;
    bool private _enabled = true;
    
    /** @dev Determine whether or not this contract supports a given interface. (This is the ERC165 API.) */
    function supportsInterface(bytes4 interfaceId) external pure override(IERC165) returns (bool) {
        return interfaceId == 0x01ffc9a7 ? true // Required by ERC165 (the ERC165 interfaceId itself)
        : interfaceId == 0xffffffff ? false  // Required by ERC165
        // Only one interface function is supported (0x88a7ca5c)
        : interfaceId == ERC1363Receiver.onTransferReceived.selector;
    }

    /**
     * @notice Handle the receipt of ERC1363 tokens
     * @dev Any ERC1363 smart contract calls this function on the recipient after a `transfer` or a `transferFrom`.
     *        This function MAY throw to revert and reject the transfer. Return of other than the magic value MUST
     *        result in the transaction being reverted. Note: the token contract address is always the message sender.
     * @return `bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)"))` (0x88a7ca5c) unless reverting.
     */
    function onTransferReceived(address, address, uint256, bytes memory)
            external override(IERC1363Receiver) returns (bytes4) {
        callCount++;
        return _enabled ? ERC1363Receiver.onTransferReceived.selector : bytes4(0);
    }
    
    function enable(bool enabled) external {
        _enabled = enabled;
    }
}

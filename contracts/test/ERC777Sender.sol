// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "../main/OmniToken/interfaces/IERC777Sender.sol";

/**
 * @title ERC777Sender
 */
contract ERC777Sender is IERC777Sender {
    uint256 public callCount;
    address private _sender;
    bytes32 constant internal ERC1820_ACCEPT_MAGIC = keccak256(bytes("ERC1820_ACCEPT_MAGIC"));
    bytes32 constant internal ERC777TokensSenderHash = keccak256(bytes("ERC777TokensSender"));

    // Note:
    // ERC1820Registry.setInterfaceImplementer(wallet.address, keccak256("ERC777TokensSender"),
    //      address(ERC777SenderContract))
    // must be called by the sending wallet for this sender to be notified
    constructor(address sender) {
        require(sender != address(0));
        _sender = sender;
    }

    // Called by ERC1820Registry.setInterfaceImplementer
    function canImplementInterfaceForAddress(bytes32 interfaceHash, address addr)
            override(IERC777Sender) external view returns(bytes32) {
        return addr == _sender && interfaceHash == ERC777TokensSenderHash ? ERC1820_ACCEPT_MAGIC : bytes32(0x00);
    }

    // IERC777Sender
    function tokensToSend(address, address, address, uint256, bytes calldata, bytes calldata)
            override(IERC777Sender) external {
        callCount++;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./IERC1820InterfaceImplementer.sol";

/**
 * @title IERC777Sender
 */
interface IERC777Sender is IERC1820InterfaceImplementer {
    function canImplementInterfaceForAddress(bytes32 interfaceHash, address addr)
            override(IERC1820InterfaceImplementer) external view returns(bytes32);
    function tokensToSend(address, address, address, uint256, bytes calldata, bytes calldata) external;
}

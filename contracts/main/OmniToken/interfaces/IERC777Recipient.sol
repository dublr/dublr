// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./IERC1820InterfaceImplementer.sol";

/**
 * @title IERC777Recipient
 */
interface IERC777Recipient is IERC1820InterfaceImplementer {
    function canImplementInterfaceForAddress(bytes32 interfaceHash, address addr)
            override(IERC1820InterfaceImplementer) external view returns(bytes32);
    function tokensReceived(address, address sender, address, uint256, bytes calldata, bytes calldata) external;
}

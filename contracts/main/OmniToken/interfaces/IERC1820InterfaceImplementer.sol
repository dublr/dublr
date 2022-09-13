// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

/**
 * @title IERC1820InterfaceImplementer
 */
interface IERC1820InterfaceImplementer {
    function canImplementInterfaceForAddress(bytes32 interfaceHash, address addr) external view returns(bytes32);
}

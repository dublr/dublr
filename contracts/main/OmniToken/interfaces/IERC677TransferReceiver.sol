// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

/**
 * @dev A transfer receiver, as defined by ERC677.
 */
interface IERC677TransferReceiver {
    function onTokenTransfer(address from, uint amount, bytes calldata data) external returns (bool success);
}


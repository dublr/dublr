// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import './IERC165.sol';

/**
 * @title IERC4523Recipient
 */
interface IERC4524Recipient is IERC165 {
    function onERC20Received(address operator, address sender, uint256 amount, bytes memory data)
            external returns(bytes4);
}

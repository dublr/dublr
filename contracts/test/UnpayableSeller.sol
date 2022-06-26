// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "../main/Dublr/Dublr.sol";

contract UnpayableSeller {
    // Insecure sell function, only for testing
    function sell(address payable dublrContract, uint256 price, uint256 amount) external {
        Dublr(dublrContract).sell(price, amount);
    }
}


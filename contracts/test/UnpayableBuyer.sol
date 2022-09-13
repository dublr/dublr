// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../main/Dublr/Dublr.sol";

contract UnpayableBuyer {
    bool private isPayable = true;
    
    receive() payable external {
        require(isPayable);
    }

    function makePayable(bool enable) external {
        isPayable = enable;
    }

    // Insecure buy function, only for testing
    function buy(address payable dublrContract) external payable {
        Dublr(dublrContract).buy{value: msg.value}(0, true, true);
    }
}


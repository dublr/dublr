// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import '../main/OmniToken/interfaces/IERC4524Recipient.sol';

/**
 * @title ERC4524Recipient
 */
contract ERC4524Recipient is IERC4524Recipient {
    uint256 public callCount;
    bool private _enabled = true;
    
    /** @dev Determine whether or not this contract supports a given interface. (This is the ERC165 API.) */
    function supportsInterface(bytes4 interfaceId) external pure override(IERC165) returns (bool) {
        return interfaceId == 0x01ffc9a7 ? true // Required by ERC165 (the ERC165 interfaceId itself)
        : interfaceId == 0xffffffff ? false  // Required by ERC165
        // Only one interface function is supported (0x4fc35859)
        : interfaceId == ERC4524Recipient.onERC20Received.selector;
    }

    /** @dev The ERC4524 recipient hook function. */
    function onERC20Received(address, address, uint256, bytes memory) external
            override(IERC4524Recipient) returns(bytes4) {
        callCount++;
        return _enabled ? ERC4524Recipient.onERC20Received.selector : bytes4(0);
    }
    
    function enable(bool enabled) external {
        _enabled = enabled;
    }
}

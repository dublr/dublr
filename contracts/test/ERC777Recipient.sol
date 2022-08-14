// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "../main/OmniToken/interfaces/IERC20.sol";
import "../main/OmniToken/interfaces/IERC777Recipient.sol";

/**
 * @title ERC777Recipient
 */
contract ERC777Recipient is IERC777Recipient {
    uint256 public callCount;
    address constant internal ERC1820_REGISTRY_ADDRESS = address(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 constant internal ERC777TokensRecipientHash = keccak256(bytes("ERC777TokensRecipient"));
    bool private reentryEnabled;

    constructor() {
        (bool success,) =
            ERC1820_REGISTRY_ADDRESS.call(abi.encodeWithSignature(
                    "setInterfaceImplementer(address,bytes32,address)",
                    /* addr = */ 0 /* equiv to address(this) */,
                    /* interfaceHash = */ ERC777TokensRecipientHash,
                    /* implementer = */ address(this)));
        require(success, "Could not call ERC1820 setInterfaceImplementer");
    }

    // Normally called by ERC1820Registry.setInterfaceImplementer, but won't be called in this case because the
    // account and its implementer are the same contract
    function canImplementInterfaceForAddress(bytes32, address)
            override(IERC777Recipient) external pure returns(bytes32) {
        revert("Should not be called");
    }

    function tokensReceived(address, address sender, address, uint256, bytes calldata, bytes calldata) external {
        require(sender != address(0));
        
        callCount++;
        
        // Call back to msg.sender (the OmniToken contract) if reentry is enabled, to test reentrancy protection
        if (reentryEnabled) {
            try IERC20(msg.sender).transfer(sender, 1) returns (bool) {
                revert("Reentrant call should not have succeeded");
            } catch Error(string memory reason) {
                revert(reason);
            } catch (bytes memory) {
                revert("Could not call contract function");
            }
        }
    }
    
    function testReentry(bool enabled) external {
        reentryEnabled = enabled;
    }
}

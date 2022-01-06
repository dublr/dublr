// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

/**
 * @title ERC777Recipient
 */
contract ERC777Recipient {
    uint256 public callCount;
    address constant internal ERC1820_REGISTRY_ADDRESS = address(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bool private reentryEnabled;

    constructor() {
        (bool success,) =
            ERC1820_REGISTRY_ADDRESS.call(abi.encodeWithSignature(
                    "setInterfaceImplementer(address,bytes32,address)",
                    /* addr = */ address(this),
                    /* interfaceHash = */ keccak256(abi.encodePacked("ERC777TokensRecipient")),
                    /* implementer = */ address(this)));
        require(success, "Could not call ERC1820 setInterfaceImplementer");
    }

    function tokensReceived(address, address sender, address, uint256, bytes calldata, bytes calldata) external {
        require(sender != address(0));
        
        callCount++;
        
        // Call back to msg.sender (the OmniToken contract) if reentry is enabled, to test reentrancy protection
        if (reentryEnabled) {
            (bool success, bytes memory returnData) = msg.sender.call(
                    abi.encodeWithSignature("approve(address,uint256)", sender, 1));
            if (!success) {
                // See OmniTokenUtils.callContractMethod
                if (returnData.length > 4 + 32 + 32) {
                    bytes4 selector;
                    uint256 offset;
                    string memory revertMsg;
                    uint256 len;
                    assembly {
                        selector := mload(add(returnData, 32))  // returnData.length is first 32 bytes
                        offset := mload(add(returnData, 36))
                        revertMsg := add(returnData, 68)        // revertMsg start addr, starting with revertMsg.length
                        len := mload(revertMsg)
                    }
                    if (selector == 0x08c379a0 && offset == 0x20 && len > 0) {
                        revert(revertMsg);
                    }
                }
                // Otherwise revert with just the provided error message
                revert("Could not call contract function");
            }
            revert("Reentrant call should not have succeeded");
        }
    }
    
    function testReentry(bool enabled) external {
        reentryEnabled = enabled;
    }
}

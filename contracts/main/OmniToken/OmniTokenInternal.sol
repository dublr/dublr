// SPDX-License-Identifier: MIT

// The OmniToken Ethereum token contract library, supporting multiple token standards.
// By Hiroshi Yamamoto.
// 虎穴に入らずんば虎子を得ず。
//
// Officially hosted at: https://github.com/dublr/dublr

pragma solidity 0.8.17;

import "./interfaces/IERC165.sol";
import "./interfaces/IERC1820Registry.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Optional.sol";
import "./interfaces/IERC20Burn.sol";
import "./interfaces/IERC20SafeApproval.sol";
import "./interfaces/IERC20IncreaseDecreaseAllowance.sol";
import "./interfaces/IERC20TimeLimitedTokenAllowances.sol";
import "./interfaces/IERC1363.sol";
import "./interfaces/IERC1363Spender.sol";
import "./interfaces/IERC1363Receiver.sol";
import "./interfaces/IERC4524.sol";
import "./interfaces/IERC4524Recipient.sol";
import "./interfaces/IEIP2612.sol";
import "./interfaces/IMultichain.sol";
import "./interfaces/IPolygonBridgeable.sol";

/**
 * @title OmniTokenInternal
 * @dev Utility functions for the OmniToken Ethereum token contract library.
 * @author Hiroshi Yamamoto
 */
abstract contract OmniTokenInternal is 
                      IERC20, IERC20Optional, IERC20Burn,
                      IERC20SafeApproval, IERC20IncreaseDecreaseAllowance, IERC20TimeLimitedTokenAllowances,
                      IERC1363, IERC4524, IEIP2612,
                      IMultichain, IPolygonBridgeable {

    /**
     * @dev Constructor.
     *
     * @param tokenName the name of the token.
     * @param tokenSymbol the ticker symbol for the token.
     * @param tokenVersion the version number string for the token.
     */
    constructor(string memory tokenName, string memory tokenSymbol, string memory tokenVersion) {
        // Remember creator of contract as owner
        _owner = msg.sender;

        name = tokenName;
        symbol = tokenSymbol;
        version = tokenVersion;

        // Precompute EIP712 domain constants
        domainFields.push(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"));
        domainFields.push(keccak256(bytes(name)));
        domainFields.push(keccak256(bytes(version)));

        // Register thet ERC165 interface with itself
        registerInterfaceViaERC165(type(IERC165).interfaceId, true);

        // Enable and register interfaces
        _owner_enableERC20(true);
        _owner_enableERC1363(true);
        _owner_enableERC4524(true);
        _owner_enableEIP2612(true);
        
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Functions common to multiple interfaces

    /** @dev The number of functions on the stack that modify contract state. */
    uint256 private _stateUpdaterDepth;

    /** @dev The number of functions on the stack that call external contracts. */
    uint256 private _extCallerDepth;

    /** @notice The total supply of tokens. */
    uint256 public override(IERC20) totalSupply;

    /** @notice The number of tokens owned by a given address. */
    mapping(address => uint256) public override(IERC20) balanceOf;

    /** @notice The name of the token. */
    string public override(IERC20Optional) name;

    /** @notice The token symbol. */
    string public override(IERC20Optional) symbol;

    /**
     * @notice The number of decimal places used to display token balances.
     * (Hardcoded to the ETH-standard value of 18.)
     */
    uint8 public constant override(IERC20Optional) decimals = 18;

    /** @notice The token version. (Optional but supported in some token implementations.) */
    string public version;

    /** @dev Creator/owner of the contract. */
    address immutable internal _owner;

    /** @dev Constant domain separator fields. */
    bytes32[] private domainFields;

    // -----------------------------------------------------------------------------------------------------------------
    // Function modifiers

    /**
     * @dev Reentrancy protection for functions that modify account state. Disallows a state-modifying
     * function (stateUpdater) from being called deeper in the callstack than a function that calls an
     * external contract (modified by `extCaller`), or vice versa.
     */
    modifier stateUpdater() {
        // Prevent reentrance
        require(_extCallerDepth == 0, "Reentrance");
        // slither-disable-next-line reentrancy-eth
        unchecked { ++_stateUpdaterDepth; }
        _;
        // slither-disable-next-line reentrancy-eth
        unchecked { --_stateUpdaterDepth; }
    }

    /**
     * @dev Reentrancy protection for functions that modify account state. Disallows a function that
     * calls an external contract (modified by `extCaller`) from being called deeper in the callstack
     * than a state-modifying function (stateUpdater), or vice versa.
     */
    modifier extCaller() {
        require(_stateUpdaterDepth == 0, "Reentrance");
        // slither-disable-next-line reentrancy-eth
        unchecked { ++_extCallerDepth; }
        _;
        // slither-disable-next-line reentrancy-eth
        unchecked { --_extCallerDepth; }
    }

    // --------------

    /**
     * @notice Emitted when the owner/deployer of the contract calls an `_owner_...` function.
     *
     * @param msgData The ABI-encoded data for the function call, from `msg.data`.
     */
    event OwnerCall(bytes msgData);

    /** @dev Limit access to a function to the owner of the contract. */
    modifier ownerOnly() {
        require(msg.sender == _owner, "Not owner");
        _;
        emit OwnerCall(msg.data);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // API enablement (needed in case a security issue is discovered with one of the APIs after the contract is created)

    /** @dev true if the ERC20 API is enabled. */
    bool internal _ERC20Enabled;

    /** @dev true if the ERC1363 API is enabled. */
    bool internal _ERC1363Enabled;

    /** @dev true if the ERC4524 API is enabled. */
    bool internal _ERC4524Enabled;

    /** @dev true if the EIP2612 permit API is enabled. */
    bool internal _EIP2612Enabled;

    /** The number of function calls in the stack for functions marked with the erc1363 modifier. */
    uint256 internal _erc1363CallDepth;

    /** The number of function calls in the stack for functions marked with the erc4524 modifier. */
    uint256 internal _erc4524CallDepth;

    /**
     * @notice Only callable by the owner/deployer of the contract.
     *
     * @dev Enable or disable ERC20 support in the API. If disabled, also disables other token APIs that are a
     * superset of ERC20, since these depend upon the ERC20 API.
     */
    function _owner_enableERC20(bool enable) public ownerOnly {
        _ERC20Enabled = enable;

        // ERC20
        registerInterfaceViaERC165(type(IERC20).interfaceId, enable);

        // ERC20 increase/decrease allowance extension
        registerInterfaceViaERC165(type(IERC20IncreaseDecreaseAllowance).interfaceId, enable);
                
        // ERC20 safe approval extension
        registerInterfaceViaERC165(type(IERC20SafeApproval).interfaceId, enable);
        
        // Don't register time-limited token allowance extension, because the OmniToken version uses seconds rather
        // than blocks for expiration, but the method type signature is the same

        // registerInterfaceViaERC1820("ERC20Token", enable);
    }

    /** @dev Require ERC20 to be enabled. */
    modifier erc20() {
        require(_ERC20Enabled, "Disabled");
        _;
    }

    // --------------

    /**
     * @notice Only callable by the owner/deployer of the contract.
     * @dev Enable or disable ERC1363 support in the API.
     */
    function _owner_enableERC1363(bool enable) public ownerOnly {
        _ERC1363Enabled = enable;

        registerInterfaceViaERC165(type(IERC1363).interfaceId, enable);

        // registerInterfaceViaERC1820("ERC1363Token", enable);
    }

    /** @dev Require ERC1363 to be enabled, and mark the ERC1363 API as active. */
    modifier erc1363() {
        require(_ERC1363Enabled, "Disabled");
        unchecked { ++_erc1363CallDepth; }
        _;
        unchecked { --_erc1363CallDepth; }
    }

    // --------------

    /**
     * @notice Only callable by the owner/deployer of the contract.
     * @dev Enable or disable ERC4524 support in the API (may only be called by the contract creator).
     */
    function _owner_enableERC4524(bool enable) public ownerOnly {
        _ERC4524Enabled = enable;
        
        registerInterfaceViaERC165(type(IERC4524).interfaceId, enable);
        
        // registerInterfaceViaERC1820("ERC4524Token", enable);
    }

    /** @dev Require ERC4524 to be enabled, and mark the ERC4524 API as active. */
    modifier erc4524() {
        require(_ERC4524Enabled, "Disabled");
        unchecked { ++_erc4524CallDepth; }
        _;
        unchecked { --_erc4524CallDepth; }
    }

    // --------------

    /**
     * @notice Only callable by the owner/deployer of the contract.
     * @dev Enable or disable EIP2612 permit support in the API.
     */
    function _owner_enableEIP2612(bool enable) public ownerOnly {
        _EIP2612Enabled = enable;

        registerInterfaceViaERC165(type(IEIP2612).interfaceId, enable);

        // registerInterfaceViaERC1820("ERC2612Permit", enable);
    }

    /** @dev Require EIP2612 permit support to be enabled. */
    modifier eip2612() {
        require(_EIP2612Enabled, "Disabled");
        _;
    }

    // --------------
    
    // Cross-chain router/bridge support:

    /** @dev Whether an address is an authorized to burn tokens for a specified account. */
    mapping(address => bool) internal isBurner;

    /** @dev Whether an address is an authorized to mint tokens for a specified account. */
    mapping(address => bool) internal isMinter;

    /**
     * @notice Only callable by the owner/deployer of the contract.
     * @dev Authorize or deauthorize a token burner.
     */
    function _owner_authorizeBurner(address addr, bool authorize) public ownerOnly {
        isBurner[addr] = authorize;
    }

    /**
     * @notice Only callable by the owner/deployer of the contract.
     * @dev Authorize or deauthorize a token minter.
     */
    function _owner_authorizeMinter(address addr, bool authorize) public ownerOnly {
        isMinter[addr] = authorize;
    }

    /** @dev Only authorized burners can call functions with this modifier. */
    modifier burnerOnly() {
        require(isBurner[msg.sender], "Not authorized");
        _;
    }

    /** @dev Only authorized minters can call functions with this modifier. */
    modifier minterOnly() {
        require(isMinter[msg.sender], "Not authorized");
        _;
    }

    /**
     * @notice Only callable by Multichain cross-chain routers or the Polygon PoS bridge's MintableERC20PredicateProxy.
     *
     * @dev Mints tokens for a Multichain router or the Polygon PoS bridge -- see:
     * https://docs.multichain.org/developer-guide/how-to-develop-under-anyswap-erc20-standards
     * https://docs.polygon.technology/docs/develop/ethereum-polygon/mintable-assets
     *
     * @param addr The address to mint tokens for.
     * @param amount The number of tokens to mint.
     */
    function mint(address addr, uint256 amount)
            virtual external override(IMultichain,IPolygonBridgeable) returns (bool success);

    // --------------

    /**
     * @dev true if unlimited allowance is enabled.
     */
    bool internal _unlimitedAllowancesEnabled = true;

    /**
     * @notice Only callable by the owner/deployer of the contract.
     *
     * @dev Enable/disable unlimited allowances.
     *
     * Note that having unlimited allowances enabled can be dangerous, $120M was stolen in the BADGER frontend
     * injection attack due to unlimited allowances.
     *
     * Disabling this causes an allowance amount of `type(uint256).max` to be rejected, which is not strictly
     * ERC20 compatible.
     * 
     * See: https://kalis.me/unlimited-erc20-allowances/
     *      https://rekt.news/badger-rekt/
     *
     * @param enable Whether to enable unlimited allowances.
     */
    function _owner_enableUnlimitedAllowances(bool enable) external ownerOnly {
        _unlimitedAllowancesEnabled = enable;
    }

    // --------------

    /** @dev true if ERC20 transfer to smart contracts is enabled. */
    bool internal _transferToContractsEnabled = true;

    /**
     * @notice Only callable by the owner/deployer of the contract.
     *
     * @dev Enable/disable ERC20 transfer to smart contracts. Note that enabling this can be dangerous:
     * millions have been lost in the Ethereum ecosystem due to users accidentally transferring tokens
     * to a smart contract rather than an EOA wallet, since smart contracts generally aren't
     * set up to function as wallets, and contract code generally can't be changed to recover
     * lost tokens.
     *
     * Disabling this is not ERC20 compatible, but it's much safer.
     *
     * @param enable Whether to enable transfer of tokens to non-EOA addresses (contracts).
     */
    function _owner_enableTransferToContracts(bool enable) external ownerOnly {
        _transferToContractsEnabled = enable;
    }

    // --------------

    /**
     * @dev true if ERC20 allows setting allowances from a non-zero value to another non-zero value.
     */
    bool internal _changingAllowanceWithoutZeroingEnabled = true;

    /**
     * @notice Only callable by the owner/deployer of the contract.
     *
     * @dev Enable/disable the ability of the ERC20 `approve` function to approve a non-zero allowance when the
     * allowance is already non-zero.
     *
     * Disabling this prevents the well-known allowance race condition vulnerability in ERC20, which is not
     * ERC20-compatible behavior, but it's much safer.
     *
     * See: https://github.com/guylando/KnowledgeLists/blob/master/EthereumSmartContracts.md
     *
     * @param enable Whether to enable changing allowances without first setting them to zero.
     */
    function _owner_enableChangingAllowanceWithoutZeroing(bool enable) external ownerOnly {
        _changingAllowanceWithoutZeroingEnabled = enable;
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Contract utility functions

    /**
     * @dev Test whether `account` is a contract.
     *
     * May return false negatives: during the execution of a contract's constructor, its address will be reported as not
     * containing a contract. Therefore, it is not safe to assume that an address for which this function returns `false`
     * is an externally-owned account (EOA) and not a contract.
     *
     * @param account The account.
     * @return Whether `account` is a contract (`true`) or is an externally-owned account (EOA) (`false`). Note that
     *         a return value of `true` is reliable, but a return value of `false` is not reliable.
     */
    function isContract(address account) internal view returns (bool) {
        // This relies on extcodesize, which returns 0 for contracts in construction, since the code is
        // only stored at the end of the constructor execution.
        return account != address(0) && account.code.length > 0;
    }

    // -----------------------------------------------------------------------------------------------------------------
    // ERC165 support for testing whether a given interface is supported

    /** @dev Supported interfaces (for ERC165 support). */
    mapping(bytes4 => bool) internal _supportedInterfaces;
    
    /**
     * @notice Determine whether or not this contract supports a given interface.
     *
     * @dev [ERC165] Implements the ERC165 API.
     * 
     * @param interfaceId The result of xor-ing together the function selectors of all functions in the interface
     * of interest.
     * @return supported `true` if this contract implements the requested interface.
     */
    function supportsInterface(bytes4 interfaceId) external view override(IERC165) returns (bool supported) {
        return _supportedInterfaces[interfaceId];
    }

    /** @dev Register a supported interface via ERC165. */
    function registerInterfaceViaERC165(bytes4 interfaceId, bool supported) internal {
        if (interfaceId != 0xffffffff) {  // ERC165 does not allow registering this interfaceId
            _supportedInterfaces[interfaceId] = supported;
        }
    }

    /**
     * @dev Check that a contract supports a given interface (declared via ERC165), reverting if not.
     *
     * @param contractAddr The contract address.
     * @param interfaceId The interface id.
     * @return supported `true` if this contract supports the requested interface.
     */
    function contractSupportsInterface(address contractAddr, bytes4 interfaceId)
            // Use extCaller modifier for reentrancy protection
            internal extCaller returns (bool supported) {
        if (isContract(contractAddr)) {
            try IERC165(contractAddr).supportsInterface(interfaceId) returns (bool result) {
                return result;
            } catch {
                // Fall through
            }
        }
        return false;
    }

    // -----------------------------------------------------------------------------------------------------------------
    // ERC1820 support for registering and finding the implementer of an interface

    /** @dev The ERC1820 registry address. */
    address internal constant ERC1820_REGISTRY_ADDRESS = address(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    /**
     * @dev Register or unregister an interface in the ERC1820 registry, with this address as the account
     * and implementer.
     */
    function registerInterfaceViaERC1820(string memory interfaceName, bool enable) internal {
        // extCaller modifier not required, since the ERC1820 registry is known and trusted
        IERC1820Registry(ERC1820_REGISTRY_ADDRESS)
                .setInterfaceImplementer(
                        // address(0) is equivalent to address(this) for first arg of `setInterfaceImplementer`
                        /* account = */ address(0),
                        /* interfaceHash = */ keccak256(bytes(interfaceName)),
                        /* implementer = */ enable ? address(this) : address(0));
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Functions for interacting with other contracts (modified with `extCaller` for reentrancy protection)

    /**
     * @dev Call the ERC1363 spender's `onApprovalReceived` function.
     *
     * @param holder The address holding the tokens being spent.
     * @param spender The address spending the tokens.
     * @param amount The number of tokens to be spent.
     * @param data Data generated by the user to be passed to the recipient.
     */
    function call_ERC1363Spender_onApprovalReceived(
            address holder, address spender, uint256 amount, bytes memory data)
            // Use extCaller modifier for reentrancy protection
            internal extCaller {
        // `spender` must declare it implements ERC1363 spender interface via ERC165
        string memory errMsg = "Not ERC1363 spender";
        require(contractSupportsInterface(spender, type(IERC1363Spender).interfaceId), errMsg);
        require(IERC1363Spender(spender).onApprovalReceived(holder, amount, data)
                == type(IERC1363Spender).interfaceId, errMsg);
    }

    /**
     * @dev Call the ERC1363 receiver's `onTransferReceived` function.
     *
     * @param operator address The address which called `transferAndCall` or `transferFromAndCall` function.
     * @param sender address The address which are token transferred from.
     * @param recipient address The address which are token transferred to.
     * @param amount uint256 The amount of tokens transferred.
     * @param data bytes Additional data with no specified format.
     */
    function call_ERC1363Receiver_onTransferReceived(
            address operator, address sender, address recipient, uint256 amount, bytes memory data)
            // Use extCaller modifier for reentrancy protection
            internal extCaller {
        // `recipient` must declare it implements ERC1363 recipient interface via ERC165
        string memory errMsg = "Not ERC1363 recipient";
        require(contractSupportsInterface(recipient, type(IERC1363Receiver).interfaceId), errMsg);
        require(IERC1363Receiver(recipient).onTransferReceived(operator, sender, amount, data)
                == type(IERC1363Receiver).interfaceId, errMsg);
    }

    /**
     * @dev Call the ERC4524 recipient's `onERC20Received` function.
     *
     * @param operator The address performing the send or mint.
     * @param sender The address holding the tokens being sent.
     * @param recipient The address of the recipient.
     * @param amount The number of tokens to be sent.
     * @param data Data generated by the user to be passed to the recipient.
     */
    function call_ERC4524TokensRecipient_onERC20Received(
            address operator, address sender, address recipient, uint256 amount, bytes memory data)
            // Use extCaller modifier for reentrancy protection
            internal extCaller {
        // Sending to an EOA (non-contract) always succeeds for ERC4524
        if (isContract(recipient)) {
            // `recipient` must declare it implements ERC4524 recipient interface via ERC165
            string memory errMsg = "Not ERC4524 recipient";
            require(contractSupportsInterface(recipient, type(IERC4524Recipient).interfaceId), errMsg);
            require(IERC4524Recipient(recipient).onERC20Received(operator, sender, amount, data)
                    == type(IERC4524Recipient).interfaceId, errMsg);
        }
        // Either recipient is an EOA, or receiver's onERC20Received function was successfully called
        // and the function returned the correct value.
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Send network currency to address

    /**
     * @dev Send an amount of NWC (network currency) to a given address. Must be called after contract state is finalized.
     *      (NWC is ETH for Ethereum, MATIC for Polygon, etc.)
     *
     * @param recipient The address to send ETH to.
     * @param amountNWC The amount of network currency (in wei) to send to the recipient.
     * @param errorMessageOnFail The error message to revert with if the payment couldn't be sent,
     *              or empty if the transaction should not revert if the attempt to send fails.
     *              If `errorMessageOnFail` is empty and the attempt to send fails, then `sendNWC` will
     *              return the `(false, returnData)` from the call.
     * @return success `true` if the send succeeded, or `false` if `errorMessageOnFail` is empty and the send failed.
     * @return returnData Any data returned from a failed call, if `success == false`.
     */
    function sendNWC(address recipient, uint256 amountNWC, string memory errorMessageOnFail)
            // Use extCaller modifier for reentrancy protection
            internal extCaller returns (bool success, bytes memory returnData) {
        require(recipient != address(0), "Bad recipient");
        if (amountNWC > 0) {
            // Calls the `receive` or `fallback` function with the specified amount of network currency (if a contract).
            // For contracts, the argument of "" delivers a zero-length payload to the call. Function calls
            // must be at least 4 bytes long, for the function selector. Solidity 0.6.0 and above will
            // call the `receive()` function if `msg.data.length == 0`, otherwise they will call the
            // `fallback()` function if `msg.data.length > 0` or there is no `receive()` function defined.
            // If there is no `receive()` or `fallback()` function defined, and the recipient is a contract,
            // then send will revert. For contracts compiled on older versions of solidity, zero-length
            // payloads will simply trigger the `fallback()` function -- there is no `receive()` function.
            // `call` automatically succeeds if the recipient is an EOA.
            (success, returnData) = recipient.call{value: amountNWC}("");
            if (!success && bytes(errorMessageOnFail).length > 0) {
                // Only revert with message if the message is not empty
                revert(errorMessageOnFail);
            }
        } else {
            return (true, "");
        }
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Permitting
    
    /** @dev The EIP2612 permit function typehash. */
    bytes32 internal constant EIP2612_PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /**
     * @notice EIP712 domain separator for EIP2612 permits.
     *
     * @dev [EIP2612] Part of the EIP2612 permit API.
     *
     * @return The domain separator for EIP2612 permits.
     */
    function DOMAIN_SEPARATOR() public view override(IEIP2612) returns (bytes32) {
        return keccak256(
            abi.encode(
                domainFields[0],
                domainFields[1],
                domainFields[2],
                // Domain separator must be dynamically generated to prevent sidechain replay attacks,
                // in case a chain is forked:
                // https://github.com/dublr/dublr/issues/10
                // "while the chainid property not being part of the block, it can only ever change on
                // a block basis (in case of forking a chain)":
                // https://github.com/ethereum/solidity/issues/8854
                // https://ethereum.stackexchange.com/a/37571/82179
                block.chainid,
                address(this)));
    }

    /**
     * @dev Check permit certificate. Reverts if certificate is not valid.
     *
     * @param deadline The block timestamp after which the certificate is invalid.
     * @param keccak256ABIEncoding The result of calling `keccak256(abi.encode(...))` with the `Permit` call typehash.
     * @param v The ECDSA `v` value.
     * @param r The ECDSA `r` value.
     * @param s The ECDSA `s` value.
     * @param requiredSigner The required value of the address recovered from the signature.
     */
    function checkPermit(uint256 deadline, bytes32 keccak256ABIEncoding,
            uint8 v, bytes32 r, bytes32 s, address requiredSigner) internal view {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= deadline, "Expired");

        // From:
        // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol
        //
        // See https://eips.ethereum.org/EIPS/eip-1271 :
        //
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (281): 0 < s < secp256k1n ÷ 2 + 1, and for v in (282): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
                && (v == 27 || v == 28), "Bad sig");

        // Recover address of signer from digest, and check it matches the required signer (the token holder)
        // The \x19 prefix is part of the Recursive Length Prefix (RLP) encoding:
        // https://blog.ricmoo.com/verifying-messages-in-solidity-50a94f82b2ca
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), keccak256ABIEncoding));
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == requiredSigner, "Bad sig");
    }
}


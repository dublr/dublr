# OmniToken API

OmniToken (not to be confused with the OMNI ERC20 token) is an extremely secure and flexible implementation of multiple Ethereum token standards, and implements several security extensions and security improvements.

As a result of careful attention to code quality and security, and given the number of supported token APIs and extensions, OmniToken is the most robust, secure, and flexible Ethereum smart contract for fungible tokens that is available today.

OmniToken is the foundation upon which the [Dublr token](/) is built.

## Token APIs supported by OmniToken

OmniToken implements all major Ethereum fungible token standards in a single token smart contract. All of these APIs work seamlessly together, and share an ultra secure hardened token implementation at the core:

* The [ERC20 token standard](https://eips.ethereum.org/EIPS/eip-20).
* The [ERC777 token standard](https://eips.ethereum.org/EIPS/eip-777). This replaces ERC20's `approve`/`transferFrom` mechanism with a system of authorized operators that have authority to transfer tokens on behalf of another contract. ERC777 also requires the recipient of tokens to implement a receiver interface so that the recipient must declare its ability to receive tokens for a `send` operation to succeed. The sender of tokens can also optionally implement a sender interface. The receiver (and optionally also the sender) must declare that they support ERC777 by registering their API using ERC1820.
* The [ERC1363 standard](https://eips.ethereum.org/EIPS/eip-1363) for safe transfer of tokens to ERC165-registered recipients. This API enables not just recipients but also spenders/operators to be notified after they have been approved to spend funds (in contrast with ERC777, which is able to notify senders/token holders, but not spenders/operators). ERC1363 has already seen some adoption, e.g. in the [FriendsFingers DAO](https://www.friendsfingers.com/dao/), and it is being added to OpenZeppelin.
* The [ERC4524 draft standard](https://eips.ethereum.org/EIPS/eip-4524) for safe transfer of tokens to ERC165-registered recipients. This is implemented despite being a draft, because of its simplicity. It is similar to ERC777, but simpler: ERC4524 relies on the standard allowance system rather than ERC777's complex operator approval system; ERC4524 requires recipients to register their supported APIs via ERC165 rather than the ERC1820 system that ERC777 uses; and ERC4524 only supports receiver notification, not sender notification.
* The [EIP2612 permit](https://eips.ethereum.org/EIPS/eip-2612) mechanism for ERC712/ERC1271-signed token permitting/approval via secp256k1 signatures.

## Comparison between the token APIs supported by OmniToken

| Feature                              | ERC20     | ERC777                | ERC1363   | ERC4524   | EIP2612          |
| ---                                  | :---:     | :---:                 | :---:     | :---:     | :---:            |
| Operator/spender permission via      | Allowance | Grant/revoke operator | Allowance | Allowance | Permit allowance |
| Sender/holder notification hook      | No        | Optional              | No        | No        | No               |
| Spender/operator notification hook   | No        | No                    | Required  | No        | No               |
| Receiver/recipient notification hook **\***| No  | Required if non-EOA   | Required  | Required if non-EOA | No     |
| Hook registration API                | N/A       | ERC1820               | ERC165    | ERC165    | N/A              |

**\* Receiver/recipient notification hook:** ERC20 and the EIP2612 permitting system allow for tokens to be sent to any contract, but OmniToken disallows this, breaking with the ERC20 standard in order to increase safety (see below). ERC777 and ERC4524 reject sending to contracts that do not implement the required receiver interface, but they do not reject sending to an EOA (Externally Owned Account / a standard non-contract wallet address). ERC1363 rejects sending to and spending by EOAs, but also to/by contracts that do not implement the receiver/spender interface.

## ERC20 extensions, and deviations from standards to increase security

### Extension APIs for mitigating ERC20 vulnerabilities

Several extensions are added on top of ERC20 by OmniToken, for addressing vulnerabilities in ERC20:

* The `increaseAllowance()` / `decreaseAllowance()` extension proposed [and adopted by OpenZeppelin](https://docs.openzeppelin.com/contracts/2.x/api/token/erc20#ERC20-increaseAllowance-address-uint256-) for mitigating the approval double-spend race condition vulnerability in ERC20.
* The "atomic compare-and-set" approval mechanism [proposed](https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM/edit) for solving the same `approve`/`transferFrom` vulnerability in ERC20.
* A modified version of the time-limited token allowances mechanism [proposed](https://github.com/vrypan/EIPs/blob/master/EIPS/eip-draft_time_limited_token_allowances.md) for reducing the chance that a forgotten allowance could be sent to an attacker by a clickjacking attack.
  * OmniToken uses seconds rather than number of blocks (as given in the proposal) for expiration time, since inter-block time intervals can vary. This is enabled by default (see below).

### Nonstandard behavior for mitigating vulnerabilities in token standards

OmniToken is configured to be 100% ERC20-compatible by default, but many aspects of the ERC20 token standard are insecure, which has resulted in enormous numbers of tokens being stolen from wallets. Therefore, OmniToken may be configured by the contract owner/deployer to break with the ERC20 standard in order to increase safety and security. Any of these changes may cause compatibility issues with some exchanges, wallets, dapps, etc.

* By calling `_owner_enableTransferToContracts(false)`, OmniToken may be configured to prevent ERC20's `transfer` and `transferFrom` functions from sending tokens to non-wallet addresses (contracts) by default, reverting with `Can't transfer to a contract`. Hundreds of millions of dollars have been lost in the ERC20 ecosystem by sending ETH or ERC20 tokens to non-EOA addresses -- sending to a non-proxied contract that does not know how to use tokens that are sent to it is equivalent to burning the tokens irretrievably. Calling `_owner_enableTransferToContracts(false)` may break OmniToken's interactions with other contracts (but it is much safer).
  * It is almost never the correct thing to do to send tokens directly to a contract, although some multisig wallets may support or even require sending ERC20 tokens directly to them, and if `_owner_enableTransferToContracts(false)` is called, these multisig wallets will not work unless you can use the ERC777/ERC1363/ERC4524 API instead of the ERC20 API to send tokens to the multisig wallet contract. Please ask your multisig wallet creator to support at least one of these interfaces for receiving tokens, preferably ERC1363 and/or ERC4524.
* By calling `_owner_enableChangingAllowanceWithoutZeroing(false)` default, OmniToken prevents setting allowances to a nonzero value unless the current allowance has a zero value. This is to prevent an allowance double-spend race condition attack. This is the most well-known vulnerabilty of ERC20, and it is now accepted good security practice to zero your allowances before setting the allowance to a nonzero value. However, many deployed contracts do not do this, as this behavior is not required by the ERC20 standard. Calling `_owner_enableChangingAllowanceWithoutZeroing(false)` may break OmniToken's interactions with other contracts (but it is much safer).
* By calling `_owner_setDefaultAllowanceExpirationSec(s)` for some small number of seconds, e.g. `s == 3600`, OmniToken enables the [time-limited token allowances](https://github.com/vrypan/EIPs/blob/master/EIPS/eip-draft_time_limited_token_allowances.md) mechanism by default, expiring allowances after the specified number of seconds. Allowances that do not expire, and that are forgotten about by token owners, have been the cause of many millions of dollars of lost tokens due to vulnerable dapps draining accounts. Calling `_owner_setDefaultAllowanceExpirationSec(s)` may break OmniToken's interactions with other contracts (but it is much safer).
  * To specify how long an allowance should remain valid on a case-by-case basis, use the `approveWithExpiration` ERC20 extension function.
* By calling `_owner_enableUnlimitedAllowances(false)`, unlimited allowances (supported by some ERC20 exchanges) of value `2**256 - 1 == type(uint256).max` are rejected by Omnitoken. Unlimited allowances can cause you to lose all your tokens in case of a security vulnerability in a smart contract or dapp that drains your account: $120M was stolen in the [BADGER frontend injection attack](https://rekt.news/badger-rekt/) due to [unlimited allowances](https://kalis.me/unlimited-erc20-allowances/).
  * As a practical matter, "unlimited" allowances are supported on all ERC20 implementations by setting an allowance to some very large number that is less than `2**256 - 1`.

Additionally OmniToken breaks with the ERC777 standard in one specific way, to increase security. ERC777 is complex and over-engineered, and despite adoption, there are proposals to deprecate its usage in favor of more recent standards like ERC1363 and ERC4524. Worst of all though, the ERC777 spec contains a gaping security hole.

* The ERC777 standard requires calling the sender interface (if implemented) _before_ tokens have been sent from the sender to the receiver. This violates the Checks-Effects-Interactions order, therefore creating the potential for serious security vulnerabilities, such as double-spend attacks. Instead of omitting ERC777, OmniToken breaks with the ERC777 standard, notifying the sender _after_ tokens have been sent and allowances updated, rather than before. This means that OmniToken's ERC777 implementation is not strictly compatible with the ERC777 standard, and this may produce unexpected behavior if contracts rely on senders being notified of transfers before the transfer occurs. The owner/deployer of the OmniToken contract may call `_owner_enableERC777(false)` to eliminate the potential for problems caused by this incompatibility with the ERC777 sender notification standard, at the cost of completely disabling the ERC777 API.

### Additional security measures

OmniToken is locked down against every known potential smart contract security problem.

* The [Checks-Effects-Interactions pattern](https://blog.openzeppelin.com/reentrancy-after-istanbul/) is used everywhere in OmniToken to prevent reentrancy attacks.
  * e.g. all state (e.g. allowances and balances) is finalized before calling external contracts via the ERC777/ERC1363/ERC4524 notification APIs, in order to follow the Checks-Effects-Interactions pattern.
* Strong reentrancy protection is implemented via function modifiers (`stateUpdater` for functions that modify core account state, and `extCaller` for functions that call other contracts; a `stateUpdater` cannot be called deeper in the call stack than an `extCaller`).
* Delegate calls into the OmniToken contract are blocked for all `stateUpdater` functions, so that:
  * the OmniToken contract cannot inadvertently modify the state of another contract, under the control of an attacker (preventing OmniToken from participating in [Mad Gadget](https://foxglovesecurity.com/2015/11/06/what-do-weblogic-websphere-jboss-jenkins-opennms-and-your-application-have-in-common-this-vulnerability/) style chained attacks);
  * the events that are output by OmniToken always represent changes to the internal state of the deployed OmniToken contract, and not changes that were redirected to another contract by an attacker (ensuring that OmniToken events are trustworthy to external observers).
* Several classes of vulnerability are prevented by using a recent version of Solidity to compile OmniToken:
  * Short address attacks are prevented by utilizing [Solidity >= 0.5.0](https://github.com/ethereum/solidity/pull/4224).
  * Overflow and underflow attacks are prevented by utilizing the default checked arithmetic support of [Solidity >= 0.8.0](https://blog.soliditylang.org/2020/12/16/solidity-v0.8.0-release-announcement/).
  * The fallback function is disabled (by not being defined in OmniToken), to block any [phantom function call](https://media.dedaub.com/phantom-functions-and-the-billion-dollar-no-op-c56f062ae49f) vulnerabilities from being triggered in callers, by using [Solidity >= 0.6.0](https://betterprogramming.pub/solidity-0-6-x-features-fallback-and-receive-functions-69895e3ffe). Also the `receive` and `fallback` payable functions are not defined by OmniToken, to prevent triggering phantom function call issues in other contracts.
* Several APIs that are safer than ERC20 are implemented in OmniToken: ERC777, ERC1363 and ERC4524.
* The OmniToken and Dublr API is copiously documented using NatSpec, so that all functions, function parameters, events, and event parameters are explained in EtherScan and in the source code. This will reduce confusion about how to properly and safely call the API.
* The OmniToken code is extensively unit-tested and 3rd-party-audited by multiple auditing companies.
* Extensive parameter validity checks are implemented for all external functions.
* All token APIs (ERC20, ERC777, ERC1363, and ERC4524) can be individually enabled or disabled by the contract owner/deployer, in case a security problem is discovered with one of the APIs.

### Additional APIs

OmniToken adds the following additional functionality to supported token APIs:

* An ERC20-esque `burn` extension function was added for burning your own tokens (in addition to ERC777's own `burn` and `operatorBurn` functions). Note that there is currently no staking benefit or other benefit conferred upon a user by burning tokens, but such a benefit may one day be conferred by another contract (such as has been implemented for SHIB). Only burn tokens if you have some benefit conferred upon you by some other smart contract for doing so!
* ERC165 and ERC1820 APIs are implemented for OmniToken so that other contracts can determine whether a deployed contract extends OmniToken, and/or to determine which interfaces OmniToken supports.

# Supported Interfaces

## [ERC20 interface](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IERC20.sol)

The standard ERC20 API.

```
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed holder, address indexed spender, uint256 value);
    
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address holder, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
```

## ERC20 extension interfaces

### [ERC20 optional API](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IERC20Optional.sol)

Optional functions defined in the ERC20 spec.

```
interface IERC20Optional is IERC20 {
    function name() external view returns (string memory tokenName);
    function symbol() external view returns (string memory tokenSymbol);
    function decimals() external view returns (uint8 numDecimals);
}
```

### [ERC20 `burn` function](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IERC20Burn.sol)

```
interface IERC20Burn {
    function burn(uint256 amount) external;
}
```

### [ERC20 `increaseAllowance` / `decreaseAllowance` extension](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IERC20IncreaseDecreaseAllowance.sol)

This extension reduces the chance for an allowance double-spend attack. See OpenZeppelin's documentation for this API [here](https://docs.openzeppelin.com/contracts/2.x/api/token/erc20#ERC20-increaseAllowance-address-uint256-).

```
interface IERC20IncreaseDecreaseAllowance {
    function increaseAllowance(address spender, uint256 addedValue)
            external returns (bool success);
    function decreaseAllowance(address spender, uint256 subtractedValue)
            external returns (bool success);
}
```

### [ERC20 "atomic compare and set" safe approval API](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IERC20SafeApproval.sol)

This extension implements the "atomic compare and set" safe approval protocol suggested in: "[ERC20 API: An Attack Vector on Approve/TransferFrom Methods](https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM/edit)".

OmniToken breaks with this proposal to name the `Transfer` event as `TransferInfo` and the `Approval` event as `ApprovalInfo`, so that the ERC20 `Transfer` and `Approval` event names are not overloaded. (The ethers library, used for unit testing of OmniToken, prints a lot of warnings if event names are overloaded.)

```
interface IERC20SafeApproval {
    event TransferInfo(address indexed spender, address indexed from, address indexed to, uint256 value);
    event ApprovalInfo(address indexed holder, address indexed spender, uint256 oldValue, uint256 value);

    function approve(address spender, uint256 expectedCurrentAmount, uint256 amount) external returns (bool success);
}
```

### [ERC20 approval with expiration (time-limited token allowances)](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IERC20TimeLimitedTokenAllowances.sol)

This extension reduces the chance for allowances to be spent by an attacker after the allowance has been forgotten by the token holder. See explanation [here](https://github.com/vrypan/EIPs/blob/master/EIPS/eip-draft_time_limited_token_allowances.md).

OmniToken breaks with this proposal to use the block timestamp rather than the block number for expiration (block mining rate is variable, so timestamp is more reliable). The default allowance validity before expiration is 1 hour.

```
interface IERC20TimeLimitedTokenAllowances {
    event ApprovalWithExpiration(address indexed holder, address indexed spender, uint256 value,
            uint256 expirationTime);

    function approveWithExpiration(address spender, uint256 amount, uint256 expirationSec)
            external returns (bool success);
    function allowanceWithExpiration(address holder, address spender)
            external view returns (uint256 remaining, uint256 expirationTime);
}
```

### [ERC165 interface for testing for supported interfaces](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IERC165.sol)

OmniToken declares its supported interfaces via ERC165.

```
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
```

## [ERC777 interface](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IERC777.sol)

```
interface IERC777 {
    event Sent(address indexed operator, address indexed from, address indexed to, uint256 amount, bytes data,
        bytes operatorData);
    event Minted(address indexed operator, address indexed to, uint256 amount, bytes data, bytes operatorData);
    event Burned(address indexed operator, address indexed from, uint256 amount, bytes data, bytes operatorData);
    event AuthorizedOperator(address indexed operator, address indexed tokenHolder);
    event RevokedOperator(address indexed operator, address indexed tokenHolder);
    
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function granularity() external view returns (uint256 tokenGranularity);
    function totalSupply() external view returns (uint256 tokenSupply);
    function balanceOf(address holder) external view returns (uint256 holderBalance);
    function send(address recipient, uint256 amount, bytes calldata data) external;
    function burn(uint256 amount, bytes calldata data) external;
    function isOperatorFor(address operator, address holder) external view returns (bool isOperator);
    function authorizeOperator(address operator) external;
    function revokeOperator(address operator) external;
    function defaultOperators() external view returns (address[] memory);
    function operatorSend(address sender, address recipient, uint256 amount, bytes calldata data,
        bytes calldata operatorData) external;
    function operatorBurn(address account, uint256 amount, bytes calldata data, bytes calldata operatorData) external;
}
```

## [ERC1363 interface](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IERC163.sol)

```
interface IERC1363 is IERC20, IERC165 {
    function transferAndCall(address recipient, uint256 amount)
        external returns (bool success);
    function transferAndCall(address recipient, uint256 amount, bytes memory data)
        external returns (bool success);
    function transferFromAndCall(address sender, address recipient, uint256 amount)
        external returns (bool success);
    function transferFromAndCall(address sender, address recipient, uint256 amount, bytes memory data)
        external returns (bool success);
    function approveAndCall(address spender, uint256 amount)
        external returns (bool success);
    function approveAndCall(address spender, uint256 amount, bytes memory data)
        external returns (bool success);
}
```

## [IERC4524 interface](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IERC4524.sol)

```
interface IERC4524 is IERC20, IERC165 {
    function safeTransfer(address recipient, uint256 amount)
            external returns(bool success);
    function safeTransfer(address recipient, uint256 amount, bytes memory data)
            external returns(bool success);
    function safeTransferFrom(address sender, address recipient, uint256 amount)
            external returns(bool success);
    function safeTransferFrom(address sender, address recipient, uint256 amount, bytes memory data)
            external returns(bool success);
}
```

## [EIP2612 permitting interface](https://github.com/dublr/dublr/blob/main/contracts/main/OmniToken/interfaces/IEIP2612.sol)

```
interface IEIP2612 {
    function permit(address holder, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s)
            external;
    function nonces(address holder)
            external view returns (uint);
    function DOMAIN_SEPARATOR()
            external view returns (bytes32);
}
```

In JavaScript, EIP2612 permits can be signed using [`eth-permit`](https://www.npmjs.com/package/eth-permit) as follows:

```
const { signERC2612Permit } = require("eth-permit");
const sig = await signERC2612Permit(
        wallet, omniTokenContract.address, holderWallet.address, spenderWallet.address, numTokens);
```

Then a spending allowance can be obtained for a spender wallet by calling the EIP2612 function `permit` in the OmniToken contract, using the following Ethers contract call:

```
await omniTokenContract["permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"](
        holderWallet.address, spenderWallet.address, numTokens, sig.deadline, sig.v, sig.r, sig.s);
```

## Contract owner API

Some additional OmniToken functions are callable only by the owner/deployer of the contract:

### Enable/disable whether ERC20 may transfer tokens to non-EOA contracts

```
function _owner_enableTransferToContracts(bool enable) external ownerOnly;
```

**Disabled by default** to prevent token loss by ERC20's `transfer`/`transferFrom` accidentally sending to non-EOA addresses.

This default is not ERC20 compatible, and may prevent using ERC20 tokens with multi-sig wallets or other similar contracts, unless these other contracts implement ERC777, ERC1363, ERC4524, or EIP2612.

To restore compatibility with ERC20, the owner/deployer of the contract may call `_owner_enableTransferToContracts(true)`.

### Enable/disable whether ERC20 may set the allowance to a non-zero value when it is already a non-zero value

```
function _owner_enableChangingAllowanceWithoutZeroing(bool enable) external ownerOnly;
```

**Disabled by default** to prevent the well-known ERC20 allowance double-spend [race condition attack](https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM/edit).

This default is not ERC20 compatible, and may prevent using ERC20 from working with some contracts that expect to be able to modify the allowance at will. However, this is considered dangerous behavior, so all secured applications will set the allowance to zero before setting it to a non-zero amount.

To restore compatibility with ERC20, the owner/deployer of the contract may call `_owner_enableChangingAllowanceWithoutZeroing(true)`.

### Enable/disable unlimited allowances

```
function _owner_enableUnlimitedAllowances(bool enable) external ownerOnly;
```

**Disabled by default** to mitigate loss in the case of forgotten allowances or dapp vulnerability.

This default is ERC20 compatible, but some exchanges allow the special value of `2^256 - 1` to designate an unlimited allowance. (In practice, any sufficiently large allowance is effectively unlimited, since the allowance can be greater than a wallet's token balance; however, if unlimited allowances are disallowed, we specifically disallow `2^256 - 1` as an allowance, to catch this special case.)

To ensure compatibility with exchanges that support unlimited allowances, the owner/deployer of the contract may call `_owner_enableUnlimitedAllowances(true)`.

### Default allowance expiration, in seconds

```
function _owner_setDefaultAllowanceExpirationSec(uint256 defaultAllowanceExpirationSec) external ownerOnly;
```

**By default, allowances expire after 3600 seconds**. This is to mitigate loss in the case of forgotten allowances or dapp vulnerability.

This default is not ERC20 compatible.

To restore compatibility with ERC20, the owner/deployer of the contract may call `_owner_setDefaultAllowanceExpirationSec(type(uint256).max)`.

### Enabling/disabling individual APIs

Individual token APIs may be enabled or disabled by the owner/deployer of the contract using the following function calls. All token APIs are **enabled by default**.

```
function _owner_enableERC20(bool enable) external ownerOnly;
function _owner_enableERC777(bool enable) external ownerOnly;
function _owner_enableERC1363(bool enable) external ownerOnly;
function _owner_enableERC4524(bool enable) external ownerOnly;
function _owner_enableEIP2612(bool enable) external ownerOnly;
```

## Gas usage

The following table shows the average amount of gas used by function call during testing. If there are multiple functions with the same name, the largest of the gas usage numbers is shown. You may need to multiply these numbers by 2 or more as the size of the contract's data structures grow with usage.

| Function name              | Avg gas used |
| :--                        |         ---: |
| approve                    |       88687  |
| approveAndCall             |      143890  |
| approveWithExpiration      |       58008  |
| authorizeOperator          |       58375  |
| burn                       |       74577  |
| decreaseAllowance          |       60493  |
| increaseAllowance          |       60112  |
| operatorBurn               |       77476  |
| operatorSend               |      116579  |
| permit                     |       93923  |
| revokeOperator             |       45130  |
| safeTransfer               |      112730  |
| safeTransferFrom           |      133631  |
| send                       |      135994  |
| transfer                   |       69903  |
| transferAndCall            |      112359  |
| transferFrom               |       82551  |
| transferFromAndCall        |      146071  |

## Token API proposals not implemented by OmniToken

There are several token standards or proposals that are intentionally not implemented by OmniToken, because they are incomplete, insecure/unsafe, or out of scope for OmniToken:

* [ERC223](https://github.com/ethereum/EIPs/issues/223): This is a poorly-written standard that is not actually backwards-compatible with ERC20 in several ways as it is defined, e.g. (1) the author forgot to include the `approve` and `transferFrom` functions required by ERC20 in the ERC223 API; (2) it is in general impossible to determine whether the receiver function was successfully called rather than the fallback function (because the receiver notification hook has no return value), thereby opening senders to [phantom function call](https://media.dedaub.com/phantom-functions-and-the-billion-dollar-no-op-c56f062ae49f) vulnerabilities, and defeating the purpose for ERC223's creation of enforcing that tokens can only be sent to receivers that implement the correct receiver notification hook.
* [ERC677](https://github.com/ethereum/EIPs/issues/677): has some of the same problems as ERC223, especially the issue with a successful call of the receiver function being indistinguishable from a call of the fallback function, because no return value is expected.
* [ERC827](https://github.com/ethereum/EIPs/issues/827): "This standard is still a draft and is proven to be unsafe to be used".
* [ERC1003](https://github.com/ethereum/EIPs/issues/1003): "While this might solve some issues with #827, it's vulnerable the same way #827 is".
* [ERC865](https://github.com/ethereum/EIPs/issues/865): "the EIP is still a draft, and doesn't seem very active. [Closing due to staleness.](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/741)"
* [ERC1155](https://eips.ethereum.org/EIPS/eip-1155): This is a strong (actively discussed) proposal for a new multi-token token standard that supports both fungible and nonfungible tokens in a single smart contract. This is beyond the scope of OmniToken.
* [ERC2771](https://eips.ethereum.org/EIPS/eip-2771): "A contract interface for receiving meta transactions through a trusted forwarder" -- out of scope for OmniToken. EIP2612 can be used to accomplish [some of the same functionality](https://help.1inch.io/en/articles/5435386-permit-712-signed-token-approvals-and-how-they-work-on-1inch).
* The [Dai permit system](https://github.com/makerdao/dss/blob/master/src/dai.sol#L124) is very similar to the EIP2612 permit system, but the Dai permit system only supports allowances being unlimited or zero, and unlimited allowances are dangerous. Also, Dai permits allow `expiry == 0` to create a permit that never expires, which is also dangerous. Therefore, this permit system is not supported.

## Legal agreement

By using the OmniToken API, you confirm that any token based on the OmniToken code (an "OmniToken-based token"), such as the Dublr token ("DUBLR"), is not considered an unregistered or illegal security by the laws of any legal jurisdiction in which you hold these tokens.

In some jurisdictions, such as the United States, any use, transfer, or sale of a token is a taxable event. It is your responsibility to record the purchase price and sale price in ETH or your local currency equivalent for each use, transfer, or sale of any OmniToken-based tokens you own, and to pay the taxes due.


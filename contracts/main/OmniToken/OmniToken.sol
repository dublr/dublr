// SPDX-License-Identifier: MIT

// The OmniToken Ethereum token contract library, supporting multiple token standards.
// By Hiroshi Yamamoto.
// 虎穴に入らずんば虎子を得ず。
//
// Officially hosted at: https://github.com/dublr/dublr

pragma solidity 0.8.17;

import "./OmniTokenInternal.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Optional.sol";
import "./interfaces/IERC20Burn.sol";
import "./interfaces/IERC20SafeApproval.sol";
import "./interfaces/IERC20IncreaseDecreaseAllowance.sol";
import "./interfaces/IERC20TimeLimitedTokenAllowances.sol";
import "./interfaces/IERC1363.sol";
import "./interfaces/IERC4524.sol";
import "./interfaces/IEIP2612.sol";
import "./interfaces/IMultichain.sol";
import "./interfaces/IPolygonBridgeable.sol";

/**
 * @title OmniToken
 * @dev The OmniToken Ethereum token contract library, supporting multiple token standards.
 * @author Hiroshi Yamamoto
 */
contract OmniToken is OmniTokenInternal {

    // -----------------------------------------------------------------------------------------------------------------
    // ERC20 fields

    /** @dev ERC20 allowances. */
    mapping(address => mapping(address => uint256)) internal _allowance;

    /** @dev The allowance amount that is treated as unlimited by some ERC20 exchanges. */
    uint256 internal constant UNLIMITED_ALLOWANCE = type(uint256).max;

    // --------------

    /** @dev The block timestamp after which the ERC20 allowance expires for a given address. */
    mapping(address => mapping(address => uint256)) internal _allowanceExpirationTimestamp;

    /** @dev The expiration time that is treated as unlimited, if unlimited expiration is enabled. */
    uint256 internal constant UNLIMITED_EXPIRATION = type(uint256).max;

    /**
     * @dev The minimum value of the `expirationSec` parameter of the `approveWithExpiration` function.
     *
     * Note that the block timestamp can be altered by miners up to about +/-15 seconds under proof of work
     * (as long as block timestamps increase monotonically), so do not use an allowance expiration time of less
     * than 15 seconds for PoW networks. For proof of stake, the block interval is set to exactly 12 seconds,
     * so the min expiration time should probably be set to 13 seconds or more for PoS networks.
     * The default is set to 16 seconds for maximum compatibility.
     */
    uint256 internal constant MIN_EXPIRATION_SEC = 16;

    /**
     * @notice The default number of seconds that an allowance is valid for, after the allowance or permit
     * is granted, before the allowance expires.
     *
     * @dev Note that the block timestamp can be altered by miners up to about +/-15 seconds under proof of work
     * (as long as block timestamps increase monotonically), so do not use an allowance expiration time of less
     * than 15 seconds for PoW networks. For proof of stake, the block interval is set to exactly 12 seconds,
     * so the expiration time should probably be set to 13 seconds or more for PoS networks.
     *
     * @dev Call `_owner_setDefaultAllowanceExpirationSec(type(uint256).max)` as the contract owner
     * if you want allowances never to expire, for backwards compatibility with ERC20, or pass a smaller
     * number to expire all allowances after that number of seconds by default.
     */
    uint256 public defaultAllowanceExpirationSec = UNLIMITED_EXPIRATION;

    /**
     * @notice Only callable by the owner/deployer of the contract.
     *
     * @dev Set the default number of seconds that an allowance is valid for. Set this to
     * `type(uint256).max == 2**256-1` if you want allowances never to expire, for backwards compatibility
     * with ERC20.
     *
     * @dev Note that the block timestamp can be altered by miners up to about +/-15 seconds under proof of work
     * (as long as block timestamps increase monotonically), so do not use an allowance expiration time of less
     * than 15 seconds for PoW networks. For proof of stake, the block interval is set to exactly 12 seconds,
     * so the expiration time should probably be set to 13 seconds or more for PoS networks.
     *
     * You can utilize a different expiration time on a case-by-case basis by calling `approveWithExpiration`.
     *
     * @param allowanceExpirationSec The number of seconds that allowances should be valid for.
     */
    function _owner_setDefaultAllowanceExpirationSec(uint256 allowanceExpirationSec) external ownerOnly {
        defaultAllowanceExpirationSec = allowanceExpirationSec;
    }

    /**
     * @dev Calculate default allowance expiration time.
     *
     * This is ERC20 compatible if `defaultAllowanceExpirationSec == type(uint256).max`.
     *
     * @return expirationTimestamp The default allowance expiration block timestamp, defaultAllowanceExpirationSec
     * seconds in the future.
     */
    function defaultAllowanceExpirationTime() private view returns (uint256 expirationTimestamp) {
        return defaultAllowanceExpirationSec == UNLIMITED_EXPIRATION
                    ? defaultAllowanceExpirationSec
                    // solhint-disable-next-line not-rely-on-time
                    : block.timestamp + defaultAllowanceExpirationSec;
    }

    // -----------------------------------------------------------------------------------------------------------------
    // EIP2612 permit API public field

    /** @notice EIP2612 permit nonces. */
    mapping(address => uint) public override(IEIP2612) nonces;

    // -----------------------------------------------------------------------------------------------------------------
    // Constructor

    /**
     * @notice OmniToken constructor.
     *
     * @param tokenName the name of the token.
     * @param tokenSymbol the ticker symbol for the token.
     * @param tokenVersion the version number string for the token.
     * @param initialMintAmount how many coins to mint for owner/deployer of contract.
     */
    constructor(string memory tokenName, string memory tokenSymbol, string memory tokenVersion,
            uint256 initialMintAmount) OmniTokenInternal(tokenName, tokenSymbol, tokenVersion) {

        if (initialMintAmount > 0) {
            // Perform initial mint for contract owner/deployer
            _mint(msg.sender, msg.sender, initialMintAmount, "");
        }

        // Register via ERC1820
        registerInterfaceViaERC1820("OmniToken", true);
        
        // (Don't need to register OmniToken API via ERC165 -- each of the individual supported APIs is already
        // registered by OmniTokenInternal's constructor)
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Core internal state update functions (modified with `stateUpdater` to prevent these functions being
    // called reentrantly, deeper in the stack than a function modified by `extCaller`, and to ensure that these
    // functions are not accidentally modified to call an `extCaller` function).

    /**
     * @dev Mint `amount` tokens into `account`.
     *
     * @param operator The address performing the mint.
     * @param account The address to mint tokens into.
     * @param amount The number of tokens to mint.
     */
    function _mint_stateUpdater(address operator, address account, uint256 amount)
            // Modified with `stateUpdater`, so `extCaller` functions cannot be called. This ensures that
            // future code changes do not break the Checks-Effects-Interactions pattern.
            internal stateUpdater {

        // PRECONDITIONS [CHECKS]:
        
        require(operator != address(0) && account != address(0) && amount != 0, "Bad arg");

        // MINT [EFFECTS]:

        // Mint tokens
        balanceOf[account] += amount;
        totalSupply += amount;

        // EMIT EVENTS:

        // Emit ERC20 mint event (indicating a transfer from address(0))
        emit Transfer(/* sender = */ address(0), /* recipient = */ account, amount);
        // Emit ERC20 "safe approval" mint event
        emit TransferInfo(operator, /* sender = */ address(0), /* recipient = */ account, amount);
        
        // NO INTERACTIONS
    }
    
    /**
     * @dev Set the value of the allowance of `spender` to spend `holder`s tokens. Called only from `_approve`
     * and `_spendAllowance`, and only after all checks have been performed.
     *
     * This function performs no checks on the validity of the allowance, the holder, or the spender.
     */
    function _setAllowance_stateUpdater(
            address holder, address spender, uint256 amount, uint256 expirationTimestamp)
            // Modified with `stateUpdater`, so `extCaller` functions cannot be called. This ensures that
            // future code changes do not break the Checks-Effects-Interactions pattern.
            private stateUpdater {

        // APPROVE [EFFECTS]:

        // Update allowance.
        uint256 prevAmount = _allowance[holder][spender];
        _allowance[holder][spender] = amount;
        
        // Update expiration.
        _allowanceExpirationTimestamp[holder][spender] = expirationTimestamp;

        // EMIT EVENTS:

        // Emit ERC20 Approval event
        emit Approval(holder, spender, amount);
        // Emit ERC20 "safe approval" event
        emit ApprovalInfo(holder, spender, prevAmount, amount);
        if (expirationTimestamp < UNLIMITED_EXPIRATION) {
            // Emit ERC20 "approval with expiration" event if approval is not unlimited
            emit ApprovalWithExpiration(holder, spender, amount, expirationTimestamp);
        }
        
        // NO INTERACTIONS
    }

    /**
     * @dev Spend `amount` of `operator`'s allowance to spend `holder`'s tokens.
     * Called only by `_transfer`, and assumes some validity checks have already been performed.
     */ 
    function _spendAllowance_stateUpdater(address operator, address holder, uint256 amount)
            // Modified with `stateUpdater`, so `extCaller` functions cannot be called. This ensures that
            // future code changes do not break the Checks-Effects-Interactions pattern.
            private stateUpdater {

        uint256 allowedAmount = _allowance[holder][/* spender = */ operator];
        
        // If unlimited allowance was previously enabled, and spender was granted an unlimited allowance,
        // and then later unlimited allowance was disabled, and the spender's allowance is still unlimited,
        // then the transfer should fail (the user's allowance needs to be set to a limited allowance
        // before transfers will succeed again).
        if (!_unlimitedAllowancesEnabled && allowedAmount == UNLIMITED_ALLOWANCE) {
            allowedAmount = 0;
        }
        
        // Fail transaction if allowance is insufficient
        require(amount <= allowedAmount, "Insufficient allowance");

        // Fail if allowance has expired
        uint256 expirationTimestamp = _allowanceExpirationTimestamp[holder][operator];
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= expirationTimestamp, "Allowance expired");
                
        // If allowance is not unlimited, reduce allowance by amount
        if (allowedAmount != UNLIMITED_ALLOWANCE) {
            // Decrease allowance by amount
            uint256 newAllowedAmount;
            unchecked { newAllowedAmount = allowedAmount - amount; }  // Save gas, checked above
            // Approve decreased allowance amount (this will update _allowance[holder][/* spender = */ operator]).
            // Will generate new allowance events.
            _setAllowance_stateUpdater(holder, /* spender = */ operator, newAllowedAmount, expirationTimestamp);
        }
        
        // NO INTERACTIONS
    }


    /**
     * @dev Destroys `amount` tokens from `account`, reducing the total supply.
     *
     * @param operator The address performing the burn.
     * @param account The address to burn tokens from.
     * @param amount The number of tokens to burn.
     */
    function _burn_stateUpdater(address operator, address account, uint256 amount) private stateUpdater {

        // PRECONDITIONS [CHECKS]:

        require(operator != address(0) && account != address(0) && amount != 0, "Bad arg");

        // BURN [EFFECTS]:

        // Burn tokens and decrease total supply
        require(amount <= balanceOf[account], "Insufficient balance");
        unchecked { balanceOf[account] -= amount; }  // Save gas by using unchecked
        totalSupply -= amount;

        // EMIT EVENTS:

        // Emit ERC20 burn event (indicating a transfer to address(0))
        emit Transfer(/* sender = */ account, /* recipient = */ address(0), amount);
        // Emit ERC20 "safe approval" transfer event
        emit TransferInfo(operator, /* sender = */ account, /* recipient = */ address(0), amount);
        
        // NO INTERACTIONS
    }

    /**
     * @dev Transfer `amount` tokens from `holder` to `recipient`.
     *
     * @param operator The address performing the transfer.
     * @param holder The address holding the tokens being transferred.
     * @param recipient The address of the recipient.
     * @param amount The number of tokens to be transferred.
     * @param useAllowance If true, use the allowance system to determine whether the user can make
     *                     the transfer, and reduce the allowance by the amount of the transfer.
     */
    function _transfer_stateUpdater(address operator, address holder, address recipient, uint256 amount,
            bool useAllowance) internal stateUpdater {

        // PRECONDITIONS [CHECKS]:

        require(operator != address(0) && holder != address(0) && recipient != address(0)
                // Don't allow sending tokens to this contract address, to catch accidental copy/paste errors.
                && recipient != address(this), "Bad arg");
        // Zero amount is valid for ERC20 transfers, for some reason (even though it's wasteful).

        // PERFORM TRANSFER [EFFECTS]:

        // If requested, check the operator has sufficient allowance to send the holder's tokens, and if so,
        // reduce the allowance by the requested amount.
        if (useAllowance && amount > 0) {
            // Spend (reduce) allowance. Will generate new allowance events, unless the allowance is unlimited.
            // Done before making the transfer, to ensure the allowance covers the transfer, but also, allowance
            // must be reduced before calling sender/recipient notification functions in external contracts.
            _spendAllowance_stateUpdater(operator, holder, amount);
        }

        // Transfer amount from holder to recipient
        require(amount <= balanceOf[holder], "Insufficient balance");
        unchecked { balanceOf[holder] -= amount; }  // Save gas by using unchecked
        balanceOf[recipient] += amount;

        // EMIT EVENTS:

        // Emit ERC20 transfer event
        emit Transfer(holder, recipient, amount);
        // Emit ERC20 "safe approval" transfer event
        emit TransferInfo(operator, holder, recipient, amount);
        
        // NO INTERACTIONS
    }

    /**
     * @dev Sets `allowedAmount` as the number of `holder`'s tokens that `spender` is allowed to transfer.
     *
     * @param holder The holder of the tokens.
     * @param spender The spender of the tokens.
     * @param allowedAmount The number of tokens to grant as an allowance.
     * @param expirationTimestamp The last valid block timestamp for the allowance.
     */
    function _approve_stateUpdater(address holder, address spender, uint256 allowedAmount,
            uint256 expirationTimestamp) internal {
    
        // PRECONDITIONS [CHECKS]:
        
        require(holder != address(0) && spender != address(0), "Bad arg");
        require(_unlimitedAllowancesEnabled || allowedAmount != UNLIMITED_ALLOWANCE, "Bad allowance");
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= expirationTimestamp, "Allowance expired");

        // APPROVE [EFFECTS], AND EMIT EVENTS:

        // Set allowed amount. Will generate new allowance events.
        _setAllowance_stateUpdater(holder, spender, allowedAmount, expirationTimestamp);
        
        // NO INTERACTIONS
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Core account management functions, called by the public API.

    /**
     * @dev Mint `amount` tokens into `account`.
     *
     * @param operator The address performing the mint.
     * @param account The address to mint tokens into.
     * @param amount The number of tokens to mint.
     * @param data Data generated by the user to be passed to the recipient.
     */
    function _mint(address operator, address account, uint256 amount, bytes memory data) internal {

        // CHECKS, EFFECTS, EVENTS -- `stateUpdater` function:
        
        _mint_stateUpdater(operator, account, amount);

        // NOTIFY RECIPIENT [INTERACTIONS] -- `extCaller` functions:

        // Notify ERC4524 token recipient of mint from address(0), if called from ERC4524 API
        if (_erc4524CallDepth > 0) {
            call_ERC4524TokensRecipient_onERC20Received(
                    operator, /* sender = */ address(0), /* recipient = */ account, amount, data);
        }
        // Call ERC1363 recipient if called from ERC1363 API
        if (_erc1363CallDepth > 0) {
            call_ERC1363Receiver_onTransferReceived(
                    operator, /* sender = */ address(0), /* recipient = */ account, amount, data);
        }
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the total supply.
     *
     * @param operator The address performing the burn.
     * @param account The address to burn tokens from.
     * @param amount The number of tokens to burn.
     */
    function _burn(address operator, address account, uint256 amount) internal {

        // CHECKS, EFFECTS, EVENTS -- `stateUpdater` function:

        _burn_stateUpdater(operator, account, amount);
    }

    /**
     * @dev Transfer `amount` tokens from `holder` to `recipient`.
     *
     * @param operator The address performing the transfer.
     * @param holder The address holding the tokens being transferred.
     * @param recipient The address of the recipient.
     * @param amount The number of tokens to be transferred.
     * @param useAllowance If true, use the allowance system to determine whether the user can make
     *                     the transfer, and reduce the allowance by the amount of the transfer.
     * @param data Data generated by the user to be passed to the recipient.
     */
    function _transfer(address operator, address holder, address recipient, uint256 amount, bool useAllowance,
            bytes memory data) internal {

        // CHECKS, EFFECTS, EVENTS -- `stateUpdater` function:

        _transfer_stateUpdater(operator, holder, recipient, amount, useAllowance);

        // NOTIFY SENDER/RECIPIENT [INTERACTIONS] -- `extCaller` functions:

        // Call ERC1363 recipient if called from ERC1363 API
        if (_erc1363CallDepth > 0) {
            call_ERC1363Receiver_onTransferReceived(operator, holder, recipient, amount, data);
        }
        // Call ERC4524 recipient if called from ERC4524 API
        if (_erc4524CallDepth > 0) {
            call_ERC4524TokensRecipient_onERC20Received(operator, holder, recipient, amount, data);
        }
    }

    /**
     * @dev Sets `allowedAmount` as the number of `holder`'s tokens that `spender` is allowed to transfer.
     *
     * @param holder The holder of the tokens.
     * @param spender The spender of the tokens.
     * @param allowedAmount The number of tokens to grant as an allowance.
     * @param expirationTimestamp The last valid block timestamp for the allowance.
     * @param data Data to be passed to the spender, if the approval is via ERC1363's `approveAndCall` function.
     */
    function _approve(address holder, address spender, uint256 allowedAmount, uint256 expirationTimestamp,
            bytes memory data) internal {

        // CHECKS, EFFECTS, EVENTS -- `stateUpdater` function:

        _approve_stateUpdater(holder, spender, allowedAmount, expirationTimestamp);

        // NOTIFY SPENDER [INTERACTIONS] -- `extCaller` function:
        
        // Notify ERC1363 spender, if called from ERC1363 API
        if (_erc1363CallDepth > 0) {
            call_ERC1363Spender_onApprovalReceived(/* holder = */ holder, spender, allowedAmount, data);
        }
    }

    // -----------------------------------------------------------------------------------------------------------------
    // ERC20 allowance/approve/transfer/transferFrom API functions

    /**
     * @notice Get the number of tokens that `spender` can spend on behalf of `holder`.
     *
     * @dev [ERC20] Returns the remaining number of tokens that `spender` will be allowed to spend on
     * behalf of `holder`, via a call to `transferFrom`. Zero by default. Also returns zero if
     * allowance has expired.
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or spender.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param holder The token holder.
     * @param spender The token spender.
     * @return amount The allowance of `spender` to spend the funds of `holder`.
     */
    function allowance(address holder, address spender) public view erc20 override(IERC20)
            returns (uint256 amount) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp <= _allowanceExpirationTimestamp[holder][spender]
                ? _allowance[holder][spender]
                : 0;  // Allowance has expired
    }

    /**
     * @notice Approve another account (or contract) to spend tokens on your behalf.
     *
     * @dev [ERC20] Approves a `spender` to be allowed to spend `amount` tokens on behalf of the
     * caller, via a call to `transferFrom`.
     *
     * Note that by default (unless the behavior was changed by the contract owner/deployer), the allowance
     * has to be set to zero before it can be set to a non-zero amount, to prevent the well-known ERC20 allowance
     * race condition that can allow double-spending of allowances. This is not fully ERC20-compatible, but it
     * is much safer.
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or spender.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param spender The spender.
     * @param amount The allowance amount. Use a value of `0` to disallow `spender` spending tokens on behalf
     *          of the caller. Use a value of `2**256-1` to set unlimited allowance, if unlimited allowances are
     *          enabled. The allowed amount may be greater than the account balance.
     * @return success `true` if the approval succeeded (otherwise reverts).
     */
    function approve(address spender, uint256 amount) external erc20 override(IERC20)
            returns (bool success) {
        if (!_changingAllowanceWithoutZeroingEnabled && amount != 0) {
            // ERC20 safety: have to set allowance to zero (or let it expire) before it can be set to non-zero
            require(allowance(/* holder = */ msg.sender, spender) == 0, "Curr allowance nonzero");
        }
        _approve(/* holder = */ msg.sender, spender, amount, defaultAllowanceExpirationTime(), "");
        return true;
    }

    /**
     * @notice Transfer tokens to another account.
     *
     * @dev [ERC20] Moves `amount` tokens from the caller's account to `recipient`.
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param recipient The token recipient.
     * @param amount The number of tokens to transfer from the caller to `recipient`.
     * @return success `true` if the operation succeeded (otherwise reverts).
     */
    function transfer(address recipient, uint256 amount) external erc20 override(IERC20)
            returns (bool success) {
        // ERC20 tokens should almost never need to be sent to a smart contract -- tokens sent to a smart
        // contract are generally considered burned. Therefore, disallow transfer to smart contracts.
        // This is non-standard, but provides important protection to users against the most common mistake
        // in sending ERC20 tokens, which has caused millions of dollars in loss.
        // Instead, the user should use `approve` and `transferFrom`, or ERC1363/ERC4524.
        require(_transferToContractsEnabled || !isContract(recipient), "Can't transfer to contract");
        // Perform the transfer
        _transfer(/* operator = */ msg.sender, /* sender = */ msg.sender, recipient, amount,
                /* useAllowance = */ false, "");
        return true;
    }

    /**
     * @notice Transfer tokens from a holder account to a recipient account account, on behalf of the holder.
     *
     * @dev [ERC20] Moves `amount` tokens from `sender` to `recipient`. The caller must have previously been
     * approved by `sender` to send at least `amount` tokens on their behalf, by `sender` calling `approve`.
     * `amount` is deducted from the caller’s allowance (unless the allowance is set to unlimited).
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     * 
     * @param holder The token holder.
     * @param recipient The token recipient.
     * @param amount The number of tokens to transfer from the caller to `recipient`.
     * @return success `true` if the operation succeeded (otherwise reverts).
     */
    function transferFrom(address holder, address recipient, uint256 amount) external erc20 override(IERC20)
            returns (bool success) {
        // Don't allow transfer to contracts, as with `transfer` function
        require(_transferToContractsEnabled || !isContract(recipient), "Can't transfer to contract");
        // Perform the transfer
        _transfer(/* operator = */ msg.sender, holder, recipient, amount, /* useAllowance = */ true, "");
        return true;
    }

    // -----------------------------------------------------------------------------------------------------------------
    // ERC20 extensions

    /**
     * @notice Safely increase the allowance for a spender to spend your tokens.
     *
     * @dev [ERC20 extension] Increases the ERC20 token allowance granted to `spender` by the caller.
     * This is an alternative to `approve` that can mitigate for the double-spend race condition attack
     * that is described here:
     *
     * https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM/edit
     *
     * N.B. the transaction will revert if the allowance is currently set to the unlimited allowance
     * amount of `2**256-1`, since the correct new allowance amount cannot be determined by addition.
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or spender.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param spender The token spender.
     * @param amountToAdd The number of tokens by which to increase the allowance of `spender`.
     * @return success `true` if the operation succeeded (otherwise reverts).
     */
    function increaseAllowance(address spender, uint256 amountToAdd)
            external erc20 override(IERC20IncreaseDecreaseAllowance) returns (bool success) {
        if (amountToAdd > 0) {
            uint256 allowedAmount = _allowance[/* holder = */ msg.sender][spender];
            // Don't increase an unlimited allowance
            require(allowedAmount != UNLIMITED_ALLOWANCE, "Unlimited allowance");
            // Don't increase an expired allowance
            // solhint-disable-next-line not-rely-on-time
            require(block.timestamp <= _allowanceExpirationTimestamp[/* holder = */ msg.sender][spender],
                    "Allowance expired");
            // Increase allowance
            _approve(/* holder = */ msg.sender, spender, allowedAmount + amountToAdd,
                    // Reset allowance expiration time every time allowance is increased
                    defaultAllowanceExpirationTime(), "");
        }
        return true;
    }

    /**
     * @notice Safely decrease the allowance for a spender to spend your tokens.
     *
     * @dev [ERC20 extension] Decreases the ERC20 token allowance granted to `spender` by the caller.
     * This is an alternative to `approve` that can mitigate for the double-spend race condition attack
     * that is described here:
     *
     * https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM/edit
     *
     * N.B. the transaction will revert if the allowance is currently set to the unlimited allowance
     * amount of `2**256-1`, since the correct new allowance amount cannot be determined by subtraction.
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or spender.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param spender The token spender.
     * @param amountToSubtract The number of tokens by which to decrease the allowance of `spender`.
     * @return success `true` if the operation succeeded (otherwise reverts).
     *         Note that this operation will revert if amountToSubtract is greater than the current allowance.
     */
    function decreaseAllowance(address spender, uint256 amountToSubtract)
            external erc20 override(IERC20IncreaseDecreaseAllowance) returns (bool success) {
        if (amountToSubtract > 0) {
            uint256 allowedAmount = _allowance[/* holder = */ msg.sender][spender];
            // Don't decrease an unlimited allowance
            require(allowedAmount != UNLIMITED_ALLOWANCE, "Unlimited allowance");
            // Can't decrease by more than the current allowance
            require(amountToSubtract <= allowedAmount, "Insufficient allowance");
            // Don't decrease an expired allowance
            // solhint-disable-next-line not-rely-on-time
            require(block.timestamp <= _allowanceExpirationTimestamp[/* holder = */ msg.sender][spender],
                    "Allowance expired");
            // Decrease allowance
            uint256 newAllowedAmount;
            unchecked { newAllowedAmount = allowedAmount - amountToSubtract; }  // Save gas with unchecked
            _approve(/* holder = */ msg.sender, spender, newAllowedAmount,
                    // Reset allowance expiration time every time allowance is decreased
                    defaultAllowanceExpirationTime(), "");
        }
        return true;
    }

    /**
     * @notice Safely change the allowance for a spender to spend your tokens.
     * 
     * @dev [ERC20 extension] Atomically compare-and-set the allowance for a spender.
     * This is designed to mitigate the ERC-20 allowance attack described in:
     *
     * "ERC20 API: An Attack Vector on Approve/TransferFrom Methods"
     * https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM/edit
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or spender.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param spender The spender.
     * @param expectedCurrentAmount The expected amount of `spender`'s current allowance.
     *        If the current allowance does not match this value, then the transaction will revert.
     * @param amount The new allowance amount.
     * @return success `true` if the operation succeeded (otherwise reverts).
     */
    function approve(address spender, uint256 expectedCurrentAmount, uint256 amount)
            external erc20 override(IERC20SafeApproval) returns (bool success) {
        require(_allowance[/* holder = */ msg.sender][spender] == expectedCurrentAmount, "Allowance mismatch");
        // Approve new allowance, with default expiration time.
        _approve(/* holder = */ msg.sender, spender, amount, defaultAllowanceExpirationTime(), "");
        return true;
    }

    /**
     * @notice Approve a spender to spend your tokens with a specified expiration time.
     *
     * @dev ERC20 extension function for approving with time-limited allowances.
     *
     * See: https://github.com/vrypan/EIPs/blob/master/EIPS/eip-draft_time_limited_token_allowances.md
     *
     * @dev Note that the block timestamp can be altered by miners up to about +/-15 seconds under proof of work
     * (as long as block timestamps increase monotonically), so do not use an allowance expiration time of less
     * than 15 seconds for PoW networks. For proof of stake, the block interval is set to exactly 12 seconds,
     * so the expiration time should probably be set to 13 seconds or more for PoS networks.
     *
     * Note that by default (unless the behavior was changed by the contract owner/deployer), the allowance
     * has to be set to zero before it can be set to a non-zero amount, to prevent the well-known ERC20 allowance
     * race condition that can allow double-spending of allowances. This is not fully ERC20-compatible (and
     * it is not the defined behavior of this ERC20 extension), but it is much safer than the ERC20 default.
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or spender.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param spender The token spender.
     * @param amount The number of tokens to allow spender to spend on the caller's behalf.
     * @param expirationSec The number of seconds after which the allowance expires, or `2**256-1` if the
     *          allowance should not expire (consider this unsafe), or `0` if spending must happen in the
     *          same block as approval (e.g. for a flash loan).
     *          Note: The proposal for this ERC20 extension API requires a user to specify the number of
     *          blocks an approval should be valid for before expiration. OmniToken uses seconds instead
     *          of number of blocks, because mining does not happen at a reliable interval.
     * @return success `true` if approval was successful.
     */
    function approveWithExpiration(address spender, uint256 amount, uint256 expirationSec)
            external erc20 override(IERC20TimeLimitedTokenAllowances) returns (bool success) {
        if (!_changingAllowanceWithoutZeroingEnabled && amount != 0) {
            // Have to set allowance to zero (or let it expire) before it can be set to non-zero
            require(allowance(/* holder = */ msg.sender, spender) == 0, "Curr allowance nonzero");
        }
        require(expirationSec >= MIN_EXPIRATION_SEC, "expirationSec too small");
        _approve(/* holder = */ msg.sender, spender, amount,
                expirationSec == UNLIMITED_EXPIRATION ? expirationSec
                        // solhint-disable-next-line not-rely-on-time
                        : block.timestamp + expirationSec, "");
        return true;
    }
    
    /**
     * @notice Get the expiration timestamp for the allowance of a spender to spend tokens on behalf of a holder.
     * 
     * @dev ERC20 extension function for returning the allowance amount and block timestamp after which allowance
     * expires. Expiration time will be `2**256-1` for allowances that do not expire, or smaller than that value
     * for time-limited allowances.
     *
     * See: https://github.com/vrypan/EIPs/blob/master/EIPS/eip-draft_time_limited_token_allowance.md
     *
     * @param holder The token holder.
     * @param spender The token spender.
     * @return remainingAmount The amount of the allowance remaining, or 0 if the allowance has expired.
     * @return expirationTimestamp The block timestamp after which the allowance expires.
     */
    function allowanceWithExpiration(address holder, address spender)
            external view erc20 override(IERC20TimeLimitedTokenAllowances)
            returns (uint256 remainingAmount, uint256 expirationTimestamp) {
        remainingAmount = allowance(holder, spender);
        expirationTimestamp = _allowanceExpirationTimestamp[holder][spender];
    }

    /**
     * @notice Burn tokens.
     *
     * @dev [ERC20 extension] Burn tokens. Destroys `amount` tokens from caller's account forever,
     * reducing the total supply. Use with caution, as this cannot be reverted, and you should ensure
     * that some other smart contract guarantees you some benefit for burning tokens before you burn
     * them.
     *
     * By convention, burning is logged as a transfer to the zero address.
     *
     * @param amount The amount to burn.
     */
    function burn(uint256 amount) external erc20 override(IERC20Burn) {
        _burn(/* operator = */ msg.sender, /* account = */ msg.sender, amount);
    }
    
    // -----------------------------------------------------------------------------------------------------------------
    // ERC1363 functions
    
    /**
     * @notice Transfer tokens to a recipient, and then call the ERC1363 recipient notification interface
     * on the recipient.
     *
     * @dev [ERC1363] Transfer tokens from the caller to `recipient`, and then call the ERC1363 receiver
     * interface's `onTransferReceived` on the recipient. The transaction will fail if the recipient does
     * not implement this interface (including if the recipient address is an EOA address).
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param recipient The address which you want to transfer tokens to.
     * @param amount The number of tokens to be transferred.
     * @return success `true` unless the transaction is reverted.
     */
    function transferAndCall(address recipient, uint256 amount)
            external erc1363 override(IERC1363) returns (bool success) {
        // Safety is guaranteed by the erc1363 function modifier, which sets _erc1363CallDepth,
        // which requires _transfer to successfully notify the ERC1363 recipient
        _transfer(/* operator = */ msg.sender, /* holder = */ msg.sender, recipient, amount,
                  /* useAllowance = */ false, "");
        return true;
    }

    /**
     * @notice Transfer tokens to a recipient, and then call the ERC1363 recipient notification interface
     * on the recipient.
     *
     * @dev [ERC1363] Transfer tokens from the caller to `recipient`, and then call the ERC1363 receiver
     * interface's `onTransferReceived` on the recipient. The transaction will fail if the recipient does
     * not implement this interface (including if the recipient address is an EOA address).
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param recipient The address which you want to transfer tokens to.
     * @param amount The number of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `recipient`.
     * @return success `true` unless the transaction is reverted.
     */
    function transferAndCall(address recipient, uint256 amount, bytes calldata data)
            external erc1363 override(IERC1363) returns (bool success) {
        // Safety is guaranteed by the erc1363 function modifier, which sets _erc1363CallDepth,
        // which requires _transfer to successfully notify the ERC1363 recipient
        _transfer(/* operator = */ msg.sender, /* holder = */ msg.sender, recipient, amount,
                  /* useAllowance = */ false, data);
        return true;
    }

    /**
     * @notice Transfer tokens to a recipient on behalf of another account, and then call the ERC1363
     * recipient notification interface on the recipient.
     *
     * @dev [ERC1363] Transfer tokens from `holder` to `recipient`, and then call the ERC1363 spender
     * interface's `onApprovalReceived` on the recipient.
     * The transaction will fail if the recipient does not implement the required interface,
     * including if the recipient address is an EOA address.
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param holder The address which you want to send tokens on behalf of.
     * @param recipient The address which you want to transfer tokens to.
     * @param amount The number of tokens to be transferred.
     * @return success `true` unless the transaction is reverted.
     */
    function transferFromAndCall(address holder, address recipient, uint256 amount)
            external erc1363 override(IERC1363) returns (bool success) {
        // Safety is guaranteed by the erc1363 function modifier, which sets _erc1363CallDepth,
        // which requires _transfer to successfully notify the ERC1363 recipient
        _transfer(/* operator = */ msg.sender, holder, recipient, amount, /* useAllowance = */ true, "");
        return true;
    }


    /**
     * @notice Transfer tokens to a recipient on behalf of another account, and then call the ERC1363
     * recipient notification interface on the recipient.
     *
     * @dev [ERC1363] Transfer tokens from `holder` to `recipient`, and then call the ERC1363 spender
     * interface's `onApprovalReceived` on the recipient.
     * The transaction will fail if the recipient does not implement the required interface,
     * including if the recipient address is an EOA address.
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param holder The address which you want to send tokens from.
     * @param recipient The address which you want to transfer tokens to.
     * @param amount The number of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `recipient`.
     * @return success `true` unless the transaction is reverted.
     */
    function transferFromAndCall(address holder, address recipient, uint256 amount, bytes calldata data)
            external erc1363 override(IERC1363) returns (bool success) {
        // Safety is guaranteed by the erc1363 function modifier, which sets _erc1363CallDepth,
        // which requires _transfer to successfully notify the ERC1363 recipient
        _transfer(/* operator = */ msg.sender, holder, recipient, amount, /* useAllowance = */ true, data);
        return true;
    }

    /**
     * @notice Approve another account to spend your tokens, and then call the ERC1363 spender notification
     * interface on the spender.
     *
     * @dev [ERC1363] Approve `spender` to spend the specified number of tokens on behalf of
     * caller (the token holder), and then call `onApprovalReceived` on spender.
     * The transaction will fail if the recipient does not implement the required interface,
     * including if the recipient address is an EOA address.
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the spender or recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param spender The address which will spend the funds.
     * @param amount The number of tokens to allow the spender to spend.
     * @return success `true` unless the transaction is reverted.
     */
    function approveAndCall(address spender, uint256 amount)
            external erc1363 override(IERC1363) returns (bool success) {
        // Safety is guaranteed by the erc1363 function modifier, which sets _erc1363CallDepth,
        // which requires _approve to successfully notify the ERC1363 spender
        _approve(/* holder = */ msg.sender, spender, amount, defaultAllowanceExpirationTime(), "");
        return true;
    }

    /**
     * @notice Approve another account to spend your tokens, and then call the ERC1363 spender notification
     * interface on the spender.
     *
     * @dev [ERC1363] Approve `spender` to spend the specified number of tokens on behalf of
     * caller (the token holder), and then call `onApprovalReceived` on spender.
     * The transaction will fail if the recipient does not implement the required interface,
     * including if the recipient address is an EOA address.
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the spender or recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param spender The address which will spend the funds.
     * @param amount The number of tokens to be allow the spender to spend.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return success `true` unless the transaction is reverted.
     */
    function approveAndCall(address spender, uint256 amount, bytes calldata data)
            external erc1363 override(IERC1363) returns (bool success) {
        // Safety is guaranteed by the erc1363 function modifier, which sets _erc1363CallDepth,
        // which requires _approve to successfully notify the ERC1363 spender
        _approve(/* holder = */ msg.sender, spender, amount, defaultAllowanceExpirationTime(), data);
        return true;
    }
       
    // -----------------------------------------------------------------------------------------------------------------
    // ERC4524 functions

    /**
     * @notice Transfer funds and then notify the recipient via the ERC4524 receiver interface.
     *
     * @dev [ERC4524] Move `amount` tokens from the caller's account to `recipient`. Only succeeds if `recipient`
     * correctly implements the ERC4524 receiver interface, or if the receiver is an EOA (non-contract wallet).
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param recipient The token recipient.
     * @param amount The number of tokens to transfer from the caller to `recipient`.
     * @return success `true` if the operation succeeded (otherwise reverts).
     */
    function safeTransfer(address recipient, uint256 amount)
            external erc4524 override(IERC4524) returns(bool success) {
        // Safety is guaranteed by the erc4524 function modifier, which sets _erc4524CallDepth,
        // which requires _transfer to successfully notify the ERC4524 recipient
        _transfer(/* operator = */ msg.sender, /* holder = */ msg.sender, recipient, amount,
                  /* useAllowance = */ false, "");
        return true;
    }
    
    /**
     * @notice Transfer funds and then notify the recipient via the ERC4524 receiver interface.
     *
     * @dev [ERC4524] Move `amount` tokens from the caller's account to `recipient`. Only succeeds if `recipient`
     * correctly implements the ERC4524 receiver interface, or if the receiver is an EOA (non-contract wallet).
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param recipient The token recipient.
     * @param amount The number of tokens to transfer from the caller to `recipient`.
     * @param data Extra data to add to the emmitted transfer event.
     * @return success `true` if the operation succeeded (otherwise reverts).
     */
    function safeTransfer(address recipient, uint256 amount, bytes calldata data)
            external erc4524 override(IERC4524) returns(bool success) {
        // Safety is guaranteed by the erc4524 function modifier, which sets _erc4524CallDepth,
        // which requires _transfer to successfully notify the ERC4524 recipient
        _transfer(/* operator = */ msg.sender, /* holder = */ msg.sender, recipient, amount,
                  /* useAllowance = */ false, data);
        return true;
    }
    
    /**
     * @notice Transfer funds and then notify the recipient via the ERC4524 receiver interface.
     *
     * @dev [ERC4524] Move `amount` tokens from `holder` to `recipient`. (The caller must have
     * previously been approved by `holder` to send at least `amount` tokens on behalf of `holder`, by
     * `holder` calling `approve`.) `amount` is then deducted from the caller’s allowance.
     * Only succeeds if `recipient` correctly implements the ERC4524 receiver interface,
     * or if `recipient` is an EOA (non-contract wallet).
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     * 
     * @param holder The token holder.
     * @param recipient The token recipient.
     * @param amount The number of tokens to transfer from the caller to `recipient`.
     * @return success `true` if the operation succeeded (otherwise reverts).
     */
    function safeTransferFrom(address holder, address recipient, uint256 amount)
            external erc4524 override(IERC4524) returns(bool success) {
        // Safety is guaranteed by the erc4524 function modifier, which sets _erc4524CallDepth,
        // which requires _transfer to successfully notify the ERC4524 recipient
        _transfer(/* operator = */ msg.sender, holder, recipient, amount, /* useAllowance = */ true, "");
        return true;
    }
    
    /**
     * @notice Transfer funds and then notify the recipient via the ERC4524 receiver interface.
     *
     * @dev [ERC4524] Move `amount` tokens from `holder` to `recipient`. (The caller must have
     * previously been approved by `holder` to send at least `amount` tokens on behalf of `holder`, by
     * `holder` calling `approve`.) `amount` is then deducted from the caller’s allowance.
     * Only succeeds if `recipient` correctly implements the ERC4524 receiver interface,
     * or if `recipient` is an EOA (non-contract wallet).
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or recipient.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     * 
     * @param holder The token holder.
     * @param recipient The token recipient.
     * @param amount The number of tokens to transfer from the caller to `recipient`.
     * @param data Extra data to add to the emmitted transfer event.
     * @return success `true` if the operation succeeded (otherwise reverts).
     */
    function safeTransferFrom(address holder, address recipient, uint256 amount, bytes calldata data)
            external erc4524 override(IERC4524) returns(bool success) {
        // Safety is guaranteed by the erc4524 function modifier, which sets _erc4524CallDepth,
        // which requires _transfer to successfully notify the ERC4524 recipient
        _transfer(/* operator = */ msg.sender, holder, recipient, amount, /* useAllowance = */ true, data);
        return true;
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Permitting

    /**
     * @notice Convert a signed certificate into a permit or allowance for a spender account to spend tokens
     * on behalf of a holder account.
     *
     * @dev [EIP2612] Implements the EIP2612 permit standard. Sets the spendable allowance for `spender` to
     * spend `holder`'s tokens, which can then be transferred using the ERC20 `transferFrom` function.
     *
     * https://eips.ethereum.org/EIPS/eip-2612
     * https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2ERC20.sol
     *
     * @notice By calling this function, you confirm that this token is not considered an unregistered or
     * illegal security, and that this smart contract is not considered an unregistered or illegal exchange,
     * by the laws of any legal jurisdiction in which you hold or use tokens, or any legal jurisdiction
     * of the holder or spender.
     * 
     * @notice In some jurisdictions, such as the United States, any use, transfer, or sale of a token is
     * a taxable event. It is your responsibility to record the purchase price and sale price in ETH or
     * your local currency for each use, transfer, or sale of tokens you own, and to pay the taxes due.
     *
     * @param holder The token holder that signed the certificate.
     * @param spender The spender who will be authorized to spend tokens on behalf of `holder`.
     * @param amount The number of tokens `spender` will be authorized to spend on behalf of `holder`.
     * @param deadline The block timestamp after which the certificate expires.
     *          Note that if the permit is granted, then the allowance that is approved has its own deadline,
     *          separate from the certificate deadline. By default, allowances expire 1 hour after they are
     *          granted, but this may be modified by the contract owner -- call `defaultAllowanceExpirationSec()`
     *          to get the current value.
     * @param v The ECDSA certificate `v` value.
     * @param r The ECDSA certificate `r` value.
     * @param s The ECDSA certificate `s` value.
     */
    function permit(address holder, address spender, uint256 amount, uint256 deadline,
            uint8 v, bytes32 r, bytes32 s) external eip2612 override(IEIP2612) {
            
        // Check whether permit is valid (reverts if not)
        uint256 nonce;
        unchecked { nonce = nonces[holder]++; }
        checkPermit(deadline,
                keccak256(abi.encode(EIP2612_PERMIT_TYPEHASH, holder, spender, amount, nonce, deadline)),
                v, r, s, /* requiredSigner = */ holder);
                
        // Approve amount allowed in the permit
        _approve(holder, spender, amount,
                // Use the default allowance expiration time
                defaultAllowanceExpirationTime(), "");
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Cross-chain bridge/router support (for Multichain router and Polygon PoS bridge).
    //
    // Setting up Multichain:
    //     https://github.com/anyswap/CrossChain-Router/issues/5#issuecomment-1241463675
    //     https://docs.multichain.org/listing-and-integration/token-listing/erc20-cross-chain-options
    //
    // Setting up Polygon PoS bridge:
    //     https://wiki.polygon.technology/docs/develop/ethereum-polygon/getting-started/
    
    /**
     * @notice Used by Multichain cross-chain routers to detect the supported router mode.
     *
     * @dev See:
     * https://docs.multichain.org/developer-guide/how-to-develop-under-anyswap-erc20-standards
     */
    address public immutable override(IMultichain) underlying = address(0);
    
    /**
     * @notice Only callable by Multichain cross-chain routers.
     *
     * @dev Burns tokens for a Multichain router -- see:
     * https://docs.multichain.org/developer-guide/how-to-develop-under-anyswap-erc20-standards
     *
     * @param addr The address to burn tokens for.
     * @param amount The number of tokens to burn.
     */
    function burn(address addr, uint256 amount)
            // Only authorized burners can call this method
            burnerOnly
            external override(IMultichain) returns (bool success) {
        _burn(/* operator = */ msg.sender, /* account = */ addr, amount);
        return true;
    }

    /**
     * @notice Called on the Polygon contract when user wants to withdraw tokens from Polygon back to Ethereum.
     *
     * @dev Burns the caller's tokens. Should only be called on the Polygon network, and this is only one step
     * of several required steps to complete the transfer of assets back to Ethereum:
     * https://docs.polygon.technology/docs/develop/ethereum-polygon/pos/getting-started/#withdrawals
     *
     * @param amount The number of tokens to withdraw (burn).
     */
    function withdraw(uint256 amount)
            // No burnerOnly authorization needed
            // (user burns their own tokens when withdrawing from Polygon)
            external override(IPolygonBridgeable) {
        _burn(/* operator = */ msg.sender, /* account = */ msg.sender, amount);
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
            // Only authorized minters can call this method
            minterOnly
            external override(OmniTokenInternal /* IMultichain,IPolygonBridgeable */)
            returns (bool success) {
        _mint(/* operator = */ msg.sender, /* account = */ addr, amount, "");
        return true;
    }

    /**
     * @notice Only callable by the Polygon PoS bridge's ChildChainManager.
     *
     * @dev Called on the Polygon contract when tokens are deposited on the Polygon chain -- see:
     * https://docs.polygon.technology/docs/develop/ethereum-polygon/mintable-assets
     *
     * @param addr The address to deposit tokens for.
     * @param depositData The ABI-encoded number of tokens to deposit.
     */
    function deposit(address addr, bytes calldata depositData)
            // Only authorized minters can call this method
            minterOnly
            external override(IPolygonBridgeable) {
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(/* operator = */ msg.sender, /* account = */ addr, amount, "");
    }
}


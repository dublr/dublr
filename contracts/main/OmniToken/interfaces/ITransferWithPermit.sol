// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

/**
 * @notice Allow permitted transfers in the style of EIP2612.
 *
 * @dev This is not part of the EIP2612 standard; however, it is implemented in AnySwap's ERC20
 * token template V5 ( https://github.com/anyswap/chaindata/blob/main/AnyswapV5ERC20.sol ),
 * and it provides useful functionality.
 */
interface ITransferWithPermit {
    /**
     * @notice Allow permitted transfers in the style of EIP2612.
     *
     * @dev This is not part of the EIP2612 standard; however, it is implemented in AnySwap's ERC20
     * token template V5 ( https://github.com/anyswap/chaindata/blob/main/AnyswapV5ERC20.sol ),
     * and it provides useful functionality.
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
     * @param recipient The recipient of the tokens.
     * @param amount The number of tokens that `msg.sender` has been authorized to transfer on behalf of `holder`.
     * @param deadline The block timestamp after which the certificate expires.
     * @param v The ECDSA certificate `v` value.
     * @param r The ECDSA certificate `r` value.
     * @param s The ECDSA certificate `s` value.
     */
    function transferWithPermit(address holder, address recipient, uint256 amount, uint256 deadline,
            uint8 v, bytes32 r, bytes32 s) external returns (bool success);
}


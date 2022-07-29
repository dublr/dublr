// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

/**
 * @dev Interface of Parity function registration API.
 */
interface IParityRegistry {
    /**
     * @notice Register a function with Parity.
     */
    function register(string memory method) external;
}


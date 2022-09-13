// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

/**
 * @dev Interface of the Polygon chain-bridging API.
 * See: https://docs.polygon.technology/docs/develop/ethereum-polygon/mintable-assets
 */
interface IPolygonBridgeable {
    /**
     * @notice Only callable by Polygon ChildChainManager.
     *
     * @dev Called on the Polygon contract when tokens are deposited on the Polygon chain.
     * Only callable by ChildChainManager (DEPOSITOR_ROLE). Contract addresses:
     * Mumbai: 0xb5505a6d998549090530911180f38aC5130101c6
     * Mainnet: 0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa
     *
     * @param user address to deposit tokens for
     * @param depositData ABI-encoded amount
     */
    function deposit(address user, bytes calldata depositData) external;

    /**
     * @notice Called on the Polygon contract when user wants to withdraw tokens from Polygon back to Ethereum.
     *
     * @dev Burn's the user's tokens. Should only be called on the Polygon network, and this is only one step
     * of all the required steps to complete the transfer of assets back to Ethereum:
     * https://docs.polygon.technology/docs/develop/ethereum-polygon/pos/getting-started/#withdrawals
     *
     * @param amount amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external;
}


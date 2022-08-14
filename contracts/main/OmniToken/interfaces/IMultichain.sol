// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

/**
 * @dev Interface of the Multichain chain-bridging API.
 * See: https://docs.multichain.org/developer-guide/how-to-develop-under-anyswap-erc20-standards
 */
interface IMultichain {
    /**
     * @notice Only callable by Multichain cross-chain router bridges.
     * @dev Mints tokens for a Multichain router -- see:
     * https://docs.multichain.org/developer-guide/how-to-develop-under-anyswap-erc20-standards
     */
    function mint(address to, uint256 amount) external returns (bool success);

    /**
     * @notice Only callable by Multichain cross-chain router bridges.
     * @dev Burns tokens for a Multichain router -- see:
     * https://docs.multichain.org/developer-guide/how-to-develop-under-anyswap-erc20-standards
     */
    function burn(address from, uint256 amount) external returns (bool success);

    /**
     * @notice Used by Multichain cross-chain router bridges to detect the bridge API.
     * @dev See:
     * https://docs.multichain.org/developer-guide/how-to-develop-under-anyswap-erc20-standards
     */
    function underlying() external view returns(address);
}


// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

/** @dev Interface for ERC1820 registry. */
interface IERC1820Registry {
    /// @notice Indicates a contract is the 'implementer' of 'interfaceHash' for 'addr'.
    event InterfaceImplementerSet(address indexed addr, bytes32 indexed interfaceHash, address indexed implementer);
    /// @notice Indicates 'newManager' is the address of the new manager for 'addr'.
    event ManagerChanged(address indexed addr, address indexed newManager);

    /// @notice Query if an address implements an interface and through which contract.
    /// @param _addr Address being queried for the implementer of an interface.
    /// (If '_addr' is the zero address then 'msg.sender' is assumed.)
    /// @param _interfaceHash Keccak256 hash of the name of the interface as a string.
    /// E.g., 'web3.utils.keccak256("ERC777TokensRecipient")' for the 'ERC777TokensRecipient' interface.
    /// @return The address of the contract which implements the interface '_interfaceHash' for '_addr'
    /// or '0' if '_addr' did not register an implementer for this interface.
    function getInterfaceImplementer(address _addr, bytes32 _interfaceHash) external view returns (address);

    /// @notice Sets the contract which implements a specific interface for an address.
    /// Only the manager defined for that address can set it.
    /// (Each address is the manager for itself until it sets a new manager.)
    /// @param _addr Address for which to set the interface.
    /// (If '_addr' is the zero address then 'msg.sender' is assumed.)
    /// @param _interfaceHash Keccak256 hash of the name of the interface as a string.
    /// E.g., 'web3.utils.keccak256("ERC777TokensRecipient")' for the 'ERC777TokensRecipient' interface.
    /// @param _implementer Contract address implementing '_interfaceHash' for '_addr'.
    function setInterfaceImplementer(address _addr, bytes32 _interfaceHash, address _implementer) external;

    /// @notice Sets '_newManager' as manager for '_addr'.
    /// The new manager will be able to call 'setInterfaceImplementer' for '_addr'.
    /// @param _addr Address for which to set the new manager.
    /// @param _newManager Address of the new manager for 'addr'. (Pass '0x0' to reset the manager to '_addr'.)
    function setManager(address _addr, address _newManager) external;

    /// @notice Get the manager of an address.
    /// @param _addr Address for which to return the manager.
    /// @return Address of the manager for a given address.
    function getManager(address _addr) external view returns(address);

    /// @notice Compute the keccak256 hash of an interface given its name.
    /// @param _interfaceName Name of the interface.
    /// @return The keccak256 hash of an interface name.
    function interfaceHash(string calldata _interfaceName) external pure returns(bytes32);

    /* --- ERC165 Related Functions --- */
    /* --- Developed in collaboration with William Entriken. --- */

    /// @notice Updates the cache with whether the contract implements an ERC165 interface or not.
    /// @param _contract Address of the contract for which to update the cache.
    /// @param _interfaceId ERC165 interface for which to update the cache.
    function updateERC165Cache(address _contract, bytes4 _interfaceId) external;

    /// @notice Checks whether a contract implements an ERC165 interface or not.
    //  If the result is not cached a direct lookup on the contract address is performed.
    //  If the result is not cached or the cached value is out-of-date, the cache MUST be updated manually by calling
    //  'updateERC165Cache' with the contract address.
    /// @param _contract Address of the contract to check.
    /// @param _interfaceId ERC165 interface to check.
    /// @return True if '_contract' implements '_interfaceId', false otherwise.
    function implementsERC165Interface(address _contract, bytes4 _interfaceId) external view returns (bool);

    /// @notice Checks whether a contract implements an ERC165 interface or not without using nor updating the cache.
    /// @param _contract Address of the contract to check.
    /// @param _interfaceId ERC165 interface to check.
    /// @return True if '_contract' implements '_interfaceId', false otherwise.
    function implementsERC165InterfaceNoCache(address _contract, bytes4 _interfaceId) external view returns (bool);
}


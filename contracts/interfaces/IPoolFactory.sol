// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// The standard interface.
interface IPoolFactory {
    function master() external view returns (address);

    function getDeployData() external view returns (bytes memory);

    // Call the function with data to create a pool.
    // For base pool factories, the data is as follows.
    // `(address tokenA, address tokenB) = abi.decode(data, (address, address));`
    function createPool(bytes calldata data) external returns (address pool);
}

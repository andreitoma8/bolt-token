// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockSwap is ERC20 {
    struct TokenInput {
        address token;
        uint256 amount;
    }

    constructor() ERC20("MockSwap", "MSWAP") {}

    function createPool(bytes calldata data) external returns (address pool) {
        return address(this);
    }

    function addLiquidity(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint256 minLiquidity,
        address callback,
        bytes calldata callbackData
    ) external payable returns (uint256 liquidity) {
        IERC20(inputs[0].token).transferFrom(msg.sender, address(this), inputs[0].amount);
        _mint(msg.sender, 100 * 10 ** 18);
    }
}

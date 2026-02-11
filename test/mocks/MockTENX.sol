// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockTENX
/// @notice Minimal ERC20 mock with a public mint function for testing.
contract MockTENX is ERC20 {
    constructor() ERC20("Mock TENX", "TENX") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

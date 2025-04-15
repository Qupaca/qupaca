//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/IERC20.sol";

interface IWrappedAsset is IERC20 {
    function wrap(address user, uint256 amount, address to, bytes calldata externalCallData, uint256 additionalTransferForCall) external payable;
    function unwrapFor(address user, uint256 amount, address to) external;
    function __init__(
        address underlying,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external;
    function unwrapTo(uint256 amount, address to) external;
    function unwrap(uint256 amount) external;
}
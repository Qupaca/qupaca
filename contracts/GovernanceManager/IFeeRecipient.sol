//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IFeeRecipient {
    function takeFee(address token, uint256 amount, uint256 partner, address ref) external payable;
}
//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IReferralManager {
    function addRewards(address ref, address token, uint256 amount) external;
}
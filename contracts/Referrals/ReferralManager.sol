//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GovernanceManager/QupacaOwnable.sol";
import "./IReferralManager.sol";
import "../lib/TransferHelper.sol";


contract ReferralManager is QupacaOwnable, IReferralManager {

    // address to total claimed
    mapping ( address => mapping ( address => uint256 ) ) public totalRewards;

    constructor(address manager_) QupacaOwnable(manager_) {}

    // function to add data to totalRewards
    function addRewards(address ref, address token, uint256 amount) external override {
        require(msg.sender == manager.feeReceiver(), 'Only Fee Receiver');
        unchecked {
            totalRewards[ref][token] += amount;
        }
    }

    // function to view rewards for a list of tokens for a user
    function rewardsFor(address user, address[] calldata tokens) external view returns (uint256[] memory) {
        uint256[] memory rewards = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            rewards[i] = totalRewards[user][tokens[i]];
        }
        return rewards;
    }

}
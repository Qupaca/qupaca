//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IHistoryManager {
    function addData(address user, uint256 GAME_ID, uint256 gameId) external;
}
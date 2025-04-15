//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IUserInfoTracker {
    function wagered(address user, uint256 amount, uint256 GAME_ID, address token, uint256 partnerId) external;
    function createViewer(address token) external returns (address viewer);
    function listAllUsers() external view returns (address[] memory);
    function totalWageredForPartner(uint256 partnerId) external view returns (uint256);
}
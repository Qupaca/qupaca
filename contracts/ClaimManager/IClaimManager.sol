//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IClaimManager {
    function credit(
        uint256 GAME_ID,
        address user
    ) external payable;
    function creditToken(
        address user,
        address token,
        uint256 GAME_ID,
        uint256 amount
    ) external;
}
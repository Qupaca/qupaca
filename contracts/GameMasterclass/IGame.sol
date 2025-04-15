//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IGame {
    /**
        Callback to provide us with randomness
     */
    function fulfillRandomRequest(
        uint256 requestId,
        uint256[] calldata rngList
    ) external;

    function play(address user, address token, uint256 amount, bytes calldata gameData) external payable;
}
//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ITokenHouse {
    function __init__(address _token, address _manager) external;
    function deposit(address to, uint256 amount) external;

    /**
        House has profited from game, call this to send value into the house and emit the correct event for SubGraphs
     */
    function houseProfit(uint256 GAME_ID, uint256 amount) external;

    /**
        Function Games Call to tell the house that a user has won the bet
     */
    function payout(uint256 GAME_ID, address user, uint256 value) external;
    
    /**
        Read function to determine the maximum payout allowed by the house at the current time
     */
    function maxPayout() external view returns (uint256);

    /**
        Randomness has been requested, withdrawals are paused until it is resolved by called `randomRequestResolved()`
     */
    function randomRequested() external;

    /**
        Resolves a random request from chainlink, allowing house users to withdraw
     */
    function randomRequestResolved() external;

    /**
        Withdraws a user's balance from the house
     */
    function withdrawFor(address user, uint256 amount) external returns (uint256);
}
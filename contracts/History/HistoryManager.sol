//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GovernanceManager/QupacaOwnable.sol";
import "./IHistoryManager.sol";

/**
    Purpose of this contract is to track all games played based on time
    Both for users and globally
 */
contract HistoryManager is QupacaOwnable, IHistoryManager {

    // Game structure
    struct Game {
        uint256 GAME_ID;
        uint256 gameId;
        uint256 timestamp;
    }

    // incrementing game nonce
    uint256 public gameNonce;

    // maps a gameNonce to a Game Struct
    mapping ( uint256 => Game ) public games;

    // maps a user to a list of gameIds they have participated in
    mapping ( address => uint256[] ) public gamesForUser;

    constructor(address manager_) QupacaOwnable(manager_) {}
    
    function addData(address user, uint256 GAME_ID, uint256 gameId) external override onlyGame {

        // add info to game nonce
        games[gameNonce] = Game(GAME_ID, gameId, block.timestamp);

        // push to user array
        gamesForUser[user].push(gameNonce);

        // increment game nonce
        unchecked { ++gameNonce; }
    }

    function getNumberOfGamesPlayed(address user) external view returns (uint256) {
        return gamesForUser[user].length;
    }

    function getGameIDsForUser(address user) external view returns (uint256[] memory) {
        return gamesForUser[user];
    }
    
    function getUserData(address user) external view returns (
        uint256[] memory GAME_IDs,
        uint256[] memory gameIds,
        uint256[] memory timestamps
    ) {

        uint len = gamesForUser[user].length;
        GAME_IDs    = new uint256[](len);
        gameIds     = new uint256[](len);
        timestamps  = new uint256[](len);
        
        for (uint i = 0; i < len;) {
            uint256 nonce = gamesForUser[user][i];
            GAME_IDs[i] = games[nonce].GAME_ID;
            gameIds[i] = games[nonce].gameId;
            timestamps[i] = games[nonce].timestamp;
            unchecked { ++i; }
        }
    }

    function getUserDataPaginated(address user, uint start, uint end) external view returns (
        uint256[] memory GAME_IDs,
        uint256[] memory gameIds,
        uint256[] memory timestamps
    ) {

        // constrain end of array
        if (end > gamesForUser[user].length) {
            end = gamesForUser[user].length;
        }

        // get length of array
        uint len = end - start;
        GAME_IDs   = new uint256[](len);
        gameIds    = new uint256[](len);
        timestamps = new uint256[](len);
        
        // loop through array, add data to each index
        for (uint i = start; i < end;) {
            uint256 nonce = gamesForUser[user][i];
            GAME_IDs[i - start]   = games[nonce].GAME_ID;
            gameIds[i - start]    = games[nonce].gameId;
            timestamps[i - start] = games[nonce].timestamp;
            unchecked { ++i; }
        }
    }

    function getMostRecentGamesForUser(address user, uint256 numGames) external view returns (
        uint256[] memory GAME_IDs, 
        uint256[] memory gameIds,
        uint256[] memory timestamps
    ) {

        // get length of games played
        uint256 end = gamesForUser[user].length;

        // if requesting more games than have been played, return all games played
        if (numGames > end) {
            numGames = end;
        }
        uint256 start = end - numGames;

        // instantiate arrays
        GAME_IDs = new uint256[](numGames);
        gameIds  = new uint256[](numGames);
        timestamps = new uint256[](numGames);
        for (uint i = start; i < end;) {
            uint256 nonce = gamesForUser[user][i];
            GAME_IDs[i - start] = games[nonce].GAME_ID;
            gameIds[i - start] = games[nonce].gameId;
            timestamps[i - start] = games[nonce].timestamp;
            unchecked { ++i; }
        }
    }

    function getMostRecentGames(uint256 numGames) external view returns (
        uint256[] memory GAME_IDs, 
        uint256[] memory gameIds,
        uint256[] memory timestamps
    ) {

        // if requesting more games than have been played, return all games played
        if (numGames > gameNonce) {
            numGames = gameNonce;
        }
        uint256 start = gameNonce - numGames;

        // instantiate arrays
        GAME_IDs = new uint256[](numGames);
        gameIds  = new uint256[](numGames);
        timestamps = new uint256[](numGames);
        for (uint i = start; i < gameNonce;) {
            GAME_IDs[i - start] = games[i].GAME_ID;
            gameIds[i - start] = games[i].gameId;
            timestamps[i - start] = games[i].timestamp;
            unchecked { ++i; }
        }
    }

    function getGameData(uint256[] calldata ids) external view returns (
        uint256[] memory GAME_IDs,
        uint256[] memory gameIds,
        uint256[] memory timestamps
    ) {

        uint len = ids.length;
        GAME_IDs    = new uint256[](len);
        gameIds     = new uint256[](len);
        timestamps  = new uint256[](len);

        for (uint i = 0; i < len;) {
            uint id = ids[i];
            GAME_IDs[i] = games[id].GAME_ID;
            gameIds[i] = games[id].gameId;
            timestamps[i] = games[id].timestamp;
            unchecked { ++i; }
        }
    }
}
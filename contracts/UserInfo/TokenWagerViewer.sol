//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/IERC20.sol";
import "../lib/Cloneable.sol";
import "./ITokenWagerViewer.sol";

contract TokenWagerViewerData {

    // Token
    address public token;

    // Total `tokens` wagered
    uint256 internal totalWagered;

    // Game Data Structure
    struct GameData {
        uint256 totalWagered;
        uint256 numGamesPlayed;
    }

    // User Info Structure
    struct UserInfo {
        uint256 totalWagered;
        mapping ( uint256 => GameData ) gameData;
    }

    // User Info Mapping
    mapping ( address => UserInfo ) internal userInfo;

    // wagered for partner
    mapping ( uint256 => uint256 ) public totalWageredForPartner;

    // factory
    address internal factory;

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

}

contract TokenWagerViewer is TokenWagerViewerData, Cloneable, ITokenWagerViewer {

    function __init__(address token_) external override {
        require(token == address(0), "Already initialized");
        require(token_ != address(0), "Token address cannot be 0");
        token = token_;
        factory = msg.sender;
        emit Transfer(address(0), address(0), 0);
    }

    function name() external view returns (string memory) {
        return string.concat(IERC20(token).name(), 'Wager');
    }

    function symbol() external view returns (string memory) {
        return string.concat(IERC20(token).symbol(), 'w');
    }

    function decimals() external view returns (uint8) {
        return IERC20(token).decimals();
    }

    function balanceOf(address user) external view returns (uint256) {
        return userInfo[user].totalWagered;
    }

    function totalSupply() external view returns (uint256) {
        return totalWagered;
    }

    function wagered(address user, uint256 amount, uint256 GAME_ID, uint256 partnerId) external override {
        require(msg.sender == factory, "Unauthorized");
        
        // increment total native Spent
        unchecked {
            
            // increment values by the amount of native spent
            totalWagered += amount;
            userInfo[user].totalWagered += amount;
            totalWageredForPartner[partnerId] += amount;
            userInfo[user].gameData[GAME_ID].totalWagered += amount;

            // increment total wagers placed
            ++userInfo[user].gameData[GAME_ID].numGamesPlayed;
        }

        // emit events for tracking
        emit Transfer(address(0), user, amount);
    }

    function getGameData(address user, uint256 GAME_ID) external view override returns (uint256 totalWagered, uint256 numGamesPlayed) {
        return (userInfo[user].gameData[GAME_ID].totalWagered, userInfo[user].gameData[GAME_ID].numGamesPlayed);
    }

    function batchGameData(address user, uint256[] calldata GAME_IDs) external view override returns (uint256[] memory totalWagered, uint256[] memory numGamesPlayed) {
        uint256 len = GAME_IDs.length;
        totalWagered = new uint256[](len);
        numGamesPlayed = new uint256[](len);
        for (uint i = 0; i < len;) {
            totalWagered[i] = userInfo[user].gameData[GAME_IDs[i]].totalWagered;
            numGamesPlayed[i] = userInfo[user].gameData[GAME_IDs[i]].numGamesPlayed;
            unchecked { ++i; }
        }
    }

    function getListOfTotalWageredByProject(uint256[] calldata projects) external view override returns (uint256[] memory) {
        uint256 len = projects.length;
        uint256[] memory list = new uint256[](len);
        for (uint i = 0; i < len;) {
            list[i] = totalWageredForPartner[projects[i]];
            unchecked { ++i; }
        }
        return list;
    }

    function getListOfTotalWagered(address[] calldata users) external view override returns (uint256[] memory) {
        uint256 len = users.length;
        uint256[] memory list = new uint256[](len);
        for (uint i = 0; i < len;) {
            list[i] = userInfo[users[i]].totalWagered;
            unchecked { ++i; }
        }
        return list;
    }

    function getListOfTotalWageredPaginated(address[] memory allUsers) external view override returns (uint256[] memory) {
        uint256[] memory list = new uint256[](allUsers.length);
        for (uint256 i = 0; i < allUsers.length;) {
            list[i] = userInfo[allUsers[i]].totalWagered;
            unchecked { ++i; }
        }
        return list;
    }
}
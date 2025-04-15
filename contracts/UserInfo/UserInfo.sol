//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GovernanceManager/QupacaOwnable.sol";
import "./IUserInfoTracker.sol";
import "./ITokenWagerViewer.sol";
import "../lib/Cloneable.sol";
import "../lib/IERC20.sol";

contract UserInfo is IUserInfoTracker, QupacaOwnable {

    // Name + Symbol for wallet support
    string public name;
    string public symbol;

    // Token Info
    address[] public allTokenViewers;
    mapping ( address => address ) public tokenToViewer;
    address public viewerImplementation;

    // Game Data Structure
    struct GameData {
        uint256 totalWagered;
        uint256 numGamesPlayed;
    }

    // User Info Structure
    struct UserInfoStruct {
        uint256 totalWagered;
        mapping ( uint256 => GameData ) gameData;
        bool exists;
    }

    // Mapping From User To Total WETH Wagered
    mapping ( address => UserInfoStruct ) private userInfo;

    // List Of All Unique Users
    address[] public allUsers;

    // Total Wagers Placed
    uint256 public totalWagersPlaced;

    // Total Wagered
    uint256 public totalWagered;

    // Total Wagered For Partner
    mapping ( uint256 => uint256 ) public override totalWageredForPartner;

    // Old UserInfo to pull data from
    address private immutable oldUserInfo;

    // Transfer Event
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(
        string memory name_,
        string memory symbol_,
        address _viewerImp,
        address oldUserInfo_,
        address manager_
    ) QupacaOwnable(manager_) {
        name = name_;
        symbol = symbol_;
        viewerImplementation = _viewerImp;
        oldUserInfo = oldUserInfo_;
    }

    function balanceOf(address user) external view returns (uint256) {
        return userInfo[user].totalWagered;
    }

    function totalSupply() external view returns (uint256) {
        return totalWagered;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function setViewerImplementation(address implementation) external onlyOwner {
        viewerImplementation = implementation;
    }

    function initOldUserInfo() external onlyOwner {
        require(oldUserInfo != address(0) && allUsers.length == 0, 'Already Init');

        address[] memory users = IUserInfoTracker(oldUserInfo).listAllUsers();
        uint len = users.length;
        for (uint i = 0; i < len;) {
            address user_ = users[i];
            uint bal = IERC20(oldUserInfo).balanceOf(user_);
            userInfo[user_].totalWagered += bal;
            allUsers.push(user_);
            emit Transfer(address(0), user_, bal);
            unchecked { ++i; }
        }
        totalWagered = IERC20(oldUserInfo).totalSupply();
        for (uint i = 0; i < 25;) {
            totalWageredForPartner[i] = IUserInfoTracker(oldUserInfo).totalWageredForPartner(i);
            unchecked { ++i; }
        }
    }

    function createViewer(address token) external override returns (address viewer) {
        require(
            msg.sender == manager.projectTokens(),
            "Unauthorized"
        );
        return _create(token);
    }

    function wagered(address user, uint256 amount, uint256 GAME_ID, address token, uint256 partnerId) external override onlyGame {

        // add to list if new user
        if (userInfo[user].exists == false) {
            allUsers.push(user);
            userInfo[user].exists = true;
        }

        // increment total wagers placed
        unchecked {
            ++totalWagersPlaced;
        }

        if (token != address(0)) {

            // check if viewer exists
            address viewer = tokenToViewer[token];
            require(viewer != address(0), "Viewer does not exist");
            
            // pass through to token viewer
            ITokenWagerViewer(viewer).wagered(user, amount, GAME_ID, partnerId);
        
        } else {

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
    }

    function _create(address token) internal returns (address newViewer) {
        
        // create clone
        newViewer = Cloneable(viewerImplementation).clone();

        // push to array and add to mapping
        allTokenViewers.push(newViewer);
        tokenToViewer[token] = newViewer;

        // initialize clone
        ITokenWagerViewer(newViewer).__init__(token);
    }

    function listAllUsers() external view override returns (address[] memory) {
        return allUsers;
    }

    function totalUsers() external view returns (uint256) {
        return allUsers.length;
    }

    function totalNativeWagered(address user) external view returns (uint256) {
        return userInfo[user].totalWagered;
    }

    function getGameData(address user, uint256 GAME_ID) external view returns (uint256 _totalWagered, uint256 numGamesPlayed) {
        return (userInfo[user].gameData[GAME_ID].totalWagered, userInfo[user].gameData[GAME_ID].numGamesPlayed);
    }

    function batchGameData(address user, uint256[] calldata GAME_IDs) external view returns (uint256[] memory _totalWagered, uint256[] memory numGamesPlayed) {
        uint256 len = GAME_IDs.length;
        _totalWagered = new uint256[](len);
        numGamesPlayed = new uint256[](len);
        for (uint i = 0; i < len;) {
            _totalWagered[i] = userInfo[user].gameData[GAME_IDs[i]].totalWagered;
            numGamesPlayed[i] = userInfo[user].gameData[GAME_IDs[i]].numGamesPlayed;
            unchecked { ++i; }
        }
    }

    function getListOfTotalWageredByProject(uint256[] calldata projects) external view returns (uint256[] memory) {
        uint256 len = projects.length;
        uint256[] memory list = new uint256[](len);
        for (uint i = 0; i < len;) {
            list[i] = totalWageredForPartner[projects[i]];
            unchecked { ++i; }
        }
        return list;
    }

    function getListOfTotalWagered(address[] calldata users) external view returns (uint256[] memory) {
        uint256 len = users.length;
        uint256[] memory list = new uint256[](len);
        for (uint i = 0; i < len;) {
            list[i] = userInfo[users[i]].totalWagered;
            unchecked { ++i; }
        }
        return list;
    }

    function getListOfTotalWageredPaginated(uint256 startIndex, uint256 endIndex) external view returns (uint256[] memory) {
        if (endIndex > allUsers.length) {
            endIndex = allUsers.length;
        }
        uint256[] memory list = new uint256[](endIndex - startIndex);
        uint256 count;
        for (uint256 i = startIndex; i < endIndex;) {
            list[count] = userInfo[allUsers[i]].totalWagered;
            unchecked { ++i; ++count; }
        }
        return list;
    }

    function paginateAllUsers(uint256 startIndex, uint256 endIndex) public view returns (address[] memory) {
        if (endIndex > allUsers.length) {
            endIndex = allUsers.length;
        }
        address[] memory list = new address[](endIndex - startIndex);
        uint256 count;
        for (uint256 i = startIndex; i < endIndex;) {
            list[count] = allUsers[i];
            unchecked { ++i; ++count; }
        }
        return list;
    }



    // Token Calls
    function getTokenTotalWagered(address token) external view returns (uint256) {
        return IERC20(tokenToViewer[token]).totalSupply();
    }

    function getTokenTotalWageredForUser(address token, address user) external view returns (uint256) {
        return IERC20(tokenToViewer[token]).balanceOf(user);
    }

    function getGameDataToken(address token, address user, uint256 GAME_ID) external view returns (uint256 _totalWagered, uint256 numGamesPlayed) {
        return ITokenWagerViewer(tokenToViewer[token]).getGameData(user, GAME_ID);
    }

    function batchGameDataToken(address token, address user, uint256[] calldata GAME_IDs) external view returns (uint256[] memory _totalWagered, uint256[] memory numGamesPlayed) {
        return ITokenWagerViewer(tokenToViewer[token]).batchGameData(user, GAME_IDs);
    }

    function getListOfTotalWageredByProjectToken(address token, uint256[] calldata projects) external view returns (uint256[] memory) {
        return ITokenWagerViewer(tokenToViewer[token]).getListOfTotalWageredByProject(projects);
    }

    function getListOfTotalWageredToken(address token, address[] calldata users) external view returns (uint256[] memory) {
        return ITokenWagerViewer(tokenToViewer[token]).getListOfTotalWagered(users);
    }

    function getListOfTotalWageredPaginatedToken(address token, uint256 startIndex, uint256 endIndex) external view returns (uint256[] memory) {
        return ITokenWagerViewer(tokenToViewer[token]).getListOfTotalWageredPaginated(paginateAllUsers(startIndex, endIndex));
    }

}
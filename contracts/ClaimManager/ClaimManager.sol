//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GovernanceManager/QupacaOwnable.sol";
import "./IClaimManager.sol";
import "../lib/TransferHelper.sol";
import "../lib/Address.sol";
import "../GameMasterclass/IGame.sol";
import "../House/IHouseManager.sol";

contract ClaimManager is IClaimManager {

    struct UserInfo {
        uint256 pendingClaim;
        uint256 totalClaimed;
        mapping ( uint256 => mapping ( address => uint256 ) ) totalWonByGame;
    }

    mapping ( address => UserInfo ) private userInfo;
    
    bool public paused = false;

        // Governance Manager
    IGovernanceManager public manager;

    modifier onlyPauser() {
        require(
            msg.sender == manager.pauseManager() || msg.sender == manager.owner(),
            'Only Pauser'
        );
        _;
    }

    modifier onlyOwner() {
        require(
            msg.sender == manager.owner(),
            'Only Owner'
        );
        _;
    }

    modifier onlyCreditor() {
        require(
            manager.isGame(msg.sender) || 
            msg.sender == manager.house() ||
            IHouseManager(IProjectTokensManager(manager.projectTokens()).houseManager()).isHouse(msg.sender),
            'UnAuthorized'
        );
        _;
    }

    constructor(address manager_) {
        manager = IGovernanceManager(manager_);
    }

    function pause() external onlyPauser() {
        paused = true;
    }

    function resume() external onlyOwner {
        paused = false;
    }

    function withdraw() external onlyOwner {
        TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    function withdraw(uint256 amount) external onlyOwner {
        TransferHelper.safeTransferETH(msg.sender, amount);
    }
    

    function credit(
        uint256 GAME_ID,
        address user
    ) external payable override onlyCreditor {
        
        unchecked {
            userInfo[user].pendingClaim += msg.value;
            userInfo[user].totalWonByGame[GAME_ID][address(0)] += msg.value;
        }
    }

    function creditToken(
        address user,
        address token,
        uint256 GAME_ID,
        uint256 amount
    ) external override onlyCreditor {
        unchecked {
            userInfo[user].totalWonByGame[GAME_ID][token] += amount;
        }
    }

    function claimFor(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length;) {
            _claim(users[i]);
            unchecked { ++i; }
        }
    }

    function claim() external {
        _claim(msg.sender);
    }

    function claimAndCall(address to, uint256 amount, bytes calldata data) external payable {
        require(
            manager.isGame(to),
            'Can Only Call Games'
        );

        // fetch remaining amount to claim
        uint256 pending = userInfo[msg.sender].pendingClaim;
        require(pending > 0, 'Zero Claimable Amount');
        if (amount > pending) {
            amount = pending; // fixes front end round off issues
        }

        // add to user's total claimed
        unchecked {
            userInfo[msg.sender].totalClaimed += amount;
            userInfo[msg.sender].pendingClaim -= amount;
        }

        // if pending claim exists, send the rest of it
        if (userInfo[msg.sender].pendingClaim > 0) {
            _claim(msg.sender);
        }

        // call game
        IGame(to).play{value: ( amount + msg.value )}(msg.sender, address(0), 0, data);
    }

    function _claim(address user) internal {

        require(!paused, 'Claim Manager Paused');

        // fetch remaining amount to claim
        uint256 pending = userInfo[user].pendingClaim;
        if (pending == 0) {
            return;
        }

        // add to user's total claimed
        unchecked {
            userInfo[user].totalClaimed += pending;
        }

        // delete users pendingClaim
        delete userInfo[user].pendingClaim;

        // send reward to user
        TransferHelper.safeTransferETH(user, pending);
    }

    function getTotalWonByGame(address user, uint256 GAME_ID, address token) external view returns (uint256) {
        return userInfo[user].totalWonByGame[GAME_ID][token];
    }

    function pendingClaim(address user) external view returns (uint256) {
        return userInfo[user].pendingClaim;
    }

    function totalWonForToken(address user, address token, uint256[] calldata GAME_IDs) external view returns (uint256[] memory) {
        uint256[] memory wonByGames = new uint256[](GAME_IDs.length);
        for (uint i = 0; i < GAME_IDs.length; i++) {
            wonByGames[i] = userInfo[user].totalWonByGame[GAME_IDs[i]][token];
        }

        return wonByGames;
    }
}
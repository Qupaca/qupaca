//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/TransferHelper.sol";
import "../GovernanceManager/QupacaOwnable.sol";
import "./IGame.sol";
import "../UserTracker/IUserInfoTracker.sol";
import "../House/IHouseManager.sol";
import "../House/IHouse.sol";
import "../House/ITokenHouse.sol";
import "../lib/IERC20.sol";
import "../ClaimManager/IClaimManager.sol";
import "../History/IHistoryManager.sol";
import "../ProjectTokens/IWrappedAssetManager.sol";

/**
    Game Master Class, any inheriting game must pass the necessary fields into the constructor
 */
contract GameMasterclass is QupacaOwnable, IGame {

    // GAME ID
    uint256 public immutable GAME_ID;

    // History Manager
    IHistoryManager public immutable history;

    /** Game Is Either Paused Or Unpaused */
    bool public paused = false;

    /** List of all used game ids */
    uint256[] public usedGameIds;
    mapping ( uint256 => bool ) public isUsedGameId;

    // Reentrancy Guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    modifier nonReentrant() {
        require(_status != _ENTERED, "Reentrancy Guard call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    struct PayoutInfo {
        address token;
        address player;
        uint256 totalToPayout;
        uint256 amountForHouse;
        uint8 unwrapType;
    }

    /**
        Builds The Necessary Components Of Any Game
     */
    constructor(
        uint256 GAME_ID_,
        address history_,
        address manager_
    ) QupacaOwnable(manager_) {

        // set other variables
        GAME_ID = GAME_ID_;
        history = IHistoryManager(history_);
    }

    //////////////////////////////////////
    ///////    OWNER FUNCTIONS    ////////
    //////////////////////////////////////

    function pause() external onlyPauser() {
        paused = true;
    }

    function resume() external onlyOwner {
        paused = false;
    }

    function withdrawETH(address to, uint256 amount) external onlyOwner {
        (bool s,) = payable(to).call{value: amount}("");
        require(s);
    }

    function withdrawToken(address token, uint amount) external onlyOwner {
        TransferHelper.safeTransfer(token, msg.sender, amount);
    }

    function _registerBet(address user, uint256 amount, address token, uint256 partnerId) internal {
        IUserInfoTracker(manager.userInfoTracker()).wagered(user, amount, GAME_ID, token, partnerId);
    }

    function _processFee(address token, uint256 feeAmount, uint256 partnerId, address ref) internal {
        if (token == address(0)) {
            IFeeRecipient(manager.feeReceiver()).takeFee{value: feeAmount}(
                token, 0, partnerId, ref
            );
        } else {
            TransferHelper.safeTransfer(token, manager.feeReceiver(), feeAmount);
            IFeeRecipient(manager.feeReceiver()).takeFee{value: 0}(
                token, feeAmount, partnerId, ref
            );
        }
    }

    function fulfillRandomRequest(uint256 requestId, uint256[] calldata rngList) external virtual {}

    function play(address player, address token, uint256 amount, bytes calldata gameData) external payable override validGameToken(token) validatePlayer(player) nonReentrant {
        require(
            !paused,
            'Paused'
        );

        // transfer in asset
        if (token != address(0)) {

            // Transfer in, noting amount received
            uint256 before = IERC20(token).balanceOf(address(this));
            TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);
            uint256 After = IERC20(token).balanceOf(address(this));
            require(
                After > before,
                'Invalid Transfer'
            );

            // get amount received
            uint256 received = After - before;

            // play game
            _playGame(player, token, received, gameData);
        } else {

            // play game
            _playGame(player, token, msg.value, gameData);
        }
    }

    // NEW Play type function that allows the user to specify whether or not they want to claim their winnings or have them auto sent
    // function play(address player, address token, uint256 amount, bool autoClaim, bytes calldata gameData) external payable override validGameToken(token) validatePlayer(player) {
    //     require(
    //         !paused,
    //         'Paused'
    //     );

    //     if (autoClaim) {
    //         require(
    //             tx.origin == player,
    //             'Auto Claim Only For Self, No Contracts Allowed'
    //         );
    //         require(
    //             player.code.length == 0,
    //             'Player is smart contract'
    //         );
    //         // NOTE: Check AGAIN if player.code.length == 0 in fulfillRandomWords -> if it is a contract, it would no longer be under construction at this time.
    //         willAutoClaim[gameId] = true; // map to gameId to fetch in fulfillRandomWords
    //     }

    //     // transfer in asset
    //     if (token != address(0)) {

    //         // Transfer in, noting amount received
    //         uint256 before = IERC20(token).balanceOf(address(this));
    //         TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);
    //         uint256 After = IERC20(token).balanceOf(address(this));
    //         require(
    //             After > before,
    //             'Invalid Transfer'
    //         );

    //         // get amount received
    //         uint256 received = After - before;

    //         // play game
    //         _playGame(player, token, received, gameData);
    //     } else {

    //         // play game
    //         _playGame(player, token, msg.value, gameData);
    //     }
    // }

    function _playGame(address player, address token, uint256 amount, bytes calldata gameData) internal virtual {}

    function _handlePayout(PayoutInfo memory info) internal {
        if (info.totalToPayout > 0) {
            // there is a payout, we won something

            if (info.totalToPayout >= info.amountForHouse) {
                // the user has won more than we are giving to the house
                // this means we need to send them (to claim manager) amountForHouse directly
                // and only request that the house `payout` the difference!

                // determine if we're using ETH or tokens
                if (info.token == address(0)) {

                    // add to user's claim manager the amount for the house
                    IClaimManager(manager.claimManager()).credit{value: info.amountForHouse}(
                        GAME_ID,
                        info.player
                    );

                    // get the difference
                    uint256 remaining = info.totalToPayout - info.amountForHouse;
                    if (remaining > 0) {
                        // payout the rest from the house
                        IHouse(manager.house()).payout(GAME_ID, info.player, remaining);
                    }

                } else {

                    // send the house the amount
                    TransferHelper.safeTransfer(info.token, info.player, info.amountForHouse);

                    // credit the user
                    IClaimManager(manager.claimManager()).creditToken(
                        info.player,
                        info.token,
                        GAME_ID,
                        info.amountForHouse
                    );

                    // get the difference
                    uint256 remaining = info.totalToPayout - info.amountForHouse;
                    if (remaining > 0) {

                        // determine the house for this token
                        address _house = getHouse(info.token);

                        // payout the rest from the house
                        ITokenHouse(_house).payout(GAME_ID, info.player, remaining);
                    }

                    if(info.unwrapType == 1) {
                        // unwrap the token
                        IWrappedAssetManager(IProjectTokensManager(manager.projectTokens()).wrappedAssetManager()).unwrapTokenForUser(info.token, info.player);
                    }
                }

            } else {
                // the user has won less than we are giving to the house
                // pay them out directly in full, send whatever is left over to the house

                if (info.token == address(0)) {

                    // add to user's claim manager the amount for the house
                    IClaimManager(manager.claimManager()).credit{value: info.totalToPayout}(
                        GAME_ID,
                        info.player
                    );

                    // calculate remaining left for the house
                    uint256 remaining = info.amountForHouse - info.totalToPayout;

                    // send the remaining to the house
                    IHouse(manager.house()).houseProfit{value: remaining }(GAME_ID);

                } else {

                    // send the house the amount
                    TransferHelper.safeTransfer(info.token, info.player, info.totalToPayout);

                    // credit the user
                    IClaimManager(manager.claimManager()).creditToken(
                        info.player,
                        info.token,
                        GAME_ID,
                        info.totalToPayout
                    );

                    // get the difference
                    uint256 remaining = info.amountForHouse - info.totalToPayout;

                    // determine the house for this token
                    address _house = getHouse(info.token);

                    // send the house the amount
                    TransferHelper.safeTransfer(info.token, _house, remaining);

                    // payout the rest from the house
                    ITokenHouse(_house).houseProfit(GAME_ID, remaining);
                    
                    if(info.unwrapType == 1) {
                        // unwrap the token
                        IWrappedAssetManager(IProjectTokensManager(manager.projectTokens()).wrappedAssetManager()).unwrapTokenForUser(info.token, info.player);
                    }
                }
            }
        
        } else {

            // we won nothing, send the house everything
            if (info.token == address(0)) {
                IHouse(manager.house()).houseProfit{value: info.amountForHouse }(GAME_ID);
            } else {

                // determine the house for this token
                address _house = getHouse(info.token);

                // send the house the amount
                TransferHelper.safeTransfer(info.token, _house, info.amountForHouse);

                // log house profit
                ITokenHouse(_house).houseProfit(GAME_ID, info.amountForHouse);
            }
        }
    }

    /// @dev logs the gameId in the used list and adds game to player's history
    function _registerGameId(address player, uint256 gameId) internal {

        // set history data
        history.addData(player, GAME_ID, gameId);

        // add to list of used game ids
        usedGameIds.push(gameId);
        isUsedGameId[gameId] = true;
    }

    function getHouse(address token) public view returns (address) {
        if (token == address(0)) {
            return manager.house();
        }
        return IHouseManager(IProjectTokensManager(manager.projectTokens()).houseManager()).houseFor(token);
    }

    function isValidGameId(uint256 gameId) public view returns (bool) {
        return isUsedGameId[gameId] == false && gameId > 0;
    }

    function batchCallIsUsedGameId(uint256[] calldata gameIds) external view returns (bool[] memory isUsed) {
        uint len = gameIds.length;
        isUsed = new bool[](len);
        for (uint i = 0; i < len;) {
            isUsed[i] = isUsedGameId[gameIds[i]];
            unchecked { ++i; }
        }
    }

    function paginateUsedGameIDs(uint256 start, uint256 end) external view returns (uint256[] memory) {
        uint count = 0;
        uint256[] memory ids = new uint256[](end - start);
        for (uint i = start; i < end;) {
            ids[count] = usedGameIds[i];
            unchecked { ++i; ++count; }
        }
        return ids;
    }

    function numUsedGameIDs() external view returns (uint256) {
        return usedGameIds.length;
    }
}
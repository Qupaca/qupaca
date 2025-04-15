//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ITokenWagerViewer {

    function __init__(address token_) external;

    function wagered(address user, uint256 amount, uint256 GAME_ID, uint256 partnerId) external;

    function getGameData(address user, uint256 GAME_ID) external view returns (uint256 totalWagered, uint256 numGamesPlayed);

    function batchGameData(address user, uint256[] calldata GAME_IDs) external view returns (uint256[] memory totalWagered, uint256[] memory numGamesPlayed);

    function getListOfTotalWageredByProject(uint256[] calldata projects) external view returns (uint256[] memory);

    function getListOfTotalWagered(address[] calldata users) external view returns (uint256[] memory);

    function getListOfTotalWageredPaginated(address[] memory allUsers) external view returns (uint256[] memory);
    
}
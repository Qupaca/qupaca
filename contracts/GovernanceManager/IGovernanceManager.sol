//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IGovernanceManager {
    function RNG() external view returns (address);
    function owner() external view returns (address);
    function pauseManager() external view returns (address);
    function supraClientAddress() external view returns (address);
    function referralManager() external view returns (address);
    function projectTokens() external view returns (address);
    function feeReceiver() external view returns (address);
    function claimManager() external view returns (address);
    function house() external view returns (address);
    function isGame(address game) external view returns (bool);
    function userInfoTracker() external view returns (address);
}
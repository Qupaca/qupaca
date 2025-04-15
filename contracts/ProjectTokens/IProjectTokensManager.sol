//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IProjectTokensManager {
    function isValidPartner(uint256 partnerNonce) external view returns (bool);
    function getFundReceiver(uint256 partner) external view returns (address);
    function isListedToken(address token) external view returns (bool);
    function getWrapper(address token) external view returns (address);
    function getHouse(address token) external view returns (address);
    function getViewer(address token) external view returns (address);
    function isWrappedAsset(address wrapper) external view returns (bool);
    function canPlayForOthers(address addr) external view returns (bool);
    function wrappedAssetManager() external view returns (address);
    function houseManager() external view returns (address);
}
//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IWrappedAssetManager {
    function isGame(address game) external view returns (bool);
    function isOwner(address user) external view returns (bool);
    function isWrappedAsset(address asset) external view returns (bool);
    function getWrapper(address token) external view returns (address);
    function createWrapper(address token) external returns (address);
    function getUnderlyingAsset(address wrapper) external view returns (address);
    function wrap(address token, uint256 amount, address contractToCall, bytes calldata externalCallData, uint256 additionalTransferForCall) external payable;
    function isGameOrHouse(address game) external view returns (bool);
    function isHouse(address house) external view returns (bool);
    function typeOfRecipient(address recipient) external view returns (uint8);
    function unwrapWrappedToken(address wrappedToken, uint256 amount) external;
    function unwrapTokenForUser(address token, address user) external;
}
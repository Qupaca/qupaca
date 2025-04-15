//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IHouseManager {

    function isHouse(address house) external view returns (bool);
    function houseFor(address token) external view returns (address);
    function createHouse(address token) external returns (address house);
    function withdrawFor(address user, address token, uint256 amount) external;
}
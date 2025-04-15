//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GovernanceManager/QupacaOwnable.sol";
import "../lib/TransferHelper.sol";
import "../lib/IERC20.sol";
import "./ITokenHouse.sol";
import "./IHouseManager.sol";
import "../lib/Cloneable.sol";
import "../ProjectTokens/IProjectTokensManager.sol";

contract HouseManager is QupacaOwnable, IHouseManager {

    // Master Implementation Contract
    address public houseImplementation;

    // List of all Houses
    address[] public allHouses;

    // Mapping of Token to House Address
    mapping ( address => address ) public override houseFor;

    // Mapping of a house to the Token it was created for
    mapping ( address => address ) public houseToToken;

    // Event for when a new house is created
    event HouseCreated(address token, address house);

    constructor(
        address houseImplementation_,
        address manager_
    ) QupacaOwnable(manager_) {
        houseImplementation = houseImplementation_;
    }

    function setImplementation(address newImplementation) external onlyOwner {
        houseImplementation = newImplementation;
    }

    function isHouse(address house) external view returns (bool) {
        return houseToToken[house] != address(0);
    }

    function createHouse(address token) external override returns (address house) {

        // ensure `token` is a valid ERC20 token
        require(
            token != address(0) &&
            bytes(IERC20(token).symbol()).length > 0,
            'Invalid Token'
        );

        // ensure only projectTokens is able to call
        require(
            msg.sender == manager.projectTokens(),
            'Unauthorized'
        );

        // create house for `token`
        house = _createHouse(token);
    }

    function _createHouse(address token) internal returns (address) {
        require(
            houseFor[token] == address(0),
            'House Already Exists'
        );

        // Create the House
        address house = Cloneable(houseImplementation).clone();

        // Initialize the House
        ITokenHouse(house).__init__(token, address(manager));

        // Set the House
        houseFor[token] = house;
        houseToToken[house] = token;

        // Add to list of all houses
        allHouses.push(house);

        // Emit Event
        emit HouseCreated(token, house);

        return house;
    }

    function getHousesForTokens(address[] calldata tokens) external view returns (address[] memory) {
        address[] memory result = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            result[i] = houseFor[tokens[i]];
        }
        return result;
    }

    function withdrawFor(address user, address token, uint256 amount) external {
        address wrappedAssetManager = IProjectTokensManager(manager.projectTokens()).wrappedAssetManager();
        require(msg.sender == wrappedAssetManager, "Unauthorized");

        address house = houseFor[token];
        require(house != address(0), "House not found");

        ITokenHouse(house).withdrawFor(user, amount);
    }
}
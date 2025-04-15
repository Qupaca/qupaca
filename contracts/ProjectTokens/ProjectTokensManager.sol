//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GovernanceManager/QupacaOwnable.sol";
import "../lib/TransferHelper.sol";
import "./IWrappedAssetManager.sol";
import "../UserTracker/IUserInfoTracker.sol";
import "../House/IHouseManager.sol";

contract ProjectTokensManager is QupacaOwnable, IProjectTokensManager {

    // listed token data set
    struct ListedPartner {
        bool isApproved;
        string name;
        address fundReceiver;
        address token;
    }

    // Token Assets
    struct TokenAssets {
        address wrapper;
        address house;
        address viewer;
        uint256 index;
    }

    // maps a token to its generated assets
    mapping ( address => TokenAssets ) public tokenAssets;

    // list of all generated tokens
    address[] public allTokens;

    // list of all partners
    mapping ( uint256 => ListedPartner ) public partnerInfo;

    // maps an address to whether or not they can create tokens
    mapping ( address => bool ) public canCreate;

    // managers
    address public override wrappedAssetManager;
    address public override houseManager;

    // events
    event NewTokenAssetListed(address token, address wrapper, address house, address viewer);

    constructor(address wrappedAssetManager_, address houseManager_, address manager_) QupacaOwnable(manager_) {
        wrappedAssetManager = wrappedAssetManager_;
        houseManager = houseManager_;
    }

    function withdrawTokens(address token, address to, uint256 amount) external onlyOwner {
        TransferHelper.safeTransfer(token, to, amount);
    }

    function withdrawETH(address to, uint256 amount) external onlyOwner {
        TransferHelper.safeTransferETH(to, amount);
    }

    function setCanCreate(address user, bool canCreate_) external onlyOwner {
        canCreate[user] = canCreate_;
    }

    function setManagers(address wrappedAssetManager_, address houseManager_) external onlyOwner {
        wrappedAssetManager = wrappedAssetManager_;
        houseManager = houseManager_;
    }

    function removeTokenSupport(address token, bool deleteAssetsFromMemory) external onlyOwner {
        require(tokenAssets[token].wrapper != address(0), "Token not supported");
        uint256 index = tokenAssets[token].index;
        uint256 len = allTokens.length;
        address lastToken = allTokens[len - 1];
        allTokens[index] = lastToken;
        tokenAssets[lastToken].index = index;
        allTokens.pop();
        if (deleteAssetsFromMemory) {
            delete tokenAssets[token];
        }
    }

    function hardOverrideSetTokenAssets(
        address token,
        address wrapper,
        address house,
        address viewer,
        bool addToList
    ) external onlyOwner {
        tokenAssets[token].wrapper = wrapper;
        tokenAssets[token].house = house;
        tokenAssets[token].viewer = viewer;
        if (addToList) {
            tokenAssets[token].index = allTokens.length;
            allTokens.push(token);
        }       
    }

    function createTokenContracts(
        address token
    ) external returns (address wrapper, address house, address viewer) {
        require(canCreate[msg.sender] || canCreate[address(0)] || msg.sender == manager.owner(), "Unauthorized");
        require(tokenAssets[token].wrapper == address(0), "Already created");

        // generate all assets
        wrapper = IWrappedAssetManager(wrappedAssetManager).createWrapper(token);
        house = IHouseManager(houseManager).createHouse(wrapper);
        viewer = IUserInfoTracker(manager.userInfoTracker()).createViewer(wrapper);
        require(wrapper != address(0) && house != address(0) && viewer != address(0), "Failed to create assets");

        // assign assets
        tokenAssets[token].wrapper = wrapper;
        tokenAssets[token].house = house;
        tokenAssets[token].viewer = viewer;
        tokenAssets[token].index = allTokens.length;

        // push to token list
        allTokens.push(token);

        // emit event
        emit NewTokenAssetListed(token, wrapper, house, viewer);
    }

    function listPartner(
        uint256 partnerNonce,
        address fundReceiver,
        string calldata name,
        address token
    ) external onlyOwner {
        require(partnerInfo[partnerNonce].isApproved == false, "Already listed");
        require(partnerNonce > 0, "Invalid partner nonce");

        // set data
        partnerInfo[partnerNonce].isApproved = true;
        partnerInfo[partnerNonce].name = name;
        partnerInfo[partnerNonce].fundReceiver = fundReceiver;
        partnerInfo[partnerNonce].token = token;
    }

    function removeListedPartner(uint256 partnerNonce_) external onlyOwner {
        delete partnerInfo[partnerNonce_].isApproved;
    }

    function setPartnerData(
        uint256 partnerNonce_,
        address fundReceiver,
        string calldata name,
        address token
    ) external onlyOwner {
        partnerInfo[partnerNonce_].name = name;
        partnerInfo[partnerNonce_].fundReceiver = fundReceiver;
        partnerInfo[partnerNonce_].token = token;
    }

    function isValidPartner(uint256 partnerNonce_) external view override returns (bool) {
        return partnerInfo[partnerNonce_].isApproved || partnerNonce_ == 0;
    }

    function getFundReceiver(uint256 partner) external view override returns (address) {
        return partnerInfo[partner].fundReceiver;
    }

    function canPlayForOthers(address addr) external view override returns (bool) {
        return addr == manager.claimManager() || IWrappedAssetManager(wrappedAssetManager).isWrappedAsset(addr);
    }

    function fetchAllPartnerInfo(uint start, uint end) external view returns (
        uint256[] memory partnerIds,
        address[] memory fundReceivers,
        string[] memory names
    ) {

        uint256 len = 0;
        for (uint i = start; i < end;) {
            if (partnerInfo[i].isApproved) {
                unchecked { ++len; }
            }
            unchecked { ++i; }
        }

        uint count = 0;
        partnerIds = new uint256[](len);
        names = new string[](len);
        fundReceivers = new address[](len);

        for (uint i = start; i < end;) {
            if (partnerInfo[i].isApproved) {
                partnerIds[count] = i;
                names[count] = partnerInfo[i].name;
                fundReceivers[count] = partnerInfo[i].fundReceiver;
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }
    }

    function fetchParnterInfo(uint256[] calldata partnerIds) external view returns (
        address[] memory fundReceivers,
        string[] memory names
    ) {
        uint len = partnerIds.length;
        names = new string[](len);
        fundReceivers = new address[](len);

        for (uint i = 0; i < len;) {
            names[i] = partnerInfo[partnerIds[i]].name;
            fundReceivers[i] = partnerInfo[partnerIds[i]].fundReceiver;
            unchecked { ++i; }
        }
    }

    function fetchAllTokens() external view returns (address[] memory) {
        return allTokens;
    }

    function isListedToken(address token) external view override returns (bool) {
        return tokenAssets[token].house != address(0) && allTokens[tokenAssets[token].index] == token;
    }

    function getWrapper(address token) external view override returns (address) {
        return tokenAssets[token].wrapper;
    }

    function getHouse(address token) external view override returns (address) {
        return tokenAssets[token].house;
    }

    function getViewer(address token) external view override returns (address) {
        return tokenAssets[token].viewer;
    }

    function isWrappedAsset(address wrapper) external view override returns (bool) {
        return IWrappedAssetManager(wrappedAssetManager).isWrappedAsset(wrapper);
    }

    function fetchAllTokensAndAssets() external view returns (
        address[] memory,
        address[] memory wrappers,
        address[] memory houses,
        address[] memory viewers
    ) {
        uint256 len = allTokens.length;
        wrappers = new address[](len);
        houses = new address[](len);
        viewers = new address[](len);

        for (uint i = 0; i < len;) {
            wrappers[i] = tokenAssets[allTokens[i]].wrapper;
            houses[i] = tokenAssets[allTokens[i]].house;
            viewers[i] = tokenAssets[allTokens[i]].viewer;
            unchecked { ++i; }
        }
        return (allTokens, wrappers, houses, viewers);
    }

    function fetchTokenAssets(address token) external view returns (
        address wrapper,
        address house,
        address viewer
    ) {
        wrapper = tokenAssets[token].wrapper;
        house = tokenAssets[token].house;
        viewer = tokenAssets[token].viewer;
    }

    function paginateTokens(uint256 startIndex, uint256 endIndex) external view returns (address[] memory) {
        if (endIndex > allTokens.length) {
            endIndex = allTokens.length;
        }
        address[] memory list = new address[](endIndex - startIndex);
        uint256 count;
        for (uint256 i = startIndex; i < endIndex;) {
            list[count] = allTokens[i];
            unchecked { ++i; ++count; }
        }
        return list;
    }

    function paginateTokenAssets(uint256 startIndex, uint256 endIndex) external view returns (address[] memory wrappers, address[] memory houses, address[] memory viewers) {
        if (endIndex > allTokens.length) {
            endIndex = allTokens.length;
        }
        wrappers = new address[](endIndex - startIndex);
        houses = new address[](endIndex - startIndex);
        viewers = new address[](endIndex - startIndex);
        uint256 count;
        for (uint256 i = startIndex; i < endIndex;) {
            wrappers[count] = tokenAssets[allTokens[i]].wrapper;
            houses[count] = tokenAssets[allTokens[i]].house;
            viewers[count] = tokenAssets[allTokens[i]].viewer;
            unchecked { ++i; ++count; }
        }
    }

    receive() external payable {}
}
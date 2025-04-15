//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GovernanceManager/QupacaOwnable.sol";
import "../lib/IERC20.sol";
import "../lib/Cloneable.sol";
import "../lib/TransferHelper.sol";
import "./IWrappedAsset.sol";
import "./IWrappedAssetManager.sol";
import "../House/IHouseManager.sol";

contract WrappedAssetManager is QupacaOwnable, IWrappedAssetManager {

    // list of all wrapped assets
    address[] public allWrappedAssets;

    // list of all underlying assets that have been wrapped
    address[] public allUnderlyingAssets;

    // maps a wrapped asset to its underlying asset
    mapping ( address => address ) public getUnderlying;

    // maps an underlying asset to its wrapped asset
    mapping ( address => address ) public getWrapperFor;

    // implementation contract for wrapping asset
    address public implementation;

    // HouseManager contract
    IHouseManager public houseManager;

    // create wrapper event
    event WrapperCreated(address indexed underlying, address indexed wrapper);

    constructor(
        address implementation_,
        address manager_
    ) QupacaOwnable(manager_) {
        implementation = implementation_;
    }

    function setImplementation(address implementation_) external onlyOwner {
        implementation = implementation_;
    }

    function setHouseManager(address houseManager_) external onlyOwner {
        houseManager = IHouseManager(houseManager_);
    }

    /**
        Wraps `token` in wrapper and sends to `contractToCall` with `externalCallData`
     */
    function wrap(address token, uint256 amount, address contractToCall, bytes calldata externalCallData, uint256 additionalTransferForCall) external payable override {
        
        // get wrapper for token
        address wrapper = getWrapperFor[token];

        // if token does not have a wrapper, create one -- maybe not yet, have ProjectTokens create the wrapper and all contracts at once
        // if (wrapper == address(0)) {
        //     wrapper = _createWrapper(token);
        // }
        require(wrapper != address(0), "Wrapper not found");

        // transfer assets to wrapper, noting how many have been found
        uint256 received = _transferAssetFromSenderTo(token, wrapper, amount);

        // if `contractToCall` is not zero, ensure that `contractToCall` can be trusted
        if (contractToCall != address(0)) {
            // MAKE SURE THIS CALL IS NOT TO THE UNDERLYING ITSELF OR ANYWHERE WE DO NOT ALLOW
            require(isGameOrHouse(contractToCall), "Invalid contractToCall");

            // wrap the asset, passing in the calldata        
            IWrappedAsset(getWrapperFor[token]).wrap{value: msg.value}(msg.sender, received, contractToCall, externalCallData, additionalTransferForCall);
        } else {
            // wrap the asset, passing in the calldata        
            IWrappedAsset(getWrapperFor[token]).wrap{value: msg.value}(msg.sender, received, address(0), new bytes(0), 0);
        }

    }

    function unwrap(address token, uint256 amount) external {
        // get wrapper for token
        address wrapper = getWrapperFor[token];
        require(wrapper != address(0), "Wrapper not found");

        // unwrap the asset
        IWrappedAsset(wrapper).unwrapFor(msg.sender, amount, msg.sender);
    }

    function unwrapWrappedToken(address wrappedToken, uint256 amount) external override {
        require(getUnderlying[wrappedToken] != address(0), "Invalid Token");

        // unwrap the asset
        IWrappedAsset(wrappedToken).unwrapFor(msg.sender, amount, msg.sender);
    }

    function unwrapFor(address token, uint256 amount, address to) external {
        // get wrapper for token
        address wrapper = getWrapperFor[token];
        require(wrapper != address(0), "Wrapper not found");

        // unwrap the asset
        IWrappedAsset(wrapper).unwrapFor(msg.sender, amount, to);
    }

    function batchUnwrap(address[] calldata tokens, uint256[] calldata amounts) external {

        // fetch length for gas savings
        uint len = tokens.length;
        require(len == amounts.length, "Invalid input");

        // loop through all tokens
        for (uint i = 0; i < len;) {

            // get wrapper for token
            address wrapper = getWrapperFor[tokens[i]];
            require(wrapper != address(0), "Wrapper not found");

            // unwrap the asset
            IWrappedAsset(wrapper).unwrapFor(msg.sender, amounts[i], msg.sender);

            // increment loop
            unchecked { ++i; }
        }
    }

    function unwrapAll(address[] calldata tokens) external {

        // fetch length for gas savings
        uint len = tokens.length;

        // loop through all tokens
        for (uint i = 0; i < len;) {

            // get wrapper for token
            address wrapper = getWrapperFor[tokens[i]];
            require(wrapper != address(0), "Wrapper not found");

            // get amount of wrapper owned by user
            uint256 amount = IERC20(wrapper).balanceOf(msg.sender);

            // unwrap the asset if user has any
            if (amount > 0) {
                IWrappedAsset(wrapper).unwrapFor(msg.sender, amount, msg.sender);
            }

            // increment loop
            unchecked { ++i; }
        }
    }

    function unwrapTokenForUser(address wrapper, address user) external onlyGame() {
        // get token for wrapper
        address token = getUnderlying[wrapper];
        require(token != address(0), "Token not found");

        // get amount of wrapper owned by user
        uint256 amount = IERC20(wrapper).balanceOf(user);

        // unwrap the asset if user has any
        if (amount > 0) {
            IWrappedAsset(wrapper).unwrapFor(user, amount, user);
        }
    }

    function withdrawAndUnwrap(address token, uint256 amount) external {
        // get wrapper for token
        address wrapper = getWrapperFor[token];
        require(wrapper != address(0), "Wrapper not found");

        // withdraw and unwrap
        houseManager.withdrawFor(msg.sender, wrapper, amount);

        // get amount of wrapper owned by user
        uint256 allAmount = IERC20(wrapper).balanceOf(msg.sender);

        // unwrap the asset if user has any
        if (allAmount > 0) {
            IWrappedAsset(wrapper).unwrapFor(msg.sender, allAmount, msg.sender);
        }
    }

    function createWrapper(address token) external override returns (address) {
        require(msg.sender == manager.projectTokens(), "Unauthorized");
        require(token != address(0), "Zero Address");
        require(getWrapperFor[token] == address(0), "Wrapper already exists");
        return _createWrapper(token);
    }

    function isGame(address game) public view override returns (bool) {
        return manager.isGame(game);
    }

    function isGameOrHouse(address game) public view override returns (bool) {
        return manager.isGame(game) || houseManager.isHouse(game);
    }

    function isHouse(address house) public view override returns (bool) {
        return houseManager.isHouse(house);
    }

    function typeOfRecipient(address recipient) external view override returns (uint8) {
        if (isGame(recipient)) {
            return 1;
        } else if (isHouse(recipient)) {
            return 2;
        } else {
            return 0;
        }
    }

    function isOwner(address user) external view override returns (bool) {
        return manager.owner() == user;
    }

    function getWrapper(address token) external view override returns (address) {
        return getWrapperFor[token];
    }
    
    function getUnderlyingAsset(address wrapper) external view override returns (address) {
        return getUnderlying[wrapper];
    }

    function _createWrapper(address token) internal returns (address wrapper) {

        // if a wrapper already exists, return it
        if (getWrapperFor[token] != address(0)) {
            return getWrapperFor[token];
        }

        // pull token metadata
        (string memory name, string memory symbol, uint8 decimals) = pullTokenMetadata(token);

        // create new wrapped asset
        wrapper = Cloneable(implementation).clone(); 

        // initialize wrapped asset
        IWrappedAsset(wrapper).__init__(token, string.concat('w',name), string.concat('w',symbol), decimals);

        // add wrapper to list of all wrapped assets
        allWrappedAssets.push(wrapper);

        // add underlying asset to list of all underlying assets
        allUnderlyingAssets.push(token);

        // add mappings
        getUnderlying[wrapper] = token;
        getWrapperFor[token] = wrapper;

        // emit event to track
        emit WrapperCreated(token, wrapper);
    }

    function pullTokenMetadata(address token) public view returns (
        string memory name,
        string memory symbol,
        uint8 decimals
    ) {
        (bool s, bytes memory retData) = token.staticcall(abi.encodeWithSignature("name()"));
        if (s) {
            name = abi.decode(retData, (string));
        } else {
            revert("No Token Name");
        }

        (s, retData) = token.staticcall(abi.encodeWithSignature("symbol()"));
        if (s) {
            symbol = abi.decode(retData, (string));
        } else {
            revert("No Token Symbol");
        }

        (s, retData) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (s) {
            decimals = abi.decode(retData, (uint8));
        } else {
            revert("No Token Decimals");
        }
    }

    function _transferAssetFromSenderTo(address token, address wrapper, uint256 amount) internal returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        // ensure user has enough balance and allowance
        require(
            IERC20(token).balanceOf(msg.sender) >= amount,
            "Insufficient balance"
        );
        require(
            IERC20(token).allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );

        // get old balance of wrapper
        uint256 oldBalance = IERC20(token).balanceOf(wrapper);

        // transfer assets to wrapper
        TransferHelper.safeTransferFrom(token, msg.sender, wrapper, amount);

        // get new balance of wrapper
        uint256 newBalance = IERC20(token).balanceOf(wrapper);

        // ensure tokens were sent
        require(
            newBalance > oldBalance,
            "No tokens sent"
        );

        // return the difference
        return newBalance - oldBalance;
    }

    function isWrappedAsset(address wrappedAsset) external view override returns (bool) {
        return getUnderlying[wrappedAsset] != address(0);
    }

    function hasWrappedAsset(address token) external view returns (bool) {
        return getWrapperFor[token] != address(0);
    }

    // get list of all wrapped assets
    function allWrappedAssetsLength() external view returns (uint256) {
        return allWrappedAssets.length;
    }

    // get list of all underlying assets
    function allUnderlyingAssetsLength() external view returns (uint256) {
        return allUnderlyingAssets.length;
    }

    // paginate wrapped assets
    function paginateWrappedAssets(uint256 start, uint256 end) external view returns (address[] memory) {
        
        // ensure end is never greater than length
        if (end > allWrappedAssets.length) {
            end = allWrappedAssets.length;
        }

        // create array of wrapped assets
        address[] memory ret = new address[](end - start);

        // loop through, fetching wrapped assets
        for (uint i = start; i < end;) {
            ret[i - start] = allWrappedAssets[i];
            unchecked { ++i; }
        }

        // return array
        return ret;
    }

    // paginate wrapped assets
    function paginateUnderlyingAssets(uint256 start, uint256 end) external view returns (address[] memory) {
        
        // ensure end is never greater than length
        if (end > allUnderlyingAssets.length) {
            end = allUnderlyingAssets.length;
        }

        // create array of wrapped assets
        address[] memory ret = new address[](end - start);

        // loop through, fetching wrapped assets
        for (uint i = start; i < end;) {
            ret[i - start] = allUnderlyingAssets[i];
            unchecked { ++i; }
        }

        // return array
        return ret;
    }

    // get all balances of a user on all wrapped assets
    function allBalancesOf(address user) external view returns (uint256[] memory) {
        uint len = allWrappedAssets.length;
        uint256[] memory ret = new uint256[](len);
        for (uint i = 0; i < len;) {
            ret[i] = IERC20(allWrappedAssets[i]).balanceOf(user);
            unchecked { ++i; }
        }
        return ret;
    }

    // paginate all balances of a user for wrapped assets
    function paginateAllBalancesOfUserWithAssets(address user, uint256 start, uint256 end) external view returns (uint256[] memory, address[] memory, address[] memory) {
        
        // ensure end is never greater than length
        if (end > allWrappedAssets.length) {
            end = allWrappedAssets.length;
        }

        // create array of wrapped assets
        uint256[] memory ret = new uint256[](end - start);
        address[] memory wrappers = new address[](end - start);
        address[] memory tokens = new address[](end - start);

        // loop through, fetching wrapped assets
        for (uint i = start; i < end;) {
            ret[i - start] = IERC20(allWrappedAssets[i]).balanceOf(user);
            wrappers[i - start] = allWrappedAssets[i];
            tokens[i - start] = getUnderlying[allWrappedAssets[i]];
            unchecked { ++i; }
        }

        // return array
        return (ret, wrappers, tokens);
    }

    // paginate all balances of a user for all wrapped assets
    function paginateAllBalancesOfUser(address user, uint256 start, uint256 end) external view returns (uint256[] memory) {
        
        // ensure end is never greater than length
        if (end > allWrappedAssets.length) {
            end = allWrappedAssets.length;
        }

        // create array of wrapped assets
        uint256[] memory ret = new uint256[](end - start);

        // loop through, fetching wrapped assets
        for (uint i = start; i < end;) {
            ret[i - start] = IERC20(allWrappedAssets[i]).balanceOf(user);
            unchecked { ++i; }
        }

        // return array
        return ret;
    }

    // return list of balances for user from passed in array of wrapped assets
    function getBalancesOf(address user, address[] calldata wrappedAssets) external view returns (uint256[] memory) {
        uint len = wrappedAssets.length;
        uint256[] memory ret = new uint256[](len);
        for (uint i = 0; i < len;) {
            ret[i] = IERC20(wrappedAssets[i]).balanceOf(user);
            unchecked { ++i; }
        }
        return ret;
    }

    // get number of wrapped assets
    function getNumberOfWrappedAssets() external view returns (uint256) {
        return allWrappedAssets.length;
    }

    // get number of underlying assets
    function getNumberOfUnderlyingAssets() external view returns (uint256) {
        return allUnderlyingAssets.length;
    }

    // get users balance of wrapped and unwrapped asset
    function getBothBalancesFromUnderlying(address user, address token) external view returns (uint256 wrapped, uint256 underlying, uint256 totalBalance, uint8 decimals) {

        // get wrapper address from token
        address wrappedAsset = getWrapperFor[token];
        if (wrappedAsset == address(0)) {
            return (IERC20(token).balanceOf(user), 0, IERC20(token).balanceOf(user), IERC20(token).decimals());
        }

        wrapped = IERC20(wrappedAsset).balanceOf(user);
        underlying = IERC20(token).balanceOf(user);
        totalBalance = wrapped + underlying;
        decimals = IERC20(token).decimals();
    }

    // get users balance of wrapped and unwrapped asset
    function getBothBalancesFromWrapper(address user, address wrappedAsset) external view returns (uint256 wrapped, uint256 underlying, uint256 totalBalance, uint8 decimals) {

        // get wrapper address from token
        address token = getUnderlying[wrappedAsset];
        if (token == address(0)) {
            return (IERC20(wrappedAsset).balanceOf(user), 0, IERC20(wrappedAsset).balanceOf(user), IERC20(wrappedAsset).decimals());
        }

        wrapped = IERC20(wrappedAsset).balanceOf(user);
        underlying = IERC20(token).balanceOf(user);
        totalBalance = wrapped + underlying;
        decimals = IERC20(token).decimals();
    }
}
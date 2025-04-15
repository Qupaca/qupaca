//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IWrappedAsset.sol";
import "../lib/Cloneable.sol";
import "./IWrappedAssetManager.sol";
import "../lib/IERC20.sol";
import "../lib/TransferHelper.sol";
import "../GameMasterclass/IGame.sol";
import "../House/ITokenHouse.sol";

contract WrappedAssetData {

    /** Underlying Asset */
    address public underlying;

    /** Token Info */
    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    uint256 internal _totalSupply;

    /** balance and approval mappings */
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;

    /** Wrapped Asset Manager */
    address public wrappedAssetManager;

    /** Hide Transfers */
    bool public hideTransfers;

    /** Event */
    event GameApprovalSpend(address indexed from, address indexed to, uint256 value);
}

contract WrappedAsset is WrappedAssetData, Cloneable, IWrappedAsset {

    function __init__(
        address _underlying,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) external override {
        require(underlying == address(0) && wrappedAssetManager == address(0), "Already initialized");
        require(_underlying != address(0), "Underlying address cannot be 0");

        // set state
        underlying = _underlying;
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        wrappedAssetManager = msg.sender;
        hideTransfers = true;
        emit Transfer(address(0), address(0), 0);
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transfer(msg.sender, recipient, amount);
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {

        if (sender == address(this)) {
            emit GameApprovalSpend(sender, recipient, amount);
        } else {
            require(
                _allowances[sender][msg.sender] >= amount,
                'Insufficient Allowance'
            );
            _allowances[sender][msg.sender] -= amount;
        }

        // return transfer
        return _transfer(sender, recipient, amount);
    }

    /**
        Wrap method lets user wrap their underlying tokens then initiate a call to an external contract
        This will let users wrap their tokens into a game call, so users can wrap and play within one function call
     */
    function wrap(address user, uint256 amount, address to, bytes calldata externalCallData, uint256 additionalTransferForCall) external payable override {
        require(msg.sender == wrappedAssetManager, "Only Wrapped Asset Manager");
        
        // if data is not empty, decode it and initiate contract call
        if (externalCallData.length > 0 && to != underlying && to != address(0) && IWrappedAssetManager(wrappedAssetManager).isGameOrHouse(to)) {

            // wrap tokens for address(this) to be transferred in
            _wrap(address(this), amount);

            // get the recipient type
            uint8 TYPE = IWrappedAssetManager(wrappedAssetManager).typeOfRecipient(to);
            require(TYPE == 1 || TYPE == 2, "Invalid Recipient");

            // transfer in additional assets if needed
            if (additionalTransferForCall > 0) {
                require(
                    _balances[user] >= additionalTransferForCall,
                    'Insufficient Balance'
                );
                
                unchecked {
                    _balances[user] -= additionalTransferForCall;
                    _balances[address(this)] += additionalTransferForCall;
                }
                
                if (!hideTransfers) {
                    emit Transfer(user, address(0), amount);
                }
            }

            if (TYPE == 1) {
                // call game
                IGame(to).play{value: msg.value}(user, address(this), _balances[address(this)], externalCallData);
            } else {
                // call house
                ITokenHouse(to).deposit(user, _balances[address(this)]);
            }

        } else {
            // wrap tokens for user
            _wrap(user, amount);
        }
    }

    /**
        Unwrap method lets users burn their wrapped tokens and receive the underlying asset 1:1
     */
    function unwrapFor(address user, uint256 amount, address to) external override {
        require(msg.sender == wrappedAssetManager, "Only Wrapped Asset Manager");

        // unwrap for user, sending to `to`
        _unwrap(user, amount, to);
    }

    function unwrapTo(uint256 amount, address to) external override {
        _unwrap(msg.sender, amount, to);
    }

    function unwrap(uint256 amount) external override {
        _unwrap(msg.sender, amount, msg.sender);
    }

    function setHideTransfers(bool hideTransfers_) external {
        require(
            IWrappedAssetManager(wrappedAssetManager).isOwner(msg.sender),
            "Only Owner"
        );
        hideTransfers = hideTransfers_;
    }

    function _unwrap(address user, uint256 amount, address to) internal {
        // ensure user has enough balance
        require(
            amount <= _balances[user],
            'Insufficient Balance'
        );
        require(
            amount > 0,
            'Zero Amount'
        );

        // decrement user balance
        _balances[user] -= amount;
        unchecked {
            // decrement total supply
            _totalSupply -= amount;
        }

        // transfer underlying asset to user
        TransferHelper.safeTransfer(underlying, to, amount);

        if (!hideTransfers) {
            emit Transfer(user, address(0), amount);
        }
    }

    function _wrap(address user, uint256 amount) internal {
        if (amount == 0 || user == address(0)) {
            return;
        }
        unchecked {
            _balances[user] += amount;
            _totalSupply += amount;
        }
        if (!hideTransfers) {
            emit Transfer(address(0), user, amount);
        }
    }

    /** Internal Transfer */
    function _transfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(
            recipient != address(0),
            'Zero Recipient'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= _balances[sender],
            'Insufficient Balance'
        );
        
        // decrement sender balance
        _balances[sender] -= amount;
        unchecked {
            // add amount to recipient balance
            _balances[recipient] += amount;
        }

        // emit Transfer event for block explorers
        if (!hideTransfers) {
            emit Transfer(sender, recipient, amount);
        }

        // return success
        return true;
    }

    // removes assets from contract that are not wrapped assets
    function withdrawForeignTokens(address token, address to) external {
        require(
            IWrappedAssetManager(wrappedAssetManager).isOwner(msg.sender),
            "Only Wrapped Asset Manager Owner Can Call"
        );
        require(
            token != underlying,
            "Cannot withdraw underlying asset"
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
    }

    function withdrawNative(address to, uint256 amount) external {
        require(
            IWrappedAssetManager(wrappedAssetManager).isOwner(msg.sender),
            "Only Wrapped Asset Manager Owner Can Call"
        );
        require(
            amount <= address(this).balance,
            "Insufficient Balance"
        );
        TransferHelper.safeTransferETH(to, amount);
    }

    // removes excess tokens from contract that may have been gained via reward mechanisms, but are not part of the total
    function skimExcessTokens(address to) external {
        require(
            IWrappedAssetManager(wrappedAssetManager).isOwner(msg.sender),
            "Only Wrapped Asset Manager Owner Can Call"
        );

        // get true balance
        uint256 balance = IERC20(underlying).balanceOf(address(this));

        // if the true balance is greater than recorded balance, set them equal
        if (balance > _totalSupply) {
            IERC20(underlying).transfer(to, balance - _totalSupply);
        }
    }

    receive() external payable {}
}
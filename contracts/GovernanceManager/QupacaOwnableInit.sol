//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IFeeRecipient.sol";
import "./IGovernanceManager.sol";
import "../ProjectTokens/IProjectTokensManager.sol";
import "../RNG/IRNG.sol";

contract QupacaOwnableInit {

    // Governance Manager
    IGovernanceManager public manager;
    
    bool public initialized;
    
    function __init__(address manager_) public {
        require(manager_ != address(0), "QupacaOwnableInit: invalid manager");
        require(!initialized, "QupacaOwnableInit: already initialized");
        manager = IGovernanceManager(manager_);
        initialized = true;
    }
    
    modifier onlyPauser() {
        require(
            msg.sender == manager.pauseManager() || msg.sender == manager.owner(),
            'Only Pauser'
        );
        _;
    }

    modifier onlyOwner() {
        require(
            msg.sender == manager.owner(),
            'Only Owner'
        );
        _;
    }

    modifier onlyGame() {
        require(
            manager.isGame(msg.sender),
            'UnAuthorized'
        );
        _;
    }

    modifier onlyRNG() {
        require(
            msg.sender == manager.RNG(),
            'Only RNG Contract'
        );
        _;
    }

    modifier onlyValidToken(address token_) {
        require(
            IProjectTokensManager(manager.projectTokens()).isWrappedAsset(token_),
            'Invalid Token'
        );
        _;
    }

    modifier validGameToken(address token_) {
        require(
            token_ == address(0) || IProjectTokensManager(manager.projectTokens()).isWrappedAsset(token_),
            'Invalid Token'
        );
        _;
    }

    modifier validatePlayer(address player) {
        if (player != msg.sender) {
            require(
                IProjectTokensManager(manager.projectTokens()).canPlayForOthers(msg.sender),
                'UnAuthorized To Play For Others'
            );
        }
        _;
    }
}
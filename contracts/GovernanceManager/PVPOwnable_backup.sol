//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IFeeRecipient.sol";
import "./IGovernanceManager.sol";
import "../ProjectTokens/IProjectTokensManager.sol";
import "../RNG/IRNG.sol";

contract PVPOwnable_backup {

    // Governance Manager
    IGovernanceManager public constant manager = IGovernanceManager(0x4be93bfDa830D9107E6c2D927E5dE6BC0342E3bE);
    // Test Governance Manager
    // IGovernanceManager public constant manager = IGovernanceManager(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512);

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
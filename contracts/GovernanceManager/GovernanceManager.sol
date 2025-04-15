//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract GovernanceManager {

    /** Master Of Protocol */
    address private _owner;

    // Is A Game Contract
    mapping ( address => bool ) private _isGame;

    // User Info Tracker
    address public userInfoTracker;

    // House Contract For PvH Games
    address public house;

    // Referral Contract
    address public referralManager;

    // Fee Manager
    address public feeReceiver;
    address public feeSetter;

    // Pause Manager
    address public pauseManager;

    // Supra client address
    address public supraClientAddress;

    // Project Tokens Contract
    address public projectTokens;

    // Claim Manager Contract
    address public claimManager;

    // RNG Contract
    address public RNG;

    // onlyOwner modifier
    modifier onlyOwner() {
        require(msg.sender == _owner, 'Only Owner');
        _;
    }

    constructor(
        address owner_,
        address feeSetter_
    ) {
        
        // set ownership
        _owner = owner_;
        feeSetter = feeSetter_;
    }

    function setFeeReceiver(address newReceiver) external {
        require(msg.sender == feeSetter, 'Only Fee Setter');
        feeReceiver = newReceiver;
    }

    function setFeeSetter(address newSetter) external {
        require(msg.sender == feeSetter, 'Only Fee Setter');
        feeSetter = newSetter;
    }

    function setClaimManager(address newClaimManager) external onlyOwner {
        require(newClaimManager != address(0), 'Zero Address');
        claimManager = newClaimManager;
    }

    function setPauseManager(address newPauseManager) external onlyOwner {
        require(newPauseManager != address(0), 'Zero Address');
        pauseManager = newPauseManager;
    }

    function setProjectTokens(address newProjectTokens) external onlyOwner {
        require(newProjectTokens != address(0), 'Zero Address');
        projectTokens = newProjectTokens;
    }

    function setSupraClientAddress(address newSupraClientAddress) external onlyOwner {
        require(newSupraClientAddress != address(0), 'Zero Address');
        supraClientAddress = newSupraClientAddress;
    }

    function setRNG(address newRNG) external onlyOwner {
        RNG = newRNG;
    }

    function setHouse(address house_) external onlyOwner {
        require(
            house_ != address(0),
            'Zero House'
        );
        house = house_;
        _isGame[house_] = true;
    }

    function changeOwner(address newOwner) external onlyOwner {
        _owner = newOwner;
    }

    function setIsGame(address game, bool isGame_) external onlyOwner {
        _isGame[game] = isGame_;
    }

    function setReferralManager(address newManager) external onlyOwner {
        referralManager = newManager;
    }

    function setUserInfoTracker(address newTracker) external onlyOwner {
        userInfoTracker = newTracker;
    }

    function getOwner() external view returns (address) {
        return _owner;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function isGame(address game) external view returns (bool) {
        return _isGame[game] || game == _owner;
    }

}
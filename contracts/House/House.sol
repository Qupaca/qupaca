//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GovernanceManager/QupacaOwnable.sol";
import "../lib/SafeMath.sol";
import "../lib/TransferHelper.sol";
import "../ClaimManager/IClaimManager.sol";
import "./IHouse.sol";

/**
    House Contract is responsible for managing House funds.
    Only games can interact with functions
    Users can stake funds into the house IF they are permitted to do so, or unless the public toggle is enabled
 */
contract House is QupacaOwnable, IHouse {

    using SafeMath for uint256;

    // Trackable User Info
    struct UserInfo {
        uint256 balance;
        uint256 totalStaked;
        uint256 totalWithdrawn;
        uint256 unlockTime;
        bool isFeeExempt;
        uint256 maxContribution;
    }

    // User -> UserInfo
    mapping ( address => UserInfo ) public userInfo;

    // Whether or not staking is open to the public
    bool public publicStaking = true;

    bool public paused = false;

    // Fee Denom
    uint256 private constant FEE_DENOM = 10_000;

    // total supply of staked units
    uint256 public totalShares;

    // lock time
    uint256 public lockTime = 30 minutes;

    // precision factor
    uint256 private constant precision = 10**18;

    // Max Payout per game percentage
    uint256 public maxPayoutPerGame = 500; // 5% of total house balance

    // Exit Fee, reflected to house participants
    uint256 public exitFee = 200; // 2% exit fee, up to 10% max

    // Percentage of entry/exit fee that is reflected to the pool
    uint256 public reflectPercentage = 5000; // 50%

    // Halts Withdrawals While Randomness is being Requested
    uint256 public resolutionsPending;

    // Determines whether or not halting withdrawals while game resolutions are pending is permitted
    bool public enableInGamePausing = true;

    // The minimum price the house can fall to before PvH games are disabled
    // This value can be re-set if this occurs, allowing PvH games to continue
    // The idea for this is to allow time for devs to source a potential issue in a game that allowed the price to fall so low
    // This exists to protect house stakers from losing large sums of value too quickly
    uint256 public MIN_PRICE;

    // track volume in and volume out
    uint256 public volumeIn;
    uint256 public volumeOut;

    // Reentrancy Guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    modifier nonReentrant() {
        require(_status != _ENTERED, "Reentrancy Guard call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // Events
    event Deposit(address depositor, uint256 amount);
    event Withdraw(address withdrawer, uint256 amount);
    event HouseWon(uint256 GAME_ID, uint256 profit);
    event HouseLost(uint256 GAME_ID, address user, uint256 loss);

    constructor(address manager_) QupacaOwnable(manager_) {

        // set reentrancy
        _status = _NOT_ENTERED;

        emit Transfer(address(0), address(0), 0);
    }

    function name() external pure override returns (string memory) {
        return "House RON";
    }
    function symbol() external pure override returns (string memory) {
        return "HRON";
    }
    function decimals() external pure override returns (uint8) {
        return 18;
    }
    function totalSupply() external view override returns (uint256) {
        return address(this).balance;
    }

    function maxPayout() public view returns (uint256) {
        return ( address(this).balance * maxPayoutPerGame ) / FEE_DENOM;
    }

    function pause() external onlyPauser() {
        paused = true;
    }

    function resume() external onlyOwner {
        paused = false;
    }

    /** Shows The Value In RON Of The Users House RON Tokens */
    function balanceOf(address account) public view override returns (uint256) {
        // maybe have a flag for certain contracts, if the flag is true it shows their flat balance
        // if the flag is false it shwos the reflections balance. We would need to check this mapping again
        // in the withdraw contract and skip the step where the convert the passed in balance to an Account Balance
        // or lets just not show the RON amount, and instead have a flat conversion rate like in XUSD
        return ReflectionsFromContractBalance(userInfo[account].balance);
    }

    function allowance(address, address) external pure override returns (uint256) { 
        return 0;
    }
    
    function approve(address, uint256) public override returns (bool) {
        emit Approval(msg.sender, address(0), 0);
        return true;
    }
  
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        if (recipient == msg.sender) {
            withdraw(amount);
        }
        return true;
    }
    function transferFrom(address, address recipient, uint256 amount) external override returns (bool) {
        if (recipient == msg.sender) {
            withdraw(amount);
        }        
        return true;
    }

    function setLockTime(uint256 newLockTime) external onlyOwner {
        require(
            newLockTime <= 100 days,
            'Lock Time Too Long'
        );
        lockTime = newLockTime;
    }

    function setMaxContribution(address user, uint256 max) external onlyOwner {
        userInfo[user].maxContribution = max;
    }

    function setFeeExemption(address user, bool isExempt) external onlyOwner {
        userInfo[user].isFeeExempt = isExempt;
    }

    function setPublicStaking(bool isPublic) external onlyOwner {
        publicStaking = isPublic;
    }

    function setExitFee(uint256 exitFee_) external onlyOwner {
        require(
            exitFee_ <= FEE_DENOM / 10,
            'Exit Fee Too High'
        );
        exitFee = exitFee_;
    }

    function setReflectionPercentage(uint256 newPercent) external onlyOwner {
        require(
            newPercent <= FEE_DENOM,
            'Reflect Percent Too High'
        );
        reflectPercentage = newPercent;
    }

    /**
        Just in case resolutionsPending gets stuck above zero due to an error with chainlink VRF, etc
        Cannot increase the value greater than it currently is -- that would lock people in the House for forever
        Can only reduce the value
     */
    function hardSetResolutionsPending(uint256 resolutionsPending_) external onlyOwner {
        require(
            resolutionsPending_ < resolutionsPending,
            'Cannot Manually Increase This Value'
        );
        resolutionsPending = resolutionsPending_;
    }

    /**
        Enables Pausing withdrawals while games are awaiting resolution from chainlink VRF
     */
    function setEnableInGamePausing(bool isEnabled) external onlyOwner {
        enableInGamePausing = isEnabled;
    }

    function recoverForeignToken(address token) external onlyOwner {
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }
    
    function setMaxPayoutPerGame(uint256 newMaxPayout) external onlyOwner {
        require(
            newMaxPayout <= FEE_DENOM / 4,
            'Max Payout Percentage Too High'
        );
        maxPayoutPerGame = newMaxPayout;
    }

    function setMinPrice(uint256 percentOfCurrent) external onlyOwner {
        require(
            percentOfCurrent <= 950,
            'Min Price Cannot Exceed 95% Of Current Value'
        );
        require(
            percentOfCurrent >= 10,
            'Min Price Must Be Greater Than Or Equal To 1% Of Current'
        );
        MIN_PRICE = ( _calculatePrice() * percentOfCurrent ) / 1_000;
    }

    /**
        Deposits Ronin From Sender
        Locks In Contract, Minting RON House Tokens
     */
    function deposit() external payable nonReentrant {
        require(
            msg.value > 0,
            'Zero Value'
        );

        // Track Balance Before Deposit
        uint previousBalance = address(this).balance - msg.value;

        // mint appropriate balance to recipient
        if (totalShares == 0 || previousBalance == 0) {
            _registerFirstPurchase(msg.sender, msg.value);
        } else {
            _mintTo(msg.sender, msg.value, previousBalance);
        }

        if (publicStaking == false) {
            require(
                balanceOf(msg.sender) <= userInfo[msg.sender].maxContribution,
                'Max Contribution Exceeded'
            );
        }
    }

    /**
        Redeems `amount` of RON, As Seen From BalanceOf()
     */
    function withdraw(uint256 amount) public nonReentrant returns (uint256) {

        // check for in-Game Pausing
        if (enableInGamePausing == true) {
            require(
                resolutionsPending == 0,
                'Game Resolutions Are Pending'
            );
        }

        // ensure lock time
        require(
            timeUntilUnlock(msg.sender) == 0,
            'Not Yet Time'
        );

        // Turn RON Amount Into Contract Balance Amount
        uint MAXI_Amount = amount == balanceOf(msg.sender) ? userInfo[msg.sender].balance : RONToContractBalance(amount);

        require(
            userInfo[msg.sender].balance > 0 &&
            userInfo[msg.sender].balance >= MAXI_Amount &&
            balanceOf(msg.sender) >= amount &&
            amount > 0 &&
            MAXI_Amount > 0,
            'Insufficient Funds'
        );

        // burn MAXI Tokens From Sender
        _burn(msg.sender, MAXI_Amount, amount);

        // increment total withdrawn
        unchecked {
            userInfo[msg.sender].totalWithdrawn += amount;
        }
        
        // emit Event
        emit Withdraw(msg.sender, amount);

        // if fees exist, apply them
        if (exitFee > 0 && userInfo[msg.sender].isFeeExempt == false) {

            // split up fee and nonReflected Fee
            uint256 fee = ( amount * exitFee ) / FEE_DENOM;
            uint256 nonReflectFee = ( fee * reflectPercentage ) / FEE_DENOM;

            if (nonReflectFee > 0) {
                // send fee to receiver
                TransferHelper.safeTransferETH(manager.feeReceiver(), nonReflectFee);
            }

            // send value to user
            TransferHelper.safeTransferETH(msg.sender, amount - fee);
        } else {
            // send value to user
            TransferHelper.safeTransferETH(msg.sender, amount);
        }
        
        // return send amount
        return amount;
    }

    receive() external payable {
        require(totalShares > 0, 'Zero Shares');
        require(_status != _ENTERED, "Reentrancy Guard call");
        unchecked {
            volumeIn += msg.value;
        }
    }

    function randomRequested() external override nonReentrant onlyGame {
        require(paused == false, 'House is paused');

        require(
            _calculatePrice() >= MIN_PRICE,
            'PRICE TOO LOW, PvH GAMES PAUSED'
        );
        if (enableInGamePausing == false) {
            return;
        }
        unchecked {
            ++resolutionsPending;
        }
    }

    function randomRequestResolved() external override nonReentrant onlyGame {
        require(paused == false, 'House is paused');

        if (enableInGamePausing == false) {
            return;
        }
        // subtract resolutions pending
        if (resolutionsPending > 0) {
            unchecked {
                --resolutionsPending;
            }
        }
    }

    /**
        Request A Payout from the house from a successful Game.
        Only callable by Game Contracts
     */
    function payout(uint256 GAME_ID, address user, uint256 value) external override nonReentrant onlyGame {

        require(paused == false, 'House is paused');
        
        // constrain value lost to be the maximum payout
        if (value >= maxPayout()) {
            value = maxPayout();
        }

        // add to user's claim contract balance to avoid reentrancy
        IClaimManager(manager.claimManager()).credit{value: value}(
            GAME_ID,
            user
        );

        // add to volume out
        unchecked {
            volumeOut += value;
        }

        // emit house lost event
        emit HouseLost(GAME_ID, user, value);
    }

    function houseProfit(uint256 GAME_ID) external payable override onlyGame nonReentrant {
        unchecked {
            volumeIn += msg.value;
        }
        emit HouseWon(GAME_ID, msg.value);
    }

    /**
        Registers the First Stake
     */
    function _registerFirstPurchase(address user, uint received) internal {
        
        // increment total staked
        userInfo[user].totalStaked += received;

        // mint MAXI Tokens To Sender
        _mint(user, received, received);

        emit Deposit(user, received);
    }

    function _mintTo(address sender, uint256 received, uint256 previousBalance) internal {
        // Number Of Maxi Tokens To Mint
        uint nToMint = (totalShares.mul(received).div(previousBalance));
        require(
            nToMint > 0,
            'Zero To Mint'
        );

        // increment total staked
        userInfo[sender].totalStaked += received;

        // mint MAXI Tokens To Sender
        _mint(sender, nToMint, received);

        emit Deposit(sender, received);
    }


    /**
     * Burns `amount` of Contract Balance Token
     */
    function _burn(address from, uint256 amount, uint256 roninAmount) private {

        // update balances
        userInfo[from].balance = userInfo[from].balance.sub(amount);
        totalShares = totalShares.sub(amount);
        
        // emit Transfer
        // emit Transfer(from, address(0), bnbAmount);
    }

    /**
     * Mints `amount` of Contract Balance Token
     */
    function _mint(address to, uint256 amount, uint256 roninWorth) private {
        unchecked {
            userInfo[to].balance += amount;
            totalShares += amount;
        }
        userInfo[to].unlockTime = block.timestamp + lockTime;
        // emit Transfer(address(0), to, ronin);
    }

    /**
        Fetches the time until a user's staked amount can be withdrawn
     */
    function timeUntilUnlock(address user) public view returns (uint256) {
        return userInfo[user].unlockTime > block.timestamp ? userInfo[user].unlockTime - block.timestamp : 0;
    }

    /**
        Converts A RON Amount Into A RON MAXI Amount
     */
    function RONToContractBalance(uint256 amount) public view returns (uint256) {
        return amount.mul(precision).div(_calculatePrice());
    }

    /**
        Converts A RON MAXI Amount Into A RON Amount
     */
    function ReflectionsFromContractBalance(uint256 amount) public view returns (uint256) {
        return amount.mul(_calculatePrice()).div(precision);
    }

    /** Conversion Ratio For MAXI -> RON */
    function calculatePrice() external view returns (uint256) {
        return _calculatePrice();
    }

    /** Returns Total Profit for User In Token From MAXI */
    function getTotalProfits(address user) external view returns (int256) {
        uint top = balanceOf(user) + userInfo[user].totalWithdrawn;
        return int256(top) - int256(userInfo[user].totalStaked);
    }
    
    /** Conversion Ratio For MAXI -> RON */
    function _calculatePrice() internal view returns (uint256) {
        return ( address(this).balance * precision ) / totalShares;
    }
}
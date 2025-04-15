//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GovernanceManager/QupacaOwnableInit.sol";
import "../lib/SafeMath.sol";
import "../lib/TransferHelper.sol";
import "../lib/IERC20.sol";
import "../ClaimManager/IClaimManager.sol";
import "./ITokenHouse.sol";
import "./HouseDataTracking.sol";
import "../ProjectTokens/IProjectTokensManager.sol";

contract TokenHouseData is HouseDataTracking {

    // Fee Denom
    uint256 internal constant FEE_DENOM = 10_000;

    // Pause House
    bool public paused = false;

    // precision factor
    uint256 internal constant precision = 10**18;

    // Trackable User Info
    struct UserInfo {
        uint256 balance;
        uint256 totalStaked;
        uint256 totalWithdrawn;
        uint256 unlockTime;
    }

    // User -> UserInfo
    mapping ( address => UserInfo ) public userInfo;

    struct GameStats {
        uint256 totalProfitIn;
        uint256 totalDebtOut;
    }
    mapping ( uint256 => GameStats ) public gameStats;

    // Token For This House
    address public token;
    string internal tokenSymbol;

    // total supply of staked units
    uint256 public totalShares;

    // lock time
    uint256 public lockTime;

    // Max Payout per game percentage
    uint256 public maxPayoutPerGame;

    // Exit Fee, reflected to house participants
    uint256 public exitFee;

    // Percentage of entry/exit fee that is reflected to the pool
    uint256 public reflectPercentage;

    // Halts Withdrawals While Randomness is being Requested
    uint256 public resolutionsPending;

    // Implementation Contract
    bool internal isImplementation;

    // Reentrancy Guard
    uint256 internal constant _NOT_ENTERED = 1;
    uint256 internal constant _ENTERED = 2;
    uint256 internal _status;
    modifier nonReentrant() {
        require(_status != _ENTERED, "Reentrancy Guard call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // Events
    event HouseWon(uint256 GAME_ID, uint256 profit);
    event HouseLost(uint256 GAME_ID, address user, uint256 loss);
    event Transfer(address indexed from, address indexed to, uint256 value);
}

/**
    House Contract is responsible for managing House funds.
    Only games can interact with functions that affect the house balance aside from users depositing or withdrawing
 */
contract TokenHouse is TokenHouseData, QupacaOwnableInit, ITokenHouse {

    using SafeMath for uint256;

    constructor(address manager_) {
        QupacaOwnableInit.__init__(manager_);
    }

    function __init__(address _token, address manager_) external {
        require(token == address(0), 'Already Initialized');
        require(_token != address(0), 'Invalid Token Address');
        require(manager_ != address(0), 'Invalid Manager Address');

        // initialize QupacaOwnableInit
        QupacaOwnableInit.__init__(manager_);

        // initalize constructor data
        token = _token;
        tokenSymbol = IERC20(_token).symbol();

        // initialize standard data
        lockTime = 1 hours;       // 1 hour lock time to prevent house abuse
        maxPayoutPerGame = 500;   // 5% of total house balance
        exitFee = 200;            // 2% exit fee
        reflectPercentage = 5000; // 50%

        // set reentrancy
        _status = _NOT_ENTERED;
    }

    function name() external view returns (string memory) {
        return string.concat(tokenSymbol, " House");
    }
    function symbol() external view returns (string memory) {
        return string.concat("H", tokenSymbol);
    }
    function decimals() external view returns (uint8) {
        return IERC20(token).decimals();
    }
    function totalSupply() external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function maxPayout() public view returns (uint256) {
        return ( IERC20(token).balanceOf(address(this)) * maxPayoutPerGame ) / FEE_DENOM;
    }

    function pause() external onlyPauser() {
        paused = true;
    }

    function resume() external onlyOwner {
        paused = false;
    }

    /** Shows The Value In Token Of The Users House Token Tokens */
    function balanceOf(address account) public view returns (uint256) {
        // show the value in Token of the users house Token tokens, adjusted for the current growth of the house
        return ReflectionsFromContractBalance(userInfo[account].balance);
    }

    function setLockTime(uint256 newLockTime) external onlyOwner {
        require(
            newLockTime <= 30 days,
            'Lock Time Too Long'
        );
        lockTime = newLockTime;
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

    function recoverForeignToken(address _token) external onlyOwner {
        require(token != _token, 'Cannot Recover House Token');
        TransferHelper.safeTransfer(_token, msg.sender, IERC20(_token).balanceOf(address(this)));
    }

    function recoverETH() external onlyOwner {
        TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }
    
    function setMaxPayoutPerGame(uint256 newMaxPayout) external onlyOwner {
        require(
            newMaxPayout <= FEE_DENOM / 4,
            'Max Payout Percentage Too High'
        );
        maxPayoutPerGame = newMaxPayout;
    }

    function enableCloning() external onlyOwner {
        isImplementation = true;
    }

    function disableCloning() external onlyOwner {
        isImplementation = false;
    }

    /**
        @dev Deploys and returns the address of a clone of address(this
        Created by DeFi Mark To Allow Clone Contract To Easily Create Clones Of Itself
        Without redundancy
     */
    function clone() external nonReentrant returns(address) {
        require(isImplementation, 'Not Implementation Contract');
        return _clone(address(this));
    }


    /**
        Deposits Tokens From Sender
        Locks In Contract, Minting House Tokens
     */
    function deposit(address to, uint256 amount) external override nonReentrant {
        if (to != msg.sender) {
            require(
                IProjectTokensManager(manager.projectTokens()).isWrappedAsset(msg.sender),
                'Unauthorized'
            );
        }

        // Track Balance Before Deposit
        uint previousBalance = IERC20(token).balanceOf(address(this));

        // Transfer Tokens To Contract
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);

        // Note balance received
        uint256 received = IERC20(token).balanceOf(address(this)) - previousBalance;
        require(received > 0, 'Zero Received');

        // mint appropriate balance to recipient
        if (totalShares == 0 || previousBalance == 0) {
            _registerFirstPurchase(to, received);
        } else {
            _mintTo(to, received, previousBalance);
        }
    }

    /**
        Redeems `amount` of token, As Seen From BalanceOf()
     */
    function withdraw(uint256 amount) external nonReentrant returns (uint256) {

        // check for on-going game
        require(
            resolutionsPending == 0,
            'Game Resolutions Are Pending'
        );
        
        // ensure lock time
        require(
            timeUntilUnlock(msg.sender) == 0,
            'Not Yet Time'
        );

        // Turn token Amount Into Contract Balance Amount
        uint MAXI_Amount = amount == balanceOf(msg.sender) ? userInfo[msg.sender].balance : tokenToContractBalance(amount);

        // ensure user has enough balance
        if (MAXI_Amount > userInfo[msg.sender].balance) {
            MAXI_Amount = userInfo[msg.sender].balance;
        }

        require(
            userInfo[msg.sender].balance > 0 &&
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

        // if fees exist, apply them
        if (exitFee > 0) {

            // split up fee and nonReflected Fee
            uint256 fee = ( amount * exitFee ) / FEE_DENOM;
            uint256 nonReflectFee = ( fee * reflectPercentage ) / FEE_DENOM;

            if (nonReflectFee > 0) {
                // send fee to receiver
                TransferHelper.safeTransfer(token, manager.feeReceiver(), nonReflectFee);
            }

            // send value to user
            TransferHelper.safeTransfer(token, msg.sender, amount - fee);
        } else {
            // send value to user
            TransferHelper.safeTransfer(token, msg.sender, amount);
        }

        // log price change
        log(_calculatePrice());
        
        // return send amount
        return amount;
    }
    
    function withdrawFor(address user, uint256 amount) external nonReentrant returns (uint256) {

        address houseManager = IProjectTokensManager(manager.projectTokens()).houseManager();
        require(
            houseManager == msg.sender,
            'Unauthorized'
        );

        // check for on-going game
        require(
            resolutionsPending == 0,
            'Game Resolutions Are Pending'
        );
        
        // ensure lock time
        require(
            timeUntilUnlock(user) == 0,
            'Not Yet Time'
        );

        // Turn token Amount Into Contract Balance Amount
        uint MAXI_Amount = amount == balanceOf(user) ? userInfo[user].balance : tokenToContractBalance(amount);

        // ensure user has enough balance
        if (MAXI_Amount > userInfo[user].balance) {
            MAXI_Amount = userInfo[user].balance;
        }

        require(
            userInfo[user].balance > 0 &&
            balanceOf(user) >= amount &&
            amount > 0 &&
            MAXI_Amount > 0,
            'Insufficient Funds'
        );

        // burn MAXI Tokens From Sender
        _burn(user, MAXI_Amount, amount);

        // increment total withdrawn
        unchecked {
            userInfo[user].totalWithdrawn += amount;
        }

        // if fees exist, apply them
        if (exitFee > 0) {

            // split up fee and nonReflected Fee
            uint256 fee = ( amount * exitFee ) / FEE_DENOM;
            uint256 nonReflectFee = ( fee * reflectPercentage ) / FEE_DENOM;

            if (nonReflectFee > 0) {
                // send fee to receiver
                TransferHelper.safeTransfer(token, manager.feeReceiver(), nonReflectFee);
            }

            // send value to user
            TransferHelper.safeTransfer(token, user, amount - fee);
        } else {
            // send value to user
            TransferHelper.safeTransfer(token, user, amount);
        }

        // log price change
        log(_calculatePrice());
        
        // return send amount
        return amount;
    }

    receive() external payable {}

    function randomRequested() external override nonReentrant onlyGame {
        require(paused == false, 'House is paused');

        unchecked {
            ++resolutionsPending;
        }
    }

    function randomRequestResolved() external override nonReentrant onlyGame {
        require(paused == false, 'House is paused');

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
        
        // constrain value lost to be the max payout
        uint256 payoutAmount = value > maxPayout() ? maxPayout() : value;

        // add to user's claim contract balance
        IClaimManager(manager.claimManager()).creditToken(user, token, GAME_ID, payoutAmount);

        // transfer funds to user
        TransferHelper.safeTransfer(token, user, payoutAmount);

        // track data
        unchecked {
            gameStats[GAME_ID].totalDebtOut += payoutAmount;
        }

        // emit house lost event
        emit HouseLost(GAME_ID, user, payoutAmount);
    }

    function houseProfit(uint256 GAME_ID, uint256 amount) external override onlyGame nonReentrant {
        // emit house won event
        emit HouseWon(GAME_ID, amount);

        // track data
        unchecked {
            gameStats[GAME_ID].totalProfitIn += amount;
        }
    }

    /**
        Registers the First Stake
     */
    function _registerFirstPurchase(address user, uint received) internal {
        
        // increment total staked
        userInfo[user].totalStaked += received;

        // mint MAXI Tokens To Sender
        _mint(user, received, received);

        // log price change
        log(_calculatePrice());
    }

    function _mintTo(address sender, uint256 received, uint256 previousBalance) internal {
        // Number Of Maxi Tokens To Mint
        uint nToMint = (totalShares.mul(received)).div(previousBalance);
        require(
            nToMint > 0,
            'Zero To Mint'
        );

        // increment total staked
        unchecked {
            userInfo[sender].totalStaked += received;
        }

        // mint MAXI Tokens To Sender
        _mint(sender, nToMint, received);

        // log price change
        log(_calculatePrice());
    }


    /**
     * Burns `amount` of Contract Balance Token
     */
    function _burn(address from, uint256 amount, uint256 tokenAmount) private {

        // update balances
        userInfo[from].balance = userInfo[from].balance.sub(amount, "Insufficient Balance");
        totalShares = totalShares.sub(amount);
        
        // emit Transfer
        emit Transfer(from, address(0), tokenAmount);
    }

    /**
     * Mints `amount` of Contract Balance Token
     */
    function _mint(address to, uint256 amount, uint256 tokenWorth) private {
        unchecked {
            userInfo[to].balance += amount;
            totalShares += amount;
        }
        userInfo[to].unlockTime = block.timestamp + lockTime;
        emit Transfer(address(0), to, tokenWorth);
    }

    /**
        Fetches the time until a user's staked amount can be withdrawn
     */
    function timeUntilUnlock(address user) public view returns (uint256) {
        return userInfo[user].unlockTime > block.timestamp ? userInfo[user].unlockTime - block.timestamp : 0;
    }

    /**
        Converts A Token Amount Into A Token MAXI Amount
     */
    function tokenToContractBalance(uint256 amount) public view returns (uint256) {
        return amount.mul(precision).div(_calculatePrice());
    }

    /**
        Converts A Token MAXI Amount Into A Token Amount
     */
    function ReflectionsFromContractBalance(uint256 amount) public view returns (uint256) {
        return amount.mul(_calculatePrice()).div(precision);
    }

    /** Conversion Ratio For MAXI -> Token */
    function calculatePrice() external view returns (uint256) {
        return _calculatePrice();
    }

    /** Returns Total Profit for User In Token From MAXI */
    function getTotalProfits(address user) external view returns (int256) {
        uint top = balanceOf(user) + userInfo[user].totalWithdrawn;
        return int256(top) - int256(userInfo[user].totalStaked);
    }
    
    /** Conversion Ratio For MAXI -> Token */
    function _calculatePrice() internal view returns (uint256) {
        return ( IERC20(token).balanceOf(address(this)) * precision ) / totalShares;
    }

    /** Batches game stats calls for multiple game ids to reduce rpc calls */
    function batchGameStats(uint256[] calldata GAME_IDs) external view returns (uint256[] memory, uint256[] memory) {
        uint len = GAME_IDs.length;
        uint256[] memory totalProfitIn = new uint256[](len);
        uint256[] memory totalDebtOut = new uint256[](len);
        for (uint i = 0; i < len; i++) {
            totalProfitIn[i] = gameStats[GAME_IDs[i]].totalProfitIn;
            totalDebtOut[i] = gameStats[GAME_IDs[i]].totalDebtOut;
        }
        return (totalProfitIn, totalDebtOut);
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create opcode, which should never revert.
     */
    function _clone(address implementation) internal returns (address instance) {
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }

}
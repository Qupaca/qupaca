// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import "../GameMasterclass/GameMasterclass.sol";
import "../ClaimManager/IClaimManager.sol";
import "../House/IHouse.sol";

/**
    Plinko Game
 */
contract Plinko is GameMasterclass {

    // Base Min Gas
    uint256 public base_min_gas;
    uint256 public extra_gas_per_ball;

    address public gasRecipient;

    // Max Balls Per Drop
    uint8 public maxBalls = 100;

    // Game Struct
    struct Game {
        /** Which GameMode */
        uint8 gameMode;

        /** Player */
        address player;

        /** Amount Bet Per Ball */
        uint256 betAmount;

        /** Total Amount For House */
        uint256 amountForHouse;

        /** Number of Ball Batches */
        uint8 numBalls;

        /** Which Boost */
        uint8 whichBoost;

        /** Unwrap Type */
        uint8 unwrapType;

        /** Final Output -- list of bucket indexes */
        uint8[] buckets;

        /** Total Payout Amount */
        uint256 payout;

        /** Token Being Played */
        address token;

        /** Whether or not the game has ended and the VRF has called back */
        bool hasEnded;
    }

    // game params struct
    struct GameParams {
        address player;
        address token;
        uint256 amount;
        uint8 unwrapType;
        uint8 gameMode;
        uint8 numBalls;
        uint8 whichBoost;
        uint256 gameId;
        uint256 partnerId;
        address ref;
    }

    // mapping from GameID => Game
    mapping ( uint256 => Game ) public games;

    /** Boost Structure */
    struct Boost {
        uint8 boostOdds;
        uint16 payoutReduction;
    }

    // RandomResultParams
    struct RandomResultParams {
        uint256 gameId;
        uint8 gameMode;
        uint256 betAmount;
        uint8 numBalls;
        uint256 maxBucketVal;
        uint8 boostNo;
        uint8 boostOdds;
        uint8 numBuckets;
        uint256 betAmountPerBall;
        uint256 totalToPayout;
    }

    // request ID => GameID
    mapping ( uint256 => uint256 ) private requestToGame;

    // Bet Amount Limits
    mapping(address => uint256) public betAmountLimits;

    /** Platform Fee Taken Out Of Buy In */
    uint256 public platformFee = 200;
    uint256 public boostFee    = 0;

    /** Fee Denominator */
    uint256 private constant FEE_DENOM = 10_000;

    /** Payout Denom */
    uint256 public constant PAYOUT_DENOM = 10_000; // 0.01x precision (payout of 100 = 1%, 10,000 = 1x, 1,000,000 = 100x)

    // Game Mode Structure
    struct GameMode {
        uint112[] bucketWeights; // a list of bucket weights, which the rng is checked against to determine the bucket index
        mapping ( uint8 => uint256 ) payouts; // maps an index of bucketWeights to a payout => payouts[0] would be the payout for the first bucket
        mapping ( uint8 => Boost ) boosts;
    }

    // Maps a multiplier to a bonus jackpot payout
    // NOTE: map it to indexes in reel0,1,2 -- so we can give more jackpot bonuses to pots like BNB-BNB-BNB (0.06% chance)
    mapping ( uint8 => GameMode ) private gameModes;

    /** Locks changes to odds */
    bool public oddsLocked;

    /// @notice emitted after the platform fee has been changed
    event SetPlatformFee(uint256 newFee);

    /// @notice emitted after a random request has been sent out
    event RandomnessRequested(uint256 gameId);

    /// @notice emitted after a game has been started at a specific table
    event GameStarted(address indexed user, uint256 gameId);

    /// @notice Emitted after the VRF comes back with the index of the winning player
    event GameEnded(
        address indexed user, 
        uint256 gameId, 
        uint256 buyIn,
        uint256 payout
    );

    /// @notice Emitted if the fulfilRandomWords function needs to return out for any reason
    event FulfilRandomFailed(uint256 requestId, uint256 gameId, uint256[] randomWords);

    /// @notice Emitted when the reel data is updated, emits the odds associated with the reel data
    event OddsLocked();

    constructor(
        uint256 GAME_ID_,

        /** History Manager */
        address history_,

        /** Spin Gas */
        uint256 base_min_gas_,
        uint256 extra_gas_per_ball_,
        address manager_,

        /** Gas Recipient */
        address gasRecipient_

    ) GameMasterclass(GAME_ID_, history_, manager_) {
        base_min_gas = base_min_gas_;
        extra_gas_per_ball = extra_gas_per_ball_;

        require(gasRecipient_ != address(0));
        gasRecipient = gasRecipient_;
    }

    function setGasRecipient(address newGasRecipient) external onlyOwner {
        require(newGasRecipient != address(0));
        gasRecipient = newGasRecipient;
    }

    function setBaseMinGas(uint256 newBaseMinGas, uint256 newExtraGasPerBall) external onlyOwner {
        base_min_gas = newBaseMinGas;
        extra_gas_per_ball = newExtraGasPerBall;
    }

    function setMaxBalls(uint8 newMaxBalls) external onlyOwner {
        require(newMaxBalls <= 250, 'Cannot Exceed 250');
        maxBalls = newMaxBalls;
    }

    // set bet amount limits
    function setBetAmountLimits(address[] calldata tokens, uint256[] calldata limits) external onlyOwner {
        require(tokens.length == limits.length, "Array lengths must match");
        for (uint256 i = 0; i < tokens.length; i++) {
            betAmountLimits[tokens[i]] = limits[i];
        }
    }

    function getBetAmountLimits(
        address[] calldata tokens
    ) external view returns (uint256[] memory) {
        uint256[] memory limits = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            limits[i] = betAmountLimits[tokens[i]];
        }
        return limits;
    }

    function setPlatformFee(uint256 newPlatform) external onlyOwner {
        require(
            newPlatform <= FEE_DENOM / 20,
            'Cannot Exceed 5%'
        );
        platformFee = newPlatform;
        emit SetPlatformFee(newPlatform);
    }

    function lockOdds() external onlyOwner {
        oddsLocked = true;
        emit OddsLocked();
    }

    function setGameMode(
        uint8 gameMode,
        uint112[] calldata bucketWeights,
        uint256[] calldata payouts,
        uint8[] calldata boostOdds,
        uint16[] calldata payoutReductions
    ) external onlyOwner {
        require(
            oddsLocked == false,
            'Odds Are Locked'
        );
        require(
            bucketWeights.length == payouts.length,
            'Invalid Length'
        );
        gameModes[gameMode].bucketWeights = bucketWeights;
        for (uint8 i = 0; i < payouts.length;) {
            gameModes[gameMode].payouts[i] = payouts[i];
            unchecked { ++i; }
        }

        // set boosts
        for (uint8 i = 0; i < boostOdds.length;) {
            gameModes[gameMode].boosts[i + 1] = Boost(boostOdds[i], payoutReductions[i]);
            unchecked { ++i; }
        }
    }

    function _playGame(address player, address token, uint256 amount, bytes calldata gameData) internal override {

        // decode game data
        (
            uint8 unwrapType,
            uint8 gameMode,
            uint8 numBalls,
            uint8 whichBoost,
            uint256 gameId,
            uint256 partnerId,
            address ref
        ) = abi.decode(gameData, (uint8, uint8, uint8, uint8, uint256, uint256, address));

        GameParams memory params = GameParams({
            player: player,
            token: token,
            amount: amount,
            unwrapType: unwrapType,
            gameMode: gameMode,
            numBalls: numBalls,
            whichBoost: whichBoost,
            gameId: gameId,
            partnerId: partnerId,
            ref: ref
        });

        // determine gas
        uint256 minGas = quoteExtraGas(params.numBalls);

        // validate args
        require(
            isValidGameId(params.gameId),
            'Game ID Already Used'
        );
        require(
            params.numBalls > 0 && params.numBalls <= maxBalls,
            'Invalid Number of Balls'
        );
        require(
            gameModes[params.gameMode].bucketWeights.length > 0,
            'INVALID GAME MODE'
        );
        require(
            msg.value >= minGas,
            'Invalid Value'
        );

        if (params.whichBoost > 0) {
            require(
                gameModes[params.gameMode].boosts[params.whichBoost].payoutReduction > 0,
                'Invalid Boost'
            );
        }

        // calculate the bet amount
        uint256 totalBetAmount = params.token == address(0) ? msg.value - minGas : params.amount;
        // take platform fee out of the buy in
        uint256 platformFeeAmount = params.whichBoost == 0 ? 
            ( totalBetAmount * platformFee ) / FEE_DENOM :
            ( totalBetAmount * ( platformFee + boostFee ) ) / FEE_DENOM;
        totalBetAmount -= platformFeeAmount;

        uint256 betAmount = totalBetAmount / params.numBalls; // get bet amount per ball
        if (betAmountLimits[params.token] > 0) {
            require(
                betAmount <= betAmountLimits[params.token],
                "Bet amount per ball exceeds allowed limit"
            );
        }

        require(
            betAmount > 0,
            'Invalid Bet Amount'
        );

        TransferHelper.safeTransferETH(gasRecipient, minGas);

        // send to platform receiver
        _processFee(params.token, platformFeeAmount, params.partnerId, params.ref);

        // save game data
        games[params.gameId].gameMode = params.gameMode;
        games[params.gameId].player = params.player;
        games[params.gameId].betAmount = betAmount;
        games[params.gameId].whichBoost = params.whichBoost;
        games[params.gameId].unwrapType = params.unwrapType;
        games[params.gameId].amountForHouse = totalBetAmount;
        games[params.gameId].numBalls = params.numBalls;
        games[params.gameId].token = params.token;
        games[params.gameId].buckets = new uint8[](params.numBalls); // set buckets length to the number of balls we are dropping

        // process points
        _registerBet(params.player, totalBetAmount, params.token, params.partnerId);

        // fetch random number
        _requestRandom(params.gameId, params.numBalls);

        // add to list of used game ids and history
        _registerGameId(params.player, params.gameId);
        
        // emit event
        emit GameStarted(params.player, params.gameId);
    }

    function _requestRandom(uint256 gameId, uint8 numBalls) internal {

        // request random words from RNG contract
        uint256 requestId = IRNG(manager.RNG()).generateRequest(
            "fulfillRandomRequest(uint256,uint256[])",
            numBalls,
            2,
            manager.supraClientAddress()
        );

        // require that the requestId is unused
        require(
            requestToGame[requestId] == 0,
            'RequestId In Use'
        );

        // map this request ID to the game it belongs to
        requestToGame[requestId] = gameId;

        // set data in house
        IHouse(getHouse(games[gameId].token)).randomRequested();

        // emit event
        emit RandomnessRequested(gameId);
    }

    /**
        Callback to provide us with randomness
     */
    function fulfillRandomRequest(
        uint256 requestId,
        uint256[] calldata rngList
    ) external override onlyRNG {

        // get game ID from requestId
        RandomResultParams memory params;
        params.gameId = requestToGame[requestId];
        params.gameMode = games[params.gameId].gameMode;
        params.betAmount = games[params.gameId].betAmount;
        params.numBalls = games[params.gameId].numBalls;
        params.maxBucketVal = maxBucketValue(params.gameMode);
        
        // if faulty ID, remove
        if (
            params.gameId == 0 || 
            games[params.gameId].player == address(0) || 
            games[params.gameId].hasEnded == true ||
            params.betAmount == 0 ||
            params.maxBucketVal == 0 ||
            params.numBalls == 0
        ) {
            emit FulfilRandomFailed(requestId, params.gameId, rngList);
            return;
        }

        // set game has ended
        games[params.gameId].hasEnded = true;

        // clear storage
        delete requestToGame[requestId];

        // get boost
        params.boostNo = games[params.gameId].whichBoost;
        params.boostOdds = gameModes[params.gameMode].boosts[params.boostNo].boostOdds;
        params.numBuckets = params.boostNo == 0 ? 0 : uint8(gameModes[params.gameMode].bucketWeights.length);

        // fetch the bet amount per spin
        params.betAmountPerBall = params.boostNo > 0 ?
            ( params.betAmount * gameModes[params.gameMode].boosts[params.boostNo].payoutReduction ) / 1_000 : 
            params.betAmount;

        // resolve request in house
        IHouse(getHouse(games[params.gameId].token)).randomRequestResolved();

        // total to pay out for the house and total to send the house
        params.totalToPayout = 0;

        // loop through the balls
        for (uint8 i = 0; i < params.numBalls;) {

            // fetch random word
            uint256 rando = rngList[i];

            // get index of bucket
            uint8 index = getBucketIndex(params.gameMode, rando % params.maxBucketVal);

            if (params.boostNo > 0 && index != 0 && index != params.numBuckets - 1) {
                if (params.boostOdds >= 100 || ((uint256(keccak256(abi.encodePacked(rando))) % 100) < params.boostOdds )) {
                    if (index <= (params.numBuckets - 1 ) / 2) {
                        unchecked { --index; }
                    } else {
                        unchecked { ++index; }
                    }
                }
            }
            
            // add to total payout
            params.totalToPayout += ( params.betAmountPerBall * gameModes[params.gameMode].payouts[index] ) / PAYOUT_DENOM;

            // store in games bucket array
            games[params.gameId].buckets[i] = index;

            // increment loop
            unchecked { ++i; }
        }

        // save payout info
        games[params.gameId].payout = params.totalToPayout;

        // Use struct to pack parameters
        PayoutInfo memory info = PayoutInfo({
            token: games[params.gameId].token,
            player: games[params.gameId].player,
            totalToPayout: params.totalToPayout,
            amountForHouse: games[params.gameId].amountForHouse,
            unwrapType: games[params.gameId].unwrapType
        });

        // handle payment
        _handlePayout(info);

        // emit game ended event
        emit GameEnded(
            games[params.gameId].player, 
            params.gameId, 
            params.betAmount * params.numBalls,
            params.totalToPayout
        );
    }

    function quoteExtraGas(uint8 numBalls) public view returns (uint256) {
        return base_min_gas + ( extra_gas_per_ball * numBalls );
    }

    function getBucketIndex(uint8 gameMode, uint256 random) public view returns (uint8) {
        uint8 len = uint8(gameModes[gameMode].bucketWeights.length);
        uint8 index = len;
        for (uint8 i = 0; i < len;) {
            if (random < gameModes[gameMode].bucketWeights[i]) {
                index = i;
                break;
            }
            unchecked { ++i; }
        }
        return index;
    }

    function maxBucketValue(uint8 gameMode) public view returns (uint256) {
        uint len = gameModes[gameMode].bucketWeights.length;
        if (len == 0) {
            return 0;
        }
        return gameModes[gameMode].bucketWeights[len - 1];
    }


    function getPayoutAmount(uint256 betAmount, uint8 gameMode, uint8 index) public view returns (uint256) {
        return ( betAmount * gameModes[gameMode].payouts[index] ) / PAYOUT_DENOM;
    }

    function getPayout(uint8 gameMode, uint8 index) public view returns (uint256) {
        return gameModes[gameMode].payouts[index];
    }

    function getBucketWeights(uint8 gameMode) external view returns (uint112[] memory) {
        return gameModes[gameMode].bucketWeights;
    }

    function getBoost(uint8 gameMode, uint8 index) external view returns (uint8, uint16) {
        return ( gameModes[gameMode].boosts[index].boostOdds, gameModes[gameMode].boosts[index].payoutReduction );
    }

    function getGameInfo(uint256 gameId) external view returns (
        address player,
        uint8 gameMode,
        uint8 numBalls,
        uint8 whichBoost,
        uint8 unwrapType,
        uint256 betAmount,
        uint8[] memory bucketIndexes,
        uint256 totalPayout,
        address token,
        bool hasEnded
    ) {
        player = games[gameId].player;
        gameMode = games[gameId].gameMode;
        numBalls = games[gameId].numBalls;
        whichBoost = games[gameId].whichBoost;
        unwrapType = games[gameId].unwrapType;
        bucketIndexes = games[gameId].buckets;
        betAmount = games[gameId].betAmount;
        totalPayout = games[gameId].payout;
        token = games[gameId].token;
        hasEnded = games[gameId].hasEnded;
    }
}

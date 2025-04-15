// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GameMasterclass/GameMasterclass.sol";
import "../ClaimManager/IClaimManager.sol";
import "../House/IHouse.sol";

/**
    Slots PvH Game
 */
contract Slots is GameMasterclass {
    /** Reel Info */
    uint8[] public reel1;
    uint8[] public reel2;
    uint8[] public reel3;

    // Game Struct
    struct Game {
        /** Player */
        address player;
        /** Amount Bet */
        uint256 betAmount;
        /** Token Being Bet */
        address token;
        /** Total Amount For House */
        uint256 amountForHouse;
        /** Number of spins */
        uint8 numSpins;
        /** Which Boost */
        uint8 whichBoost;
        /** Unwrap Type */
        uint8 unwrapType;
        /** Final Output -- reels */
        uint8[] num0;
        uint8[] num1;
        uint8[] num2;
        /** Payouts */
        uint256 payout;
        /** Whether or not the game has ended and the VRF has called back */
        bool hasEnded;
    }

    /** Boost Structure */
    struct Boost {
        uint8 boostOdds;
        uint16 payoutReduction;
    }
    mapping(uint8 => Boost) public boosts;

    // mapping from GameID => Game
    mapping(uint256 => Game) public games;

    // request ID => GameID
    mapping(uint256 => uint256) private requestToGame;

    // Bet Amount Limits
    mapping(address => uint256) public betAmountLimits;

    /** Platform Fee Taken Out Of Buy In */
    uint256 public platformFee = 200;
    uint256 public boostFee = 0;

    // boost multiplier
    uint8 public boostGasMultiplier = 180;

    /** Fee Denominator */
    uint256 private constant FEE_DENOM = 10_000;

    /** Maps three random numbers to a payout */
    mapping(uint8 => mapping(uint8 => mapping(uint8 => uint256))) public payout;

    /** Payout Denom */
    uint256 public constant PAYOUT_DENOM = 10_000; // 0.01x precision (payout of 100 = 1%, 10,000 = 1x, 1,000,000 = 100x)

    // buy in gas per spin
    uint256 public minBuyInGas;
    uint256 public buyInGasPerSpin;
    uint8 public boostMultiplier;

    address public gasRecipient;

    // min spins
    uint256 public MIN_SPINS = 1;
    uint256 public MAX_SPINS = 30;

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
    event FulfilRandomFailed(
        uint256 requestId,
        uint256 gameId,
        uint256[] randomWords
    );

    /// @notice Emitted when the reel data is updated, emits the odds associated with the reel data
    event OddsLocked();

    struct GameParams {
        address player;
        address token;
        uint256 amount;
        uint8 unwrapType;
        uint8 numSpins;
        uint8 whichBoost;
        uint256 gameId;
        uint256 partnerId;
        address ref;
    }

    constructor(
        /** Constructor Arguments For Master Class */
        uint256 GAME_ID_,
        /** History Manager */
        address history_,
        /** Governance Manager */
        address manager_,
        /** Game Configs */
        uint8[] memory reel1_,
        uint8[] memory reel2_,
        uint8[] memory reel3_,
        uint256 minBuyInGas_,
        uint256 buyInGasPerSpin_,
        uint8[] memory boostOdds,
        uint16[] memory payoutReductions,
        address gasRecipient_
    ) GameMasterclass(GAME_ID_, history_, manager_) {
        // set reels
        reel1 = reel1_;
        reel2 = reel2_;
        reel3 = reel3_;
        require(
            reel1_.length == reel2_.length && reel2_.length == reel3_.length,
            "Invalid Reel Length"
        );

        // set gas info
        require(gasRecipient_ != address(0));
        minBuyInGas = minBuyInGas_; // 0.03 ether;  // = 0.001 ether;
        buyInGasPerSpin = buyInGasPerSpin_; // 0.001 ether; // = 0.00005 ether;
        gasRecipient = gasRecipient_;

        // set boosts
        for (uint8 i = 0; i < boostOdds.length; i++) {
            boosts[i + 1] = Boost(boostOdds[i], payoutReductions[i]);
        }
    }

    // set bet amount limits
    function setBetAmountLimits(
        address[] calldata tokens,
        uint256[] calldata limits
    ) external onlyOwner {
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

    // set min spins
    function setMinSpins(uint256 newMin) external onlyOwner {
        MIN_SPINS = newMin;
    }
    function setMaxSpins(uint256 newMax) external onlyOwner {
        MAX_SPINS = newMax;
    }

    function setBoostGasMultiplier(uint8 newMultiplier) external onlyOwner {
        boostGasMultiplier = newMultiplier;
    }

    function setBoost(
        uint8 boostId,
        uint8 boostOdds,
        uint16 payoutReduction
    ) external onlyOwner {
        require(boostId > 0, "Invalid Boost ID");
        boosts[boostId] = Boost(boostOdds, payoutReduction);
    }

    function setBuyInGasInfo(
        uint256 newMin,
        uint256 newGasPerSpin
    ) external onlyOwner {
        minBuyInGas = newMin;
        buyInGasPerSpin = newGasPerSpin;
    }

    function setPlatformFee(uint256 newPlatform) external onlyOwner {
        require(newPlatform <= FEE_DENOM / 10, "Cannot Exceed 10%");
        platformFee = newPlatform;
        emit SetPlatformFee(newPlatform);
    }

    function setBoostFee(uint256 newBoost) external onlyOwner {
        require(newBoost <= FEE_DENOM / 10, "Cannot Exceed 10%");
        boostFee = newBoost;
    }

    function setGasRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0));
        gasRecipient = newRecipient;
    }

    function lockOdds() external onlyOwner {
        oddsLocked = true;
        emit OddsLocked();
    }

    function setReels(
        uint8[] calldata reel1_,
        uint8[] calldata reel2_,
        uint8[] calldata reel3_
    ) external onlyOwner {
        require(oddsLocked == false, "Odds Are Locked");
        require(
            reel1_.length == reel2_.length && reel2_.length == reel3_.length,
            "Invalid Reel Length"
        );
        reel1 = reel1_;
        reel2 = reel2_;
        reel3 = reel3_;
    }

    function batchSetPayouts(
        uint8[] calldata coins0,
        uint8[] calldata coins1,
        uint8[] calldata coins2,
        uint256[] calldata payoutMultiplier
    ) external onlyOwner {
        require(oddsLocked == false, "Odds are locked");
        uint len = coins0.length;
        require(len == coins1.length, "Invalid Length 0-1");
        require(len == coins2.length, "Invalid Length 0-2");
        require(len == payoutMultiplier.length, "Invalid Length 0-payout");

        for (uint i = 0; i < len; ) {
            // set payout
            payout[coins0[i]][coins1[i]][coins2[i]] = payoutMultiplier[i];
            unchecked {
                ++i;
            }
        }
    }

    function _playGame(
        address player,
        address token,
        uint256 amount,
        bytes calldata gameData
    ) internal override {
        // decode input data
        (
            uint8 unwrapType,
            uint8 numSpins,
            uint8 whichBoost,
            uint256 gameId,
            uint256 partnerId,
            address ref
        ) = abi.decode(gameData, (uint8, uint8, uint8, uint256, uint256, address));

        GameParams memory params = GameParams({
            player: player,
            token: token,
            amount: amount,
            unwrapType: unwrapType,
            numSpins: numSpins,
            whichBoost: whichBoost,
            gameId: gameId,
            partnerId: partnerId,
            ref: ref
        });

        // validate inputs
        require(
            params.numSpins >= MIN_SPINS && params.numSpins <= MAX_SPINS,
            "Invalid Spin Count"
        );
        require(isValidGameId(params.gameId), "Game ID Already Used");

        // determine gas required to spin
        uint256 gasRequired = getMinBuyInGas(params.numSpins, params.whichBoost > 0);
        require(msg.value >= gasRequired, "Invalid Ether Sent For BuyIn Gas");

        // calculate the bet amount
        uint256 totalBetAmount = params.token == address(0)
            ? params.amount - gasRequired
            : params.amount;
        // take platform fee out of the buy in
        uint256 platformFeeAmount = params.whichBoost == 0
            ? (totalBetAmount * platformFee) / FEE_DENOM
            : (totalBetAmount * (platformFee + boostFee)) / FEE_DENOM;
        totalBetAmount -= platformFeeAmount;

        uint256 betAmountPerSpin = totalBetAmount / params.numSpins;
        if (betAmountLimits[params.token] > 0) {
            require(
                betAmountPerSpin <= betAmountLimits[params.token],
                "Bet amount per spin exceeds allowed limit"
            );
        }

        if (params.whichBoost > 0) {
            require(boosts[params.whichBoost].payoutReduction > 0, "Invalid Boost");
        }

        TransferHelper.safeTransferETH(gasRecipient, gasRequired);

        // send to platform receiver
        _processFee(params.token, platformFeeAmount, params.partnerId, params.ref);

        // save game data
        games[params.gameId].player = params.player;
        games[params.gameId].betAmount = betAmountPerSpin;
        games[params.gameId].token = params.token;
        games[params.gameId].amountForHouse = totalBetAmount;
        games[params.gameId].numSpins = params.numSpins;
        games[params.gameId].whichBoost = params.whichBoost;
        games[params.gameId].num0 = new uint8[](params.numSpins);
        games[params.gameId].num1 = new uint8[](params.numSpins);
        games[params.gameId].num2 = new uint8[](params.numSpins);
        games[params.gameId].unwrapType = params.unwrapType;

        // process points
        _registerBet(params.player, totalBetAmount, params.token, params.partnerId);

        // fetch random number
        _requestRandom(params.gameId, params.numSpins);

        // add to list of used game ids and history
        _registerGameId(params.player, params.gameId);

        // emit event
        emit GameStarted(params.player, params.gameId);
    }

    function _requestRandom(uint256 gameId, uint8 numSpins) internal {
        // request random words from RNG contract
        uint256 requestId = IRNG(manager.RNG()).generateRequest(
            "fulfillRandomRequest(uint256,uint256[])",
            uint8(numSpins * uint8(3)),
            2,
            manager.supraClientAddress()
        );

        // require that the requestId is unused
        require(requestToGame[requestId] == 0, "RequestId In Use");

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
        uint256 gameId = requestToGame[requestId];

        // if faulty ID, remove
        if (
            gameId == 0 ||
            games[gameId].player == address(0) ||
            games[gameId].hasEnded == true
        ) {
            emit FulfilRandomFailed(requestId, gameId, rngList);
            return;
        }

        // set game has ended
        games[gameId].hasEnded = true;

        // clear storage
        delete requestToGame[requestId];

        // resolve request in house
        IHouse(getHouse(games[gameId].token)).randomRequestResolved();

        // get boost
        uint8 boostNo = games[gameId].whichBoost;
        uint8 boostOdds = boosts[boostNo].boostOdds;

        // fetch the bet amount per spin
        uint256 betAmountPerSpin = boostNo > 0
            ? (games[gameId].betAmount * boosts[boostNo].payoutReduction) /
                1_000
            : games[gameId].betAmount;

        // total to pay out for the house and total to send the house
        uint256 totalToPayout = 0;

        // fetch number of spins
        uint8 numSpins = games[gameId].numSpins;

        // loop through spins
        for (uint i = 0; i < numSpins; ) {
            // select randoms
            uint256 rand1 = rngList[i * 3];
            uint256 rand2 = rngList[(i * 3) + 1];
            uint256 rand3 = rngList[(i * 3) + 2];

            // fetch index (coin) of reel array
            uint8 index1 = getMinIndexReel1(rand1 % numOptionsReel1());
            uint8 index2 = getMinIndexReel2(rand2 % numOptionsReel2());
            uint8 index3 = getMinIndexReel3(rand3 % numOptionsReel3());

            if (boostNo > 0) {
                // if boost is active, determine if user gets boost
                if (
                    index1 > 0 &&
                    ((uint256(keccak256(abi.encodePacked(rand1))) % 100) <
                        boostOdds)
                ) {
                    // user gets boost
                    unchecked {
                        --index1;
                    }
                }
                if (
                    index2 > 0 &&
                    ((uint256(keccak256(abi.encodePacked(rand2))) % 100) <
                        boostOdds)
                ) {
                    // user gets boost
                    unchecked {
                        --index2;
                    }
                }
                if (
                    index3 > 0 &&
                    ((uint256(keccak256(abi.encodePacked(rand3))) % 100) <
                        boostOdds)
                ) {
                    // user gets boost
                    unchecked {
                        --index3;
                    }
                }
            }

            // save indexes to state
            games[gameId].num0[i] = index1;
            games[gameId].num1[i] = index2;
            games[gameId].num2[i] = index3;

            // if payout exists, user won this spin
            if (payout[index1][index2][index3] > 0) {
                // increment data, add to total payout
                totalToPayout +=
                    (payout[index1][index2][index3] * betAmountPerSpin) /
                    PAYOUT_DENOM;
            }
            unchecked {
                ++i;
            }
        }

        // save payout info
        games[gameId].payout = totalToPayout;

        // handle payouts
        PayoutInfo memory info = PayoutInfo({
            token: games[gameId].token,
            player: games[gameId].player,
            totalToPayout: totalToPayout,
            amountForHouse: games[gameId].amountForHouse,
            unwrapType: games[gameId].unwrapType
        });
        _handlePayout(info);

        // emit game ended event
        emit GameEnded(
            games[gameId].player,
            gameId,
            games[gameId].betAmount * numSpins,
            totalToPayout
        );
    }

    function optionsReel1() external view returns (uint8[] memory) {
        return reel1;
    }

    function optionsReel2() external view returns (uint8[] memory) {
        return reel2;
    }

    function optionsReel3() external view returns (uint8[] memory) {
        return reel3;
    }

    function getMinIndexReel1(uint256 random) public view returns (uint8) {
        uint8 len = uint8(reel1.length);
        uint8 index = len;
        for (uint8 i = 0; i < len; ) {
            if (random < reel1[i]) {
                index = i;
                break;
            }
            unchecked {
                ++i;
            }
        }
        return index;
    }

    function getMinIndexReel2(uint256 random) public view returns (uint8) {
        uint8 len = uint8(reel2.length);
        uint8 index = len;
        for (uint8 i = 0; i < len; ) {
            if (random < reel2[i]) {
                index = i;
                break;
            }
            unchecked {
                ++i;
            }
        }
        return index;
    }

    function getMinIndexReel3(uint256 random) public view returns (uint8) {
        uint8 len = uint8(reel3.length);
        uint8 index = len;
        for (uint8 i = 0; i < len; ) {
            if (random < reel3[i]) {
                index = i;
                break;
            }
            unchecked {
                ++i;
            }
        }
        return index;
    }

    function numOptionsReel1() public view returns (uint8) {
        return reel1[reel1.length - 1];
    }

    function numOptionsReel2() public view returns (uint8) {
        return reel2[reel2.length - 1];
    }

    function numOptionsReel3() public view returns (uint8) {
        return reel3[reel3.length - 1];
    }

    function getPayout(
        uint8 coin1,
        uint8 coin2,
        uint8 coin3
    ) public view returns (uint256) {
        return payout[coin1][coin2][coin3];
    }

    function getMinBuyInGas(
        uint8 numSpins,
        bool withBoost
    ) public view returns (uint256) {
        uint256 baseGas = minBuyInGas + (numSpins * buyInGasPerSpin);
        return withBoost ? (baseGas * boostGasMultiplier) / 100 : baseGas;
    }

    function quoteValue(
        uint256 buyIn,
        uint8 numSpins,
        bool withBoost
    ) external view returns (uint256) {
        return (buyIn * numSpins) + getMinBuyInGas(numSpins, withBoost);
    }

    function getGameInfo(
        uint256 gameId
    )
        external
        view
        returns (
            address player,
            uint256 betAmount,
            uint8 numSpins,
            uint8 whichBoost,
            uint8 unwrapType,
            uint8[] memory num0,
            uint8[] memory num1,
            uint8[] memory num2,
            uint256 totalPayout,
            address token,
            bool hasEnded
        )
    {
        player = games[gameId].player;
        betAmount = games[gameId].betAmount;
        numSpins = games[gameId].numSpins;
        whichBoost = games[gameId].whichBoost;
        unwrapType = games[gameId].unwrapType;
        num0 = games[gameId].num0;
        num1 = games[gameId].num1;
        num2 = games[gameId].num2;
        totalPayout = games[gameId].payout;
        token = games[gameId].token;
        hasEnded = games[gameId].hasEnded;
    }
}

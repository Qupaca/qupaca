// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GameMasterclass/GameMasterclass.sol";
import "../ClaimManager/IClaimManager.sol";
import "../House/IHouse.sol";
// import "../lib/ArrayValidator.sol";

/**
    Roulette PvH Game
 */
contract Roulette is GameMasterclass {

    /** Payout Denom */
    uint256 public constant PAYOUT_DENOM = 10_000; // 0.01x precision (payout of 100 = 0.01x, 10,000 = 1x, 1,000,000 = 100x)

    // constants
    uint256 public constant color_payout = 20_500;             // 2.05x
    uint256 public constant even_odd_payout = 20_500;          // 2.05x
    uint256 public constant half_payout = 20_500;              // 2.05x
    uint256 public constant third_payout = 30_750;             // 3.075x
    uint256 public constant number_payout = 369_000;           // 36.9x

    uint8 public constant MAX_NUMBER = 38; // 38 is 00
    uint8 public constant MIN_NUMBER_TO_ADD = 1;

    uint8 public constant FIRST_THIRD = 39;
    uint8 public constant SECOND_THIRD = 40;
    uint8 public constant THIRD_THIRD = 41;
    uint8 public constant FIRST_COLUMN = 42;
    uint8 public constant SECOND_COLUMN = 43;
    uint8 public constant THIRD_COLUMN = 44;
    uint8 public constant FIRST_HALF = 45;
    uint8 public constant SECOND_HALF = 46;
    uint8 public constant EVEN = 47;
    uint8 public constant ODD = 48;
    uint8 public constant BLACK = 49;
    uint8 public constant RED = 50;
    
    uint8 public constant ZERO = 1;
    uint8 public constant DOUBLE_ZERO = 38;

    /**
        1 - 0
        38 - 00
        39 - first 12 (third)
        40 - second 12 (third)
        41 - third 12 (third)
        42 - first column
        43 - second column
        44 - third column
        45 - first half
        46 - second half
        47 - even
        48 - odd
        49 - black
        50 - red
     */
    uint256 public constant MAX_BET_NUMBER_ENTRY = 50;

    // Number Struct
    struct Number {
        uint8 color;
        bool isInFirstColumn;
        bool isInSecondColumn;
        bool isInThirdColumn;
        bool isInFirstThird;
        bool isInSecondThird;
        bool isInThirdThird;
        bool isInFirstHalf;
        bool isInSecondHalf;
    }
    
    // Mapping from game number to Number Structure
    mapping ( uint8 => Number ) public numbers;

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

        /** Bets Per Game Numbers */
        mapping ( uint8 => uint256 ) betPerNumber;

        /** List Game Numbers */
        uint8[] gameNumbers;
        uint256[] gameBets;

        /** Final Output -- chosen number */
        uint8 chosenNumber;

        /** Unwrap Type */
        uint8 unwrapType;

        /** Payouts */
        uint256 payout;

        /** Whether or not the game has ended and the VRF has called back */
        bool hasEnded;
    }

    // mapping from GameID => Game
    mapping ( uint256 => Game ) public games;

    // request ID => GameID
    mapping ( uint256 => uint256 ) private requestToGame;

    /** Platform Fee Taken Out Of Buy In */
    uint256 public platformFee = 200;

    /** Fee Denominator */
    uint256 private constant FEE_DENOM = 10_000;

    // buy in gas per spin
    uint256 public minBuyInGas;
    uint256 public buyInGasPerGuess;

    address public gasRecipient;

    // min spins
    uint256 public MAX_GUESSES = 60;

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

    constructor(
        /** Constructor Arguments For Master Class */
        uint256 GAME_ID_,

        /** History Manager */
        address history_,

        /** Game Configs */
        uint256 minBuyInGas_,
        uint256 buyInGasPerGuess_,
        address manager_,
        address gasRecipient_

    ) GameMasterclass(GAME_ID_, history_, manager_) {

        // set gas info
        require(gasRecipient_ != address(0));
        minBuyInGas     = minBuyInGas_;     // 0.03 ether;  // = 0.001 ether;
        buyInGasPerGuess = buyInGasPerGuess_; // 0.001 ether; // = 0.00005 ether;
        gasRecipient = gasRecipient_;

        // init mappings
        __initNumbers__();
    }

    // set max guesses
    function setMaxSpins(uint256 newMax) external onlyOwner {
        MAX_GUESSES = newMax;
    }

    function setBuyInGasInfo(uint256 newMin, uint256 newGasPerSpin) external onlyOwner {
        minBuyInGas = newMin;
        buyInGasPerGuess = newGasPerSpin;
    }

    function setPlatformFee(uint256 newPlatform) external onlyOwner {
        require(
            newPlatform <= FEE_DENOM / 10,
            'Cannot Exceed 10%'
        );
        platformFee = newPlatform;
        emit SetPlatformFee(newPlatform);
    }

    function setGasRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0));
        gasRecipient = newRecipient;
    }

    function _playGame(address player, address token, uint256 amount, bytes calldata gameData) internal override {

        // // decode input data
        (
            uint8 unwrapType,
            uint8[] memory gameNumbers,
            uint256[] memory amounts,
            uint256 gameId,
            uint256 partnerId,
            address ref
        ) = abi.decode(gameData, (uint8, uint8[], uint256[], uint256, uint256, address));

        // // avoid stack-too-deep errors
        address _token = token;
        address _player = player;
        uint256 len = gameNumbers.length;
        require(len == amounts.length, 'Invalid Input Length');
        require(len <= MAX_GUESSES, 'Too Many Guesses');

        // // determine gas required to spin
        uint256 gasRequired = minBuyInGas + ( len * buyInGasPerGuess );
        require(
            msg.value >= gasRequired,
            'Invalid Ether Sent For BuyIn Gas'
        );

        // // calculate the bet amount
        uint256 totalBetAmount = _token == address(0) ? msg.value - gasRequired : amount;

        // // take platform fee out of the buy in
        uint256 platformFeeAmount = ( totalBetAmount * platformFee ) / FEE_DENOM;
        totalBetAmount -= platformFeeAmount;

        // // scope the totalAmounts value, as it will be used to validate the amounts
        // {
        uint totalAmounts = 0;
        // // loop through each number, adding to bets mapping as needed
        for (uint i = 0; i < len;) {
            require(
                gameNumbers[i] <= MAX_BET_NUMBER_ENTRY && gameNumbers[i] > 0,
                'Invalid Number Range'
            );
            require(
                amounts[i] > 0,
                'No Bet Amount'
            );
            require(
                games[gameId].betPerNumber[gameNumbers[i]] == 0,
                'Cannot Bet On Same Number Twice'
            );

            totalAmounts += amounts[i];
            games[gameId].betPerNumber[gameNumbers[i]] += amounts[i];

            unchecked {
                ++i;
            }
        }

        // // ensure the amounts passed in matches the value sent
        require(
            totalAmounts <= totalBetAmount,
            'Invalid Bet Amounts'
        );

        // }

        // // validate inputs
        require(
            isValidGameId(gameId),
            'Game ID Already Used'
        );

        TransferHelper.safeTransferETH(gasRecipient, gasRequired);

        // // send to platform receiver
        _processFee(_token, platformFeeAmount, partnerId, ref);

        // // save game data
        games[gameId].unwrapType = unwrapType;
        games[gameId].player = _player;
        games[gameId].betAmount = totalBetAmount;
        games[gameId].token = _token;
        // games[gameId].amountForHouse = totalBetAmount - platformFeeAmount;
        games[gameId].amountForHouse = totalBetAmount;
        games[gameId].gameNumbers = gameNumbers;
        games[gameId].gameBets = amounts;

        // // process points
        _registerBet(_player, totalBetAmount, _token, partnerId);

        // // fetch random number
        _requestRandom(gameId);

        // // add to list of used game ids and history
        _registerGameId(_player, gameId);
        
        // // emit event
        emit GameStarted(_player, gameId);
    }

    function _requestRandom(uint256 gameId) internal {

        // request random words from RNG contract
        uint256 requestId = IRNG(manager.RNG()).generateRequest(
            "fulfillRandomRequest(uint256,uint256[])", 
            1, 
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

        // fetch random number
        uint8 num = uint8(rngList[0] % MAX_NUMBER) + 1;

        // determine payout
        uint256 totalPayout = _getPayout(games[gameId].gameNumbers, games[gameId].gameBets, num);

        // save payout info
        games[gameId].payout = totalPayout;
        games[gameId].chosenNumber = num;

        // handle payouts
        PayoutInfo memory info = PayoutInfo({
            token: games[gameId].token,
            player: games[gameId].player,
            totalToPayout: totalPayout,
            amountForHouse: games[gameId].amountForHouse,
            unwrapType: games[gameId].unwrapType
        });
        _handlePayout(info);

        // emit game ended event
        emit GameEnded(games[gameId].player, gameId, games[gameId].betAmount, totalPayout);
    }

    function getMinBuyInGas(uint8 numGuesses) public view returns (uint256) {
        return minBuyInGas + ( numGuesses * buyInGasPerGuess );
    }

    /**
        1 - 0
        38 - 00
        39 - first 12 (third)
        40 - second 12 (third)
        41 - third 12 (third)
        42 - first column
        43 - second column
        44 - third column
        45 - first half
        46 - second half
        47 - even
        48 - odd
        49 - black
        50 - red

        2 - 1
        3 - 2
        ...
     */
    function _getPayout(uint8[] memory gameNumbers, uint256[] memory bets, uint8 chosenNumber) internal view returns (uint256 totalPayout) {

        // loop through each gameNumber, checking if it either matches chosenNumber, or is in the same category (red/black/column/row)
        uint len = gameNumbers.length;
        for (uint i = 0; i < len;) {

            // define number we are working with
            uint8 selectedNumber = gameNumbers[i];

            // check if this number is a category or a real number
            if (selectedNumber > MAX_NUMBER) {
                // number is either thirds, columns, halves, evens/odds, or colors

                if (selectedNumber == FIRST_THIRD && numbers[chosenNumber].isInFirstThird) {
                    // number is in first third, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);
                } else if (selectedNumber == SECOND_THIRD && numbers[chosenNumber].isInSecondThird) {
                    // number is in second third, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);
                } else if (selectedNumber == THIRD_THIRD && numbers[chosenNumber].isInThirdThird) {
                    // number is in third third, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);
                } else if (selectedNumber == FIRST_COLUMN && numbers[chosenNumber].isInFirstColumn) {
                    // number is in first column, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);
                } else if (selectedNumber == SECOND_COLUMN && numbers[chosenNumber].isInSecondColumn) {
                    // number is in second column, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);
                } else if (selectedNumber == THIRD_COLUMN && numbers[chosenNumber].isInThirdColumn) {
                    // number is in third column, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);
                } else if (selectedNumber == FIRST_HALF && numbers[chosenNumber].isInFirstHalf) {
                    // number is in first half, pay out
                    totalPayout += (( bets[i] * half_payout ) / PAYOUT_DENOM);
                } else if (selectedNumber == SECOND_HALF && numbers[chosenNumber].isInSecondHalf) {
                    // number is in second half, pay out
                    totalPayout += (( bets[i] * half_payout ) / PAYOUT_DENOM);
                
                } else if (selectedNumber == EVEN && chosenNumber > 1 && chosenNumber < MAX_NUMBER && (chosenNumber - 1) % 2 == 0) {
                    // number is even, pay out
                    totalPayout += (( bets[i] * even_odd_payout ) / PAYOUT_DENOM);
                    
                } else if (selectedNumber == ODD && chosenNumber > 1 && chosenNumber < MAX_NUMBER && (chosenNumber - 1) % 2 == 1) {
                    // number is odd, pay out
                    totalPayout += (( bets[i] * even_odd_payout ) / PAYOUT_DENOM);
                
                } else if (selectedNumber == BLACK && numbers[chosenNumber].color == 1) {
                    // number is black, pay out
                    totalPayout += (( bets[i] * color_payout ) / PAYOUT_DENOM);
                } else if (selectedNumber == RED && numbers[chosenNumber].color == 0) {
                    // number is red, pay out
                    totalPayout += (( bets[i] * color_payout ) / PAYOUT_DENOM);
                }


            } else {
                // selectedNumber is a whole number value

                if (selectedNumber == chosenNumber) {
                    // selectedNumber is the chosen number, pay out
                    totalPayout += (( bets[i] * number_payout ) / PAYOUT_DENOM);
                }
            }
            unchecked { ++i; }
        }
    }

    function determinePayout(uint8[] calldata gameNumbers, uint256[] calldata bets, uint8 chosenNumber) external view returns (uint256 totalPayout) {

        // loop through each gameNumber, checking if it either matches chosenNumber, or is in the same category (red/black/column/row)
        uint len = gameNumbers.length;
        for (uint i = 0; i < len;) {

            // define number we are working with
            uint8 selectedNumber = gameNumbers[i];

            // check if this number is a category or a real number
            if (selectedNumber > MAX_NUMBER) {
                // number is either thirds, columns, halves, evens/odds, or colors

                if (selectedNumber == FIRST_THIRD && numbers[chosenNumber].isInFirstThird) {
                    // number is in first third, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);

                } else if (selectedNumber == SECOND_THIRD && numbers[chosenNumber].isInSecondThird) {
                    // number is in second third, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);

                } else if (selectedNumber == THIRD_THIRD && numbers[chosenNumber].isInThirdThird) {
                    // number is in third third, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);

                } else if (selectedNumber == FIRST_COLUMN && numbers[chosenNumber].isInFirstColumn) {
                    // number is in first column, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);

                } else if (selectedNumber == SECOND_COLUMN && numbers[chosenNumber].isInSecondColumn) {
                    // number is in second column, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);

                } else if (selectedNumber == THIRD_COLUMN && numbers[chosenNumber].isInThirdColumn) {
                    // number is in third column, pay out
                    totalPayout += (( bets[i] * third_payout ) / PAYOUT_DENOM);

                } else if (selectedNumber == FIRST_HALF && numbers[chosenNumber].isInFirstHalf) {
                    // number is in first half, pay out
                    totalPayout += (( bets[i] * half_payout ) / PAYOUT_DENOM);

                } else if (selectedNumber == SECOND_HALF && numbers[chosenNumber].isInSecondHalf) {
                    // number is in second half, pay out
                    totalPayout += (( bets[i] * half_payout ) / PAYOUT_DENOM);
                
                } else if (selectedNumber == EVEN && chosenNumber > 1 && chosenNumber < MAX_NUMBER && (chosenNumber - 1) % 2 == 0) {
                    // number is even, pay out
                    totalPayout += (( bets[i] * even_odd_payout ) / PAYOUT_DENOM);
                    
                } else if (selectedNumber == ODD && chosenNumber > 1 && chosenNumber < MAX_NUMBER && (chosenNumber - 1) % 2 == 1) {
                    // number is odd, pay out
                    totalPayout += (( bets[i] * even_odd_payout ) / PAYOUT_DENOM);
                
                } else if (selectedNumber == BLACK && numbers[chosenNumber].color == 1) {
                    // number is black, pay out
                    totalPayout += (( bets[i] * color_payout ) / PAYOUT_DENOM);

                } else if (selectedNumber == RED && numbers[chosenNumber].color == 0) {
                    // number is red, pay out
                    totalPayout += (( bets[i] * color_payout ) / PAYOUT_DENOM);
                }


            } else {
                // selectedNumber is a whole number value

                if (selectedNumber == chosenNumber) {
                    // selectedNumber is the chosen number, pay out
                    totalPayout += (( bets[i] * number_payout ) / PAYOUT_DENOM);
                }
            }
            unchecked { ++i; }
        }
    }

    function __initNumbers__() internal {
        // 0 = red, 1 = black, 2 = green
        // initialize number to color mapping
        numbers[ZERO].color = 2; // 1 = 0
        numbers[2].color = 1; // 2 = 1 ( any number here is 1 more than the actual number )
        numbers[3].color = 0;
        numbers[4].color = 1;
        numbers[5].color = 0;
        numbers[6].color = 1;
        numbers[7].color = 0;
        numbers[8].color = 1;
        numbers[9].color = 0;
        numbers[10].color = 1;
        numbers[11].color = 0;
        numbers[12].color = 0;
        numbers[13].color = 1;
        numbers[14].color = 0;
        numbers[15].color = 1;
        numbers[16].color = 0;
        numbers[17].color = 1;
        numbers[18].color = 0;
        numbers[19].color = 1;
        numbers[20].color = 0;
        numbers[21].color = 0;
        numbers[22].color = 1;
        numbers[23].color = 0;
        numbers[24].color = 1;
        numbers[25].color = 0;
        numbers[26].color = 1;
        numbers[27].color = 0;
        numbers[28].color = 1;
        numbers[29].color = 1;
        numbers[30].color = 0;
        numbers[31].color = 1;
        numbers[32].color = 0;
        numbers[33].color = 1;
        numbers[34].color = 0;
        numbers[35].color = 1;
        numbers[36].color = 0;
        numbers[37].color = 1;
        numbers[DOUBLE_ZERO].color = 2; // 00 = 38

        // initialize third mappings
        for (uint8 i = 2; i < MAX_NUMBER;) {

            uint256 actual_number = ( i - 1 );

            // initialize third mappings
            if (actual_number <= 12) {
                numbers[i].isInFirstThird = true;
            } else if (actual_number <= 24) {
                numbers[i].isInSecondThird = true;
            } else {
                numbers[i].isInThirdThird = true;
            }

            // initialize column mappings
            if (actual_number % 3 == 1) {
                numbers[i].isInFirstColumn = true;
            } else if (actual_number % 3 == 2) {
                numbers[i].isInSecondColumn = true;
            } else {
                numbers[i].isInThirdColumn = true;
            }

            // initialize half mappings
            if (actual_number <= 18) {
                numbers[i].isInFirstHalf = true;
            } else {
                numbers[i].isInSecondHalf = true;
            }

            unchecked { ++i; }
        }
    }

    function getTotalBet(uint8[] calldata _numbers, uint256[] calldata amounts) external pure returns (uint256 totalAmounts) {
        // loop through each number, adding to bets mapping as needed
        uint len = _numbers.length;
        // loop through each number, adding to bets mapping as needed
        for (uint i = 0; i < len;) {
            require(
                _numbers[i] <= MAX_BET_NUMBER_ENTRY && _numbers[i] > 0,
                'Invalid Number Range'
            );
            require(
                amounts[i] > 0,
                'No Bet Amount'
            );
            unchecked {
                totalAmounts += amounts[i];
            }
        }
    }

    function getGameInfo(uint256 gameId) external view returns (
        address player,
        uint256 betAmount,
        uint256 totalPayout,
        address token,
        bool hasEnded,
        uint8 chosenNumber,
        uint8 unwrapType,
        uint8[] memory gameNumbers,
        uint256[] memory betsPerNumbers
    ) {
        player = games[gameId].player;
        betAmount = games[gameId].betAmount;
        totalPayout = games[gameId].payout;
        token = games[gameId].token;
        hasEnded = games[gameId].hasEnded;
        chosenNumber = games[gameId].chosenNumber;
        unwrapType = games[gameId].unwrapType;
        gameNumbers = games[gameId].gameNumbers;

        uint len = games[gameId].gameNumbers.length;    
        betsPerNumbers = new uint256[](len);
        for (uint i = 0; i < len;) {
            betsPerNumbers[i] = games[gameId].betPerNumber[
                games[gameId].gameNumbers[i]
            ];
            unchecked { ++i; }
        }
    }
}
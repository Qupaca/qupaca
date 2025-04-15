//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract HouseDataTracking {

    struct PriceChange {
        uint256 price;
        uint256 timestamp;
    }

    uint256 internal priceChangeIndex;

    mapping ( uint256 => PriceChange ) private priceChanges;

    function log(uint256 price) internal {
        priceChanges[priceChangeIndex] = PriceChange(price, block.timestamp);
        unchecked {
            ++priceChangeIndex;
        }
    }

    function getPriceChange(uint256 index) external view returns (uint256, uint256) {
        return (priceChanges[index].price, priceChanges[index].timestamp);
    }

    function getPriceChangeCount() external view returns (uint256) {
        return priceChangeIndex;
    }

    function batchGetPriceChange(uint256 startIndex, uint256 endIndex) external view returns (uint256[] memory, uint256[] memory) {
        if (endIndex > priceChangeIndex) {
            endIndex = priceChangeIndex;
        }
        if (startIndex >= endIndex || priceChangeIndex == 0) {
            return (new uint256[](0), new uint256[](0));
        }

        uint256[] memory prices = new uint256[](endIndex - startIndex);
        uint256[] memory timestamps = new uint256[](endIndex - startIndex);

        for (uint256 i = startIndex; i < endIndex;) {
            prices[i - startIndex] = priceChanges[i].price;
            timestamps[i - startIndex] = priceChanges[i].timestamp;
            unchecked { ++i; }
        }

        return (prices, timestamps);
    }

    function getListOfPriceChanges(uint256[] calldata indexes) external view returns (uint256[] memory, uint256[] memory) {
        uint len = indexes.length;
        uint256[] memory prices = new uint256[](len);
        uint256[] memory timestamps = new uint256[](len);

        for (uint256 i = 0; i < len;) {
            prices[i] = priceChanges[indexes[i]].price;
            timestamps[i] = priceChanges[indexes[i]].timestamp;
            unchecked { ++i; }
        }

        return (prices, timestamps);
    }

    function getEvenlySplitPriceChanges(uint256 numDataPoints) external view returns (uint256[] memory, uint256[] memory) {
        if (priceChangeIndex == 0) {
            return (new uint256[](0), new uint256[](0));
        }

        if (numDataPoints > priceChangeIndex) {
            numDataPoints = priceChangeIndex;
        }

        uint256[] memory prices = new uint256[](numDataPoints);
        uint256[] memory timestamps = new uint256[](numDataPoints);

        // calculate step, how many price changes to skip
        uint256 step = priceChangeIndex / ( numDataPoints - 1 );

        for (uint256 i = 0; i < numDataPoints - 1;) {
            prices[i] = priceChanges[i * step].price;
            timestamps[i] = priceChanges[i * step].timestamp;
            unchecked { ++i; }
        }

        // set most recent prices
        prices[numDataPoints - 1] = priceChanges[priceChangeIndex - 1].price;
        timestamps[numDataPoints - 1] = priceChanges[priceChangeIndex - 1].timestamp;

        return (prices, timestamps);
    }

    function getApproxAverageEvenlySplitPriceChanges(uint256 numDataPoints, uint256 averageCount) external view returns (uint256[] memory, uint256[] memory) {
        if (priceChangeIndex == 0) {
            return (new uint256[](0), new uint256[](0));
        }

        if (numDataPoints > priceChangeIndex) {
            numDataPoints = priceChangeIndex;
        }

        // create arrays to store prices and timestamps
        uint256[] memory prices = new uint256[](numDataPoints);
        uint256[] memory timestamps = new uint256[](numDataPoints);

        // calculate step, how many price changes to skip
        uint256 step = priceChangeIndex / ( numDataPoints - 1 );
        if (step <= averageCount) {
            averageCount = step - 1;
        }

        // loop through data points, determining average price changes around each step
        for (uint256 i = 0; i < numDataPoints - 1;) {
            
            // find average price changes around each step
            uint256 sumPrice = 0;
            uint256 sumTimestamp = 0;
            for (uint j = 0; j < averageCount;) {
                unchecked { 
                    sumPrice += priceChanges[(i * step) + j].price;
                    sumTimestamp += priceChanges[(i * step) + j].timestamp;
                    ++j; 
                }
            }

            prices[i] = sumPrice / averageCount;
            timestamps[i] = sumTimestamp / averageCount;
            unchecked { ++i; }
        }

        // set most recent prices
        prices[numDataPoints - 1] = priceChanges[priceChangeIndex - 1].price;
        timestamps[numDataPoints - 1] = priceChanges[priceChangeIndex - 1].timestamp;

        return (prices, timestamps);
    }

    function getAverageTimeAndPrice(uint256[] calldata indexes) external view returns (uint256, uint256) {
        uint len = indexes.length;
        uint256 sumPrice;
        uint256 sumTimestamp;

        for (uint256 i = 0; i < len;) {
            unchecked {
                sumPrice += priceChanges[indexes[i]].price;
                sumTimestamp += priceChanges[indexes[i]].timestamp;
                ++i;
            }
        }

        return (sumPrice / len, sumTimestamp / len);
    }
}
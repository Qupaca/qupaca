// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../GovernanceManager/PVPOwnable.sol";
import "../lib/Address.sol";
import "../GameMasterclass/IGame.sol";

contract GameCredits is PVPOwnable {

    mapping ( address => uint256 ) public currentValue;

    struct Gift {
        uint256 value;
        address sender;
        address recipient;
    }
    mapping ( uint256 => Gift ) public gifts;

    mapping ( address => uint256[] ) public giftsSent;
    mapping ( address => uint256[] ) public giftsReceived;

    address[] public allGiftedUsers;

    uint256 public giftNonce;

    uint256 public minGift;

    modifier ensureGame(address game) {
        require(
            manager.isGame(game),
            "Invalid Game"
        );
        _;
    }

    constructor(uint256 minGift_) {
        minGift = minGift_;
    }

    function setMinGift(uint256 _minGift) external onlyOwner {
        minGift = _minGift;
    }

    function withdrawETH(uint256 amount, address to) external onlyOwner {
        (bool s,) = payable(to).call{value: amount}("");
        require(s);
    }

    function withdrawToken(address token, uint256 amount, address to) external onlyOwner {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeTransfer: transfer failed'
        );
    }

    function credit(address user) external payable {
        require(msg.value >= minGift, "Invalid Value");
        require(user != address(0), "Invalid User");
        require(user != msg.sender, "Cannot Gift Yourself");

        // add value to user
        unchecked {
            currentValue[user] += msg.value;
        }

        // store gift
        gifts[giftNonce] = Gift(msg.value, msg.sender, user);

        // store gift in user's history
        giftsSent[msg.sender].push(giftNonce);

        // add user to allGiftedUsers if they have no gifts
        if (giftsReceived[user].length == 0) {
            allGiftedUsers.push(user);
        }

        // store gift in recipient's history
        giftsReceived[user].push(giftNonce);

        // increment gift nonce
        unchecked { ++giftNonce; }
    }

    function playGame(
        address game,
        uint256 value,
        bytes calldata data
    ) external payable ensureGame(game) {

        // use the value
        _useValue(msg.sender, value);

        // execute the game function
        IGame(game).play{value: (value + msg.value)}(msg.sender, address(0), 0, data);
    }

    function _useValue(address user, uint256 value) internal {

        // fetch remaining value
        uint256 remainingValue = currentValue[user];
        require(remainingValue > 0, "Invalid Value");

        // quote value needed for this game
        require(value <= remainingValue, "Insufficient Value");
        require(value > 0, "No Value to Use");

        // burn credit if value is equal to remaining value
        unchecked {
            currentValue[user] -= value;
        }
    }

    function getGiftsSent(address user) external view returns (uint256[] memory) {
        return giftsSent[user];
    }

    function getGiftsReceived(address user) external view returns (uint256[] memory) {
        return giftsReceived[user];
    }

    function getAllGiftedUsers() external view returns (address[] memory) {
        return allGiftedUsers;
    }

    function getNumberOfGiftedUsers() external view returns (uint256) {
        return allGiftedUsers.length;
    }

    function paginateGiftedUsers(uint256 startIndex, uint256 endIndex) external view returns (address[] memory) {
        uint256 len = allGiftedUsers.length;
        if (endIndex > len) {
            endIndex = len;
        }
        address[] memory users = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex;) {
            users[i - startIndex] = allGiftedUsers[i];
            unchecked { ++i; }
        }
        return users;
    }

    function paginateGiftsSent(address user, uint256 startIndex, uint256 endIndex) external view returns(uint256[] memory) {
        uint256 lenSent = giftsSent[user].length;
        if (endIndex > lenSent) {
            endIndex = lenSent;
        }
        uint256[] memory sent = new uint256[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex;) {
            sent[i - startIndex] = giftsSent[user][i];
            unchecked { ++i; }
        }
        return sent;
    }

    function paginateGiftsReceived(address user, uint256 startIndex, uint256 endIndex) external view returns(uint256[] memory) {
        uint256 lenReceived = giftsReceived[user].length;
        if (endIndex > lenReceived) {
            endIndex = lenReceived;
        }
        uint256[] memory received = new uint256[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex;) {
            received[i - startIndex] = giftsReceived[user][i];
            unchecked { ++i; }
        }
        return received;
    }

    function getGiftInfo(uint256[] calldata giftIds) external view returns (
        uint256[] memory values,
        address[] memory senders,
        address[] memory recipients
    ) {
        uint256 len = giftIds.length;
        values = new uint256[](len);
        senders = new address[](len);
        recipients = new address[](len);
        for (uint256 i = 0; i < len;) {
            values[i] = gifts[giftIds[i]].value;
            senders[i] = gifts[giftIds[i]].sender;
            recipients[i] = gifts[giftIds[i]].recipient;
            unchecked { ++i; }
        }
    }

    function getGiftInfo(address user) external view returns (
        uint256[] memory valuesSent,
        address[] memory usersSent,
        uint256[] memory valuesReceived,
        address[] memory receivedFrom
    ) {
        uint256[] memory sent = giftsSent[user];
        uint256[] memory received = giftsReceived[user];
        uint256 lenSent = sent.length;
        uint256 lenReceived = received.length;
        valuesSent = new uint256[](lenSent);
        usersSent = new address[](lenSent);
        valuesReceived = new uint256[](lenReceived);
        receivedFrom = new address[](lenReceived);
        for (uint256 i = 0; i < lenSent;) {
            valuesSent[i] = gifts[sent[i]].value;
            usersSent[i] = gifts[sent[i]].recipient;
            unchecked { ++i; }
        }
        for (uint256 i = 0; i < lenReceived;) {
            valuesReceived[i] = gifts[received[i]].value;
            receivedFrom[i] = gifts[received[i]].sender;
            unchecked { ++i; }
        }
    }

    function paginateGiftsSentInfo(address user, uint256 startIndex, uint256 endIndex) external view returns(
        uint256[] memory valuesSent,
        address[] memory usersSent
    ) {
        uint256 lenSent = giftsSent[user].length;
        if (endIndex > lenSent) {
            endIndex = lenSent;
        }
        valuesSent = new uint256[](endIndex - startIndex);
        usersSent = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex;) {
            valuesSent[i - startIndex] = gifts[giftsSent[user][i]].value;
            usersSent[i - startIndex] = gifts[giftsSent[user][i]].recipient;
            unchecked { ++i; }
        }
    }

    function paginateGiftsReceivedInfo(address user, uint256 startIndex, uint256 endIndex) external view returns(
        uint256[] memory valuesReceived,
        address[] memory receivedFrom
    ) {
        uint256 lenReceived = giftsReceived[user].length;
        if (endIndex > lenReceived) {
            endIndex = lenReceived;
        }
        valuesReceived = new uint256[](endIndex - startIndex);
        receivedFrom = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex;) {
            valuesReceived[i - startIndex] = gifts[giftsReceived[user][i]].value;
            receivedFrom[i - startIndex] = gifts[giftsReceived[user][i]].sender;
            unchecked { ++i; }
        }
    }
}
//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IRNG {
    function generateRequest(string memory functionSig , uint8 rngCount, uint256 numConfirmations,address clientWalletAddress) external returns(uint256);
}

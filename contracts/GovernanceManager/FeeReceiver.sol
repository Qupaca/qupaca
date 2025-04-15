//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/IERC20.sol";
import "../lib/TransferHelper.sol";
import "../lib/Ownable.sol";
import "../Referrals/IReferralManager.sol";
import "../ProjectTokens/IProjectTokensManager.sol";
import "./IFeeRecipient.sol";
import "./IGovernanceManager.sol";
import "../ProjectTokens/IWrappedAsset.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
}

contract FeeReceiver is Ownable, IFeeRecipient {

    // list of all recipients
    address[] public recipients;

    // maps address to allocation of points
    mapping ( address => uint256 ) public allocation;
    mapping ( address => bool ) public unwrapForUser;

    // total points allocated
    uint256 public totalAllocation;

    // Governance Manager 
    address public manager;

    // tracks token wagered to fees collected
    mapping ( address => uint256 ) public totalFees;

    // Partner cut
    uint256 public partnerCut = 10;

    // Referral cut
    uint256 public referralCut = 5;

    // WETH
    IWETH public immutable WETH;

    modifier onlyGame() {
        require(
            IGovernanceManager(manager).isGame(msg.sender),
            'UnAuthorized'
        );
        _;
    }

    constructor(
        address _WETH,
        address _manager
    ) {
        WETH = IWETH(_WETH);
        manager = _manager;
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        TransferHelper.safeTransfer(token, to, amount);
    }

    function withdrawETH(address to, uint256 amount) external onlyOwner {
        _sendETH(to, amount);
    }

    function setGovernanceManager(address newManager) external onlyOwner {
        manager = newManager;
    }

    function setReferralCut(uint256 newCut) external onlyOwner {
        referralCut = newCut;
    }

    function setPartnerCut(uint256 newCut) external onlyOwner {
        partnerCut = newCut;
    }

    function setUnwrapForUser(address user, bool unwrap) external onlyOwner {
        unwrapForUser[user] = unwrap;
    }

    function addRecipient(address newRecipient, uint256 newAllocation, bool unwrapForAddr) external onlyOwner {
        require(
            allocation[newRecipient] == 0,
            'Already Added'
        );

        // add to list
        recipients.push(newRecipient);

        // set allocation and increase total allocation
        allocation[newRecipient] = newAllocation;
        unwrapForUser[newRecipient] = unwrapForAddr;
        unchecked {
            totalAllocation += newAllocation;
        }
    }

    function takeFee(address token, uint256 feeAmount, uint256 partner, address ref) external override payable onlyGame {

        // amount to use in calculations
        uint256 amount = token == address(0) ? msg.value : feeAmount;

        // increment total fees collected
        unchecked {
            totalFees[token] += amount;
        }

        // return out if data not supported
        if (amount == 0) {
            return;
        }

        // fetch the referral manager if ref exists
        if (ref != address(0) && ref != tx.origin) {
            address referralManager = IGovernanceManager(manager).referralManager();
            if (referralManager != address(0)) {
                
                // calculate ref fee
                uint256 refCut = ( amount * referralCut ) / 100;

                // if ref cut is not zero
                if (refCut > 0) {

                    // if token is ETH, deposit into WETH and transfer, else transfer
                    if (token == address(0)) {
                        WETH.deposit{value: refCut}();
                        WETH.transfer(ref, refCut);
                    } else {
                        TransferHelper.safeTransfer(token, ref, refCut);
                    }

                    // log rewards in referral manager
                    IReferralManager(referralManager).addRewards(ref, token, refCut);
                }
            }
        }
        
        // check if the partner themselves have a wallet to receive funds, and if someone referred the partner to us
        if (partner > 0) {

            // fetch partner info
            address partnerFeeReceiver = IProjectTokensManager(IGovernanceManager(manager).projectTokens()).getFundReceiver(partner);
            if (partnerFeeReceiver != address(0)) {
                uint256 partnerAmount = ( amount * partnerCut ) / 100;
                if (partnerAmount == 0) {
                    return;
                }

                // send partnerAmount
                if (token == address(0)) {
                    TransferHelper.safeTransferETH(partnerFeeReceiver, ( amount * partnerCut ) / 100);
                } else {
                    TransferHelper.safeTransfer(token, partnerFeeReceiver, ( amount * partnerCut ) / 100);
                }
            }
        }
    }

    function removeRecipient(address recipient) external onlyOwner {

        // ensure recipient is in the system
        uint256 allocation_ = allocation[recipient];
        require(
            allocation_ > 0,
            'User Not Present'
        );

        // delete allocation, subtract from total allocation
        delete allocation[recipient];
        unchecked {
            totalAllocation -= allocation_;
        }

        // remove address from array
        uint index = recipients.length;
        for (uint i = 0; i < recipients.length;) {
            if (recipients[i] == recipient) {
                index = i;
                break;
            }
            unchecked { ++i; }
        }
        require(
            index < recipients.length,
            'Recipient Not Found'
        );

        // swap positions with last element then pop last element off
        recipients[index] = recipients[recipients.length - 1];
        recipients.pop();
    }

    function setAllocation(address recipient, uint256 newAllocation) external onlyOwner {

        // ensure recipient is in the system
        uint256 allocation_ = allocation[recipient];
        require(
            allocation_ > 0,
            'User Not Present'
        );

        // adjust their allocation and the total allocation
        allocation[recipient] = ( allocation[recipient] + newAllocation ) - allocation_;
        totalAllocation = ( totalAllocation + newAllocation ) - allocation_;
    }

    function triggerTokens(address[] calldata tokens) external {

        uint len = tokens.length;
        for (uint i = 0; i < len;) {
            triggerToken(tokens[i]);
            unchecked { ++i; }
        }
    }

    function triggerToken(address token) public {

        // get balance of token
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) {
            return;
        }

        // split balance into distributions
        uint256[] memory distributions = splitAmount(amount);

        // transfer distributions to each recipient
        uint len = distributions.length;
        for (uint i = 0; i < len;) {
            _send(token, recipients[i], distributions[i]);
            unchecked { ++i; }
        }
    }

    function triggerETH() external {

        // Ensure an ETH balance
        require(
            address(this).balance > 0,
            'Zero Amount'
        );

        // split balance into distributions
        uint256[] memory distributions = splitAmount(address(this).balance);

        // transfer distributions to each recipient
        uint len = distributions.length;
        for (uint i = 0; i < len;) {
            _sendETH(recipients[i], distributions[i]);
            unchecked { ++i; }
        }
    }

    function _sendETH(address to, uint amount) internal {
        TransferHelper.safeTransferETH(to, amount);
    }

    function _send(address token, address to, uint256 amount) internal {
        if (to == address(0) || amount == 0) {
            return;
        }
        if (token == address(0)) {
            _sendETH(to, amount);
        } else {
            if (IProjectTokensManager(IGovernanceManager(manager).projectTokens()).isWrappedAsset(token) && unwrapForUser[to]) {
                IWrappedAsset(token).unwrapTo(amount, to);
            } else {
                TransferHelper.safeTransfer(token, to, amount);
            }
        }
    }

    function getRecipients() external view returns (address[] memory) {
        return recipients;
    }

    function splitAmount(uint256 amount) public view returns (uint256[] memory distributions) {

        // length of recipient list
        uint256 len = recipients.length;
        distributions = new uint256[](len);

        // loop through recipients, setting their allocations
        for (uint i = 0; i < len;) {
            distributions[i] = ( ( amount * allocation[recipients[i]] ) / totalAllocation );
            unchecked { ++i; }
        }
    }

    receive() external payable {}
}
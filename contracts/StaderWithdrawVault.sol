pragma solidity ^0.8.16;

import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IStaderOperatorRegistry.sol';
import './interfaces/IStaderNodeWithdrawManager.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderWithdrawVault is Initializable, AccessControlUpgradeable {
    bytes32 public constant POOL_MANAGER = keccak256('POOL_MANAGER');
    IStaderOperatorRegistry public staderOperatorRegistry;
    address payable public staderPoolManager;
    address payable public nodeWithdrawManager;
    address payable public staderTreasury;
    uint256 public validatorDeposit;
    uint256 public protocolCommission;

    function initialize(address _owner) external initializer {
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev skimmed rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        // emit ETHReceived(msg.value);
    }

    function transferUserShareToPoolManager(
        uint256 _operatorID,
        uint256 _userDeposit,
        bytes memory _pubKey,
        bool _withdrawStatus
    ) external onlyRole(POOL_MANAGER) {
        uint256 userShare = calculateUserShare(_userDeposit, _withdrawStatus);
        uint256 staderFeeShare = calculateStaderFee(_userDeposit, _withdrawStatus);
        uint256 nodeShare = calculateNodeShare(validatorDeposit - _userDeposit, _userDeposit, _withdrawStatus);
        address nodeOperator = staderOperatorRegistry.operatorByOperatorId(_operatorID);
        (, , , address operatorRewardAddress, , , , ) = staderOperatorRegistry.operatorRegistry(nodeOperator);
        IStaderStakePoolManager(staderPoolManager).receiveWithdrawVaultUserShare{value: userShare}();
        _sendValue(staderTreasury, staderFeeShare);
        if (_withdrawStatus) IStaderNodeWithdrawManager(nodeWithdrawManager).processNodeWithdraw(_pubKey);
        else _sendValue(payable(operatorRewardAddress), nodeShare);
    }

    function calculateUserShare(uint256 _userDeposit, bool _withdrawStatus) public view returns (uint256) {
        if (_withdrawStatus) {
            if (address(this).balance > validatorDeposit) {
                return
                    _userDeposit +
                    ((address(this).balance - validatorDeposit) * _userDeposit * (100 - protocolCommission)) /
                    (validatorDeposit * 100);
            } else if (address(this).balance < _userDeposit) {
                return address(this).balance;
            } else {
                return _userDeposit;
            }
        }
        return (address(this).balance * _userDeposit * (100 - protocolCommission)) / (validatorDeposit * 100);
    }

    function calculateNodeShare(
        uint256 _nodeDeposit,
        uint256 _userDeposit,
        bool _withdrawStatus
    ) public view returns (uint256) {
        require(_nodeDeposit + _userDeposit == validatorDeposit, 'invalid input');
        if (_withdrawStatus) {
            if (address(this).balance > validatorDeposit) {
                return
                    address(this).balance -
                    calculateUserShare(_userDeposit, _withdrawStatus) -
                    calculateStaderFee(_userDeposit, _withdrawStatus);
            } else if (address(this).balance <= _userDeposit) {
                return 0;
            } else {
                return address(this).balance - _userDeposit;
            }
        }
        return
            (address(this).balance * _nodeDeposit) /
            validatorDeposit +
            ((address(this).balance * _userDeposit * protocolCommission) / (validatorDeposit * 100 * 2));
    }

    function calculateStaderFee(uint256 _userDeposit, bool _withdrawStatus) public view returns (uint256) {
        if (_withdrawStatus) {
            if (address(this).balance > validatorDeposit) {
                return
                    ((address(this).balance - validatorDeposit) * _userDeposit * protocolCommission) /
                    (validatorDeposit * 100 * 2);
            } else {
                return 0;
            }
        }
        return (address(this).balance * _userDeposit * protocolCommission) / (validatorDeposit * 100 * 2);
    }

    function _sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, 'Address: insufficient balance');

        // solhint-disable-next-line
        (bool success, ) = recipient.call{value: amount}('');
        require(success, 'Address: unable to send value, recipient may have reverted');
    }
}
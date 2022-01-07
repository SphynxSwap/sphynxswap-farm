// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.7.5;

interface ITeller {
    function newBond( 
        address _bonder, 
        address _principal,
        uint _principalPaid,
        uint _payout, 
        uint _expires,
        uint _BID
    ) external returns ( uint index_ );
    function redeem(address _bonder, uint256 BID_) external returns (uint256);
    function getReward() external;
    function setFEReward(uint256 reward) external;
    function percentVestedFor(address _bonder, uint256 _BID) external view returns (uint256 percentVested_);
    function pendingPayoutFor( address _depositor, uint256 _BID ) external view returns ( uint pendingPayout_ );
}
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "../libs/SafeMath.sol";
import "../libs/SafeERC20.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IStaking.sol";
import "../interfaces/IOwnable.sol";
import "../interfaces/IsSPH.sol";
import "../interfaces/ITeller.sol";

import "../types/SphynxAccessControlled.sol";

contract BondTeller is ITeller, SphynxAccessControlled {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IsSPH;

    /* ========== EVENTS =========== */

    event BondCreated(address indexed bonder, uint256 payout, uint256 expires);
    event Redeemed(address indexed bonder, uint256 payout);

    /* ========== MODIFIERS ========== */

    modifier onlyDepository() {
        require(msg.sender == depository, "Only depository");
        _;
    }

    /* ========== STRUCTS ========== */

    // Info for bond holder
    struct Bond {
        address principal; // token used to pay for bond
        uint256 principalPaid; // amount of principal token paid for bond
        uint256 payout; // sSPH remaining to be paid. agnostic balance
        uint256 vested; // Block when bond is vested
        uint256 created; // time bond was created
        uint256 redeemed; // time bond was redeemed
    }

    /* ========== STATE VARIABLES ========== */

    address internal immutable depository; // contract where users deposit bonds
    IStaking internal immutable staking; // contract to stake payout
    ITreasury internal immutable treasury;
    IERC20 internal immutable SPH;
    IsSPH internal immutable sSPH; // payment token

    mapping(address => mapping(uint256 => Bond)) public bonderInfo; // user data
    mapping(address => uint256[]) public indexesFor; // user bond indexes

    mapping(address => uint256) public FERs; // front end operator rewards
    uint256 public feReward;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _depository,
        address _staking,
        address _treasury,
        address _ohm,
        address _sSPH,
        address _authority
    ) SphynxAccessControlled(ISphynxAuthority(_authority)) {
        require(_depository != address(0), "Zero address: Depository");
        depository = _depository;
        require(_staking != address(0), "Zero address: Staking");
        staking = IStaking(_staking);
        require(_treasury != address(0), "Zero address: Treasury");
        treasury = ITreasury(_treasury);
        require(_ohm != address(0), "Zero address: SPH");
        SPH = IERC20(_ohm);
        require(_sSPH != address(0), "Zero address: sSPH");
        sSPH = IsSPH(_sSPH);
    }

    /* ========== DEPOSITORY FUNCTIONS ========== */

    /**
     * @notice add new bond payout to user data
     * @param _bonder address
     * @param _principal address
     * @param _principalPaid uint256
     * @param _payout uint256
     * @param _expires uint256
     * @param _BID uint256
     * @return index_ uint256
     */
    function newBond(
        address _bonder,
        address _principal,
        uint256 _principalPaid,
        uint256 _payout,
        uint256 _expires,
        uint256 _BID
    ) external override onlyDepository returns (uint256 index_) {
        uint256 reward = _payout.mul(feReward).div(10_000);
        treasury.mint(address(this), _payout.add(reward));

        SPH.approve(address(staking), _payout);
        staking.stake(address(this), _payout, true, true);

        FERs[_bonder] = FERs[_bonder].add(reward); // front end operator reward
        
        bonderInfo[_bonder][_BID] = Bond({
            principal: _principal,
            principalPaid: _principalPaid,
            created: block.number,
            vested: _expires,
            payout: sSPH.toG(_payout).add(sSPH.toG(bonderInfo[_bonder][_BID].payout)),
            redeemed: 0
        });
        index_ = 0;
    }

    // pay reward to front end operator
    function getReward() external override {
        uint256 reward = FERs[msg.sender];
        FERs[msg.sender] = 0;
        SPH.safeTransfer(msg.sender, reward);
    }

    /**
     *  @notice redeem bond for user
     *  @param _bonder address
     *  @param BID_ calldata uint256
     *  @return dues uint256
     */
    function redeem(address _bonder, uint256 BID_) public override returns (uint256 dues) {
        Bond memory info = bonderInfo[ _bonder ][BID_];
        uint percentVested = percentVestedFor( _bonder, BID_ ); // (blocks since last interaction / vesting term remaining)
        uint256 reward = FERs[msg.sender];

        if ( percentVested >= 10000 ) { // if fully vested
            delete bonderInfo[ _bonder ][BID_]; // delete user info
            dues = sSPH.fromG(info.payout);
            pay(_bonder, dues);
            FERs[msg.sender] = 0;
            SPH.safeTransfer(msg.sender, reward);   
            emit Redeemed(_bonder, dues);

        } else { // if unfinished
            // calculate payout vested
            uint payout = info.payout.mul( percentVested ).div( 10000 );
            // store updated deposit info
            bonderInfo[ _bonder ][BID_] = Bond({
                principal: bonderInfo[ _bonder ][BID_].principal,
                payout: info.payout.sub( payout ),
                vested: info.vested.sub( block.number.sub( info.created ) ),
                created: block.number,
                principalPaid: bonderInfo[ _bonder ][BID_].principalPaid,
                redeemed: 0
            });
            dues = sSPH.fromG(payout);
            pay(_bonder, dues);
            emit Redeemed(_bonder, dues);
        }
        return dues;
    }

    

    /* ========== OWNABLE FUNCTIONS ========== */

    // set reward for front end operator (4 decimals. 100 = 1%)
    function setFEReward(uint256 reward) external override onlyPolicy {
        feReward = reward;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     *  @notice send payout
     *  @param _amount uint256
     */
    function pay(address _bonder, uint256 _amount) internal {
        sSPH.safeTransfer(_bonder, _amount);
    }

    
     /**
     *  @notice calculate amount of OHM available for claim by depositor
     *  @param _depositor address
     *  @return pendingPayout_ uint
     */
    function pendingPayoutFor( address _depositor, uint256 _BID ) external override view returns ( uint pendingPayout_ ) {
        uint percentVested = percentVestedFor( _depositor, _BID);
        uint payout = bonderInfo[ _depositor ][_BID].payout;

        if ( percentVested >= 10000 ) {
            pendingPayout_ = payout;
        } else {
            pendingPayout_ = payout.mul( percentVested ).div( 10000 );
        }
    }
    /**
     * @notice calculate how far into vesting a depositor is
     * @param _bonder address
     * @param _BID uint256
     * @return percentVested_ uint256
     */
    function percentVestedFor(address _bonder, uint256 _BID) public view override returns (uint256 percentVested_) {

        Bond memory bond = bonderInfo[ _bonder ][_BID] ;
        uint blocksSinceLast = block.number.sub( bond.created );
        uint vesting = bond.vested;

        if ( vesting > 0 ) {
            percentVested_ = blocksSinceLast.mul( 10000 ).div( vesting );
        } else {
            percentVested_ = 0;
        }
    }
}

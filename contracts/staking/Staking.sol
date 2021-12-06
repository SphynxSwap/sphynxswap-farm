// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "../libs/SafeMath.sol";
import "../libs/SafeERC20.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/IsSPH.sol";
import "../interfaces/IgSPH.sol";
import "../interfaces/IDistributor.sol";

import "../types/SphynxAccessControlled.sol";

contract SphynxStaking is SphynxAccessControlled {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IsSPH;
    using SafeERC20 for IgSPH;

    /* ========== EVENTS ========== */

    event DistributorSet(address distributor);
    event WarmupSet(uint256 warmup);

    /* ========== DATA STRUCTURES ========== */

    struct Epoch {
        uint256 length;
        uint256 number;
        uint256 endBlock;
        uint256 distribute;
    }

    struct Claim {
        uint256 deposit;
        uint256 gons;
        uint256 expiry;
        bool lock; // prevents malicious delays for claim
    }

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable SPH;
    IsSPH public immutable sSPH;
    IgSPH public immutable gSPH;

    Epoch public epoch;

    address public distributor;

    mapping(address => Claim) public warmupInfo;
    uint256 public warmupPeriod;
    uint256 private gonsInWarmup;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _ohm,
        address _sSPH,
        address _gSPH,
        uint256 _epochLength,
        uint256 _firstEpochNumber,
        uint256 _firstEpochBlock,
        address _authority
    ) SphynxAccessControlled(ISphynxAuthority(_authority)) {
        require(_ohm != address(0), "Zero address: SPH");
        SPH = IERC20(_ohm);
        require(_sSPH != address(0), "Zero address: sSPH");
        sSPH = IsSPH(_sSPH);
        require(_gSPH != address(0), "Zero address: gSPH");
        gSPH = IgSPH(_gSPH);

        epoch = Epoch({length: _epochLength, number: _firstEpochNumber, endBlock: _firstEpochBlock, distribute: 0});
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice stake SPH to enter warmup
     * @param _to address
     * @param _amount uint
     * @param _claim bool
     * @param _rebasing bool
     * @return uint
     */
    function stake(
        address _to,
        uint256 _amount,
        bool _rebasing,
        bool _claim
    ) external returns (uint256) {
        rebase();

        SPH.safeTransferFrom(msg.sender, address(this), _amount);

        if (_claim && warmupPeriod == 0) {
            return _send(_to, _amount, _rebasing);
        } else {
            Claim memory info = warmupInfo[_to];
            if (!info.lock) {
                require(_to == msg.sender, "External deposits for account are locked");
            }

            warmupInfo[_to] = Claim({
                deposit: info.deposit.add(_amount),
                gons: info.gons.add(sSPH.gonsForBalance(_amount)),
                expiry: epoch.number.add(warmupPeriod),
                lock: info.lock
            });

            gonsInWarmup = gonsInWarmup.add(sSPH.gonsForBalance(_amount));

            return _amount;
        }
    }

    /**
     * @notice retrieve stake from warmup
     * @param _to address
     * @param _rebasing bool
     * @return uint
     */
    function claim(address _to, bool _rebasing) public returns (uint256) {
        Claim memory info = warmupInfo[_to];

        if (!info.lock) {
            require(_to == msg.sender, "External claims for account are locked");
        }

        if (epoch.number >= info.expiry && info.expiry != 0) {
            delete warmupInfo[_to];

            gonsInWarmup = gonsInWarmup.sub(info.gons);

            return _send(_to, sSPH.balanceForGons(info.gons), _rebasing);
        }
        return 0;
    }

    /**
     * @notice forfeit stake and retrieve SPH
     * @return uint
     */
    function forfeit() external returns (uint256) {
        Claim memory info = warmupInfo[msg.sender];
        delete warmupInfo[msg.sender];

        gonsInWarmup = gonsInWarmup.sub(info.gons);

        SPH.safeTransfer(msg.sender, info.deposit);

        return info.deposit;
    }

    /**
     * @notice prevent new deposits or claims from ext. address (protection from malicious activity)
     */
    function toggleLock() external {
        warmupInfo[msg.sender].lock = !warmupInfo[msg.sender].lock;
    }

    /**
     * @notice redeem sSPH for SPHs
     * @param _to address
     * @param _amount uint
     * @param _trigger bool
     * @param _rebasing bool
     * @return amount_ uint
     */
    function unstake(
        address _to,
        uint256 _amount,
        bool _trigger,
        bool _rebasing
    ) external returns (uint256 amount_) {
        if (_trigger) {
            rebase();
        }

        amount_ = _amount;
        if (_rebasing) {
            sSPH.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            gSPH.burn(msg.sender, _amount); // amount was given in gSPH terms
            amount_ = gSPH.balanceFrom(_amount); // convert amount to SPH terms
        }

        SPH.safeTransfer(_to, amount_);
    }

    /**
     * @notice convert _amount sSPH into gBalance_ gSPH
     * @param _to address
     * @param _amount uint
     * @return gBalance_ uint
     */
    function wrap(address _to, uint256 _amount) external returns (uint256 gBalance_) {
        sSPH.safeTransferFrom(msg.sender, address(this), _amount);

        gBalance_ = gSPH.balanceTo(_amount);
        gSPH.mint(_to, gBalance_);
    }

    /**
     * @notice convert _amount gSPH into sBalance_ sSPH
     * @param _to address
     * @param _amount uint
     * @return sBalance_ uint
     */
    function unwrap(address _to, uint256 _amount) external returns (uint256 sBalance_) {
        gSPH.burn(msg.sender, _amount);

        sBalance_ = gSPH.balanceFrom(_amount);
        sSPH.safeTransfer(_to, sBalance_);
    }

    /**
     * @notice trigger rebase if epoch over
     */
    function rebase() public {
        if (epoch.endBlock <= block.number) {
            sSPH.rebase(epoch.distribute, epoch.number);

            epoch.endBlock = epoch.endBlock.add(epoch.length);
            epoch.number++;

            if (distributor != address(0)) {
                IDistributor(distributor).distribute();
            }

            if (contractBalance() <= totalStaked()) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = contractBalance().sub(totalStaked());
            }
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice send staker their amount as sSPH or gSPH
     * @param _to address
     * @param _amount uint
     * @param _rebasing bool
     */
    function _send(
        address _to,
        uint256 _amount,
        bool _rebasing
    ) internal returns (uint256) {
        if (_rebasing) {
            sSPH.safeTransfer(_to, _amount); // send as sSPH (equal unit as SPH)
            return _amount;
        } else {
            gSPH.mint(_to, gSPH.balanceTo(_amount)); // send as gSPH (convert units from SPH)
            return gSPH.balanceTo(_amount);
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice returns the sSPH index, which tracks rebase growth
     * @return uint
     */
    function index() public view returns (uint256) {
        return sSPH.index();
    }

    /**
     * @notice returns contract SPH holdings, including bonuses provided
     * @return uint
     */
    function contractBalance() public view returns (uint256) {
        return SPH.balanceOf(address(this));
    }

    /**
     * @notice total supply staked
     */
    function totalStaked() public view returns (uint256) {
        return sSPH.circulatingSupply();
    }

    /**
     * @notice total supply in warmup
     */
    function supplyInWarmup() public view returns (uint256) {
        return sSPH.balanceForGons(gonsInWarmup);
    }

    /* ========== MANAGERIAL FUNCTIONS ========== */

    /**
     * @notice sets the contract address for LP staking
     * @param _distributor address
     */
    function setDistributor(address _distributor) external onlyGovernor {
        distributor = _distributor;
        emit DistributorSet(_distributor);
    }

    /**
     * @notice set warmup period for new stakers
     * @param _warmupPeriod uint
     */
    function setWarmupLength(uint256 _warmupPeriod) external onlyGovernor {
        warmupPeriod = _warmupPeriod;
        emit WarmupSet(_warmupPeriod);
    }
}

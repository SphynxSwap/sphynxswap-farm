// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IsSPH.sol";
import "../../interfaces/IwsSPH.sol";
import "../../interfaces/IgSPH.sol";
import "../../interfaces/ITreasury.sol";
import "../../interfaces/IStaking.sol";
import "../../interfaces/IOwnable.sol";
import "../../interfaces/IUniswapV2Router.sol";
import "../../interfaces/IStakingV1.sol";
import "../../interfaces/ITreasuryV1.sol";

import "../../types/SphynxAccessControlled.sol";

import "../../libs/SafeMath.sol";
import "../../libs/SafeERC20.sol";

contract SphynxTokenMigrator is SphynxAccessControlled {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IgSPH;
    using SafeERC20 for IsSPH;
    using SafeERC20 for IwsSPH;

    /* ========== MIGRATION ========== */

    event TimelockStarted(uint256 block, uint256 end);
    event Migrated(address staking, address treasury);
    event Funded(uint256 amount);
    event Defunded(uint256 amount);

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable oldSPH;
    IsSPH public immutable oldsSPH;
    IwsSPH public immutable oldwsSPH;
    ITreasuryV1 public immutable oldTreasury;
    IStakingV1 public immutable oldStaking;

    IUniswapV2Router public immutable sushiRouter;
    IUniswapV2Router public immutable uniRouter;

    IgSPH public gSPH;
    ITreasury public newTreasury;
    IStaking public newStaking;
    IERC20 public newSPH;

    bool public ohmMigrated;
    bool public shutdown;

    uint256 public immutable timelockLength;
    uint256 public timelockEnd;

    uint256 public oldSupply;

    constructor(
        address _oldSPH,
        address _oldsSPH,
        address _oldTreasury,
        address _oldStaking,
        address _oldwsSPH,
        address _sushi,
        address _uni,
        uint256 _timelock,
        address _authority
    ) SphynxAccessControlled(ISphynxAuthority(_authority)) {
        require(_oldSPH != address(0), "Zero address: SPH");
        oldSPH = IERC20(_oldSPH);
        require(_oldsSPH != address(0), "Zero address: sSPH");
        oldsSPH = IsSPH(_oldsSPH);
        require(_oldTreasury != address(0), "Zero address: Treasury");
        oldTreasury = ITreasuryV1(_oldTreasury);
        require(_oldStaking != address(0), "Zero address: Staking");
        oldStaking = IStakingV1(_oldStaking);
        require(_oldwsSPH != address(0), "Zero address: wsSPH");
        oldwsSPH = IwsSPH(_oldwsSPH);
        require(_sushi != address(0), "Zero address: Sushi");
        sushiRouter = IUniswapV2Router(_sushi);
        require(_uni != address(0), "Zero address: Uni");
        uniRouter = IUniswapV2Router(_uni);
        timelockLength = _timelock;
    }

    /* ========== MIGRATION ========== */

    enum TYPE {
        UNSTAKED,
        STAKED,
        WRAPPED
    }

    // migrate SPHv1, sSPHv1, or wsSPH for SPHv2, sSPHv2, or gSPH
    function migrate(
        uint256 _amount,
        TYPE _from,
        TYPE _to
    ) external {
        require(!shutdown, "Shut down");

        uint256 wAmount = oldwsSPH.sSPHTowSPH(_amount);

        if (_from == TYPE.UNSTAKED) {
            require(ohmMigrated, "Only staked until migration");
            oldSPH.safeTransferFrom(msg.sender, address(this), _amount);
        } else if (_from == TYPE.STAKED) {
            oldsSPH.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            oldwsSPH.safeTransferFrom(msg.sender, address(this), _amount);
            wAmount = _amount;
        }

        if (ohmMigrated) {
            require(oldSupply >= oldSPH.totalSupply(), "SPHv1 minted");
            _send(wAmount, _to);
        } else {
            gSPH.mint(msg.sender, wAmount);
        }
    }

    // migrate all Sphynx tokens held
    function migrateAll(TYPE _to) external {
        require(!shutdown, "Shut down");

        uint256 ohmBal = 0;
        uint256 sSPHBal = oldsSPH.balanceOf(msg.sender);
        uint256 wsSPHBal = oldwsSPH.balanceOf(msg.sender);

        if (oldSPH.balanceOf(msg.sender) > 0 && ohmMigrated) {
            ohmBal = oldSPH.balanceOf(msg.sender);
            oldSPH.safeTransferFrom(msg.sender, address(this), ohmBal);
        }
        if (sSPHBal > 0) {
            oldsSPH.safeTransferFrom(msg.sender, address(this), sSPHBal);
        }
        if (wsSPHBal > 0) {
            oldwsSPH.safeTransferFrom(msg.sender, address(this), wsSPHBal);
        }

        uint256 wAmount = wsSPHBal.add(oldwsSPH.sSPHTowSPH(ohmBal.add(sSPHBal)));
        if (ohmMigrated) {
            require(oldSupply >= oldSPH.totalSupply(), "SPHv1 minted");
            _send(wAmount, _to);
        } else {
            gSPH.mint(msg.sender, wAmount);
        }
    }

    // send preferred token
    function _send(uint256 wAmount, TYPE _to) internal {
        if (_to == TYPE.WRAPPED) {
            gSPH.safeTransfer(msg.sender, wAmount);
        } else if (_to == TYPE.STAKED) {
            newStaking.unwrap(msg.sender, wAmount);
        } else if (_to == TYPE.UNSTAKED) {
            newStaking.unstake(msg.sender, wAmount, false, false);
        }
    }

    // bridge back to SPH, sSPH, or wsSPH
    function bridgeBack(uint256 _amount, TYPE _to) external {
        if (!ohmMigrated) {
            gSPH.burn(msg.sender, _amount);
        } else {
            gSPH.safeTransferFrom(msg.sender, address(this), _amount);
        }

        uint256 amount = oldwsSPH.wSPHTosSPH(_amount);
        // error throws if contract does not have enough of type to send
        if (_to == TYPE.UNSTAKED) {
            oldSPH.safeTransfer(msg.sender, amount);
        } else if (_to == TYPE.STAKED) {
            oldsSPH.safeTransfer(msg.sender, amount);
        } else if (_to == TYPE.WRAPPED) {
            oldwsSPH.safeTransfer(msg.sender, _amount);
        }
    }

    /* ========== OWNABLE ========== */

    // halt migrations (but not bridging back)
    function halt() external onlyPolicy {
        require(!ohmMigrated, "Migration has occurred");
        shutdown = !shutdown;
    }

    // withdraw backing of migrated SPH
    function defund(address reserve) external onlyGovernor {
        require(ohmMigrated, "Migration has not begun");
        require(timelockEnd < block.number && timelockEnd != 0, "Timelock not complete");

        oldwsSPH.unwrap(oldwsSPH.balanceOf(address(this)));

        uint256 amountToUnstake = oldsSPH.balanceOf(address(this));
        oldsSPH.approve(address(oldStaking), amountToUnstake);
        oldStaking.unstake(amountToUnstake, false);

        uint256 balance = oldSPH.balanceOf(address(this));

        if(balance > oldSupply) {
            oldSupply = 0;
        } else {
            oldSupply -= balance;
        }

        uint256 amountToWithdraw = balance.mul(1e18);
        oldSPH.approve(address(oldTreasury), amountToWithdraw);
        oldTreasury.withdraw(amountToWithdraw, reserve);
        IERC20(reserve).safeTransfer(address(newTreasury), IERC20(reserve).balanceOf(address(this)));

        emit Defunded(balance);
    }

    // start timelock to send backing to new treasury
    function startTimelock() external onlyGovernor {
        require(timelockEnd == 0, "Timelock set");
        timelockEnd = block.number.add(timelockLength);

        emit TimelockStarted(block.number, timelockEnd);
    }

    // set gSPH address
    function setgSPH(address _gSPH) external onlyGovernor {
        require(address(gSPH) == address(0), "Already set");
        require(_gSPH != address(0), "Zero address: gSPH");

        gSPH = IgSPH(_gSPH);
    }

    // call internal migrate token function
    function migrateToken(address token) external onlyGovernor {
        _migrateToken(token, false);
    }

    /**
     *   @notice Migrate LP and pair with new SPH
     */
    function migrateLP(
        address pair,
        bool sushi,
        address token,
        uint256 _minA,
        uint256 _minB
    ) external onlyGovernor {
        uint256 oldLPAmount = IERC20(pair).balanceOf(address(oldTreasury));
        oldTreasury.manage(pair, oldLPAmount);

        IUniswapV2Router router = sushiRouter;
        if (!sushi) {
            router = uniRouter;
        }

        IERC20(pair).approve(address(router), oldLPAmount);
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            token, 
            address(oldSPH), 
            oldLPAmount,
            _minA, 
            _minB, 
            address(this), 
            block.timestamp
        );

        newTreasury.mint(address(this), amountB);

        IERC20(token).approve(address(router), amountA);
        newSPH.approve(address(router), amountB);

        router.addLiquidity(
            token, 
            address(newSPH), 
            amountA, 
            amountB, 
            amountA, 
            amountB, 
            address(newTreasury), 
            block.timestamp
        );
    }

    // Failsafe function to allow owner to withdraw funds sent directly to contract in case someone sends non-ohm tokens to the contract
    function withdrawToken(
        address tokenAddress,
        uint256 amount,
        address recipient
    ) external onlyGovernor {
        require(tokenAddress != address(0), "Token address cannot be 0x0");
        require(tokenAddress != address(gSPH), "Cannot withdraw: gSPH");
        require(tokenAddress != address(oldSPH), "Cannot withdraw: old-SPH");
        require(tokenAddress != address(oldsSPH), "Cannot withdraw: old-sSPH");
        require(tokenAddress != address(oldwsSPH), "Cannot withdraw: old-wsSPH");
        require(amount > 0, "Withdraw value must be greater than 0");
        if (recipient == address(0)) {
            recipient = msg.sender; // if no address is specified the value will will be withdrawn to Owner
        }

        IERC20 tokenContract = IERC20(tokenAddress);
        uint256 contractBalance = tokenContract.balanceOf(address(this));
        if (amount > contractBalance) {
            amount = contractBalance; // set the withdrawal amount equal to balance within the account.
        }
        // transfer the token from address of this contract
        tokenContract.safeTransfer(recipient, amount);
    }

    // migrate contracts
    function migrateContracts(
        address _newTreasury,
        address _newStaking,
        address _newSPH,
        address _newsSPH,
        address _reserve
    ) external onlyGovernor {
        require(!ohmMigrated, "Already migrated");
        ohmMigrated = true;
        shutdown = false;

        require(_newTreasury != address(0), "Zero address: Treasury");
        newTreasury = ITreasury(_newTreasury);
        require(_newStaking != address(0), "Zero address: Staking");
        newStaking = IStaking(_newStaking);
        require(_newSPH != address(0), "Zero address: SPH");
        newSPH = IERC20(_newSPH);

        oldSupply = oldSPH.totalSupply(); // log total supply at time of migration

        gSPH.migrate(_newStaking, _newsSPH); // change gSPH minter

        _migrateToken(_reserve, true); // will deposit tokens into new treasury so reserves can be accounted for

        _fund(oldsSPH.circulatingSupply()); // fund with current staked supply for token migration

        emit Migrated(_newStaking, _newTreasury);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    // fund contract with gSPH
    function _fund(uint256 _amount) internal {
        newTreasury.mint(address(this), _amount);
        newSPH.approve(address(newStaking), _amount);
        newStaking.stake(address(this), _amount, false, true); // stake and claim gSPH

        emit Funded(_amount);
    }

    /**
     *   @notice Migrate token from old treasury to new treasury
     */
    function _migrateToken(address token, bool deposit) internal {
        uint256 balance = IERC20(token).balanceOf(address(oldTreasury));

        uint256 excessReserves = oldTreasury.excessReserves();
        uint256 tokenValue = oldTreasury.valueOf(token, balance);

        if (tokenValue > excessReserves) {
            tokenValue = excessReserves;
            balance = excessReserves * 10**9;
        }

        oldTreasury.manage(token, balance);

        if (deposit) {
            IERC20(token).safeApprove(address(newTreasury), balance);
            newTreasury.deposit(balance, token, tokenValue);
        } else {
            IERC20(token).safeTransfer(address(newTreasury), balance);
        }
    }
}

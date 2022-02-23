pragma solidity 0.6.12;

import '@sphynxswap/sphynx-swap-lib/contracts/math/SafeMath.sol';
import '@sphynxswap/sphynx-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@sphynxswap/sphynx-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@sphynxswap/sphynx-swap-lib/contracts/access/Ownable.sol';

import './SphynxToken.sol';

// Have fun reading it. Hopefully it's bug-free. God bless.
contract LockPool is Ownable {
	using SafeMath for uint256;
	using SafeBEP20 for IBEP20;

	// Info of each user.
	struct UserInfo {
		uint256 amount; // How many LP tokens the user has provided.
		uint256 rewardDebt; // Reward debt. See explanation below.
		//
		// We do some fancy math here. Basically, any point in time, the amount of Sphynxs
		// entitled to a user but is pending to be distributed is:
		//
		//   pending reward = (user.amount * pool.accsphynxPerShare) - user.rewardDebt
		//
		// Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
		//   1. The pool's `accsphynxPerShare` (and `lastRewardBlock`) gets updated.
		//   2. User receives the pending reward sent to his/her address.
		//   3. User's `amount` gets updated.
		//   4. User's `rewardDebt` gets updated.
	}

	// Info of each pool.
	struct PoolInfo {
		IBEP20 lpToken; // Address of LP token contract.
		uint256 allocPoint; // How many allocation points assigned to this pool. sphynxs to distribute per block.
		uint256 lastRewardBlock; // Last block number that sphynxs distribution occurs.
		uint256 accSphynxPerShare; // Accumulated Sphynxs per share, times 1e12. See below.
	}

	// The sphynx TOKEN!
	SphynxToken public sphynx;
	// Dev address.
	address public devaddr;
	// sphynx tokens created per block.
	uint256 public sphynxPerBlock;
	// Bonus muliplier for early sphynx makers.
	uint256 public BONUS_MULTIPLIER = 1;

	uint256 public toBurn = 20;

	// Info of each pool.
	PoolInfo[] public poolInfo;
	// Info of each user that stakes LP tokens.
	mapping(uint256 => mapping(address => UserInfo)) public userInfo;
	// Total allocation poitns. Must be the sum of all allocation points in all pools.
	uint256 public totalAllocPoint = 0;
	// The block number when sphynx mining starts.
	uint256 public startBlock;

	event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
	event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
	event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
	event SetDev(address newDev);

	constructor(
		SphynxToken _sphynx,
		address _devaddr,
		uint256 _sphynxPerBlock,
		uint256 _startBlock
	) public {
		sphynx = _sphynx;
		devaddr = _devaddr;
		sphynxPerBlock = _sphynxPerBlock;
		startBlock = _startBlock;

		// staking pool
		poolInfo.push(PoolInfo({ lpToken: _sphynx, allocPoint: 100, lastRewardBlock: startBlock, accSphynxPerShare: 0 }));

		totalAllocPoint = 100;
	}

	function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
		BONUS_MULTIPLIER = multiplierNumber;
	}

	function poolLength() external view returns (uint256) {
		return poolInfo.length;
	}

	// Add a new lp to the pool. Can only be called by the owner.
	// XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
	function add(
		uint256 _allocPoint,
		IBEP20 _lpToken,
		bool _withUpdate
	) public onlyOwner {
		if (_withUpdate) {
			massUpdatePools();
		}
		uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
		totalAllocPoint = totalAllocPoint.add(_allocPoint);
		poolInfo.push(PoolInfo({ lpToken: _lpToken, allocPoint: _allocPoint, lastRewardBlock: lastRewardBlock, accSphynxPerShare: 0 }));
	}

	// Update the given pool's sphynx allocation point. Can only be called by the owner.
	function set(
		uint256 _pid,
		uint256 _allocPoint,
		bool _withUpdate
	) public onlyOwner {
		if (_withUpdate) {
			massUpdatePools();
		}
		totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
		poolInfo[_pid].allocPoint = _allocPoint;
	}

	function changeToBurn(uint256 value) public onlyOwner {
		toBurn = value;
	}

	// Return reward multiplier over the given _from to _to block.
	function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
		return _to.sub(_from).mul(BONUS_MULTIPLIER);
	}

	// View function to see pending sphynxs on frontend.
	function pendingSphynx(uint256 _pid, address _user) external view returns (uint256) {
		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][_user];
		uint256 accSphynxPerShare = pool.accSphynxPerShare;
		uint256 lpSupply = pool.lpToken.balanceOf(address(this));
		if (block.number > pool.lastRewardBlock && lpSupply != 0) {
			uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
			uint256 sphynxReward = multiplier.mul(sphynxPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
			accSphynxPerShare = accSphynxPerShare.add(sphynxReward.mul(1e12).div(lpSupply));
		}
		return user.amount.mul(accSphynxPerShare).div(1e12).sub(user.rewardDebt);
	}

	// Update reward variables for all pools. Be careful of gas spending!
	function massUpdatePools() public {
		uint256 length = poolInfo.length;
		for (uint256 pid = 0; pid < length; ++pid) {
			updatePool(pid);
		}
	}

	// Update reward variables of the given pool to be up-to-date.
	function updatePool(uint256 _pid) public {
		PoolInfo storage pool = poolInfo[_pid];
		if (block.number <= pool.lastRewardBlock) {
			return;
		}
		uint256 lpSupply = pool.lpToken.balanceOf(address(this));
		if (lpSupply == 0) {
			pool.lastRewardBlock = block.number;
			return;
		}
		uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
		uint256 sphynxReward = multiplier.mul(sphynxPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
		sphynx.mint(devaddr, sphynxReward.div(100));
		sphynx.mint(address(this), sphynxReward);
		pool.accSphynxPerShare = pool.accSphynxPerShare.add(sphynxReward.mul(1e12).div(lpSupply));
		pool.lastRewardBlock = block.number;
	}

	// Deposit LP tokens to MasterChef for sphynx allocation.
	function deposit(uint256 _pid, uint256 _amount) public {
		require(_pid != 0, 'deposit sphynx by staking');

		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][msg.sender];
		updatePool(_pid);
		if (user.amount > 0) {
			uint256 pending = user.amount.mul(pool.accSphynxPerShare).div(1e12).sub(user.rewardDebt);
			if (pending > 0) {
				safeSphynxTransfer(msg.sender, pending);
			}
		}
		if (_amount > 0) {
			pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
			user.amount = user.amount.add(_amount);
		}
		user.rewardDebt = user.amount.mul(pool.accSphynxPerShare).div(1e12);
		emit Deposit(msg.sender, _pid, _amount);
	}

	// Withdraw LP tokens from MasterChef.
	function withdraw(uint256 _pid, uint256 _amount) public {
		require(_pid != 0, 'withdraw sphynx by unstaking');

		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][msg.sender];
		require(user.amount >= _amount, 'withdraw: not good');
		updatePool(_pid);
		uint256 pending = user.amount.mul(pool.accSphynxPerShare).div(1e12).sub(user.rewardDebt);
		if (pending > 0) {
			safeSphynxTransfer(msg.sender, pending);
		}
		if (_amount > 0) {
			user.amount = user.amount.sub(_amount);
			pool.lpToken.safeTransfer(address(msg.sender), _amount);
		}
		user.rewardDebt = user.amount.mul(pool.accSphynxPerShare).div(1e12);
		emit Withdraw(msg.sender, _pid, _amount);
	}

	// Stake sphynx tokens to MasterChef
	function enterStaking(uint256 _amount) public {
		PoolInfo storage pool = poolInfo[0];
		UserInfo storage user = userInfo[0][msg.sender];
		updatePool(0);
		if (user.amount > 0) {
			uint256 pending = user.amount.mul(pool.accSphynxPerShare).div(1e12).sub(user.rewardDebt);
			if (pending > 0) {
				safeSphynxTransfer(msg.sender, pending);
			}
		}
		if (_amount > 0) {
			pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
			user.amount = user.amount.add(_amount);
		}
		user.rewardDebt = user.amount.mul(pool.accSphynxPerShare).div(1e12);
		emit Deposit(msg.sender, 0, _amount);
	}

	// Withdraw sphynx tokens from STAKING.
	function leaveStaking(uint256 _amount) public {
		PoolInfo storage pool = poolInfo[0];
		UserInfo storage user = userInfo[0][msg.sender];
		require(user.amount >= _amount, 'withdraw: not good');
		updatePool(0);
		uint256 pending = user.amount.mul(pool.accSphynxPerShare).div(1e12).sub(user.rewardDebt);
		if (pending > 0) {
			safeSphynxTransfer(msg.sender, pending);
		}
		if (_amount > 0) {
			user.amount = user.amount.sub(_amount);
			pool.lpToken.safeTransfer(address(msg.sender), _amount);
		}
		user.rewardDebt = user.amount.mul(pool.accSphynxPerShare).div(1e12);

		emit Withdraw(msg.sender, 0, _amount);
	}

	// Withdraw without caring about rewards. EMERGENCY ONLY.
	function emergencyWithdraw(uint256 _pid) public {
		PoolInfo storage pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][msg.sender];
		pool.lpToken.safeTransfer(address(msg.sender), user.amount);
		emit EmergencyWithdraw(msg.sender, _pid, user.amount);
		user.amount = 0;
		user.rewardDebt = 0;
	}

	// Safe sphynx transfer function, just in case if rounding error causes pool to not have enough sphynxs.
	function safeSphynxTransfer(address _to, uint256 _amount) internal {
		uint256 amount = _amount.mul(toBurn).div(100);
		sphynx.transfer(0x000000000000000000000000000000000000dEaD, amount);
		sphynx.transfer(_to, _amount.sub(amount));
	}

	// Update dev address by the previous dev.
	function dev(address _devaddr) public {
		require(msg.sender == devaddr, 'dev: wut?');
		devaddr = _devaddr;
		emit SetDev(_devaddr);
	}

	// Sphynx has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
	function updateEmissionRate(uint256 _perBlock) public onlyOwner {
		massUpdatePools();
		sphynxPerBlock = _perBlock;
	}
}

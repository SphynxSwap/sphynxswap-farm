// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@sphynxswap/sphynx-swap-lib/contracts/access/Manageable.sol';
import '@sphynxswap/sphynx-swap-lib/contracts/token/BEP20/BEP20.sol';
import './dependencies/pancake-swap-core/contracts/interfaces/IPancakePair.sol';
import './dependencies/pancake-swap-core/contracts/interfaces/IPancakeFactory.sol';
import './dependencies/pancake-swap-perphery/contracts/interfaces/IPancakeRouter02.sol';

contract SphynxToken is BEP20, Manageable {
	using SafeMath for uint256;

	IPancakeRouter02 public pancakeSwapRouter;
	address public pancakeSwapPair;

	bool private swapping;

	address public marketingWallet;
	address public developmentWallet;
	address public lotteryAddress;

	uint256 public swapTokensAtAmount = 50000 * (10**18);

	uint256 public marketingFee;
	uint256 public developmentFee;
	uint256 public lotteryFee;
	uint256 public totalFees;
	uint256 public blockNumber;

	bool public SwapAndLiquifyEnabled = true;
	bool public sendToLottery = false;

	// exlcude from fees and max transaction amount
	mapping(address => bool) private _isExcludedFromFees;

	// store addresses that are automated market maker pairs. Any transfer to these addresses
	// could be subject to a maximum transfer amount
	mapping(address => bool) public automatedMarketMakerPairs;

	// Contract Events
	event ExcludeFromFees(address indexed account, bool isExcluded);
	event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
	event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
	event MarketingWalletUpdated(address indexed newMarketingWallet, address indexed oldMarketingWallet);
	event DevelopmentWalletUpdated(address indexed newDevelopmentWallet, address indexed oldDevelopmentWallet);
	event LotteryAddressUpdated(address indexed newLotteryAddress, address indexed oldLotteryAddress);
	event UpdatePancakeSwapRouter(address indexed newAddress, address indexed oldAddress);
	event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);
	event UpdateSwapAndLiquify(bool value);
	event UpdateSendToLottery(bool value);
	event SetMarketingFee(uint256 value);
	event SetDevelopmentFee(uint256 value);
	event SetLotteryFee(uint256 value);
	event SetAllFeeToZero(uint256 marketingFee, uint256 developmentFee, uint256 lotteryFee);
	event MaxFees(uint256 marketingFee, uint256 developmentFee, uint256 lotteryFee);
	event SetNumberOfTokensToSwap(uint256 swapTokensAtAmount);
	event SetBlockNumber(uint256 blockNumber);

	constructor() public BEP20('Sphynx Token', 'SPHYNX') {
		uint256 _marketingFee = 5;
		uint256 _developmentFee = 5;
		uint256 _lotteryFee = 1;

		marketingFee = _marketingFee;
		developmentFee = _developmentFee;
		lotteryFee = _lotteryFee;
		totalFees = _marketingFee.add(_developmentFee);
		blockNumber = 0;

		marketingWallet = address(0x982687617bc9a76420138a0F82b2fC1B8B11BbE3);
		developmentWallet = address(0x4A48062b88d5B8e9f0B7A5149F87288899C2d7f9);

		IPancakeRouter02 _pancakeSwapRouter = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // mainnet
		// Create a pancakewap pair for SYS
		address _pancakeSwapPair = IPancakeFactory(_pancakeSwapRouter.factory()).createPair(address(this), _pancakeSwapRouter.WETH());

		pancakeSwapRouter = _pancakeSwapRouter;
		pancakeSwapPair = _pancakeSwapPair;

		_setAutomatedMarketMakerPair(pancakeSwapPair, true);

		address _owner = address(0x4711ae0ffe1761f44692299EA6C0Ee16067C3269);

		// exclude from paying fees or having max transaction amount
		excludeFromFees(marketingWallet, true);
		excludeFromFees(developmentWallet, true);
		excludeFromFees(address(this), true);
		excludeFromFees(_owner, true);

		_mint(_owner, 1000000000 * (10**18));
	}

	receive() external payable {}

	// mint function for masterchef;
	function mint(address to, uint256 amount) public onlyOwner {
		_mint(to, amount);
	}

	function updateSwapAndLiquifiy(bool value) public onlyManager {
		SwapAndLiquifyEnabled = value;
		emit UpdateSwapAndLiquify(value);
	}

	function updateSendToLottery(bool value) public onlyManager {
		sendToLottery = value;
		emit UpdateSendToLottery(value);
	}

	function setMarketingFee(uint256 value) external onlyManager {
		require(value <= 5, 'SPHYNX: Invalid marketingFee');
		marketingFee = value;
		totalFees = marketingFee.add(developmentFee);
		emit SetMarketingFee(value);
	}

	function setDevelopmentFee(uint256 value) external onlyManager {
		require(value <= 5, 'SPHYNX: Invalid developmentFee');
		developmentFee = value;
		totalFees = marketingFee.add(developmentFee);
		emit SetDevelopmentFee(value);
	}

	function setLotteryFee(uint256 value) external onlyManager {
		require(value <= 1, 'SPHYNX: Invalid lotteryFee');
		lotteryFee = value;
		emit SetLotteryFee(value);
	}

	function setAllFeeToZero() external onlyOwner {
		marketingFee = 0;
		developmentFee = 0;
		lotteryFee = 0;
		totalFees = 0;
		emit SetAllFeeToZero(marketingFee, developmentFee, lotteryFee);
	}

	function maxFees() external onlyOwner {
		marketingFee = 5;
		developmentFee = 5;
		lotteryFee = 1;
		totalFees = marketingFee.add(developmentFee);
		emit MaxFees(marketingFee, developmentFee, lotteryFee);
	}

	function updatePancakeSwapRouter(address newAddress) public onlyManager {
		require(newAddress != address(pancakeSwapRouter), 'SPHYNX: The router already has that address');
		emit UpdatePancakeSwapRouter(newAddress, address(pancakeSwapRouter));
		pancakeSwapRouter = IPancakeRouter02(newAddress);
		address _pancakeSwapPair = IPancakeFactory(pancakeSwapRouter.factory()).createPair(address(this), pancakeSwapRouter.WETH());
		_setAutomatedMarketMakerPair(pancakeSwapPair, false);
		pancakeSwapPair = _pancakeSwapPair;
		_setAutomatedMarketMakerPair(pancakeSwapPair, true);
	}

	function excludeFromFees(address account, bool excluded) public onlyManager {
		require(_isExcludedFromFees[account] != excluded, "SPHYNX: Account is already the value of 'excluded'");
		_isExcludedFromFees[account] = excluded;

		emit ExcludeFromFees(account, excluded);
	}

	function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
		for (uint256 i = 0; i < accounts.length; i++) {
			_isExcludedFromFees[accounts[i]] = excluded;
		}

		emit ExcludeMultipleAccountsFromFees(accounts, excluded);
	}

	function setAutomatedMarketMakerPair(address pair, bool value) public onlyManager {
		_setAutomatedMarketMakerPair(pair, value);
	}

	function _setAutomatedMarketMakerPair(address pair, bool value) private {
		require(automatedMarketMakerPairs[pair] != value, 'SPHYNX: Automated market maker pair is already set to that value');
		automatedMarketMakerPairs[pair] = value;

		emit SetAutomatedMarketMakerPair(pair, value);
	}

	function setNumberOfTokensToSwap(uint256 _amount) public onlyManager {
		swapTokensAtAmount = _amount * (10**18);
		emit SetNumberOfTokensToSwap(swapTokensAtAmount);
	}

	function updateMarketingWallet(address newMarketingWallet) public onlyManager {
		require(newMarketingWallet != marketingWallet, 'SPHYNX: The marketing wallet is already this address');
		excludeFromFees(newMarketingWallet, true);
		excludeFromFees(marketingWallet, false);
		emit MarketingWalletUpdated(newMarketingWallet, marketingWallet);
		marketingWallet = newMarketingWallet;
	}

	function updateDevelopmentgWallet(address newDevelopmentWallet) public onlyManager {
		require(newDevelopmentWallet != developmentWallet, 'SPHYNX: The development wallet is already this address');
		excludeFromFees(newDevelopmentWallet, true);
		excludeFromFees(developmentWallet, false);
		emit DevelopmentWalletUpdated(newDevelopmentWallet, developmentWallet);
		developmentWallet = newDevelopmentWallet;
	}

	function updateLotteryAddress(address newLotteryAddress) public onlyManager {
		require(newLotteryAddress != lotteryAddress, 'SPHYNX: The lottery wallet is already this address');
		excludeFromFees(newLotteryAddress, true);
		excludeFromFees(lotteryAddress, false);
		emit LotteryAddressUpdated(newLotteryAddress, lotteryAddress);
		lotteryAddress = newLotteryAddress;
	}

	function setBlockNumber() public onlyOwner {
		blockNumber = block.number;
		emit SetBlockNumber(blockNumber);
	}

	function isExcludedFromFees(address account) public view returns (bool) {
		return _isExcludedFromFees[account];
	}

	function _transfer(
		address from,
		address to,
		uint256 amount
	) internal override {
		require(from != address(0), 'BEP20: transfer from the zero address');
		require(to != address(0), 'BEP20: transfer to the zero address');

		if (amount == 0) {
			super._transfer(from, to, 0);
			return;
		}

		uint256 contractTokenBalance = balanceOf(address(this));

		bool canSwap = contractTokenBalance >= swapTokensAtAmount;

		if (canSwap && !swapping && !automatedMarketMakerPairs[from] && SwapAndLiquifyEnabled) {
			swapping = true;

			// Set number of tokens to sell to swapTokensAtAmount
			contractTokenBalance = swapTokensAtAmount;

			uint256 marketingTokens = contractTokenBalance.mul(marketingFee).div(totalFees);
			swapTokensForEth(marketingTokens, marketingWallet);

			uint256 developmentTokens = contractTokenBalance.sub(marketingTokens);
			swapTokensForEth(developmentTokens, developmentWallet);

			swapping = false;
		}

		// indicates if fee should be deducted from transfer
		bool takeFee = true;

		// if any account belongs to _isExcludedFromFee account then remove the fee
		if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
			takeFee = false;
		}

		if (block.number - blockNumber <= 10) {
			uint256 afterBalance = balanceOf(to) + amount;
			require(afterBalance <= 250000 * (10**18), 'Owned amount exceeds the maxOwnedAmount');
		}

		if (takeFee) {
			uint256 fees;
			if (block.number - blockNumber <= 5) {
				fees = amount.mul(99).div(10**2);
			} else {
				fees = amount.mul(totalFees).div(10**2);
				if (sendToLottery) {
					uint256 lotteryAmount = amount.mul(lotteryFee).div(10**2);
					amount = amount.sub(lotteryAmount);
					super._transfer(from, lotteryAddress, lotteryAmount);
				}
			}

			amount = amount.sub(fees);
			super._transfer(from, address(this), fees);
		}

		super._transfer(from, to, amount);
	}

	// Swap tokens on PacakeSwap
	function swapTokensForEth(uint256 tokenAmount, address to) private {
		// generate the pancakeswap pair path of token -> weth
		address[] memory path = new address[](2);
		path[0] = address(this);
		path[1] = pancakeSwapRouter.WETH();

		_approve(address(this), address(pancakeSwapRouter), tokenAmount);

		// make the swap
		pancakeSwapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
			tokenAmount,
			0, // accept any amount of ETH
			path,
			to,
			block.timestamp
		);
	}
}

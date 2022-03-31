// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@sphynxswap/sphynx-swap-lib/contracts/access/Manageable.sol";
import "@sphynxswap/sphynx-swap-lib/contracts/token/BEP20/BEP20.sol";
import "@sphynxswap/sphynx-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@sphynxswap/sphynx-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@sphynxswap/swap-core/contracts/interfaces/ISphynxPair.sol";
import "@sphynxswap/swap-core/contracts/interfaces/ISphynxFactory.sol";
import "@sphynxswap/swap-periphery/contracts/interfaces/ISphynxRouter02.sol";

contract SphynxToken is BEP20, Manageable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    ISphynxRouter02 public sphynxSwapRouter;
    address public sphynxSwapPair;

    bool private swapping;

    mapping(address => bool) public masterChef;
    address public sphynxBridge;
    address public liquidityWallet;

    address payable public marketingWallet =
        payable(0x3e20C4bFf0f34BA46f9D33599d3aEAa7e815B19f);
    address payable public developmentWallet =
        payable(0x93c3ae3C4d2B6F98533A4b1E8df6F25DcC37f3Ad);

    uint256 public nativeAmountToSwap = 1 ether;

    uint256 public marketingFeeOnBuy;
    uint256 public developmentFeeOnBuy;
    uint256 public burnFee;
    uint256 public totalFeesOnBuy;
    uint256 public marketingFeeOnSell;
    uint256 public developmentFeeOnSell;
    uint256 public liquidityFeeOnBuy;
    uint256 public liquidityFeeOnSell;
    uint256 public totalFeesOnSell;
    uint256 public blockNumber;
    uint256 public liquidityShare = 2;
    uint256 public marketingShare = 5;
    uint256 public developmentShare = 5;
    uint256 public totalShares = 12;

    bool public SwapAndLiquifyEnabled = false;
    bool public stopTrade = false;
    uint256 public maxTxAmount = 1000000000 * (10**18); // Initial Max Tx Amount
    mapping(address => bool) signers;
    mapping(uint256 => address) signersArray;
    mapping(address => bool) stopTradeSign;

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;

    // getting fee addresses
    mapping(address => bool) public _isGetFees;

    // store addresses that are automated market maker pairs. Any transfer to these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    modifier onlyMasterChefAndBridge() {
        require(
            masterChef[msg.sender] || msg.sender == sphynxBridge,
            "Permission Denied"
        );
        _;
    }

    modifier onlySigner() {
        require(signers[msg.sender], "not-a-signer");
        _;
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    // Contract Events
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event GetFee(address indexed account, bool isGetFee);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event MarketingWalletUpdated(
        address indexed newMarketingWallet,
        address indexed oldMarketingWallet
    );
    event DevelopmentWalletUpdated(
        address indexed newDevelopmentWallet,
        address indexed oldDevelopmentWallet
    );
    event UpdateSphynxSwapRouter(
        address indexed newAddress,
        address indexed oldAddress
    );
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 nativeReceived,
        uint256 tokensIntoLiqudity
    );
    event UpdateSwapAndLiquify(bool value);
    event SetMarketingFee(uint256 onBuy, uint256 onSell);
    event SetDevelopmentFee(uint256 onBuy, uint256 onSell);
    event SetBurnFee(uint256 value);
    event SetDistribution(
        uint256 liquidity,
        uint256 marketing,
        uint256 development
    );
    event SetLiquidityFee(uint256 onBuy, uint256 onSell);
    event SetNativeAmountToSwap(uint256 nativeAmountToSwap);
    event SetBlockNumber(uint256 blockNumber);
    event UpdateMasterChef(address masterChef);
    event UpdateSphynxBridge(address sphynxBridge);
    event UpdateMaxTxAmount(uint256 txAmount);

    constructor() public BEP20("Sphynx Labs", "SPHYNX") {
        marketingFeeOnBuy = 4;
        marketingFeeOnSell = 5;
        developmentFeeOnBuy = 4;
        developmentFeeOnSell = 5;
        burnFee = 1;
        liquidityFeeOnBuy = 0;
        liquidityFeeOnSell = 1;
        liquidityWallet = msg.sender;
        totalFeesOnBuy = marketingFeeOnBuy.add(developmentFeeOnBuy).add(
            liquidityFeeOnBuy
        );
        totalFeesOnSell = marketingFeeOnSell.add(developmentFeeOnSell).add(
            liquidityFeeOnSell
        );

        ISphynxRouter02 _sphynxSwapRouter = ISphynxRouter02(
            0x10ED43C718714eb63d5aA57B78B54704E256024E
        ); // mainnet
        // Create a sphynxswap pair for SPHYNX
        address _sphynxSwapPair = ISphynxFactory(_sphynxSwapRouter.factory())
            .createPair(address(this), _sphynxSwapRouter.WETH());

        sphynxSwapRouter = _sphynxSwapRouter;
        sphynxSwapPair = _sphynxSwapPair;

        _setAutomatedMarketMakerPair(sphynxSwapPair, true);

        // exclude from paying fees or having max transaction amount
        excludeFromFees(marketingWallet, true);
        excludeFromFees(developmentWallet, true);
        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);

        // set getFee addresses
        _isGetFees[_sphynxSwapPair] = true;

        _mint(owner(), 1000000000 * (10**18));

        _status = _NOT_ENTERED;

        //multi-sign-wallets
        signers[0x35BfE8dA53F94d6711F111790643D2D403992b56] = true;
        signers[0x96C463B615228981A2c30B842E8A8e4e933CEc46] = true;
        signers[0x7278fC9C49A2B6bd072b9d47E3c903ef0e12bb83] = true;
        signersArray[0] = 0x35BfE8dA53F94d6711F111790643D2D403992b56;
        signersArray[1] = 0x96C463B615228981A2c30B842E8A8e4e933CEc46;
        signersArray[2] = 0x7278fC9C49A2B6bd072b9d47E3c903ef0e12bb83;
    }

    receive() external payable {}

    // mint function for masterchef;
    function mint(address to, uint256 amount) public onlyMasterChefAndBridge {
        _mint(to, amount);
    }

    function updateSwapAndLiquifiy(bool value) public onlyManager {
        SwapAndLiquifyEnabled = value;
        emit UpdateSwapAndLiquify(value);
    }

    function updateLiquidityWallet(address _liquidityWallet)
        external
        onlyManager
    {
        liquidityWallet = _liquidityWallet;
    }

    function setMarketingFee(uint256 _onBuy, uint256 _onSell)
        external
        onlyManager
    {
        require(_onBuy <= 10 && _onSell <= 10, "SPHYNX: Invalid marketingFee");
        marketingFeeOnBuy = _onBuy;
        marketingFeeOnSell = _onSell;
        totalFeesOnBuy = marketingFeeOnBuy.add(developmentFeeOnBuy).add(
            liquidityFeeOnBuy
        );
        totalFeesOnSell = marketingFeeOnSell.add(developmentFeeOnSell).add(
            liquidityFeeOnSell
        );
        emit SetMarketingFee(_onBuy, _onSell);
    }

    function setDevelopmentFee(uint256 _onBuy, uint256 _onSell)
        external
        onlyManager
    {
        require(_onBuy <= 10 && _onSell <= 10, "SPHYNX: Invalid marketingFee");
        developmentFeeOnBuy = _onBuy;
        developmentFeeOnSell = _onSell;
        totalFeesOnBuy = developmentFeeOnBuy.add(marketingFeeOnBuy).add(
            liquidityFeeOnBuy
        );
        totalFeesOnSell = developmentFeeOnSell.add(marketingFeeOnSell).add(
            liquidityFeeOnSell
        );
        emit SetDevelopmentFee(_onBuy, _onSell);
    }

    function setLiquidityFee(uint256 _onBuy, uint256 _onSell)
        external
        onlyManager
    {
        require(_onBuy <= 10 && _onSell <= 10, "SPHYNX: Invalid marketingFee");
        liquidityFeeOnBuy = _onBuy;
        liquidityFeeOnSell = _onSell;
        totalFeesOnBuy = liquidityFeeOnBuy.add(developmentFeeOnBuy).add(
            marketingFeeOnBuy
        );
        totalFeesOnSell = liquidityFeeOnSell.add(developmentFeeOnSell).add(
            marketingFeeOnSell
        );
        emit SetLiquidityFee(_onBuy, _onSell);
    }

    function setBurnFee(uint256 value) external onlyManager {
        require(value <= 5, "SPHYNX: Invalid burnFee");
        burnFee = value;
        emit SetBurnFee(value);
    }

    function updateShares(
        uint256 _liquidity,
        uint256 _marketing,
        uint256 _development
    ) external onlyManager {
        liquidityShare = _liquidity;
        marketingShare = _marketing;
        developmentShare = _development;
        totalShares = liquidityShare.add(marketingShare).add(developmentShare);

        emit SetDistribution(_liquidity, _marketing, _development);
    }

    function updateSphynxSwapRouter(address newAddress) public onlyManager {
        require(
            newAddress != address(sphynxSwapRouter),
            "SPHYNX: The router already has that address"
        );
        emit UpdateSphynxSwapRouter(newAddress, address(sphynxSwapRouter));
        sphynxSwapRouter = ISphynxRouter02(newAddress);
        address _sphynxSwapPair;
        _sphynxSwapPair = ISphynxFactory(sphynxSwapRouter.factory()).getPair(
            address(this),
            sphynxSwapRouter.WETH()
        );
        if (_sphynxSwapPair == address(0)) {
            _sphynxSwapPair = ISphynxFactory(sphynxSwapRouter.factory())
                .createPair(address(this), sphynxSwapRouter.WETH());
        }
        _setAutomatedMarketMakerPair(sphynxSwapPair, false);
        sphynxSwapPair = _sphynxSwapPair;
        _setAutomatedMarketMakerPair(sphynxSwapPair, true);
    }

    function updateMasterChef(address _masterChef, bool _value)
        public
        onlyManager
    {
        masterChef[_masterChef] = _value;
        emit UpdateMasterChef(_masterChef);
    }

    function updateSphynxBridge(address _sphynxBridge) public onlyManager {
        require(
            sphynxBridge != _sphynxBridge,
            "SPHYNX: SphynxBridge already exists!"
        );
        _isExcludedFromFees[sphynxBridge] = false;
        sphynxBridge = _sphynxBridge;
        _isExcludedFromFees[sphynxBridge] = true;
        emit UpdateSphynxBridge(_sphynxBridge);
    }

    function excludeFromFees(address account, bool excluded)
        public
        onlyManager
    {
        require(
            _isExcludedFromFees[account] != excluded,
            "SPHYNX: Account is already the value of 'excluded'"
        );
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function setFeeAccount(address account, bool isGetFee) public onlyManager {
        require(
            _isGetFees[account] != isGetFee,
            "SPHYNX: Account is already the value of 'isGetFee'"
        );
        _isGetFees[account] = isGetFee;

        emit GetFee(account, isGetFee);
    }

    function excludeMultipleAccountsFromFees(
        address[] calldata accounts,
        bool excluded
    ) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        public
        onlyManager
    {
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "SPHYNX: Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function setNativeAmountToSwap(uint256 _nativeAmount) public onlyManager {
        nativeAmountToSwap = _nativeAmount;
        emit SetNativeAmountToSwap(nativeAmountToSwap);
    }

    function updateMarketingWallet(address newMarketingWallet)
        public
        onlyManager
    {
        require(
            newMarketingWallet != marketingWallet,
            "SPHYNX: The marketing wallet is already this address"
        );
        excludeFromFees(newMarketingWallet, true);
        excludeFromFees(marketingWallet, false);
        emit MarketingWalletUpdated(newMarketingWallet, marketingWallet);
        marketingWallet = payable(newMarketingWallet);
    }

    function updateDevelopmentgWallet(address newDevelopmentWallet)
        public
        onlyManager
    {
        require(
            newDevelopmentWallet != developmentWallet,
            "SPHYNX: The development wallet is already this address"
        );
        excludeFromFees(newDevelopmentWallet, true);
        excludeFromFees(developmentWallet, false);
        emit DevelopmentWalletUpdated(newDevelopmentWallet, developmentWallet);
        developmentWallet = payable(newDevelopmentWallet);
    }

    function setBlockNumber() public onlyOwner {
        blockNumber = block.number;
        emit SetBlockNumber(blockNumber);
    }

    function updateMaxTxAmount(uint256 _amount) public onlyManager {
        maxTxAmount = _amount;
        emit UpdateMaxTxAmount(_amount);
    }

    function updateStopTrade(bool _value) external onlySigner {
        require(stopTrade != _value, "already-set");
        require(!stopTradeSign[msg.sender], "already-sign");
        stopTradeSign[msg.sender] = true;
        if (
            stopTradeSign[signersArray[0]] &&
            stopTradeSign[signersArray[1]] &&
            stopTradeSign[signersArray[2]]
        ) {
            stopTrade = _value;
            stopTradeSign[signersArray[0]] = false;
            stopTradeSign[signersArray[1]] = false;
            stopTradeSign[signersArray[2]] = false;
        }
    }

    function updateSignerWallet(address _signer) external onlySigner {
        signers[msg.sender] = false;
        signers[_signer] = true;
        for (uint256 i = 0; i < 3; i++) {
            if (signersArray[i] == msg.sender) {
                signersArray[i] = _signer;
            }
        }
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(!stopTrade, "trade-stopped");
        require(amount <= maxTxAmount, "max-tx-amount-overflow");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (SwapAndLiquifyEnabled) {
            uint256 contractTokenBalance = balanceOf(address(this));
            uint256 nativeTokenAmount = _getTokenAmountFromNative();

            bool canSwap = contractTokenBalance >= nativeTokenAmount;

            if (canSwap && !swapping && !automatedMarketMakerPairs[from]) {
                swapping = true;
                // Set number of tokens to sell to nativeTokenAmount
                contractTokenBalance = nativeTokenAmount;
                swapTokens(contractTokenBalance);
                swapping = false;
            }
        }

        if (_isGetFees[to] && blockNumber == 0) {
            blockNumber = block.number;
        }

        // indicates if fee should be deducted from transfer
        bool takeFee = true;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (takeFee) {
            if (block.number - blockNumber <= 10) {
                uint256 afterBalance = balanceOf(to) + amount;
                require(
                    afterBalance <= 250000 * (10**18),
                    "Owned amount exceeds the maxOwnedAmount"
                );
            }
            uint256 fees;
            if (_isGetFees[from] || _isGetFees[to]) {
                if (block.number - blockNumber <= 10) {
                    fees = amount.mul(99).div(10**2);
                } else {
                    if (_isGetFees[from]) {
                        fees = amount.mul(totalFeesOnBuy).div(10**2);
                    } else {
                        fees = amount.mul(totalFeesOnSell).div(10**2);
                    }
                    uint256 burnAmount = amount.mul(burnFee).div(10**2);
                    amount = amount.sub(burnAmount);
                    super._transfer(from, address(this), burnAmount);
                    _burn(address(this), burnAmount);
                }
                amount = amount.sub(fees);
                super._transfer(from, address(this), fees);
            }
        }

        super._transfer(from, to, amount);
    }

    function swapTokens(uint256 tokenAmount) private {
        uint256 tokensForLiquidity = tokenAmount.mul(liquidityShare).div(
            totalShares
        );
        uint256 swapTokenAmount = tokenAmount.sub(tokensForLiquidity);
        swapTokensForNative(swapTokenAmount);
        uint256 swappedNative = address(this).balance;
        uint256 nativeForLiquidity = swappedNative.mul(liquidityShare).div(
            totalShares
        );
        uint256 nativeForMarketing = swappedNative.mul(marketingShare).div(
            totalShares
        );
        uint256 nativeForDevelopment = swappedNative
            .sub(nativeForMarketing)
            .sub(nativeForLiquidity);
        if (tokensForLiquidity > 0) {
            addLiquidity(tokensForLiquidity, nativeForLiquidity);
        }
        if (nativeForMarketing > 0) {
            transferNativeToMarketingWallet(nativeForMarketing);
        }
        if (nativeForDevelopment > 0) {
            transferNativeToDevelopmentWallet(nativeForDevelopment);
        }
    }

    function addLiquidity(uint256 tokenAmount, uint256 nativeAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(sphynxSwapRouter), tokenAmount);

        // add the liquidity
        sphynxSwapRouter.addLiquidityETH{value: nativeAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
    }

    // Swap tokens on PacakeSwap
    function swapTokensForNative(uint256 tokenAmount) private {
        // generate the sphynxswap pair path of token -> WETH
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = sphynxSwapRouter.WETH();

        _approve(address(this), address(sphynxSwapRouter), tokenAmount);

        // make the swap
        sphynxSwapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of Native
            path,
            address(this),
            block.timestamp
        );
    }

    function _getTokenAmountFromNative() internal view returns (uint256) {
        uint256 tokenAmount;
        address[] memory path = new address[](2);
        path[0] = sphynxSwapRouter.WETH();
        path[1] = address(this);
        uint256[] memory amounts = sphynxSwapRouter.getAmountsOut(
            nativeAmountToSwap,
            path
        );
        tokenAmount = amounts[1];
        return tokenAmount;
    }

    function transferNativeToMarketingWallet(uint256 amount) private {
        marketingWallet.transfer(amount);
    }

    function transferNativeToDevelopmentWallet(uint256 amount) private {
        developmentWallet.transfer(amount);
    }
}

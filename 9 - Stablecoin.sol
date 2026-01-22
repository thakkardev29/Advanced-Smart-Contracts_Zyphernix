// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SimpleStablecoin is ERC20, Ownable, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    /* ========== ROLES ========== */

    bytes32 public constant PRICE_ORACLE_ROLE =
        keccak256("PRICE_ORACLE_ROLE");

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable collateralAsset;
    uint8 public immutable collateralAssetDecimals;

    AggregatorV3Interface public priceOracle;

    // 150 = 150% collateralization
    uint256 public collateralRatio = 150;

    /* ========== EVENTS ========== */

    event StablecoinMinted(
        address indexed user,
        uint256 mintedAmount,
        uint256 collateralLocked
    );

    event StablecoinRedeemed(
        address indexed user,
        uint256 burnedAmount,
        uint256 collateralReleased
    );

    event OracleUpdated(address indexed newOracle);
    event CollateralRatioUpdated(uint256 newRatio);

    /* ========== ERRORS ========== */

    error ZeroAddress();
    error ZeroMintAmount();
    error InsufficientBalance();
    error CollateralRatioInvalid();

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _collateralToken,
        address _initialOwner,
        address _priceOracle
    )
        ERC20("Simple USD Stablecoin", "sUSD")
        Ownable(_initialOwner)
    {
        if (_collateralToken == address(0)) revert ZeroAddress();
        if (_priceOracle == address(0)) revert ZeroAddress();

        collateralAsset = IERC20(_collateralToken);
        collateralAssetDecimals =
            IERC20Metadata(_collateralToken).decimals();

        priceOracle = AggregatorV3Interface(_priceOracle);

        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        _grantRole(PRICE_ORACLE_ROLE, _initialOwner);
    }

    /* ========== PRICE FEED ========== */

    function fetchLatestPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceOracle.latestRoundData();
        require(price > 0, "Invalid oracle data");
        return uint256(price);
    }

    /* ========== CORE LOGIC ========== */

    function mint(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroMintAmount();

        uint256 oraclePrice = fetchLatestPrice();

        uint256 usdValue =
            amount * (10 ** decimals());

        uint256 rawCollateral =
            (usdValue * collateralRatio) /
            (100 * oraclePrice);

        uint256 collateralRequired =
            (rawCollateral * (10 ** collateralAssetDecimals)) /
            (10 ** priceOracle.decimals());

        collateralAsset.safeTransferFrom(
            msg.sender,
            address(this),
            collateralRequired
        );

        _mint(msg.sender, amount);

        emit StablecoinMinted(
            msg.sender,
            amount,
            collateralRequired
        );
    }

    function redeem(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroMintAmount();
        if (balanceOf(msg.sender) < amount)
            revert InsufficientBalance();

        uint256 oraclePrice = fetchLatestPrice();

        uint256 usdValue =
            amount * (10 ** decimals());

        uint256 rawCollateral =
            (usdValue * 100) /
            (collateralRatio * oraclePrice);

        uint256 collateralToRelease =
            (rawCollateral * (10 ** collateralAssetDecimals)) /
            (10 ** priceOracle.decimals());

        _burn(msg.sender, amount);
        collateralAsset.safeTransfer(
            msg.sender,
            collateralToRelease
        );

        emit StablecoinRedeemed(
            msg.sender,
            amount,
            collateralToRelease
        );
    }

    /* ========== ADMIN FUNCTIONS ========== */

    function updateCollateralRatio(uint256 newRatio)
        external
        onlyOwner
    {
        if (newRatio < 100) revert CollateralRatioInvalid();
        collateralRatio = newRatio;
        emit CollateralRatioUpdated(newRatio);
    }

    function updatePriceOracle(address newOracle)
        external
        onlyRole(PRICE_ORACLE_ROLE)
    {
        if (newOracle == address(0)) revert ZeroAddress();
        priceOracle = AggregatorV3Interface(newOracle);
        emit OracleUpdated(newOracle);
    }

    /* ========== VIEW HELPERS ========== */

    function collateralNeededForMint(uint256 amount)
        public
        view
        returns (uint256)
    {
        if (amount == 0) return 0;

        uint256 oraclePrice = fetchLatestPrice();
        uint256 usdValue =
            amount * (10 ** decimals());

        uint256 rawCollateral =
            (usdValue * collateralRatio) /
            (100 * oraclePrice);

        return
            (rawCollateral * (10 ** collateralAssetDecimals)) /
            (10 ** priceOracle.decimals());
    }

    function collateralReturnedOnRedeem(uint256 amount)
        public
        view
        returns (uint256)
    {
        if (amount == 0) return 0;

        uint256 oraclePrice = fetchLatestPrice();
        uint256 usdValue =
            amount * (10 ** decimals());

        uint256 rawCollateral =
            (usdValue * 100) /
            (collateralRatio * oraclePrice);

        return
            (rawCollateral * (10 ** collateralAssetDecimals)) /
            (10 ** priceOracle.decimals());
    }
}

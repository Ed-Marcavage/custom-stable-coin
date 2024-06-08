// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "forge-std/console.sol";

/*
 * @title DSCEngine
 * @author Ed Marcavage
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    // Errors ///////
    ///////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__FailedToDepositCollateral();
    error DSCEngine__HealthFactorBelowMinimum(uint256 healthFactor);
    error DSCEngine__FailedToMintDsc();
    error DSCEngine__FailedToRedeemCollateral();
    error DSCEngine__TransferFailed();

    ///////////////////
    //State Variable //
    ///////////////////
    // 1. ADDITIONAL_FEED_PRECISION: This constant is used to adjust the price feed from 8 to 18 decimal places.
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    // 2. LIQUIDATION_PRECISION: This constant is used to adjust the liquidation threshold from 50% to 200%.
    uint256 private constant LIQUIDATION_PRECISION = 100;
    // 3. PRECISION: This constant is used to adjust the precision of the health factor to 18 decimal places.
    uint256 private constant PRECISION = 1e18;
    // 4. LIQUIDATION_THRESHOLD: This constant is used to set the liquidation threshold at 200%.
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    // 5. MIN_HEALTH_FACTOR: This constant is used to set the minimum health factor at 1.
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    DecentralizedStableCoin private immutable i_dsc;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint amount))
        private s_collateralDeposited;

    mapping(address user => uint amountDcsMinted) private s_DscMinted;

    /////////////////
    // Events///////
    ////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint indexed amount
    );
    address[] private s_collateralTokes;

    event CollateralRedeemed(
        address indexed user,
        address indexed token,
        uint indexed amount
    );

    ///////////////////
    // Modifiers///////
    ///////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokes.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////
    // Functions/////
    /////////////////

    /*
     * @param tokenCollateral: The address of the token to deposit as collateral
     * @param amountCollateral: The amount of the token to deposit as collateral
     * @param amountDscToMint: The amount of DSC to mint
     * @notice This function allows a user to deposit collateral and mint DSC in one transaction
     */

    function depositCollateralAndMintDSC(
        address tokenCollateral,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depostCollateral(tokenCollateral, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     *
     * @param tokenCollateral: The address of the token to redeem as collateral
     * @param amountCollateral: The amount of the token to redeem as collateral
     * @param amountDscToBurn: The amount of DSC to burn
     * @notice This function allows a user to redeem collateral and burn DSC in one transaction
     */
    function redeemCollateralForDSC(
        address tokenCollateral,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateral, amountCollateral);
    }

    function depostCollateral(
        address tokenCollateral,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateral] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateral, amountCollateral);

        bool success = IERC20(tokenCollateral).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__FailedToDepositCollateral();
        }
        // deposit collateral
    }

    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__FailedToMintDsc();
        }
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] -= amountCollateral;
        emit CollateralRedeemed(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transfer(
            msg.sender,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__FailedToRedeemCollateral();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(
        uint256 amountDscToBurn
    ) public moreThanZero(amountDscToBurn) {
        s_DscMinted[msg.sender] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(
            msg.sender,
            address(this),
            amountDscToBurn
        );

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // may not be needed bc reducing debt should increase health factor
    }

    ///Private Functions////
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        //50000000000000000000000_00000000_0000000000
        if (healthFactor < MIN_HEALTH_FACTOR /**1e18 */) {
            revert DSCEngine__HealthFactorBelowMinimum(healthFactor);
        }
    }

    function _healthFactor(address user) private view returns (uint256) {
        // get total dsc minted
        // get total collateral value
        (
            uint256 totalDscMinted,
            uint256 totalCollateralValue
        ) = _getAccountInformation(user);
        // video 8
        // time value by 50 then divide by 100
        uint256 collateralAdjustedForThreshold = (totalCollateralValue *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        //2000_00000000_0000000000
        // console.log("totalCollateralValue", totalCollateralValue / PRECISION);
        // console.log(
        //     "* LIQUIDATION_THRESHOLD (50)",
        //     totalCollateralValue * LIQUIDATION_THRESHOLD
        // );
        // console.log("% LIQUIDATION_PRECISION", collateralAdjustedForThreshold);
        // console.log("* PRECISION", collateralAdjustedForThreshold * PRECISION);
        // console.log(
        //     "HF",
        //     (collateralAdjustedForThreshold * PRECISION) / totalDscMinted
        // );

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValue)
    {
        totalCollateralValue = getAccountCollateralUSDValue(user);
        totalDscMinted = s_DscMinted[user];
    }

    /// Public & External Functions ///
    function getAccountCollateralUSDValue(
        address user
    ) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < s_collateralTokes.length; i++) {
            address token = s_collateralTokes[i];
            uint256 amount = s_collateralDeposited[user][token];
            uint256 price = getUsdValueOfCollateral(token, amount);
            totalCollateralValue += amount * price;
        }
    }

    function getUsdValueOfCollateral(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // * ADDITIONAL_FEED_PRECISION - adds 10 decimals to the price feed
        // 200000000000 -> 2000000000000000000000

        // / PRECISION - divides the price by 1e18
        // 2000000000000000000000 -> 2000

        // 2000_00000000_0000000000 = 2000_00000000 * 1e10
        uint256 convertedPriceFeedPrice = uint256(price) *
            ADDITIONAL_FEED_PRECISION;

        // 2000 = 2000_00000000_0000000000 / 1e18
        uint256 convertedPriceFeedPriceToPrecision = convertedPriceFeedPrice /
            PRECISION;

        uint256 priceUsd = amount * convertedPriceFeedPriceToPrecision;

        return priceUsd;
    }

    function getAccountAmountCollateral(
        address user,
        address token
    ) public view returns (uint totalCollateralAmount) {
        totalCollateralAmount = s_collateralDeposited[user][token];
    }

    function getDSCMinted(address user) public view returns (uint) {
        return s_DscMinted[user];
    }
}

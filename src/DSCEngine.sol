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

    ///////////////////
    //State Variable //
    ///////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    DecentralizedStableCoin private immutable i_dsc;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint amount))
        private s_collateralDeposited;

    mapping(address user => uint amountDcsMinted) private s_DscMinted;

    /////////////////
    // Events///////
    ////////////////
    event CollateralDeposited(address user, address token, uint amount);
    address[] private s_collateralTokes;

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

    function depostCollateral(
        address tokenCollateral,
        uint256 amountCollateral
    )
        external
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
    ) external moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///Private Functions////
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
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
        uint256 collateralAdjustedForThreshold = (totalCollateralValue *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

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
        // 1. uint256(price) converts the price from int256 to uint256.
        // 2. Multiply the price by ADDITIONAL_FEED_PRECISION to convert it to 18 decimal places for uniform calculation.
        //    This multiplication adjusts the 8 decimal place price to match the standard 18 decimal precision used in most DeFi projects.
        // 3. Multiply the adjusted price by the amount of the collateral to get the total value in 18 decimal places.
        // 4. Finally, divide by PRECISION to correct the multiplication by ADDITIONAL_FEED_PRECISION, ensuring the result is normalized to 18 decimals.
        uint256 priceUsd = (amount *
            (uint256(price) * ADDITIONAL_FEED_PRECISION)) / PRECISION;
        return priceUsd;
    }
}

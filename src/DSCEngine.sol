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
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";
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
    // Errors
    ///////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__FailedToDepositCollateral();
    error DSCEngine__HealthFactorBelowMinimum(uint256 healthFactor);
    error DSCEngine__FailedToMintDsc();
    error DSCEngine__FailedToRedeemCollateral();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ///////////////////
    // Types
    ///////////////////
    using OracleLib for AggregatorV3Interface;

    ///////////////////
    // State Variables
    ///////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators

    DecentralizedStableCoin private immutable i_dsc;

    /// @dev Mapping of token address to price feed address
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;

    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address collateralToken => uint256 amount))
        private s_collateralDeposited;

    /// @dev Amount of DSC minted by user
    mapping(address user => uint256 amount) private s_DSCMinted;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint indexed amount
    );
    address[] private s_collateralTokens;

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint amount
    );

    ///////////////////
    // Modifiers
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

    ///////////////////
    // Functions
    ///////////////////

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
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////

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
        depositCollateral(tokenCollateral, amountCollateral);
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
    ) external moreThanZero(amountCollateral) isAllowedToken(tokenCollateral) {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        redeemCollateral(tokenCollateral, amountCollateral);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have DSC minted, you will not be able to redeem until you burn your DSC
     */

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(
        uint256 amountDscToBurn
    ) external moreThanZero(amountDscToBurn) {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender); // may not be needed bc reducing debt should increase health factor
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     * Eds note:
     * totalCollateralToSeize - should always be 110% of debtToCover
     * _burnDsc is why the liqudator needs DSC
     *      - We need cover/remove the debt of the insolvent user until they are no longer insolvent
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // If covering 100 DSC, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Burn DSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(
            collateral,
            tokenAmountFromDebtCovered + bonusCollateral,
            user,
            msg.sender
        );
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////
    // Public Functions
    ///////////////////

    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__FailedToMintDsc();
        }
    }

    /*
     * @param tokenCollateral: The address of the token to deposit as collateral
     * @param amountCollateral: The amount of the token to deposit as collateral
     * @notice This function allows a user to deposit collateral
     * @note Updates mapping of user to amount of collateral deposited
     * @note Then transfers the collateral from the user to this contract
     */

    function depositCollateral(
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

    ///////////////////
    // Private Functions
    ///////////////////

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );

        // transfer collateral to liquidator, from this contracts balance
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__FailedToRedeemCollateral();
        }
    }

    /*
     * @dev low-level internal function, do not call unless the function calling is checking health factor before
     */
    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValue)
    {
        totalCollateralValue = getAccountCollateralValue(user);
        totalDscMinted = s_DSCMinted[user];
    }

    // @note - forcing 100% collateralization not 200%, i think
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 totalCollateralValue
        ) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, totalCollateralValue);
    }

    //The return value always has the same number of decimals as the token itself, whereas it is supposed to be an 18-decimal USD amount.
    // note crux of the issue
    // - amount is assumed to always be 1e18
    // - so if convertedPriceFeedPriceToPrecision is multiplied by 1e8 for example, the result will be off by 1e10 decimals bc convertedPriceFeedPriceToPrecision is actual price in USD (2000)
    // of by delta of token decimals & 18
    //      Left:  3000000000000
    //      Right: 30000000000000000000000

    // note - imact, internal acounting off causing HF to think value of
    // -- BTC is $0.000003 instead of $30,000
    // thus depositing 1 BTC basiclly doesnt impact HF
    function _getUsdValue(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );

        //30000.00000000
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        uint256 tokenDecimals = IERC20Metadata(token).decimals();
        uint256 amountAdjusted = amount * 10 ** (18 - tokenDecimals);

        uint256 convertedPriceFeedPrice = uint256(price) *
            ADDITIONAL_FEED_PRECISION;

        uint256 convertedPriceFeedPriceToPrecision = convertedPriceFeedPrice /
            PRECISION;
        // console.log("price", uint256(price));
        // console.log("convertedPriceFeedPrice", convertedPriceFeedPrice);
        // console.log(
        //     "convertedPriceFeedPriceToPrecision",
        //     convertedPriceFeedPriceToPrecision
        // );
        uint256 priceUsd = amount * convertedPriceFeedPriceToPrecision;
        //uint256 priceUsd = amountAdjusted * convertedPriceFeedPriceToPrecision;
        // console.log("priceUsd", priceUsd);
        return priceUsd;
    }

    // HF = (Collateral x 0.5) / DSC
    // OR Collateral / (DSC x 2)
    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 totalCollateralValue
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        // Effectively just halving the collateral value by dividing by 50 & multiplying by 100
        // 1,000_000000000000000000 (2e21)
        uint256 effectiveCollateralAtThreshold = (totalCollateralValue *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // Adjust for precision to maintain ratio accuracy
        //example
        // 123456789111111111 * PRECISION =
        // 123456789111111111_000000000000000000
        // multiply by 1e18 effectivly shifts the decimal place 18 places to the right
        // - or adds 18 zeros to the end of the number
        // 1,000_000000000000000000_000000000000000000 (1e39)
        uint256 collateralInTermsOfDsc = effectiveCollateralAtThreshold *
            PRECISION;

        // Calculate the health factor
        //1000000000000000000 (1e18) = (1e39) / 1e21
        uint256 healthFactor = collateralInTermsOfDsc / totalDscMinted;
        return healthFactor;
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        //.500000000000000000
        if (healthFactor < MIN_HEALTH_FACTOR /**1e18 */) {
            revert DSCEngine__HealthFactorBelowMinimum(healthFactor);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountInformation(
        address user
    )
        public
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValue)
    {
        (totalDscMinted, totalCollateralValue) = _getAccountInformation(user);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValue += _getUsdValue(token, amount);
        }
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    //The return value always has 18 decimals, but it should instead match the token's decimals since it returns a token amount.
    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        uint256 tokenDecimals = IERC20Metadata(token).decimals();

        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        uint256 adjustedUSD = usdAmountInWei * PRECISION;
        uint256 adjustedPrice = uint256(price) * ADDITIONAL_FEED_PRECISION;
        uint256 rawTokenAmount = adjustedUSD / adjustedPrice;
        uint256 tokenAmount = rawTokenAmount / (10 ** (18 - tokenDecimals));

        console.log("price", uint256(price));
        console.log("adjustedUSD", adjustedUSD);
        console.log("adjustedPrice", adjustedPrice);
        console.log("rawTokenAmount", rawTokenAmount);
        console.log("tokenAmount", tokenAmount);

        // note fixed broken
        //   price 29999.00000000
        //   adjustedUSD 2727181818181000000000000000000
        //   adjustedPrice 29999.000000000000000000
        //   rawTokenAmount .90909090 - note return this if broke
        //   tokenAmount 0 - return this when fixed

        return rawTokenAmount;
    }

    function getAccountAmountCollateral(
        address user,
        address token
    ) public view returns (uint totalCollateralAmount) {
        totalCollateralAmount = s_collateralDeposited[user][token];
    }

    function getDSCMinted(address user) public view returns (uint) {
        return s_DSCMinted[user];
    }

    function getHealthFactor(address user) public view returns (uint) {
        return _healthFactor(user);
    }

    function getLiquidationBonus() public pure returns (uint) {
        return LIQUIDATION_BONUS;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import "forge-std/console.sol";

contract DSCEngineTest is Test {
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 1 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    address public user = address(1);

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    uint256 public collateralToCover = 20 ether;

    DeployDecentralizedStableCoin deployDecentralizedStableCoin;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address public liquidator = makeAddr("liquidator");

    ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        // approve dsce contract to use amountCollateral amount of weth
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function setUp() external {
        deployDecentralizedStableCoin = new DeployDecentralizedStableCoin();
        (dsc, dsce, config) = deployDecentralizedStableCoin.run();
        (ethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    ///////////////////////////////////////////////////
    // TEST External & Public View & Pure Functions
    //////////////////////////////////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetUsdValuePriceChange() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);

        int256 ethUsdUpdatedPrice = 100e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 ethAmountChanged = 15e18;
        uint256 expectedUsdChanged = 1_500e18;
        uint256 actualUsdChanged = dsce.getUsdValue(weth, ethAmountChanged);

        assertEq(expectedUsdChanged, actualUsdChanged);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 1000 ether; //1000 * 1e18
        // 2,000$ per 1 eth in mock
        uint256 expectedWeth = 0.5 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testGetTokenAmountFromUsdPriceChanged() public {
        uint256 usdAmount = 1000 * 1e18; //1000 ether;
        // 2,000$ per 1 eth in mock
        uint256 expectedWeth = 0.5 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);

        int256 ethUsdUpdatedPrice = 15e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 usdAmountChanged = 5 * 1e18; //10 ether;
        // 2,000$ per 1 eth in mock
        uint256 expectedWethChanged = 333333333333333333;
        uint256 actualWethChanged = dsce.getTokenAmountFromUsd(
            weth,
            usdAmountChanged
        );
        assertEq(expectedWethChanged, actualWethChanged);
    }

    function testGetAccountAmountCollateral() public depositedCollateral {
        uint256 expectedUsd = AMOUNT_COLLATERAL * 2000;
        uint256 actualUsd = dsce.getAccountCollateralValue(USER);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetAccountInformation()
        public
        depositedCollateralAndMintedDsc
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, amountToMint);
        // 10_000000000000000000
        // 100000000000000000000_00000000_0000000000
        assertEq(expectedDepositedAmount, amountCollateral);
    }

    function testCalculateHealthFactor() public {
        uint256 dscMinted = 1000e18;
        uint256 collateralValue = 2000e18;
        uint256 expectedHealthFactor = 1e18;
        uint256 actualHealthFactor = dsce.calculateHealthFactor(
            dscMinted,
            collateralValue
        );
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    // Collateral Needed = Health Factor × Amount Borrowed × 2
    function testCalculateHealthFactorVariable() public {
        // HF 1
        uint256 dscMinted = 1000e18;
        uint256 collateralValue = 2000e18;
        uint256 expectedHealthFactor = 1e18;
        uint256 actualHealthFactor = dsce.calculateHealthFactor(
            dscMinted,
            collateralValue
        );
        assertEq(expectedHealthFactor, actualHealthFactor);

        // HF 2
        dscMinted = 1000e18;
        collateralValue = 4000e18;
        expectedHealthFactor = 2e18;
        actualHealthFactor = dsce.calculateHealthFactor(
            dscMinted,
            collateralValue
        );
        assertEq(expectedHealthFactor, actualHealthFactor);
        //6000_000000000000000000 @ 1000e18
        //12.000_000000000000000000
        //8000_000000000000000000
        console.log("requiredCollateral", requiredCollateral(2, 1500e18));

        // HF 2
        dscMinted = 1500e18;
        collateralValue = 6000e18;
        expectedHealthFactor = 2e18;
        actualHealthFactor = dsce.calculateHealthFactor(
            dscMinted,
            collateralValue
        );
        assertEq(expectedHealthFactor, actualHealthFactor);

        // HF 3
        dscMinted = 100e18;
        collateralValue = 600e18;
        expectedHealthFactor = 3e18;
        actualHealthFactor = dsce.calculateHealthFactor(
            dscMinted,
            collateralValue
        );
        assertEq(expectedHealthFactor, actualHealthFactor);

        dscMinted = 10e18;
        collateralValue = 100e18;
        expectedHealthFactor = 5e18;
        actualHealthFactor = dsce.calculateHealthFactor(
            dscMinted,
            collateralValue
        );
        assertEq(expectedHealthFactor, actualHealthFactor);

        dscMinted = 10e18;
        collateralValue = 20e18;
        expectedHealthFactor = 1e18;
        actualHealthFactor = dsce.calculateHealthFactor(
            dscMinted,
            collateralValue
        );
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function requiredCollateral(
        uint256 healthFactor,
        uint256 borrowedAmount
    ) public pure returns (uint256) {
        return healthFactor * borrowedAmount * 2;
    }

    function testCalculateVariableHealthFactor() public {
        uint256 startingAmountToMint = 10_000 ether;
        uint256 startingCollateral = 20_000 ether;
        uint256 expectedHealthFactor = 1e18;
        uint256 actualHealthFactor = dsce.calculateHealthFactor(
            startingAmountToMint,
            startingCollateral
        );
        //1_000000000000000000
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function testGetCollateralAccountAmountCollateral()
        public
        depositedCollateral
    {
        uint256 expectedUsd = AMOUNT_COLLATERAL;
        uint256 actualUsd = dsce.getAccountAmountCollateral(USER, weth);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetDSCMinted() public depositedCollateralAndMintedDsc {
        uint actualMinted = dsce.getDSCMinted(USER);
        assertEq(amountToMint, actualMinted);
    }

    ///////////////////
    // constructor ////
    ///////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testConstructorFailsMisMatchArraySize() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////
    // DEPOSIT ////
    ///////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanDepositCollateral() public depositedCollateral {
        uint actualCollateral = dsce.getAccountAmountCollateral(USER, weth);
        assertEq(AMOUNT_COLLATERAL, actualCollateral);
    }

    function testRevertIfUnapprovedToken() public {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__TokenNotAllowed.selector,
                address(ranToken)
            )
        );
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////
    // MINT ///////
    ///////////////

    function testMintDsc() public depositedCollateralAndMintedDsc {
        uint actualMinted = dsce.getDSCMinted(USER);
        assertEq(amountToMint, actualMinted);
    }

    function testRevertsIfMintZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testCanMintDSCRevertsHealthFactor() public depositedCollateral {
        vm.startPrank(USER);

        uint256 expectedHealthFactor = dsce.calculateHealthFactor(
            1001e18,
            dsce.getUsdValue(weth, AMOUNT_COLLATERAL)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorBelowMinimum.selector,
                uint256(expectedHealthFactor)
            )
        );
        dsce.mintDsc(1001e18);
        vm.stopPrank();
    }

    //////////////////////////////////////
    // redeemCollateral /////////////////
    /////////////////////////////////////
    function testRedeemCollateral() public depositedCollateralAndMintedDsc {
        uint256 expectedBalance = 5 ether;

        vm.startPrank(USER);

        // TEST SENDS 5 ETH TO USER
        dsce.redeemCollateral(weth, expectedBalance);
        uint256 actualBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(expectedBalance, actualBalance);

        // TEST UPDATES COLLATERAL MAPPING
        uint256 collateralExpectedDelta = amountCollateral - expectedBalance;
        uint256 collateralActualDelta = dsce.getAccountAmountCollateral(
            USER,
            weth
        );
        assertEq(collateralExpectedDelta, collateralActualDelta);

        vm.stopPrank();
    }

    function testRedeemCollateralRevertsZero()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsUnapprovedToken()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__TokenNotAllowed.selector,
                address(ranToken)
            )
        );
        dsce.redeemCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsBrokenHealthFactor()
        public
        depositedCollateralAndMintedDsc
    {
        uint256 redeemAllCollateral = amountCollateral - amountCollateral; //0
        vm.startPrank(USER);
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(
            dsce.getDSCMinted(USER),
            dsce.getUsdValue(weth, redeemAllCollateral)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorBelowMinimum.selector,
                uint256(expectedHealthFactor)
            )
        );
        dsce.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    //////////////////////////////////////
    // redeemCollateralForDSC ///////////
    /////////////////////////////////////
    function testRedeemCollateralForDSC()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(USER);
        // w.o this line - FAIL. Reason: revert: ERC20: insufficient allowance
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralForDSC(
            weth,
            amountCollateral,
            dsce.getDSCMinted(USER)
        );
        uint256 expectedBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(expectedBalance, amountCollateral);
        vm.stopPrank();
    }

    /////////////////////////
    // liquidate ///////////
    ////////////////////////

    // @todo
    // - drop price to 15, test getUsdValue
    // play around with liquidate function
    // fully understand HF calculation
    function weiToEther(
        uint256 weiAmount,
        uint256 preciscion
    ) public pure returns (uint256) {
        return weiAmount / preciscion;
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        //MockV3Aggregator(ethUsdPriceFeed).updateAnswer(20e8);
        console.log(
            "User depositing $%s (%s ETH) For %s DSC",
            weiToEther(dsce.getUsdValue(weth, amountCollateral), 1e18),
            weiToEther(amountCollateral, 1e18),
            weiToEther(amountToMint, 1e18)
        );
        dsce.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        //100_000000000000000000
        console.log(
            "... and has a current HF of: %s = %s / %s * 2",
            weiToEther(dsce.getHealthFactor(USER), 1e18),
            weiToEther(dsce.getUsdValue(weth, amountCollateral), 1e18),
            weiToEther(amountToMint, 1e18)
        );
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dsce.getHealthFactor(USER);
        //.900000000000000000
        console.log(
            "Price of ETH droped to $%s! User now has deposited $%s For %s DSC",
            weiToEther(uint256(ethUsdUpdatedPrice), 1e8),
            weiToEther(dsce.getUsdValue(weth, amountCollateral), 1e18),
            weiToEther(amountToMint, 1e18)
        );
        console.log(
            "... and has a current HF of: .%s = %s / %s * 2",
            weiToEther(dsce.getHealthFactor(USER), 1e16),
            weiToEther(dsce.getUsdValue(weth, amountCollateral), 1e18),
            weiToEther(amountToMint, 1e18)
        );
        vm.startPrank(liquidator);
        ERC20Mock(weth).mint(liquidator, collateralToCover);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDSC(weth, collateralToCover, amountToMint);
        console.log(
            "Liquidator depositing $%s (%s ETH) For %s DSC",
            weiToEther(dsce.getUsdValue(weth, collateralToCover), 1e18),
            weiToEther(collateralToCover, 1e18),
            weiToEther(amountToMint, 1e18)
        );
        console.log(
            "... and has a current HF of: %se17 = %s / %s * 2",
            weiToEther(dsce.getHealthFactor(liquidator), 1e17),
            weiToEther(dsce.getUsdValue(weth, collateralToCover), 1e18),
            weiToEther(amountToMint, 1e18)
        );
        dsc.approve(address(dsce), amountToMint);
        //console log USER balance of DSC
        console.log("Before User has %s DSC", dsc.balanceOf(USER));
        //100000000000000000000
        //100000000000000000000
        dsce.liquidate(weth, USER, amountToMint); // We are covering their whole debt
        console.log("After User has %s DSC", dsc.balanceOf(USER));
        // bonus collateral - .555555555555555555
        // =
        console.log(
            "User has been liquidated! Their current HF is: %s = %s / %s * 2",
            weiToEther(dsce.getHealthFactor(USER), 1e18),
            weiToEther(
                dsce.getUsdValue(
                    weth,
                    dsce.getAccountAmountCollateral(USER, weth)
                ),
                1e18
            ),
            weiToEther(dsce.getDSCMinted(USER), 1e18)
        );
        console.log(
            "User Currently has $%s (%se17 ETH)",
            weiToEther(
                dsce.getUsdValue(
                    weth,
                    dsce.getAccountAmountCollateral(USER, weth)
                ),
                1e18
            ),
            //3_888888888888888890
            weiToEther(dsce.getAccountAmountCollateral(USER, weth), 1e17)
        );
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);

        // 5$ in ETH / 15$ per ETH = 0.333 ETH
        //5555555555555555555
        console.log(
            "getTokenAmountFromUsd",
            dsce.getTokenAmountFromUsd(weth, amountToMint)
        );
        console.log(
            "getLiquidationBonus",
            dsce.getTokenAmountFromUsd(weth, amountToMint) /
                dsce.getLiquidationBonus()
        );
        uint256 expectedWeth = dsce.getTokenAmountFromUsd(weth, amountToMint) +
            (dsce.getTokenAmountFromUsd(weth, amountToMint) /
                dsce.getLiquidationBonus());

        uint256 hardCodedExpected = 6_111_111_111_111_111_110;

        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost - 110% of the amount minted
        uint256 amountLiquidated = dsce.getTokenAmountFromUsd(
            weth,
            amountToMint
        ) +
            (dsce.getTokenAmountFromUsd(weth, amountToMint) /
                dsce.getLiquidationBonus());

        uint256 usdAmountLiquidated = dsce.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = dsce.getUsdValue(
            weth,
            amountCollateral
        ) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(USER);
        console.log("userCollateralValueInUsd", userCollateralValueInUsd);
        //70_000000000000000020
        uint256 hardCodedExpectedValue = 70_000_000_000_000_000_020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }
}

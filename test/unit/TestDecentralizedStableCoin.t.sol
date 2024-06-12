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

    DeployDecentralizedStableCoin deployDecentralizedStableCoin;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depostCollateral(weth, AMOUNT_COLLATERAL);
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

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 1000 * 1e18; //1000 ether;
        // 2,000$ per 1 eth in mock
        uint256 expectedWeth = 0.5 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
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
        dsce.depostCollateral(weth, 0);
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
        dsce.depostCollateral(address(ranToken), AMOUNT_COLLATERAL);
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

    function testLiquidate() public {
        // 10 ETH -> 20,000 USD
        uint256 startingCollateral = 10 ether;
        uint256 startingAmountToMint = 10_000 ether;
        uint256 liquidatorCollateral = 20 ether;
        uint256 liquidatorAmountToMint = 10_000 ether;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), startingCollateral);
        // HF - 1_000000000000000000 (20k/10k - 10 ETH @ 2,000 USD; 10,000 DSC minted)
        dsce.depositCollateralAndMintDSC(
            weth,
            startingCollateral,
            startingAmountToMint
        );
        console.log("1 - health factor", dsce.getHealthFactor(USER));
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 1099e8; // 1 ETH = $1,000
        console.log("ethUsdPriceFeed", uint256(ethUsdUpdatedPrice));
        //1000_00000000

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // HF - .500000000000000000 (10k/10k - 10 ETH @ 1,000 USD; 10,000 DSC minted)
        console.log("2 - health factor", dsce.getHealthFactor(USER));

        ERC20Mock(weth).mint(liquidator, liquidatorCollateral);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), liquidatorCollateral);
        dsce.depositCollateralAndMintDSC(
            weth,
            liquidatorCollateral,
            liquidatorAmountToMint
        );
        // HF - 1_000000000000000000 (20k/10k - 20 ETH @ 1,000 USD; 10,000 DSC minted)
        console.log("3 - health factor", dsce.getHealthFactor(liquidator));
        dsc.approve(address(dsce), liquidatorAmountToMint);
        dsce.liquidate(weth, USER, liquidatorAmountToMint);
        vm.stopPrank();

        // uint256 tokenAmountFromDebtCovered = dsce.getTokenAmountFromUsd(
        //     weth,
        //     liquidatorCollateral
        // );
        // //9989_000000000000000000
        // //11_000000000000000000
        // //10000_000000000000000000

        //weth 500000000000000000
        console.log("weth balance", ERC20Mock(weth).balanceOf(liquidator));
        assertEq(dsc.balanceOf(liquidator), startingAmountToMint);
    }
}

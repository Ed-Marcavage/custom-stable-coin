// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import "forge-std/console.sol";

contract DSCEngineTest is Test {
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 1 ether;
    uint256 amountCollateral = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    address public user = address(1);
    uint256 amountToMint = 100 ether;

    DeployDecentralizedStableCoin deployDecentralizedStableCoin;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsedPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    function setUp() external {
        deployDecentralizedStableCoin = new DeployDecentralizedStableCoin();
        (dsc, dsce, config) = deployDecentralizedStableCoin.run();
        (ethUsedPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    ///////////////////
    // constructor ////
    ///////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testConstructorFailsMisMatchArraySize() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsedPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = dsce.getUsdValueOfCollateral(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    /////////////////////////
    // depositCollateral ////
    /////////////////////////

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depostCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depostCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanDepositCollateral() public depositedCollateral {
        uint actualCollateral = dsce.getAccountAmountCollateral(USER, weth);
        assertEq(AMOUNT_COLLATERAL, actualCollateral);
    }

    function testCanMintDSC() public depositedCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(1000e18);

        uint actualCollateral = dsce.getDSCMinted(USER);
        assertEq(1000e18, actualCollateral);
        vm.stopPrank();
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether; //100 * 10^18
        // 2,000$ per 1 eth, 0.05 eth per 100$
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testRevertIfUnapprovedToken() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
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

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanDepositedCollateralAndGetAccountInfo()
        public
        depositedCollateralAndMintedDsc
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        console.log("totalDscMinted", totalDscMinted); //100_000000000000000000
        console.log("collateralValueInUsd", collateralValueInUsd); //20000_000000000000000000
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, amountToMint);
        // 10_000000000000000000
        // 100000000000000000000_00000000_0000000000
        assertEq(expectedDepositedAmount, amountCollateral);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator wethUsdPriceFeed;

    uint96 public constant MAX_DEPOSIT = type(uint96).max;
    uint256 public timesMintCalled;
    uint256 public timesLiquidateCalled;
    uint256 public timesBurnCalled;
    address[] public usersWithCollateralDeposited;
    address[] public usersWithDebt;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        wethUsdPriceFeed = MockV3Aggregator(dsce.getPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amountDsc, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];

        (uint256 totalDscMinted, uint256 totalCollateralValue) = dsce
            .getAccountInformation(sender);

        // 100 ETH (collateral) @1$
        // 20 DSC (minted)
        // HF = 2.5
        // (100 /  2) - 20 = 30
        // 100 ETH w/ 20+30 DSC minted = HF 1
        // @note - this equation gets us the max DSC that can be minted by getting HF = 1
        int256 maxDscToMint = (int256(totalCollateralValue) / 2) -
            int256(totalDscMinted);

        if (maxDscToMint < 0) {
            return;
        }

        amountDsc = bound(amountDsc, 0, uint256(maxDscToMint));

        if (amountDsc == 0) {
            return;
        }

        vm.startPrank(sender);
        dsce.mintDsc(amountDsc);
        vm.stopPrank(); //.0094828757560572792
        usersWithDebt.push(sender);
        timesMintCalled++;
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function burnDsc(uint256 amountDscToBurn, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];

        uint256 dscMinted = dsce.getDSCMinted(sender);
        if (dscMinted == 0) {
            return;
        }
        amountDscToBurn = bound(amountDscToBurn, 1, dscMinted);
        if (amountDscToBurn == 0) {
            return;
        }
        vm.startPrank(sender);
        IERC20(address(dsc)).approve(address(dsce), amountDscToBurn);
        dsce.burnDsc(amountDscToBurn);
        vm.stopPrank();
        timesBurnCalled++;
    }

    function liquidate(
        uint256 collateralSeed,
        uint256 underCollaterlizedUserSeed,
        uint256 debtToCover
    ) public {
        //limit collateral type
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        //limit users with debt
        if (usersWithDebt.length == 0) {
            return;
        }
        address sender = usersWithDebt[
            underCollaterlizedUserSeed % usersWithDebt.length
        ];
        console.log("getHealthFactor: ", dsce.getHealthFactor(sender));
        if (dsce.getHealthFactor(sender) >= 1e18) {
            return;
        }

        debtToCover = bound(debtToCover, 1, dsce.getDSCMinted(sender));

        // if (debtToCover == 0) {
        //     return;
        // }
        uint256 collateralAmount = dsce.getTokenAmountFromUsd(
            address(weth),
            debtToCover
        );
        console.log("collateralAmount: ", collateralAmount);
        //console.log("collateralAmountoDeposit: ", collateralAmountoDeposit);
        console.log("debtToCover: ", debtToCover);
        if (collateralAmount == 0) {
            return;
        }
        uint256 collateralAmountoDeposit = collateralAmount * 3;
        vm.startPrank(msg.sender);
        weth.mint(msg.sender, collateralAmountoDeposit);
        weth.approve(address(dsce), collateralAmountoDeposit);
        dsce.depositCollateralAndMintDSC(
            address(weth),
            collateralAmountoDeposit,
            debtToCover
        );
        dsce.liquidate(sender, address(collateral), debtToCover);
        vm.stopPrank();
        timesLiquidateCalled++;
        // limit debit about
    }

    // function liquidate(
    //     uint256 collateralSeed,
    //     address userToBeLiquidated,
    //     uint256 debtToCover
    // ) public {
    //     uint256 minHealthFactor = dsce.getMinHealthFactor();
    //     uint256 userHealthFactor = dsce.getHealthFactor(userToBeLiquidated);
    //     if (userHealthFactor >= minHealthFactor) {
    //         return;
    //     }
    //     debtToCover = bound(debtToCover, 1, uint256(type(uint96).max));
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     dsce.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    //     timesLiquidateCalled++;
    // }

    // fail_on_revert - false -> & w/o bound - would catch
    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateral = dsce.getAccountAmountCollateral(
            msg.sender,
            address(collateral)
        );
        // say there is a bug, where user can redeem more than they have
        // w/o this bound & fail_on_revert = false, we would catch this
        // but with this bound & fail_on_revert = true, we would not catch this
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        // or we could use https://book.getfoundry.sh/cheatcodes/assume
        if (amountCollateral == 0) {
            return;
        }
        uint256 collateralUSD = dsce.getAccountCollateralValue(msg.sender);
        uint256 dscValue = dsce.getDSCMinted(msg.sender);
        uint256 amountCollateralUSD = dsce.getUsdValue(
            address(collateral),
            amountCollateral
        );
        if (
            dsce.calculateHealthFactor(
                dscValue,
                collateralUSD - amountCollateralUSD
            ) < 1e18
        ) {
            return;
        }
        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // function updateCollateralPrice(uint96 ethUsdUpdatedPrice) public {
    //     int256 ethUsdPrice = int256(uint256(ethUsdUpdatedPrice));
    //     wethUsdPriceFeed.updateAnswer(ethUsdPrice);
    // }

    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/console.sol";

import {Handler} from "./Handler.t.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// note
// fail_on_revert - only care about invariant reverting
contract Invariants is StdInvariant, Test {
    DeployDecentralizedStableCoin deployDecentralizedStableCoin;
    DecentralizedStableCoin dsc;
    Handler handler;

    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    function setUp() external {
        deployDecentralizedStableCoin = new DeployDecentralizedStableCoin();
        (dsc, dsce, config) = deployDecentralizedStableCoin.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);
        console.log("wethValue: ", wethValue);
        console.log("wbtcValue: ", wbtcValue);
        console.log("totalSupply: ", totalSupply);
        console.log("timesMintCalled: ", handler.timesMintCalled());
        console.log("timesLiquidateCalled: ", handler.timesLiquidateCalled());
        console.log("timesBurnCalled: ", handler.timesBurnCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_getterShouldNotRevert() public view {
        dsce.getCollateralTokens();
        dsce.getLiquidationBonus();
        dsce.getUsdValue(weth, 1);
        dsce.getHealthFactor(address(this));
        dsce.getAccountInformation(address(this));
        dsce.getAccountCollateralValue(address(this));
        dsce.getAccountAmountCollateral(address(this), weth);
        dsce.getDSCMinted(address(this));
        dsce.getTokenAmountFromUsd(weth, 1);
    }
}

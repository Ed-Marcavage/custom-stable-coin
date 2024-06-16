// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.18;

// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {console} from "forge-std/console.sol";

// //import {Handler} from "./Handler.t.sol";
// import {DSCEngine} from "../../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.sol";
// import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDecentralizedStableCoin deployDecentralizedStableCoin;
//     DecentralizedStableCoin dsc;

//     DSCEngine dsce;
//     HelperConfig config;
//     address ethUsdPriceFeed;
//     address wbtcUsdPriceFeed;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployDecentralizedStableCoin = new DeployDecentralizedStableCoin();
//         (dsc, dsce, config) = deployDecentralizedStableCoin.run();
//         (, , weth, wbtc, ) = config.activeNetworkConfig();
//         targetContract(address(dsce));
//     }

//     function invariant_protocolMustHaveMoreThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

//         uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);
//         console.log("wethValue: ", wethValue);
//         console.log("wbtcValue: ", wbtcValue);
//         console.log("totalSupply: ", totalSupply);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }

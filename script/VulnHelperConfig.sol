// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;
import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20DecimalsMock} from "@openzeppelin/contracts/mocks/ERC20DecimalsMock.sol";

contract VulnHelperConfig is Script {
    uint8 public constant FEED_DECIMALS = 8;
    uint8 public constant WETH_DECIMALS = 18;
    uint8 public constant WBTC_DECIMALS = 8;

    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11_155_111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD
                wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
                wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function getOrCreateAnvilEthConfig()
        public
        returns (NetworkConfig memory anvilNetworkConfig)
    {
        // Check to see if we set an active network config
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(
            FEED_DECIMALS,
            ETH_USD_PRICE
        );
        ERC20DecimalsMock wethMock = new ERC20DecimalsMock(
            "WETH",
            "WETH",
            WETH_DECIMALS
        );
        //wethMock.mint(msg.sender, 1000 * 10 ** WETH_DECIMALS);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            FEED_DECIMALS,
            BTC_USD_PRICE
        );
        ERC20DecimalsMock wbtcMock = new ERC20DecimalsMock(
            "WBTC",
            "WBTC",
            WBTC_DECIMALS
        );
        // wbtcMock.mint(msg.sender, 1000 * 10 ** WBTC_DECIMALS);
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed), // ETH / USD
            weth: address(wethMock),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
//test/mocks/MockV3Aggregator.sol

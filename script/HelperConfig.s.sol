// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        address wETHUSDPriceFeed;
        address wBTCUSDPriceFeed;
        address wETH;
        address wBTC;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaETHConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilETHConfig();
        }
    }

    /**
     * @notice Gets the network configuration if you want to deploy on Sepolia network
     */
    function getSepoliaETHConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wETHUSDPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            wBTCUSDPriceFeed: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c,
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    /**
     * @notice Gets or creates the network configuration if you want to deploy on anvil network
     */
    function getOrCreateAnvilETHConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wETHUSDPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ETHUSDPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wETHMock = new ERC20Mock();
        MockV3Aggregator BTCUSDPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wBTCMock = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            wETHUSDPriceFeed: address(ETHUSDPriceFeed),
            wBTCUSDPriceFeed: address(BTCUSDPriceFeed),
            wETH: address(wBTCMock),
            wBTC: address(wETHMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}

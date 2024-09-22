// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// Invariants:
// protocol must never be insolvent / underCollateralized
// TODO: users can't create stableCoins with a bad health factor
// TODO: a user should only be able to be liquidated if they have a bad health factor

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../../script/DepolyDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {StopOnRevertHandler} from "./StopOnRevertHandler.t.sol";
import {console} from "forge-std/console.sol";

contract StopOnRevertInvariants is StdInvariant, Test {
    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    HelperConfig public config;

    address public ETHUSDPriceFeed;
    address public BTCUSDPriceFeed;
    address public wETH;
    address public wBTC;

    uint256 collateralAmount = 10 ether;
    uint256 amountToMint = 100 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    address public constant USER = address(1);
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    StopOnRevertHandler public handler;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ETHUSDPriceFeed, BTCUSDPriceFeed, wETH, wBTC,) = config.activeNetworkConfig();
        handler = new StopOnRevertHandler(engine, dsc);
        targetContract(address(handler));
        // targetContract(address(ETHUSDPriceFeed)); Why can't we just do this?
        // Cause the handler will check for stale price feed
    }

    function invariant_protocolMustHaveMoreValueThatTotalSupplyDollars() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 wETHDeposited = ERC20Mock(wETH).balanceOf(address(engine));
        uint256 wBTCDeposited = ERC20Mock(wBTC).balanceOf(address(engine));

        uint256 wETHValue = engine.getUSDValue(wETH, wETHDeposited);
        uint256 wBTCValue = engine.getUSDValue(wBTC, wBTCDeposited);

        console.log("wethValue: %s", wETHValue);
        console.log("wbtcValue: %s", wBTCValue);

        assert(wETHValue + wBTCValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        // engine.getHealthFactor(msg.sender);
        // engine.getCollateralTokenPriceFeed(wETH);
        engine.getDSC();
        engine.getCollateralTokens();
        engine.getMinHealthFactor();
        engine.getLiquidationPrecision();
        engine.getLiquidationBonus();
        engine.getLiquidationThreshold();
        engine.getAdditionalFeedPrecision();
        engine.getPrecision();
        // engine.getAccountInformation(msg.sender);
        // engine.getCollateralBalanceOfUser(msg.sender, wETH);
        // engine.getUSDValue(wETH, amount);
        // engine.getAccountCollateralValueInUSD(msg.sender);
        // engine.getTokenAmountFromUSD(wETH, collateralValueInUSD);
        // engine.calculateHealthFactor(msg.sender);
    }
}

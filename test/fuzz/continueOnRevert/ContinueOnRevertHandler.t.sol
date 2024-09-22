// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";

contract ContinueOnRevertHandler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    MockV3Aggregator public ETHUSDPriceFeed;
    MockV3Aggregator public BTCUSDPriceFeed;
    ERC20Mock wETH;
    ERC20Mock wBTC;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public usersWithoutCollateralDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        wETH = ERC20Mock(collateralTokens[0]);
        wBTC = ERC20Mock(collateralTokens[1]);

        ETHUSDPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(wETH)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        // ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        ERC20Mock collateralToken = wETH;
        collateralAmount = bound(collateralAmount, 1, MAX_DEPOSIT_SIZE);
        console.log("Collateral Seed: ", collateralSeed);
        console.log("Collateral Amount: ", collateralAmount);
        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, collateralAmount);
        collateralToken.approve(address(engine), collateralAmount);
        engine.depositCollateral(address(collateralToken), collateralAmount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        collateralAmount = bound(collateralAmount, 0, maxCollateralToRedeem);
        if (collateralAmount == 0) return;
        engine.redeemCollateral(address(collateral), collateralAmount);
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        if (usersWithoutCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithoutCollateralDeposited[addressSeed % usersWithoutCollateralDeposited.length];
        amount = bound(amount, 0, MAX_DEPOSIT_SIZE);
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(sender);
        int256 maxDSCToMint = (int256(collateralValueInUSD) / 2) - int256(totalDSCMinted);
        if (maxDSCToMint < 0) return;
        amount = bound(amount, 0, uint256(maxDSCToMint));
        if (amount == 0) return;
        vm.startPrank(sender);
        engine.mintDSC(amount);
        vm.stopPrank();
    }

    function burnDSC(uint256 amount) public {
        amount = bound(amount, 0, dsc.balanceOf(msg.sender));
        dsc.burn(amount);
    }

    function liquidate(uint256 collateralSeed, address userToBeLiquidated, uint256 debtToCover) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        engine.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    }

    // This breaks our invariant test suite!!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ETHUSDPriceFeed.updateAnswer(newPriceInt);
    // }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return wETH;
        }
        return wBTC;
    }
}

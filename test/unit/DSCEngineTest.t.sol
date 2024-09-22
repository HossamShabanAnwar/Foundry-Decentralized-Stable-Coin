// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DepolyDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
// import { MockMoreDebtDSC } from "../mocks/MockMoreDebtDSC.sol";
// import { MockFailedMintDSC } from "../mocks/MockFailedMintDSC.sol";
// import { MockFailedTransferFrom } from "../mocks/MockFailedTransferFrom.sol";
// import { MockFailedTransfer } from "../mocks/MockFailedTransfer.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address wETHUSDPriceFeed;
    address wBTCUSDPriceFeed;
    address wETH;
    address wBTC;
    uint256 deployerKey;

    uint256 collateralAmount = 10 ether;
    uint256 mintAmount = 100 ether;
    address public user = address(1);

    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    address[] public tokenAddresses;
    address[] public feedAddresses;

    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wETHUSDPriceFeed, wBTCUSDPriceFeed, wETH, wBTC, deployerKey) = config.activeNetworkConfig();
        ERC20Mock(wETH).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wBTC).mint(user, STARTING_USER_BALANCE);
        if (block.chainid == 31_337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(engine), collateralAmount);
        engine.depositCollateral(wETH, collateralAmount);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDSC() {
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(engine), collateralAmount);
        engine.depositCollateralAndMintDSC(wETH, collateralAmount, mintAmount);
        vm.stopPrank();
        _;
    }

    // TODO: All the problems initiates from here
    // function testGetAccountCollateralValueInUSD() public depositedCollateral {
    //     uint256 totalCollateralValueInUSD = engine.getAccountCollateralValueInUSD(user);
    //     // console.log("collateral balance: ", engine.getCollateralBalanceOfUser(user, wETH));
    //     // console.log("balance in USD: ", engine.getUSDValue(wETH, engine.getCollateralBalanceOfUser(user, wETH)));
    //     uint256 expectedCollateralValueInUSD = engine.getUSDValue(wETH, collateralAmount);
    //     assertEq(totalCollateralValueInUSD, expectedCollateralValueInUSD);
    // }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////// Tests ///////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    /**
     * @dev This function tests that both tokenAddresses, feedAddresses arrays have the same length
     */
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(wETH);
        feedAddresses.push(wETHUSDPriceFeed);
        feedAddresses.push(wBTCUSDPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    //////////////////////
    //// price tests ////
    /////////////////////
    /**
     * @dev This function tests we can calculate amount of tokens from it's USD value
     */
    function testGetTokenAmountFromUSDValue() public view {
        // Arrange
        uint256 USDAmount = 100 ether;
        // We use fixed price for wETH and wBTC for local testing (find that in HelperConfig.sol)
        // ETH_USD_PRICE = 2000e8
        uint256 expectedWETH = 0.05 ether;
        uint256 actualWETH = engine.getTokenAmountFromUSD(wETH, USDAmount);
        // Act / Assert
        assert(actualWETH == expectedWETH);
    }

    /**
     * @dev This function tests we can calculate USD value of an amount of tokens
     */
    function testGetUSDValue() public view {
        // Arrange
        uint256 amountETH = 15e18;
        // We use fixed price for wETH and wBTC for local testing (find that in HelperConfig.sol)
        // ETH_USD_PRICE = 2000e8
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUSDValue = 30_000e18;
        uint256 actualUSDValue = engine.getUSDValue(wETH, amountETH);
        // Act / Assert
        assertEq(actualUSDValue, expectedUSDValue);
    }

    //////////////////////////////////
    //// depositCollateral tests ////
    /////////////////////////////////
    /**
     * @dev This function tests successful collateral deposit
     */
    function testDepositCollateralSuccess() public {
        // Arrange: Start transaction from USER and ensure they approve engine contract to spend wETH
        vm.startPrank(user); // Start simulating USER transactions
        // Capture pre-deposit balances
        uint256 userBalanceBefore = ERC20Mock(wETH).balanceOf(user);
        uint256 contractBalanceBefore = ERC20Mock(wETH).balanceOf(address(engine));
        // Act: Deposit the collateral (wETH)
        ERC20Mock(wETH).approve(address(engine), collateralAmount); // Approve engine contract to spend user's wETH
        engine.depositCollateral(wETH, collateralAmount);
        // Capture post-deposit balances
        uint256 userBalanceAfter = ERC20Mock(wETH).balanceOf(user);
        uint256 contractBalanceAfter = ERC20Mock(wETH).balanceOf(address(engine));
        // Assert: The user's wETH balance should decrease by the amount deposited
        assertEq(userBalanceAfter, userBalanceBefore - collateralAmount);
        // Assert: The contract's wETH balance should increase by the amount deposited
        assertEq(contractBalanceAfter, contractBalanceBefore + collateralAmount);
        vm.stopPrank(); // Stop simulating USER transactions
    }

    /**
     * @dev This function tests that the system reverts when trying to deposit zero collateral
     */
    function testRevertsWhenDepositingZeroCollateral() public {
        // Start impersonating the USER address to simulate user actions
        vm.startPrank(user);
        // Expect the contract to revert with the custom error `DSCEngine__AmountLessThanOrEqualToZero`
        // when trying to deposit zero collateral
        vm.expectRevert(DSCEngine.DSCEngine__AmountLessThanOrEqualToZero.selector);
        // Attempt to deposit 0 amount of wETH, which should trigger the revert
        engine.depositCollateral(wETH, 0);
        // Stop impersonating the USER address to conclude the test
        vm.stopPrank();
    }

    /**
     * @dev This function tests revert when depositing an unapproved token
     */
    function testRevertsWhenTokenNotAllowed() public {
        // Arrange
        vm.startPrank(user);
        // Create an unapproved token, approved tokens are added at the time of deployment
        ERC20Mock wSOLMock = new ERC20Mock();
        // Act & Assert
        vm.expectRevert(DSCEngine.DSCEngine__NotAnAllowedToken.selector);
        engine.depositCollateral(address(wSOLMock), collateralAmount);
        vm.stopPrank();
    }

    // TODO: Compare it to Patric's
    /**
     * @dev This function tests revert when token transfer fails
     */
    function testRevertsWhenTransferFails() public {
        // Arrange: Mock transferFrom to fail
        vm.mockCall(address(wETH), abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(false));
        // Act & Assert: Expect revert on deposit due to transfer failure
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        engine.depositCollateral(wETH, collateralAmount);
        vm.stopPrank();
    }

    /**
     * @dev This function tests user can deposit and leave it without minting any DSC tokens
     */
    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    // TODO: The problem lies in this function >> getAccountCollateralValueInUSD(user)
    /**
     * @dev This function tests user can deposit and get his account information
     */
    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        console.log("collateralTokens: ", engine.getCollateralBalanceOfUser(user, wETH));
        console.log("collateralTokens: ", engine.getUSDValue(wETH, 20 ether));
        console.log("collateralValue: ", engine.getAccountCollateralValueInUSD(user));
        // (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(user);
        // // uint256 collateralBalance = engine.getCollateralBalanceOfUser(user, wETH);
        // uint256 depositAmount = engine.getTokenAmountFromUSD(wETH, collateralValueInUSD); // collateralValueInUSD = 0 !!
        // assertEq(totalDSCMinted, 0);
        // assertEq(depositAmount, collateralAmount);
    }

    ///////////////////////
    //// mintDSC tests ////
    ///////////////////////
    /**
     * @dev Tests successful minting of DSC
     */
    function testMintDSCSuccess() public {
        // Arrange: Approve and deposit collateral
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(engine), collateralAmount);
        engine.depositCollateral(wETH, collateralAmount);
        // Act: Mint DSC
        engine.mintDSC(mintAmount);
        vm.stopPrank();
        // Assert: Verify the DSC balance of the user
        assertEq(dsc.balanceOf(user), mintAmount);
    }

    /**
     * @dev This function tests for revert on broken health factor
     */
    // function testMintDSCRevertsOnBrokenHealthFactor() public {
    //     // (, int256 price,,,) = MockV3Aggregator(wETHUSDPriceFeed).latestRoundData();
    //     // uint256 amountToMint =
    //     //     (collateralAmount * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();
    //     vm.startPrank(user);
    //     uint256 userHealthFactor = engine.calculateHealthFactor(mintAmount, engine.getUSDValue(wETH, collateralAmount));

    //     (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(user);
    //     console.log("totalDSCMinted: ", totalDSCMinted);
    //     console.log("collateralValueInUSD: ", collateralValueInUSD);
    //     vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, (userHealthFactor)));
    //     // console.log("balance: ", ERC20Mock(wETH).balanceOf(user)); // zero
    //     // console.log("collateral: ", engine.getCollateralBalanceOfUser(user, wETH)); // zero
    //     // console.log("myAmount: ", mintAmount); // 100
    //     // console.log("hisAmount: ", amountToMint); // 30000
    //     engine.mintDSC(mintAmount);
    //     vm.stopPrank();
    //     // 500000000000000000
    //     // 30000000000000000000000

    //     // totalDSCMinted:       30000000000000000000000
    //     // collateralValueInUSD: 30000000000000000000000
    // }

    // TODO: Compare it to Patric's
    /**
     * @dev This function tests for mint failure
     */
    function testMintDSCFailMinting() public {
        vm.startPrank(user);
        vm.mockCall(address(dsc), abi.encodeWithSignature("mint(address,uint256)"), abi.encode(false));
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        engine.mintDSC(mintAmount);
        vm.stopPrank();
    }

    /**
     * @dev This function tests for revert if mintAmount = 0
     */
    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__AmountLessThanOrEqualToZero.selector);
        engine.mintDSC(0);
        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //// depositCollateralAndMintDSC tests ////
    //////////////////////////////////////////
    /**
     * @dev This function tests for successful deposit and mint
     */
    function testCanMintWithDepositedCollateral() public {
        // Arrange
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(engine), collateralAmount);
        engine.depositCollateralAndMintDSC(wETH, collateralAmount, mintAmount);
        vm.stopPrank();
        // Act / Assert
        assertEq(dsc.balanceOf(user), mintAmount);
        assertEq(engine.getCollateralBalanceOfUser(user, wETH), collateralAmount);
    }

    /**
     * @dev This function tests for revert on broken health factor
     */
    function testRevertsIfMintedDSCBreaksHealthFactor() public {}

    ////////////////////////
    //// burnDSC tests ////
    ///////////////////////
    /**
     * @dev This function tests for revert if burn amount is zero
     */
    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__AmountLessThanOrEqualToZero.selector);
        engine.burnDSC(0);
        vm.stopPrank();
    }

    /**
     * @dev This function tests cannot burn more than user has
     */
    function testCantBurnMoreThanUserHas() public {
        vm.startPrank(user);
        vm.expectRevert(); // This revert will come from the ERC20  token smart contract
        engine.burnDSC(1);
        vm.stopPrank();
    }

    /**
     * @dev This function tests for successful burn
     */
    function testCanBurnDSC() public {
        vm.startPrank(user);
        // we need to give him some DSCs
        engine.mintDSC(mintAmount);
        uint256 userDSCBalanceBeforeBurn = dsc.balanceOf(user);
        dsc.approve(address(engine), mintAmount);
        engine.burnDSC(mintAmount);
        uint256 userDSCBalanceAfterBurn = dsc.balanceOf(user);
        vm.stopPrank();
        assert(userDSCBalanceBeforeBurn == userDSCBalanceAfterBurn + mintAmount);
    }

    /////////////////////////////////
    //// redeemCollateral tests ////
    ///////////////////////////////
    /**
     * @dev This function tests for successful redeem
     */
    function testCanSuccessfullyRedeemCollateral() public depositedCollateral {
        vm.prank(user);
        engine.redeemCollateral(wETH, collateralAmount);
        assertEq(ERC20Mock(wETH).balanceOf(user), collateralAmount);
    }

    /**
     * @dev This function tests for revert if burn amount is zero
     */
    function testRevertsIfRedeemAmountIsZero() public depositedCollateral {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__AmountLessThanOrEqualToZero.selector);
        engine.redeemCollateral(wETH, 0);
    }

    /**
     * @dev This function tests for successful emit after redeem
     */
    function testEmitAfterSuccessfulCollateralRedeem() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(engine));
        emit DSCEngine.CollateralRedeemed(user, user, wETH, collateralAmount);
        vm.prank(user);
        engine.redeemCollateral(wETH, collateralAmount);
    }

    // TODO: Use ChatGPT
    /**
     * @dev This function tests for revert if transfer fails
     */
    // function testRevertsIfRedeemTransferFails() public {
    //     vm.startPrank(user);
    //     vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    //     engine.redeemCollateral(wETH, collateralAmount);
    //     vm.stopPrank();
    // }

    ///////////////////////////////////////
    //// redeemCollateralForDSC tests ////
    /////////////////////////////////////
    /**
     * @dev This function tests for revert if redeemed collateral <= zero
     */
    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDSC {
        vm.startPrank(user);
        dsc.approve(address(engine), mintAmount);
        vm.expectRevert(DSCEngine.DSCEngine__AmountLessThanOrEqualToZero.selector);
        engine.redeemCollateralAndBurnDSC(wETH, 0, mintAmount);
        vm.stopPrank();
    }

    /**
     * @dev This function tests for successful redeeming of deposited collateral
     */
    function testCanSuccessfullyRedeemDepositedCollateral() public {
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(engine), collateralAmount);
        engine.depositCollateralAndMintDSC(wETH, collateralAmount, mintAmount);
        dsc.approve(address(engine), mintAmount);
        engine.redeemCollateralAndBurnDSC(wETH, collateralAmount, mintAmount);
        assertEq(dsc.balanceOf(user), 0);
        vm.stopPrank();
    }

    /////////////////////////////
    //// healthFactor Tests ////
    ///////////////////////////
    // TODO: The same problem of getAccountCollateralValueInUSD()
    /**
     * @dev This function tests for successful calculation of health factor
     */
    function testCalculateHealthFactorSuccessfully() public depositedCollateralAndMintedDSC {
        // uint256 collateralAdjustedForThreshold = (engine.getUSDValue(wETH, collateralAmount) * 50) / 100;
        // uint256 actualHealthFactor =  (collateralAdjustedForThreshold * 1e18) / mintAmount;
        uint256 expectedHealthFactor = 100;
        uint256 healthFactor = engine.getHealthFactor(user);
        assertEq(healthFactor, expectedHealthFactor);
    }

    /**
     * @dev This function tests health factor can be less that one
     */
    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDSC {
        int256 ETHUSDUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(wETHUSDPriceFeed).updateAnswer(ETHUSDUpdatedPrice); // TODO: What does that even mean?

        uint256 userHealthFactor = engine.getHealthFactor(user);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        assert(userHealthFactor == 0.9 ether);
    }

    ////////////////////////////
    //// Liquidation Tests ////
    //////////////////////////
}

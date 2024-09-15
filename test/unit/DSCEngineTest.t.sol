// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DepolyDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address wETHUSDPriceFeed;
    address wBTCUSDPriceFeed;
    address wETH;
    address wBTC;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wETHUSDPriceFeed,, wETH,,) = config.activeNetworkConfig();
        ERC20Mock(wETH).mint(USER, STARTING_ERC20_BALANCE);
    }

    function testGetUSDValue() public view {
        // Arrange
        uint256 ethAmount = 15e18; // 15 ETH
        // 15e18 * $2000 per ETH = 30,000e18;
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = engine.getUSDValue(wETH, ethAmount);

        // Act / Assert
        assert(actualUSD == expectedUSD);
    }

    function testRevertIfCollateralEqualZero() public {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__AmountLessThanZero.selector);
        engine.depositCollateral(wETH, 0);
        vm.stopPrank();
    }
}

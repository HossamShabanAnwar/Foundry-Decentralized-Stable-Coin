// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../../script/DepolyDSC.s.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ContinueOnRevertHandler} from "./ContinueOnRevertHandler.t.sol";

contract ContinueOnRevertInvariants is StdInvariant, Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address wETH;
    address wBTC;
    ContinueOnRevertHandler handler;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, wETH, wBTC,) = config.activeNetworkConfig();
        handler = new ContinueOnRevertHandler(engine, dsc);
        targetContract(address(handler)); // The contract we will invariant test his functions
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // Get the total value of all collateral in the protocol
        // compare it to the total dept (DSC)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWETHDeposited = IERC20(wETH).balanceOf(address(engine));
        uint256 totalWBTCDeposited = IERC20(wBTC).balanceOf(address(engine));
        uint256 wETHValue = engine.getUSDValue(wETH, totalWETHDeposited);
        uint256 wBTCValue = engine.getUSDValue(wETH, totalWBTCDeposited);

        assert(wETHValue + wBTCValue >= totalSupply);
    }
}

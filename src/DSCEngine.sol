// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
/**
 * @title DSCEngine
 * @author Hossam Elanany
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 *  This stable coin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be "over collateralized". At no point, should the value of all collateral be <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the make MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    /////////////////////////
    //////// Errors /////////
    /////////////////////////
    error DSCEngine__AmountLessThanOrEqualToZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__NotAnAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken(uint256 userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__AmountExceedsCollateral();

    ////////////////////////
    //////// Types /////////
    ////////////////////////
    using OracleLib for AggregatorV3Interface;

    /////////////////////////
    //// State Variables ////
    /////////////////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% over collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means 10% bonus
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18; // To transform between ETH and WEI
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    // In case of wrapped tokens (wBTC, WETH, ..) they are deployed as smart contracts so they have addresses
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amountCollateral)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;
    /////////////////////////
    //////// Events /////////
    /////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address token, uint256 amount);
    event DSCTokenMinted(address indexed user, uint256 amount);

    /////////////////////////
    /////// Modifiers ///////
    /////////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__AmountLessThanOrEqualToZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__NotAnAllowedToken();
        }
        _;
    }

    /////////////////////////
    /////// Functions ///////
    /////////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address DSCAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(DSCAddress);
    }

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amount of collateral to deposit.
     * @param amountDSCToMint The amount of decentralized stablecoin to mint.
     * @notice This function will deposit your collateral and mint DSC in one transaction.
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /**
     * @notice Follows CEI: Checks, Effects, Interactions
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amount of collateral to deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    /**
     * @notice Follows CEI: Checks, Effects, Interactions
     * @param amountDSCToMint The amount of decentralized stablecoin to mint.
     * @notice User must have more collateral value than the minimum threshold.
     */
    // TODO: Need to rethink the order here
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        _revertIfHealthFactorIsBroken(msg.sender);
        s_DSCMinted[msg.sender] += amountDSCToMint;
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
        emit DSCTokenMinted(msg.sender, amountDSCToMint);
    }

    /**
     * @notice This function handles both redeeming collateral and burning minted DSC.
     * @param collateralTokenAddress The address of the token to deposit as collateral.
     * @param collateralAmount The amount of collateral to deposit.
     * @param amountDSCToBurn The amount of DSC to burn.
     */
    function redeemCollateralAndBurnDSC(
        address collateralTokenAddress,
        uint256 collateralAmount,
        uint256 amountDSCToBurn
    ) external moreThanZero(collateralAmount) isAllowedToken(collateralTokenAddress) {
        _burnDSC(amountDSCToBurn, msg.sender, msg.sender);
        _redeemCollateral(collateralTokenAddress, collateralAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param collateralTokenAddress The address of the token to deposit as collateral.
     * @param collateralAmount The amount of collateral to deposit.
     * @notice User can use this tailored function to redeem his own collateral not others.
     */
    function redeemCollateral(address collateralTokenAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        nonReentrant
    {
        _redeemCollateral(collateralTokenAddress, collateralAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param amountDSC The amount of collateral to deposit.
     * @notice User can use this tailored function to burn his own DSC tokens not others.
     */
    function burnDSC(uint256 amountDSC) public moreThanZero(amountDSC) {
        _burnDSC(amountDSC, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // This too probably will never be invoked..
    }

    /**
     *
     * @param tokenCollateralAddress The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR.
     * @param deptToCover The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice You can partially liquidate a user.
     * @notice You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice This function working assumes that the protocol will be roughly 150% over collateralized in order for this to work.
     * @notice A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example: if the price of the collateral plummeted before anyone could be liquidated.
     *
     * Follows CEI: Checks, Effects, Interactions
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 deptToCover)
        external
        moreThanZero(deptToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // We want to burn their DSC "dept" and take the corresponding collateral as a prize
        // Bad user has $140 in ETH as collateral and $100 worth of minted DSC as "dept"
        // deptToCover = $100 (all the DSC dept that he has minted)
        // So $100 of DSC = $??? of ETH
        uint256 tokensToBeCoveredFromTotalDept = getTokenAmountFromUSD(tokenCollateralAddress, deptToCover);
        // We will give the liquidator extra 10% of wETH to incentive people to liquidate bad users
        uint256 bonusCollateral = (tokensToBeCoveredFromTotalDept * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToBeRedeemed = tokensToBeCoveredFromTotalDept + bonusCollateral;
        _redeemCollateral(tokenCollateralAddress, totalCollateralToBeRedeemed, user, msg.sender);
        _burnDSC(deptToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////////////////////////
    /// Private & Internal View Functions ///
    /////////////////////////////////////////
    /**
     *
     * @param amountDSC Amount of DSC dept.
     * @param owner The bad user who's gonna be striped from his collateral.
     * @param liquidator The user who's gonna pay the bad user's dept and take his collateral + bonus.
     *
     * @notice This is more of a generic function where any two users can play the owner and liquidator roles.
     * @dev Do not call this Low-level internal function unless the function calling it checks for health factors being broken
     */
    function _burnDSC(uint256 amountDSC, address owner, address liquidator) private {
        s_DSCMinted[owner] -= amountDSC;
        // Now liquidator will be striped from the same amount of DSC tokens that has been burned.
        bool success = i_dsc.transferFrom(liquidator, address(this), amountDSC);
        // This next check isn't probably gonna be called, cause the revert mechanism in transferFrom() will be called first.
        // We put the check incase the transferFrom() revert wasn't triggered and the issue was somewhere else.
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDSC);
    }

    /**
     * @param collateralTokenAddress The address of the token to deposit as collateral.
     * @param collateralAmount The amount of collateral to redeem.
     * @param from User to be striped from his collateral.
     * @param to User demanding to take the collateral.
     *
     * @notice This is more of a generic function where a certain amount of collateral will be striped from a user and given to another user.
     */
    function _redeemCollateral(address collateralTokenAddress, uint256 collateralAmount, address from, address to)
        private
    {
        if (collateralAmount > s_collateralDeposited[from][collateralTokenAddress]) {
            revert DSCEngine__AmountExceedsCollateral();
        }
        s_collateralDeposited[from][collateralTokenAddress] -= collateralAmount;
        bool success = IERC20(collateralTokenAddress).transfer(to, collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        emit CollateralRedeemed(from, to, collateralTokenAddress, collateralAmount);
        _revertIfHealthFactorIsBroken(from);
    }

    /**
     * @notice - Returns total amount of successfully minted DSC, total value of user collateral in USD
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValueInUSD(user);
    }

    /**
     * @notice - Returns how close to liquidation a user is. If a user goes below 1, that means he can't get liquidated.
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBroken(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUSD)
        internal
        pure
        returns (uint256)
    {
        if (totalDSCMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
        // $150 worth of ETH wants to mint 100 DSC
        // (150 * 50 ) / 100 = 75 / 100 = 0.75 < 1 (will be liquefied)
        // $250 worth of ETH wants to mint 100 DSC
        // (250 * 50 ) / 100 = 125 / 100 = 1.25 > 1 (won't be liquefied)
    }

    function _getUSDValue(address token, uint256 amount) private view returns (uint256 valueInUSD) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        valueInUSD = (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
        return valueInUSD;
    }

    /////////////////////////////////////////
    /// Public & External View/Pure Functions ////
    /////////////////////////////////////////
    function calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUSD)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    /**
     * @param token Token we're dealing with.
     * @param collateralValueInUSD The value in USD to be conveyed to amount of tokens.
     *
     * @notice This function returns the amount of tokens in a certain amount of USD according to the current token price.
     */
    function getTokenAmountFromUSD(address token, uint256 collateralValueInUSD)
        public
        view
        returns (uint256 collateralAmount)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        collateralAmount = ((collateralValueInUSD * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
        return collateralAmount;
    }

    function getAccountCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValueInUSD) {
        // loop through each collateral token, get the amount they have deposited, and map it to the price, to get the USD value.
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += _getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUSDValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        return _getAccountInformation(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDSC() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}

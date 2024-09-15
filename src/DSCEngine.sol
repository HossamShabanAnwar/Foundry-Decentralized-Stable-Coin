// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

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
 * Our DSC system should always be "overcollateralized". At no point, should the value of all collateral be <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the make MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /////////////////////////
    //////// Errors /////////
    /////////////////////////
    error DSCEngine__AmountLessThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAnAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFailed();

    /////////////////////////
    //// State Variables ////
    /////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18; // To transform between ETH and WEI
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    // In case of wrapped tokens (wBTC, WETH, ..) they are deployed as smart contracts so they have addresses
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;
    /////////////////////////
    //////// Events /////////
    /////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    /////////////////////////
    /////// Modifiers ///////
    /////////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__AmountLessThanZero();
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
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
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
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice This function handles both redeeming collateral and burning minted DSC.
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amount of collateral to deposit.
     * @param amountDSCToBurn The amount of DSC to burn.
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)
        external
    {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amount of collateral to deposit.
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        // TODO: We should've checked if the amount is less than total collateral
        // if (amountCollateral >= s_collateralDeposited[msg.sender][tokenCollateralAddress]) {
        //     revert;
        // }
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI: Checks, Effects, Interactions
     * @param amountDSCToMint The amount of decentralized stablecoin to mint.
     * @notice User must have more collateral value than the minimum threshold.
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        // TODO: Why don't we emit an event here??
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        s_DSCMinted[msg.sender] -= amount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        // This next check isn't probably gonna be called, cause the revert mechanism in transferFrom() will be called first.
        // We put the check incase the transferFrom() revert wasn't triggered and the issue was somewhere else.
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
        _revertIfHealthFactorIsBroken(msg.sender); // This too probably will never be invoked..
    }

    function getHealthFactor() external {}

    /**
     *
     * @param collateral The ERC20 token address of the collateral you're using to make the protocol solvent again.
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
     */
    function liquidate(address collateral, address user, uint256 deptToCover) external {}

    /////////////////////////////////////////
    /// Private & Internal View Functions ///
    /////////////////////////////////////////
    /**
     * @notice - Returns total amount of successfully minted DSC, total value of user collaterals in USD
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     * @notice - Returns how close to liquidation a user is. If a user goes below 1, that means he can't get liquidated.
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
        // $150 worth of ETH wants to mint 100 DSC
        // (150 * 50 ) / 100 = 75 / 100 = 0.75 < 1 (will be liquefied)
        // $250 worth of ETH wants to mint 100 DSC
        // (250 * 50 ) / 100 = 125 / 100 = 1.25 > 1 (won't be liquefied)
    }

    // TODO: Both _healthFactor() and _revertIfHealthFactorIsBroken() functions can be merged in a single function

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /////////////////////////////////////////
    /// Public & External View Functions ////
    /////////////////////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        // loop through each collateral token, get the amount they have deposited, and map it to the price, to get the USD value.
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }
}

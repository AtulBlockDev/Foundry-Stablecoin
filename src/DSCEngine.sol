// SPDX-License-Identifier: MIT


pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/**
 * @title DSCEngine
 * @author Atulraj Sharma
 * This stablecoin has properties:
 * _Exogenous Collateral
 * _Dollar Pegged
 * _Algorihmic Stable
 * 
 */

contract DSCEngine is ReentrancyGuard {

    //Errors
    error DSCEngine_NeedMoreThanZero(); 
    error DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine_NotAllowedToken();
    error DSCEngine_TransferFailed();
    error DscEngine_HealthFactorBroken(uint256, address);
    error DSCEngine_MintingFailed();
    error DscEngine_HealthFactorOk();
    error DSCEngine_HealthFactorNotimproved();

    //State Variables

    DecentralizedStableCoin private immutable i_dsc;

    mapping(address token => address priceFeeds) private s_priceFeeds;
    mapping(address user => mapping(address tokenAddress => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) s_DscMinted;
    address[] private s_collateralTokens;
    uint256 private constant Addition_Feed_Precision = 1e10;
    uint256 private constant Precision = 1e18;
    uint256 private constant  LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant minimumHealthFactor = 1e18;



    //events

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedto,
     address indexed token, uint256 amount);


    //Modifiers
    modifier moreThanZero(uint256 _amount) {
        if(_amount <= 0){
            revert DSCEngine_NeedMoreThanZero();
        }
        _;    
    }

    modifier isAllowedToken(address token) {
        if(s_priceFeeds[token] == address(0)){
            revert DSCEngine_NotAllowedToken();
        }
        _;

        
    }

    //functions
    
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses,
     address dscAddress){
        if(tokenAddresses.length != priceFeedAddresses.length){
            revert DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for(uint256 i = 0; i < tokenAddresses.length; i++){
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);

    }
    //esxternal functions
    function depositcollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);

    }

    
    function depositCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral )public moreThanZero(amountCollateral) 
         isAllowedToken(tokenCollateralAddress) nonReentrant{
            s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
            emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
            
            bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
            if(!success){
                revert DSCEngine_TransferFailed();
            }
            
         }
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant{
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted){
            revert DSCEngine_MintingFailed();
        }



    }
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant{
       _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);

    }

         
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 tokenAmount, uint256 amountdscToBurn)  external{
        _burnDsc(amountdscToBurn, msg.sender, msg.sender);
        redeemCollateral(tokenCollateralAddress, tokenAmount);
        //redeemCollateral already checks health factor
        

    }
    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) nonReentrant{
        _burnDsc(amountDscToBurn, msg.sender, msg.sender );
         _revertIfHealthFactorIsBroken(msg.sender);
    




    }
    function liquidate(address collateral, address user, uint256 amountDebtToCover) external moreThanZero(amountDebtToCover)  nonReentrant{
        uint256 startingHealthFactor = _healthFactor(user);
        if(startingHealthFactor >= minimumHealthFactor){
            revert DscEngine_HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, amountDebtToCover);
        uint256 bonusCollateral =(tokenAmountFromDebtCovered * LIQUIDATION_BONUS/LIQUIDATION_PRECISION);
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(amountDebtToCover, user, msg.sender);
        uint256 endingUserHealthfactor = _healthFactor(user);
        if(endingUserHealthfactor <= startingHealthFactor){
            revert DSCEngine_HealthFactorNotimproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);


    }
    function getHealthFactor(address user) external view returns(uint256){
        return
        _healthFactor(user);

    }
    //Used internal function: _calculateHealthFactor
    function calculateHealthfactor(uint256 totalDscMinted, uint256 collateralValueInUsd) external pure returns(uint256){
    return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }  
     //returns how close a user is to get liquidated (Interanl Functions)
    function _healthFactor(address user) private view returns(uint256){
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);

    }
    function _revertIfHealthFactorIsBroken(address user) internal view{

        uint256 healthFactor = _healthFactor(user);
        if(healthFactor < minimumHealthFactor){
            revert DscEngine_HealthFactorBroken(healthFactor, user);
        }



    }

    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUsd){
          totalDscMinted = s_DscMinted[user];
          collateralValueInUsd = getAccountCollateralValue(user);

    }
    //The getAccountCollateralValue function is an internal function that calculates the total value of collateral deposited 
    //by a specific user in USD. It loops through all the supported collateral tokens and calculates the value of each token's 
    //collateral in USD using Chainlink price feeds. 
    //Then, it sums up the values of all collateral tokens to determine the total collateral value in USD for the user.

    function getAccountCollateralValue(address user) private view returns(uint256 totalCollateralValueInUsd){
        for(uint256 i = 0; i < s_collateralTokens.length; i++){
            address token = s_collateralTokens[i]; //looping through the tokens deposited by the user
            uint256 amount = s_collateralDeposited[user][token];  
           
            totalCollateralValueInUsd += getValueInUsd(token, amount);

        }
        return totalCollateralValueInUsd;
}

    function getValueInUsd(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]) ;
        (,int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price)*Addition_Feed_Precision * amount)/Precision; //1000e8(wbtc price) * 10e8 * 1000e18(amount of tokens)/ 1e18 (precision)

            

    }
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return(usdAmountInWei*Precision / uint256(price) * Addition_Feed_Precision);
    }
//internal Function

 function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
private{
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success){
            revert DSCEngine_TransferFailed();
        }
}
function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
      s_DscMinted[onBehalfOf] -= amountDscToBurn;
         bool success = i_dsc.transferFrom(dscFrom,  address(this), amountDscToBurn);
         if(!success){
            revert DSCEngine_TransferFailed();
         }
         i_dsc.burn(amountDscToBurn);
}
  function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) internal pure returns(uint256){
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; //Setting Collateral Threshold
        return ((collateralAdjustedForThreshold * Precision)/ totalDscMinted); // HEALTH FACTOR = COLLATERAL THRESHOLD * WEI / TOTAL DSC MINTED   
    }
//view Functions
//these are view functions that return the state variables of the contract.

function getCollateralDeposited(address user, address tokenAddress) public view returns(uint256 _collateralDeposited){
    return s_collateralDeposited[user][tokenAddress];
}
function getDscMinted(address user) public view returns(uint256 _dscMinted){
    return s_DscMinted[user]; 


}
function getPriceFeeds(address tokenAddress) public view returns(address _priceFeed){
    return s_priceFeeds[tokenAddress];
}
function getCollateralTokens() public view returns(address[] memory _collateralTokens){
    return s_collateralTokens;
}
function getAccountInformation(address user) public view returns(uint256 _totalDscMinted, uint256 _collateralValueInUsd){
    return _getAccountInformation(user);
}
}
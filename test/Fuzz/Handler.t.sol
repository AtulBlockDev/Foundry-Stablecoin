//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test{

    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_AMOUNT = type(uint96).max;
    uint256 public timesMintisCalled;
    address[] public usersWithCollateral;
    

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc){
        dsce = _dsce;
        dsc =_dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public{
        amount = bound(amount,1, MAX_DEPOSIT_AMOUNT);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender,amount);
        collateral.approve(address(dsce),amount);
        dsce.depositCollateral(address(collateral),amount);
        vm.stopPrank();
        usersWithCollateral.push(msg.sender);
        

    }
    function redeemCollateral(uint256 collateralSeed, uint256 amount) public{
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToReddem = dsce.getCollateralDeposited(address(collateral), msg.sender);
        amount = bound(amount, 0, maxCollateralToReddem);  
        if (amount == 0){
            return;
        }
        dsce.redeemCollateral(address(collateral),amount);
    }

    function mintdsc(uint256 amount, uint256 addressSeed) public{
        if (usersWithCollateral.length == 0){
            return;
        }
        address sender = usersWithCollateral[addressSeed % usersWithCollateral.length];
  
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = int256(collateralValueInUsd/2) - int256(totalDscMinted);
        if(maxDscToMint < 0){
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0){
            return;
        }

        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timesMintisCalled++;
    }



    
    
    function _getCollateralFromSeed(uint256 collateralSeed) public view returns(ERC20Mock){
        if(collateralSeed%2 ==0){
            return weth; 
        }else{
            return wbtc;   
    }

    }
}
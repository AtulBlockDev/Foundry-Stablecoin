// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedWeth} from "../mocks/MockFailedWeth.sol";

contract DSCEngineTest is Test {


    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;
    address public USER = makeAddr("user");
    uint256 public STARTING_ERC20_BALANCE = 10 ether;
    uint256 public AMOUNT_COLLATERAL = 10 ether;
    uint256 public AMOUNT_DSC = 1e18;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);


    function setUp() public {
        deployer = new DeployDSC();
        (dsce, dsc, config) = deployer.run();
        (wethUsdPriceFeed,,weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);

    }
    function testGetValueInUsd() public{
        uint256 ethAmount = 15e18;
        uint256 expectedAmount = 30000e18;
        uint256 actualValue = dsce.getValueInUsd(weth, ethAmount); //mocks are working here
        assertEq(expectedAmount, actualValue);
    }

    //Deposit Collateral
    function testRevertsifTransferIsFailed() public{
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedWeth _weth = new MockFailedWeth();
        address[] memory tokenAddresses = new address[](1);
        address[] memory feedAddresses = new address[](1);
        tokenAddresses[0] = address(_weth);
        feedAddresses[0] = wethUsdPriceFeed;
        
        
        vm.prank(owner);
        DSCEngine mockDSCE = new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
        _weth.mint(USER, AMOUNT_COLLATERAL);
        console.log(mockDSCE.getPriceFeeds(address(_weth)));
        

        vm.startPrank(USER);

        ERC20Mock(address(_weth)).approve(address(mockDSCE), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine_TransferFailed.selector);
        mockDSCE.depositCollateral(address(_weth), AMOUNT_COLLATERAL);

    }


    function testDepositCollateralInitialization() public{
        
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 collateralDeposited = dsce.getCollateralDeposited(USER, weth);
        assertEq(AMOUNT_COLLATERAL, collateralDeposited);
        vm.stopPrank();
        

    }
    function testRevertIfCollateralSentIsZero() public{
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_NeedMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
    }

    function testRevertNotAllowedToken() public{
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_NotAllowedToken.selector);
        address unknownToken = address(0);
        dsce.depositCollateral(unknownToken, AMOUNT_COLLATERAL);
    }
    function testCanEmitvenetOnCollateralDeposited() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(dsce));
        
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank(); 
        
    }
    function testSuccessfulCollateralDeposit() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 dsceBalance = ERC20Mock(weth).balanceOf(address(dsce));
        assertEq(AMOUNT_COLLATERAL, dsceBalance);
    }

    //Mint DSC
    // you were passing an invalid pricefeed address for AggregatorV3Interface, and so it was revertinng.
    // detected an error in s_collateraltokens (was pushing priceFeeds address rather than token address )
    // corrected: Make a dedicated calculatHealthFactor function to get expected health factor.
    function testCanRevertIfMintingBreaksHealthFactor() public{
        (,int256 price,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData(); 
        uint256 amountDscToMint = (AMOUNT_COLLATERAL * uint256(price) * 1e10) / 1e18 ;  //calaculating DSC equal                                                                     
        vm.startPrank(USER); //to Amount Collateral to be revrted back for breaking health factor
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = dsce.calculateHealthfactor(amountDscToMint, dsce.getValueInUsd(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DscEngine_HealthFactorBroken.selector, expectedHealthFactor, USER));
        dsce.depositcollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountDscToMint);
        vm.stopPrank();    
       
     
    }
      function testUpdatesMinterbalance() public{

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_DSC);
        assertEq(AMOUNT_DSC, dsc.balanceOf(USER));
        
      }
      //This function is checking if the s_DscMinted mapping is updated or not
      function testUpdatesDSCMintedMapping() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositcollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC);
        uint256 expectedDscMinted = dsce.getDscMinted(USER);
        assertEq(AMOUNT_DSC, expectedDscMinted);
      }
      // this test requires its own setup.
      function testRevertsIfFailedToMintDsc() public{
        MockFailedMintDSC failedDsc = new MockFailedMintDSC();
        
        address[] memory tokenAddresses = new address[](1);
        address[] memory feedAddresses = new address[](1);
        tokenAddresses[0] = weth;
        feedAddresses[0] = wethUsdPriceFeed;
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(failedDsc));
        failedDsc.transferOwnership(address(mockDsce));
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine_MintingFailed.selector);
        mockDsce.depositcollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC);
              }

        //Liquidate DSC 

       



   




    


    




}
//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";
contract InvariantsTest is StdInvariant, Test{
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external{
        deployer = new DeployDSC();
        (dsce,dsc,config) = deployer.run();
        (,,weth,wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsce,dsc);
        targetContract(address(handler));
        
    }
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public{
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getValueInUsd(weth,totalWethDeposited);
        uint256 wbtcValue = dsce.getValueInUsd(wbtc,totalWbtcDeposited);
        console.log("wethValue: %s",wethValue);
        console.log("wbtcValue: %s",wbtcValue);
        console.log("totalSupply: %s",totalSupply);
        console.log("Times mint is called: %s",handler.timesMintisCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }


}
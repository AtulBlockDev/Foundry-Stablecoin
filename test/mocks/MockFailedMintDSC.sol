// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;


import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
contract MockFailedMintDSC is ERC20Burnable, Ownable{

    error DSC_MustBeMoreThanZero();
    error DSC_BurnAmountExceedsMoreThanZero();
    error DSC_NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC"){

    }
    function burn(uint _amount) public override onlyOwner{
        uint256 balance = balanceOf(msg.sender);
        if(_amount <= 0){
            revert DSC_MustBeMoreThanZero();
            }

            if(_amount > balance){
                revert DSC_BurnAmountExceedsMoreThanZero();
            }
            super.burn(_amount);

    }
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool){
        if(_amount < 0){
            revert DSC_MustBeMoreThanZero();
            }
            if(_to == address(0)){
                revert DSC_NotZeroAddress();
            }

            _mint(_to, _amount);
            return false;

    }


}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VaultGuardians} from "../../src/protocol/VaultGuardians.sol";
import {VaultShares, IERC20} from "../../src/protocol/VaultShares.sol";
import {IVaultData} from "../../src/interfaces/IVaultData.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";


contract Handler is Test{
    VaultGuardians vaultGuardians;
    address guardian;
    address user;
    IVaultData.AllocationData allocationData;
    VaultShares vaultShares;
    ERC20Mock weth;

    constructor(VaultGuardians _vaultGuardians, VaultShares _vaultShares, ERC20Mock _weth, address _guardian, address _user){
        vaultGuardians = _vaultGuardians;
        guardian = _guardian;
        user = _user;
        vaultShares = _vaultShares;
        weth = _weth;
        assertEq(vaultShares.getGuardian(), guardian, "Second getGuardian Assert");

    }

    function becomeGuardian(uint16 uniswapAlloc, uint16 aaveAlloc) public {
        vm.assume(uniswapAlloc + aaveAlloc < 1000);
        uint16 holdAlloc = 1000 - uniswapAlloc + aaveAlloc;
        allocationData = IVaultData.AllocationData(
        holdAlloc, // hold
        uniswapAlloc, // uniswap
        aaveAlloc // aave
    );
        vm.startPrank(guardian);
        vaultGuardians.becomeGuardian(allocationData);
        vm.stopPrank();
    }

    function quitGuardian() public {
        vm.startPrank(guardian);
        vaultGuardians.quitGuardian();
        vm.stopPrank();
    }

    function reBalanceFunds() public {
        vm.startPrank(guardian);
        vaultShares.rebalanceFunds();
        vm.stopPrank();
    }

    function updateHoldingAllocation(uint16 uniswapAlloc, uint16 aaveAlloc) public {
        uint16 _uniswapAlloc = uint16(bound(uniswapAlloc, 0, 499));
        uint16 _aaveAlloc = uint16(bound(aaveAlloc, 0, 499));
        // console.log('uniswapAlloc: ', _uniswapAlloc);
        // console.log('aaveAlloc: ', _aaveAlloc);
        vm.assume(_uniswapAlloc + _aaveAlloc < 1000);
        uint16 holdAlloc = 1000 - _uniswapAlloc - _aaveAlloc;
        // console.log('holdAlloc: ', holdAlloc);
   
        
        allocationData = IVaultData.AllocationData(
        holdAlloc, // hold
        _uniswapAlloc, // uniswap
        _aaveAlloc // aave
    );
        vm.startPrank(guardian);
        vaultGuardians.updateHoldingAllocation(weth, allocationData);
        vm.stopPrank();
    }

    function redeem(uint256 amount) public {

        uint256 userShareBalance = vaultShares.balanceOf(user);
        uint256 _amount = bound(amount, 0, userShareBalance);

        vm.startPrank(user);
        vaultShares.approve(address(vaultShares), _amount);
        vaultShares.redeem(_amount, user, user);
        vm.stopPrank();
    }

    function deposit(uint256 amount) public {

        uint256 userBalance = weth.balanceOf(user);
        uint256 _amount = bound(amount, 0, userBalance);

        vm.startPrank(user);
        weth.approve(address(vaultShares), _amount);
        vaultShares.deposit(_amount, user);
        vm.stopPrank();
    }
}

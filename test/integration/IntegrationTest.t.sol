// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Base_Test} from "../Base.t.sol";
import {console} from "forge-std/console.sol";
import {VaultShares, IERC20} from "../../../src/protocol/VaultShares.sol";

contract IntegrationTest is Base_Test {
    uint256 startingGuardBalance = 10 ether;
     // s_guardianStakePrice = 10 ether;
    uint256 startingUserBalance = 10 ether;
    uint256 startingUserShareBalance;
    uint256 endingUserShareBalance;
    address guardian = makeAddr("guardian");
    address user = makeAddr("user");
    VaultShares wethVaultShares;
    AllocationData allocationData = AllocationData(
        500, // hold
        250, // uniswap
        250 // aave
    );
    AllocationData expectedAllocationData;

    uint256 holdAllocation;
        uint256 uniswapAllocation; 
        uint256 aaveAllocation;

    function setUp() public override {
        Base_Test.setUp();
    }

    modifier hasGuardian() {
        weth.mint(startingGuardBalance, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), startingGuardBalance);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();
        _;
    }

    modifier userDeposit() {
        weth.mint(startingUserBalance, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), startingUserBalance);
        wethVaultShares.deposit(startingUserBalance, user);
        vm.stopPrank();
        _;
    }

    function test_checkGuardianBalances() hasGuardian  public {
        console.log('wethVaultShares.balanceOf(guardian): ', wethVaultShares.balanceOf(guardian));
        console.log('weth.balanceOf(address(wethVaultShares)): ', weth.balanceOf(address(wethVaultShares)));
     expectedAllocationData = wethVaultShares.getAllocationData();
        console.log('holdAllocation: ', expectedAllocationData.holdAllocation);
        console.log('aaveAllocation: ', expectedAllocationData.aaveAllocation);
        console.log('uniswapAllocation: ', expectedAllocationData.uniswapAllocation);
        
    }

    function test_checkRoleBalances() hasGuardian userDeposit public {
        console.log('wethVaultShares.balanceOf(user): ', wethVaultShares.balanceOf(user));
        console.log('wethVaultShares.balanceOf(guardian): ', wethVaultShares.balanceOf(guardian));
        console.log('weth.balanceOf(address(wethVaultShares)): ', weth.balanceOf(address(wethVaultShares)));
        
    }

    function test_updateAllocation_then_reBalance() hasGuardian userDeposit public {

        startingUserShareBalance = wethVaultShares.balanceOf(user);
        AllocationData memory newAllocationData = AllocationData(
            100, // hold
            450, // uniswap
            450 // aave
        );
        vm.startPrank(guardian);
        vaultGuardians.updateHoldingAllocation(weth, newAllocationData);
        wethVaultShares.rebalanceFunds();
        vm.stopPrank();
        endingUserShareBalance = wethVaultShares.balanceOf(user);

        assertEq(endingUserShareBalance, startingUserShareBalance);

    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Base_Test} from "../Base.t.sol";
import {VaultShares, IERC20} from "../../../src/protocol/VaultShares.sol";
import {Handler} from "./Handler.t.sol";

contract Invariant is StdInvariant, Base_Test {
    uint256 initialUserBalance = 10 ether;
    uint256 initialGuardBalance = 100 ether;
    uint256 guardianStakePrice = 10 ether;

    address user = makeAddr("user");
    address guardian = makeAddr("guardian");
    VaultShares public wethVaultShares;
    Handler handler;

    uint256 initialUserSharesBalance;
    uint256 finalUserSharesBalance;

    AllocationData allocationData = AllocationData(
        500, // hold
        250, // uniswap
        250 // aave
    );

    function setUp() public override {
        Base_Test.setUp();

        weth.mint(initialGuardBalance, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), initialGuardBalance);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();
        assertEq(wethVaultShares.getGuardian(), guardian, "First getGuardian Assert");

        weth.mint(initialUserBalance, user);
        initialUserBalance = weth.balanceOf(user);

        vm.startPrank(user);
        weth.approve(address(wethVaultShares), initialUserBalance);
        wethVaultShares.deposit(initialUserBalance, user);
        vm.stopPrank();

        initialUserSharesBalance = wethVaultShares.balanceOf(user);
        console.log("initialUserSharesBalance: ", initialUserSharesBalance);
        assert(initialUserSharesBalance > 0);

        handler = new Handler(vaultGuardians, wethVaultShares, weth, guardian, user);
        bytes4[] memory selectors = new bytes4[](4);

        selectors[0] = handler.reBalanceFunds.selector;
        selectors[1] = handler.updateHoldingAllocation.selector;
        selectors[2] = handler.updateHoldingAllocation.selector;
        selectors[3] = handler.reBalanceFunds.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function testSetupVaultShares() public view {
        assertEq(wethVaultShares.getGuardian(), guardian);
    }

    function statefulFuzz_userFinalShareBalanceHasToBeEqualThanInitialShareBalance() public {
        finalUserSharesBalance = wethVaultShares.balanceOf(user);
        console.log("finalUserSharesBalance: ", finalUserSharesBalance);
        assertEq(finalUserSharesBalance, initialUserSharesBalance);
    }

    function statefulFuzz_systemWethBalanceIsEqualToStartingUsersWethBalance() public view {
        uint256 uniswapWethBalance = weth.balanceOf(uniswapRouter);
        uint256 aavePoolWethBalance = weth.balanceOf(aavePool);
        uint256 vaultWethBalance = weth.balanceOf(address(wethVaultShares));

        assertEq(
            initialUserBalance + guardianStakePrice,
            uniswapWethBalance + aavePoolWethBalance + vaultWethBalance,
            "Balances are not the same"
        );
    }

      function statefulFuzz_startingSystemBalanceEqualToFinalSystemBalance() public view {
        uint256 uniswapWethBalance = weth.balanceOf(uniswapRouter);
        uint256 aavePoolWethBalance = weth.balanceOf(aavePool);
        uint256 userWethBalance = weth.balanceOf(user);
        uint256 vaultWethBalance = weth.balanceOf(address(wethVaultShares));
        
        uint256 startingSystemBalance = initialUserBalance + guardianStakePrice; // 20 ether
        console.log('startingSystemBalance: ', startingSystemBalance);
        uint256 finalSystemBalance = uniswapWethBalance + aavePoolWethBalance + vaultWethBalance + userWethBalance;
        console.log('finalSystemBalance: ', finalSystemBalance);
        
        assertEq(
            startingSystemBalance,
            finalSystemBalance,
            "startingSystemBalance is not equal to finalSystemBalance"
        );
    }
}

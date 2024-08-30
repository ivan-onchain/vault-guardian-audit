// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IUniswapV2Router01} from "../../vendor/IUniswapV2Router01.sol";
import {IUniswapV2Factory} from "../../vendor/IUniswapV2Factory.sol";
import {AStaticUSDCData, IERC20} from "../../abstract/AStaticUSDCData.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test, console} from "forge-std/Test.sol";

contract UniswapAdapter is AStaticUSDCData {
    error UniswapAdapter__TransferFailed();

    using SafeERC20 for IERC20;

    IUniswapV2Router01 internal immutable i_uniswapRouter;
    IUniswapV2Factory internal immutable i_uniswapFactory;

    address[] private s_pathArray;

    event UniswapInvested(uint256 tokenAmount, uint256 wethAmount, uint256 liquidity);
    event UniswapDivested(uint256 tokenAmount, uint256 wethAmount);

    constructor(address uniswapRouter, address weth, address tokenOne) AStaticUSDCData(weth, tokenOne) {
        i_uniswapRouter = IUniswapV2Router01(uniswapRouter);
        i_uniswapFactory = IUniswapV2Factory(IUniswapV2Router01(i_uniswapRouter).factory());
    }

    // slither-disable-start reentrancy-eth
    // slither-disable-start reentrancy-benign
    // slither-disable-start reentrancy-events
    /**
     * @notice The vault holds only one type of asset token. However, we need to provide liquidity to Uniswap in a pair
     * @notice So we swap out half of the vault's underlying asset token for WETH if the asset token is USDC or WETH
     * @notice However, if the asset token is WETH, we swap half of it for USDC (tokenOne)
     * @notice The tokens we obtain are then added as liquidity to Uniswap pool, and LP tokens are minted to the vault
     * @param token The vault's underlying asset token
     * @param amount The amount of vault's underlying asset token to use for the investment
     */
    function _uniswapInvest(IERC20 token, uint256 amount) internal {
        // q if token == LINK them counterPartyToken = i_weth and token = LINK?
        // r yes it is correct
        IERC20 counterPartyToken = token == i_weth ? i_tokenOne : i_weth;
        // We will do half in WETH and half in the token
        uint256 amountOfTokenToSwap = amount / 2;
        // the path array is supplied to the Uniswap router, which allows us to create swap paths
        // in case a pool does not exist for the input token and the output token
        // however, in this case, we are sure that a swap path exists for all pair permutations of WETH, USDC and LINK
        // (excluding pair permutations including the same token type)
        // the element at index 0 is the address of the input token
        // the element at index 1 is the address of the output token
        s_pathArray = [address(token), address(counterPartyToken)];
        // q paths can be [weth, usdc] | [usdc, weth] | [link, weth] ??
        // r yes this is correct
        bool succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }
        uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
            amountIn: amountOfTokenToSwap,
            // q is there chance of a slippage that change the price? 
            // r yes there is a change of slippage here, for that reason it is required to specified the amountOutMin
            // High: high slippage risk due of lack of expected amountOutMin.  
            amountOutMin: amountOfTokenToSwap, 
            // amountOutMin: 0, 
            path: s_pathArray,
            to: address(this),
            deadline: block.timestamp
        });

        // q amounts[1] is the output token, so if token is tokenOne counterParty/output token is weth
        //r amounts[1] is the output token 
        // what are the units and the decimals of amounts[1]? what is the token and counterPartyToken ratio? 
        // r amounts has 18 decimal , so units of ethers looks like the ratio is 1. Also this ratios is based in the uniswap adapter mock
        succ = counterPartyToken.approve(address(i_uniswapRouter), amounts[0]);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }

        // q amounts[0] is the amount of the inputToken/oneToken? if so,  Why it is added to the amountOfTokenToSwap?  
        // succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap + amounts[0]);
        // HIGH: it is approving the double which is wrong. It only approve the 
        // amountOfTokenToSwap
        succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap);
        // succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap + amounts[0]);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }

        // amounts[1] should be the WETH amount we got back
        (uint256 tokenAmount, uint256 counterPartyTokenAmount, uint256 liquidity) = i_uniswapRouter.addLiquidity({
            tokenA: address(token),
            tokenB: address(counterPartyToken),
            // HIGH: with the above fixes this line would fails because amountADesired would worth the double than amountBDesired. Both has to worth the same.
            // amountADesired: amountOfTokenToSwap + amounts[0]
            amountADesired: amountOfTokenToSwap,
            amountBDesired: amounts[0],
            amountAMin: 0,// q why this lower limit is not used?
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
        emit UniswapInvested(tokenAmount, counterPartyTokenAmount, liquidity);
    }

    /**
     * @notice The LP tokens of the added liquidity are burnt
     * @notice The other token (which isn't the vault's underlying asset token) is swapped for the vault's underlying asset token
     * @param token The vault's underlying asset token
     * @param liquidityAmount The amount of LP tokens to burn
     */
    function _uniswapDivest(IERC20 token, uint256 liquidityAmount) internal returns (uint256 amountOfAssetReturned) {
        IERC20 counterPartyToken = token == i_weth ? i_tokenOne : i_weth;

        (uint256 tokenAmount, uint256 counterPartyTokenAmount) = i_uniswapRouter.removeLiquidity({
            tokenA: address(token),
            tokenB: address(counterPartyToken),
            liquidity: liquidityAmount,
            amountAMin: 0,
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
        s_pathArray = [address(counterPartyToken), address(token)];
        uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
            amountIn: counterPartyTokenAmount,
            amountOutMin: counterPartyTokenAmount, // q is there chance of a slippage that change the price? // r yes it should set the amountOutMi n
            path: s_pathArray,
            to: address(this),
            deadline: block.timestamp
        });
         // if amounts[1] was the WETH amount we got back in the _uniswapInvest, here in _uniswapDivest it should be the tokenOne? if so, why here is taken as weth?
        emit UniswapDivested(tokenAmount, amounts[1]);
        amountOfAssetReturned = amounts[1];
    }
    // slither-disable-end reentrancy-benign
    // slither-disable-end reentrancy-events
    // slither-disable-end reentrancy-eth
}

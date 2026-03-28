// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title  ArbBot — Atomic arbitrage contract for PancakeSwap BSC (TRADE4ME 2.0)
 * @notice Four execution modes:
 *   1. executeArb()          — same-DEX A->B->A with own capital
 *   2. flashSwapArb()        — same-DEX flash swap (zero capital)
 *   3. executeCrossDexArb()  — cross-DEX A->B on routerBuy, B->A on routerSell
 *   4. flashCrossDexArb()    — cross-DEX flash swap: borrow on PancakeSwap, sell on routerSell
 *
 * @dev  Everything in ONE transaction — if profit < minProfit -> full revert -> zero loss (except gas).
 *       VERIFY all router/factory addresses before mainnet deployment.
 */

// ── Minimal interfaces ───────────────────────────────────────────────────────

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IPancakeRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

interface IPancakePair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

// ── Main contract ────────────────────────────────────────────────────────────

contract ArbBot {

    // ── Storage ───────────────────────────────────────────────────────────────

    address public owner;
    bool    public paused;

    // PancakeSwap V2 (default DEX for same-DEX arb and flash loans)
    address public constant PANCAKE_ROUTER  = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant PANCAKE_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    // BiSwap
    address public constant BISWAP_ROUTER   = 0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8;
    address public constant BISWAP_FACTORY  = 0x858E3312ed3A876947EA49d572A7C42DE08af7EE;

    // ApeSwap
    address public constant APESWAP_ROUTER  = 0xcF0feBd3f17CEf5b47b0cD258aCf6780733b98B6;
    address public constant APESWAP_FACTORY = 0x0841BD0B734E4F5853f0dD8d7Eb8496E4597B30B;

    // MDEX (BSC) -- verify before mainnet use
    address public constant MDEX_ROUTER     = 0x7DAe51BD3E3376B8c7c4900E9107f12Be3AF1bA8;
    address public constant MDEX_FACTORY    = 0x3CD1C46068dAEa5Ebb0d3f55F6915B10648062B8;

    // Fee constants for flash repayment (PancakeSwap 0.25%)
    uint256 public constant PANCAKE_FEE_NUM = 9975;
    uint256 public constant PANCAKE_FEE_DEN = 10000;

    // ── Events ────────────────────────────────────────────────────────────────

    event ArbExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 profit,
        bool    usedFlashSwap,
        address routerBuy,
        address routerSell
    );
    event Withdrawn(address indexed token, uint256 amount);
    event Paused(bool status);

    // ── Modifiers ─────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "ArbBot: not owner");
        _;
    }

    modifier notPaused() {
        require(!paused, "ArbBot: paused");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // =========================================================================
    // MODE 1 -- executeArb : same-DEX round-trip with own capital (PancakeSwap)
    // =========================================================================

    /**
     * @notice Executes A->B->A on PancakeSwap V2 using your own capital.
     *         Reverts if net profit < minProfit.
     */
    function executeArb(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 minProfit
    ) external onlyOwner notPaused {
        require(
            IERC20(tokenA).transferFrom(msg.sender, address(this), amountIn),
            "ArbBot: transferFrom failed"
        );

        uint256 profit = _executeSwaps(PANCAKE_ROUTER, PANCAKE_ROUTER, tokenA, tokenB, amountIn, minProfit);

        uint256 finalBalance = IERC20(tokenA).balanceOf(address(this));
        require(IERC20(tokenA).transfer(msg.sender, finalBalance), "ArbBot: transfer back failed");

        emit ArbExecuted(tokenA, tokenB, amountIn, profit, false, PANCAKE_ROUTER, PANCAKE_ROUTER);
    }

    // =========================================================================
    // MODE 2 -- flashSwapArb : same-DEX flash swap (zero capital, PancakeSwap)
    // =========================================================================

    /**
     * @notice Triggers a PancakeSwap V2 flash swap.
     *         PancakeSwap lends amountIn of tokenA; callback repays amountIn + 0.25%.
     */
    function flashSwapArb(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 minProfit
    ) external onlyOwner notPaused {
        address pair = IPancakeFactory(PANCAKE_FACTORY).getPair(tokenA, tokenB);
        require(pair != address(0), "ArbBot: pair not found");

        address token0 = IPancakePair(pair).token0();
        (uint256 amount0Out, uint256 amount1Out) = tokenA == token0
            ? (amountIn, uint256(0))
            : (uint256(0), amountIn);

        bytes memory data = abi.encode(
            tokenA, tokenB, amountIn, minProfit, msg.sender,
            PANCAKE_ROUTER, PANCAKE_ROUTER
        );
        IPancakePair(pair).swap(amount0Out, amount1Out, address(this), data);
    }

    // =========================================================================
    // MODE 3 -- executeCrossDexArb : cross-DEX atomic arb with own capital
    // =========================================================================

    /**
     * @notice Executes a cross-DEX arbitrage atomically in ONE transaction:
     *           Swap 1: tokenA -> tokenB  on routerBuy   (buy cheap)
     *           Swap 2: tokenB -> tokenA  on routerSell  (sell expensive)
     *         Reverts completely if net profit < minProfit.
     *
     * @param tokenA     Starting token (e.g. WBNB)
     * @param tokenB     Intermediate token (e.g. BUSD)
     * @param amountIn   Amount of tokenA to trade (wei)
     * @param minProfit  Minimum acceptable profit in tokenA wei
     * @param routerBuy  Router address for cheap-side buy  (e.g. BISWAP_ROUTER)
     * @param routerSell Router address for expensive-side sell (e.g. PANCAKE_ROUTER)
     */
    function executeCrossDexArb(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 minProfit,
        address routerBuy,
        address routerSell
    ) external onlyOwner notPaused {
        require(routerBuy  != address(0), "ArbBot: invalid routerBuy");
        require(routerSell != address(0), "ArbBot: invalid routerSell");

        require(
            IERC20(tokenA).transferFrom(msg.sender, address(this), amountIn),
            "ArbBot: transferFrom failed"
        );

        uint256 profit = _executeSwaps(routerBuy, routerSell, tokenA, tokenB, amountIn, minProfit);

        uint256 finalBalance = IERC20(tokenA).balanceOf(address(this));
        require(IERC20(tokenA).transfer(msg.sender, finalBalance), "ArbBot: transfer back failed");

        emit ArbExecuted(tokenA, tokenB, amountIn, profit, false, routerBuy, routerSell);
    }

    // =========================================================================
    // MODE 4 -- flashCrossDexArb : cross-DEX flash swap (zero capital)
    // =========================================================================

    /**
     * @notice Borrows amountIn of tokenA via PancakeSwap flash swap,
     *         sells tokenB back to tokenA on routerSell (different DEX),
     *         repays flash loan + 0.25%, keeps spread as profit.
     *
     * @param tokenA     Token to borrow and profit in
     * @param tokenB     Intermediate token
     * @param amountIn   Amount to borrow (wei)
     * @param minProfit  Minimum net profit after flash fee (wei)
     * @param routerSell DEX router to sell tokenB for tokenA
     */
    function flashCrossDexArb(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 minProfit,
        address routerSell
    ) external onlyOwner notPaused {
        require(routerSell != address(0), "ArbBot: invalid routerSell");

        address pair = IPancakeFactory(PANCAKE_FACTORY).getPair(tokenA, tokenB);
        require(pair != address(0), "ArbBot: pair not found");

        address token0 = IPancakePair(pair).token0();
        (uint256 amount0Out, uint256 amount1Out) = tokenA == token0
            ? (amountIn, uint256(0))
            : (uint256(0), amountIn);

        // routerBuy = PANCAKE_ROUTER (borrow side); routerSell = provided
        bytes memory data = abi.encode(
            tokenA, tokenB, amountIn, minProfit, msg.sender,
            PANCAKE_ROUTER, routerSell
        );
        IPancakePair(pair).swap(amount0Out, amount1Out, address(this), data);
    }

    // =========================================================================
    // Flash swap callback -- handles MODE 2 and MODE 4
    // =========================================================================

    /**
     * @notice PancakeSwap V2 callback. Executes arbitrage then repays flash loan.
     */
    function pancakeCall(
        address /* sender */,
        uint256 /* amount0 */,
        uint256 /* amount1 */,
        bytes calldata data
    ) external notPaused {
        (
            address tokenA,
            address tokenB,
            uint256 amountIn,
            uint256 minProfit,
            address initiator,
            address routerBuy,
            address routerSell
        ) = abi.decode(data, (address, address, uint256, uint256, address, address, address));

        address pair = IPancakeFactory(PANCAKE_FACTORY).getPair(tokenA, tokenB);
        require(msg.sender == pair,  "ArbBot: callback not from pair");
        require(initiator  == owner, "ArbBot: not owner");

        _executeSwaps(routerBuy, routerSell, tokenA, tokenB, amountIn, 0);

        // Repay flash loan: amountIn + 0.25% + 1 wei rounding buffer
        uint256 amountToRepay = (amountIn * PANCAKE_FEE_DEN) / PANCAKE_FEE_NUM + 1;
        uint256 finalBalance  = IERC20(tokenA).balanceOf(address(this));

        require(
            finalBalance >= amountToRepay + minProfit,
            "ArbBot: insufficient profit after flash repay"
        );

        require(IERC20(tokenA).transfer(pair, amountToRepay), "ArbBot: flash repay failed");

        uint256 netProfit = finalBalance - amountToRepay;
        if (netProfit > 0) {
            require(IERC20(tokenA).transfer(initiator, netProfit), "ArbBot: profit transfer failed");
        }

        emit ArbExecuted(tokenA, tokenB, amountIn, netProfit, true, routerBuy, routerSell);
    }

    // =========================================================================
    // Internal -- double swap (routerBuy and routerSell may differ)
    // =========================================================================

    /**
     * @dev Swap 1: tokenA -> tokenB on routerBuy
     *      Swap 2: tokenB -> tokenA on routerSell
     *      Returns gross profit in tokenA.
     */
    function _executeSwaps(
        address routerBuy,
        address routerSell,
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 minProfit
    ) internal returns (uint256 profit) {
        // Swap 1: tokenA -> tokenB on routerBuy
        IERC20(tokenA).approve(routerBuy, amountIn);

        address[] memory pathAB = new address[](2);
        pathAB[0] = tokenA;
        pathAB[1] = tokenB;

        uint256[] memory amountsAB = IPancakeRouter(routerBuy).swapExactTokensForTokens(
            amountIn, 1, pathAB, address(this), block.timestamp + 180
        );
        uint256 amountB = amountsAB[1];

        // Swap 2: tokenB -> tokenA on routerSell
        IERC20(tokenB).approve(routerSell, amountB);

        address[] memory pathBA = new address[](2);
        pathBA[0] = tokenB;
        pathBA[1] = tokenA;

        uint256[] memory amountsBA = IPancakeRouter(routerSell).swapExactTokensForTokens(
            amountB, 1, pathBA, address(this), block.timestamp + 180
        );
        uint256 amountAOut = amountsBA[1];

        require(amountAOut > amountIn + minProfit, "ArbBot: profit below minimum");
        profit = amountAOut - amountIn;
    }

    // =========================================================================
    // Simulation helpers (view -- no gas on eth_call)
    // =========================================================================

    /**
     * @notice Simulates cross-DEX arb off-chain to estimate profit before executing.
     */
    function simulateCrossDexArb(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        address routerBuy,
        address routerSell
    ) external view returns (
        uint256 amountBReceived,
        uint256 amountAReturned,
        int256  profitOrLoss
    ) {
        address[] memory pathAB = new address[](2);
        pathAB[0] = tokenA;
        pathAB[1] = tokenB;
        amountBReceived = IPancakeRouter(routerBuy).getAmountsOut(amountIn, pathAB)[1];

        address[] memory pathBA = new address[](2);
        pathBA[0] = tokenB;
        pathBA[1] = tokenA;
        amountAReturned = IPancakeRouter(routerSell).getAmountsOut(amountBReceived, pathBA)[1];

        profitOrLoss = int256(amountAReturned) - int256(amountIn);
    }

    /**
     * @notice Same-DEX simulation (backward compatible).
     */
    function simulateArb(
        address tokenA,
        address tokenB,
        uint256 amountIn
    ) external view returns (
        uint256 amountBReceived,
        uint256 amountAReturned,
        int256  profitOrLoss
    ) {
        return this.simulateCrossDexArb(tokenA, tokenB, amountIn, PANCAKE_ROUTER, PANCAKE_ROUTER);
    }

    // =========================================================================
    // Utility
    // =========================================================================

    function withdraw(address token, uint256 amount) external onlyOwner {
        uint256 bal    = IERC20(token).balanceOf(address(this));
        uint256 toSend = amount == 0 ? bal : amount;
        require(toSend <= bal, "ArbBot: insufficient balance");
        require(IERC20(token).transfer(owner, toSend), "ArbBot: withdraw failed");
        emit Withdrawn(token, toSend);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ArbBot: zero address");
        owner = newOwner;
    }

    receive() external payable {
        revert("ArbBot: no BNB accepted");
    }
}

# MACHINE MAKER — deterministic interpretations

These are the measurable contracts used to implement the spec without silent ICT invention.
They are revisable. They are not extra filters.

## Direction

Closed-candle confirmed swings (`swing_left` / `swing_right`, default 2).

- HH + HL → BULLISH
- LH + LL → BEARISH
- otherwise → NEUTRAL

Daily is computed first, then H4. Trade only when both agree and are non-neutral.

Swings for Fibonacci are the most recent confirmed **H4** swing high and swing low (the same pair used for H4 bias).

## Fibonacci

Range = H4 swing high − H4 swing low.

- 0.50 = midpoint
- Bullish 0.62 = swing_high − 0.62 × range (retracement from the impulse high toward the low)
- Bearish 0.62 = swing_low + 0.62 × range (retracement from the impulse low toward the high)

This places 0.62 on the same side as discount (bull) / premium (bear), so it can be used as SL protection.

Bullish FVG must lie entirely below 0.50 (`fvg.high < 50%`).
Bearish FVG must lie entirely above 0.50 (`fvg.low > 50%`).

## FVG

Three closed M15 candles. Unfinished bar is never used.

- Bullish: candle3.low > candle1.high; zone = [c1.high, c3.low]
- Bearish: candle3.high < candle1.low; zone = [c3.high, c1.low]

Minimum size = `InpFVGMinPoints` (default 20). Configurable, not a hidden threshold.

Full break = **closed** M15 beyond the far side (bull close < FVG low / bear close > FVG high). The FVG is then invalidated and cleared. No IFVG.

## Entries

Only two models, evaluated on the just-closed M15 candle, model 1 first.

Model 1: wick overlaps FVG, candle does not close inside, close is back outside in trade direction, not a full break.

Model 2: wick/range reaches FVG midpoint, close back beyond that midpoint in trade direction, not a full break.

Touch without the required close is not an entry.

## SL

Raw SL = just beyond the FVG by `InpSLBufferPoints` (default 50).

- If FVG SL is **tighter** than 0.62 SL → use 0.62 (small-FVG structural protection).
- If 0.01 lot at FVG SL **exceeds** `InpRiskMoney` and 0.62 is closer → use 0.62 (large-FVG monetary protection).
- Otherwise use the FVG SL.

SL is never moved to manufacture RR. If 1:4 cannot be built from the chosen SL: NO TRADE.

## Risk / margin / capital

- Default `InpRiskMoney = 10`, `InpUseRiskPercent = false`.
- Lot from real SL distance. Cap 0.01. Do not bump min lot above allowed risk.
- Margin is **not** a strategy gate. Broker `NO_MONEY` is logged and not retried with a larger lot.
- Starting capital persisted. 5× lock persisted. Restart does not unlock. `InpResetCapitalLock=true` on init only.

## Timeframes

Always D1 / H4 / M15. Chart/tester period is ignored. `PERIOD_CURRENT` is rejected.

# MACHINE MAKER — deterministic interpretations

These are the measurable contracts used to implement the spec without silent ICT invention.
They are revisable. They are not extra filters.

## Direction

Closed-candle confirmed swings (`swing_left` / `swing_right`, default 2).

- HH + HL → BULLISH
- LH + LL → BEARISH
- otherwise → NEUTRAL

Daily is computed first, then H4. Trade only when both agree and are non-neutral.

Direction still uses confirmed D1/H4 swings. Fibonacci no longer uses that pair.

## Fibonacci

Anchors are the last available H4 extremes in `InpStructureLookback` **closed** bars (the forming H4 bar is excluded). This is **not** confirmed-swing detection (no left/right fractal).

- LastHigh = highest `high` in that window
- LastLow = lowest `low` in that window
- Chronological order of those two bars does not change the levels

Range = LastHigh − LastLow.

- 0.50 = midpoint
- Bullish 0.62 = LastHigh − 0.62 × range (retracement from the impulse high toward the low)
- Bearish 0.62 = LastLow + 0.62 × range (retracement from the impulse low toward the high)

This places 0.62 on the same side as discount (bull) / premium (bear), so it can be used as SL protection. The 50/62 convention is unchanged; only the anchors changed.

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
- If broker `volume_min` at FVG SL **exceeds** allowed risk money and 0.62 is closer → use 0.62 (large-FVG monetary protection).
- Otherwise use the FVG SL.

SL is never moved to manufacture RR or to fit a lot size. If 1:4 cannot be built from the chosen SL: NO TRADE.

## Risk / margin / capital

Risk is a percent of **live equity**, recomputed before every new entry:

`AllowedRisk = ACCOUNT_EQUITY × InpRiskPercent / 100` (default 2%).

Architecture:

```
ACCOUNT_EQUITY → RiskPercent → AllowedRiskMoney
→ structural SL (unchanged) → Entry/SL distance
→ theoretical lot → broker volume min/max/step
→ OrderCheck / margin → order or NO TRADE
```

- Default `InpRiskPercent = 2.0`. `InpMaxLot = 0` means no EA cap (broker `SYMBOL_VOLUME_MAX` only).
- Lot from real SL distance, tick size/value, and broker volume constraints. No strategic 0.01 hard cap.
- If `volume_min` at the structural SL would lose more than AllowedRisk: **NO TRADE**. Do not shrink SL. Do not raise risk.
- Margin is **not** a strategy gate. `OrderCheck` / `TRADE_RETCODE_NO_MONEY` logs `insufficient margin` and is not retried with a larger lot or a tighter SL.
- Account currency comes from `ACCOUNT_CURRENCY`. Tick value comes from the symbol. No hardcoded USD↔USC conversion.
- No starting-capital lock. No `$50 → $250 → WITHDRAWAL_REQUIRED`. Restart does not require a capital reset.

## Timeframes

Always D1 / H4 / M15. Chart/tester period is ignored. `PERIOD_CURRENT` is rejected.

## Backtest integrity (not strategy)

- Strategy Tester `OnInit` resets this EA's Global Variables (`CONSEC_SL`, `CD_START`, `CD_END`, `RISK_*`) so two tests start clean. Live trading never resets them; 2 SL → 8h cooldown still persists.
- `CopyRates` requires the requested bar count. Short history logs `insufficient history` and skips; it does not invent bars.
- Journal R uses risk money stored at fill (entry, initial SL, volume). It does not read SL from a position that already closed.
- Report splits detected FVGs, valid setups, order attempts, rejected orders, executed trades, and closed trades. A rejected `OrderCheck` is not an executed trade.

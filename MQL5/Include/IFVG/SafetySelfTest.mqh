#ifndef IFVG_SAFETYSELFTEST_MQH
#define IFVG_SAFETYSELFTEST_MQH

#include "Safety.mqh"
#include "SetupValidator.mqh"
#include "Logger.mqh"

class CIFVGSafetySelfTest
{
public:
   static int Run(CIFVGLogger &log)
   {
      int failed = 0;
      int passed = 0;

      // TEST 1 — lot 0.05 -> 0.01
      {
         const double v = CIFVGSafety::ClampLotHardCap(0.05);
         if(MathAbs(v - 0.01) > 1e-12)
         {
            log.Error("TEST 1 FAILED: expected 0.01 got " + DoubleToString(v, 4));
            failed++;
         }
         else
         {
            log.Info("TEST 1 PASS — lot 0.05 clamped to 0.01");
            passed++;
         }
      }

      // TEST 2 — 2 positions open
      {
         if(CIFVGSafety::CanOpenNewPosition(2, 2))
         {
            log.Error("TEST 2 FAILED: new trade allowed with 2 positions");
            failed++;
         }
         else
         {
            log.Info("TEST 2 PASS — NO NEW TRADE with 2 positions");
            passed++;
         }
      }

      // TEST 3 — 1 position open
      {
         if(!CIFVGSafety::CanOpenNewPosition(1, 2))
         {
            log.Error("TEST 3 FAILED: second position blocked");
            failed++;
         }
         else
         {
            log.Info("TEST 3 PASS — second position allowed when 1 is open");
            passed++;
         }
      }

      // TEST 4 — two consecutive SL -> cooldown
      {
         int c = 0;
         c = CIFVGSafety::OnPositionClosedSL(c);
         c = CIFVGSafety::OnPositionClosedSL(c);
         const bool cd = CIFVGSafety::ShouldEnterCooldown(c, 2);
         const datetime end = CIFVGSafety::CooldownEndFromStart(D'2026.01.01 00:00', 8);
         const datetime expect = D'2026.01.01 00:00' + 8 * 3600;
         if(!cd || end != expect)
         {
            log.Error("TEST 4 FAILED: cooldown not 8h after 2 SL");
            failed++;
         }
         else
         {
            log.Info("TEST 4 PASS — COOLDOWN = 8 HOURS after 2 SL");
            passed++;
         }
      }

      // TEST 5 — perfect setup during cooldown
      {
         const datetime now = D'2026.01.01 03:00';
         const datetime end = D'2026.01.01 08:00';
         if(!CIFVGSafety::IsCooldownActive(now, end))
         {
            log.Error("TEST 5 FAILED: cooldown not blocking");
            failed++;
         }
         else
         {
            log.Info("TEST 5 PASS — NO TRADE during cooldown");
            passed++;
         }
      }

      // TEST 6 — FVG without inversion
      {
         SSetup s;
         IFVG_ResetSetup(s);
         s.htf_bias = IFVG_BIAS_BULLISH;
         s.direction = IFVG_DIR_BUY;
         s.liquidity.active = true;
         s.sweep.valid = true;
         s.smt.valid = true;
         s.cisd.valid = true;
         s.displacement = true;
         s.fvg.id = 1;
         s.fvg.state = FVG_CREATED;
         CIFVGConfig cfg;
         cfg.in.max_positions = 2;
         cfg.in.max_spread_points = 50;
         cfg.in.use_smt_filter = true;
         cfg.in.smt_mode = SMT_REQUIRED;
         cfg.in.allow_buy = true;
         cfg.in.allow_sell = true;
         const SGateResult g = CSetupValidator::ValidateConfluence(s, cfg, true, 0, 10, true, true);
         if(g.passed)
         {
            log.Error("TEST 6 FAILED: FVG without inversion allowed");
            failed++;
         }
         else
         {
            log.Info("TEST 6 PASS — NO TRADE — FVG without inversion");
            passed++;
         }
      }

      // TEST 7 — IFVG without retest
      {
         SSetup s;
         IFVG_ResetSetup(s);
         s.htf_bias = IFVG_BIAS_BULLISH;
         s.direction = IFVG_DIR_BUY;
         s.liquidity.active = true;
         s.sweep.valid = true;
         s.smt.valid = true;
         s.cisd.valid = true;
         s.displacement = true;
         s.fvg.id = 1;
         s.fvg.state = FVG_INVERTED;
         s.ifvg.id = 1;
         s.ifvg.life = IFVG_LIFE_WAITING_RETEST;
         CIFVGConfig cfg;
         cfg.in.max_positions = 2;
         cfg.in.max_spread_points = 50;
         cfg.in.use_smt_filter = true;
         cfg.in.smt_mode = SMT_REQUIRED;
         cfg.in.allow_buy = true;
         cfg.in.allow_sell = true;
         const SGateResult g = CSetupValidator::ValidateConfluence(s, cfg, true, 0, 10, true, false);
         if(g.passed)
         {
            log.Error("TEST 7 FAILED: IFVG without retest allowed");
            failed++;
         }
         else
         {
            log.Info("TEST 7 PASS — NO TRADE — IFVG without retest");
            passed++;
         }
      }

      // TEST 8 — sweep without SMT while required
      {
         SSetup s;
         IFVG_ResetSetup(s);
         s.htf_bias = IFVG_BIAS_BULLISH;
         s.direction = IFVG_DIR_BUY;
         s.liquidity.active = true;
         s.sweep.valid = true;
         s.smt.valid = false;
         s.cisd.valid = true;
         s.displacement = true;
         s.fvg.id = 1;
         s.fvg.state = FVG_INVERTED;
         s.ifvg.id = 1;
         s.ifvg.life = IFVG_LIFE_RETEST;
         CIFVGConfig cfg;
         cfg.in.max_positions = 2;
         cfg.in.max_spread_points = 50;
         cfg.in.use_smt_filter = true;
         cfg.in.smt_mode = SMT_REQUIRED;
         cfg.in.allow_buy = true;
         cfg.in.allow_sell = true;
         cfg.in.gold_only_mode = false;
         const SGateResult g = CSetupValidator::ValidateConfluence(s, cfg, true, 0, 10, true, true);
         if(g.passed)
         {
            log.Error("TEST 8 FAILED: SMT missing allowed");
            failed++;
         }
         else
         {
            log.Info("TEST 8 PASS — NO TRADE — SMT missing");
            passed++;
         }
      }

      // TEST 9 — RR 1:2.4 vs target 3
      {
         double actual = 0.0;
         const bool ok = CIFVGSafety::RewardMeetsTarget(2000.0, 1990.0, 2024.0, 3.0, actual);
         if(ok)
         {
            log.Error("TEST 9 FAILED: RR 2.4 accepted");
            failed++;
         }
         else
         {
            log.Info("TEST 9 PASS — NO TRADE — RR insufficient");
            passed++;
         }
      }

      // TEST 10 — RR 1:3.2 vs target 3
      {
         double actual = 0.0;
         const bool ok = CIFVGSafety::RewardMeetsTarget(2000.0, 1990.0, 2032.0, 3.0, actual);
         if(!ok)
         {
            log.Error("TEST 10 FAILED: RR 3.2 rejected");
            failed++;
         }
         else
         {
            log.Info("TEST 10 PASS — trade allowed by RR gate (other gates still apply)");
            passed++;
         }
      }

      // Extra: input max lot cannot exceed hard cap
      {
         if(MathAbs(CIFVGSafety::ClampLotInput(0.10) - 0.01) > 1e-12)
         {
            log.Error("HARD CAP INPUT FAILED");
            failed++;
         }
         else
         {
            log.Info("HARD CAP INPUT PASS — MaxLot 0.10 -> 0.01");
            passed++;
         }
      }

      // Extra: third position never
      {
         if(CIFVGSafety::CanOpenNewPosition(2, 99))
         {
            log.Error("MAX POSITIONS BYPASS FAILED");
            failed++;
         }
         else
         {
            log.Info("MAX POSITIONS PASS — input 99 still capped at 2");
            passed++;
         }
      }

      // GOLD-ONLY — USDX/XAGUSD absence must not block
      {
         SSetup s;
         IFVG_ResetSetup(s);
         s.htf_bias = IFVG_BIAS_BULLISH;
         s.direction = IFVG_DIR_BUY;
         s.liquidity.active = true;
         s.sweep.valid = true;
         s.smt.valid = false;
         s.smt.status = SMT_STATUS_SKIPPED_GOLD_ONLY;
         s.smt.reason = "SKIPPED_GOLD_ONLY";
         s.cisd.valid = true;
         s.displacement = true;
         s.fvg.id = 1;
         s.fvg.state = FVG_INVERTED;
         s.ifvg.id = 1;
         s.ifvg.life = IFVG_LIFE_RETEST;
         CIFVGConfig cfg;
         cfg.in.max_positions = 2;
         cfg.in.max_spread_points = 50;
         cfg.in.use_smt_filter = true;
         cfg.in.smt_mode = SMT_REQUIRED;
         cfg.in.smt_symbol1 = "XAGUSD";
         cfg.in.smt_symbol2 = "USDX";
         cfg.in.allow_buy = true;
         cfg.in.allow_sell = true;
         cfg.in.gold_only_mode = true;
         cfg.in.symbol = "XAUUSD";
         if(cfg.SMTIsMandatoryGate())
         {
            log.Error("GOLD-ONLY TEST FAILED: SMT still mandatory");
            failed++;
         }
         else
         {
            log.Info("GOLD-ONLY GATE PASS — SMT is not mandatory");
            passed++;
         }
         const SGateResult g = CSetupValidator::ValidateConfluence(s, cfg, true, 0, 10, true, true);
         if(!g.passed)
         {
            log.Error("GOLD-ONLY TEST FAILED: setup blocked (" + g.reason + ")");
            failed++;
         }
         else
         {
            log.Info("GOLD-ONLY TEST PASS — USDX/XAGUSD absence does not block");
            passed++;
         }
         if(s.smt.status != SMT_STATUS_SKIPPED_GOLD_ONLY)
         {
            log.Error("GOLD-ONLY TEST FAILED: SMT status is not SKIPPED_GOLD_ONLY");
            failed++;
         }
         else
         {
            log.Info("GOLD-ONLY TEST PASS — SMT = SKIPPED_GOLD_ONLY");
            passed++;
         }
         if(CIFVGSafety::AllowsOrderOnSymbol("XAUUSD", "USDX") ||
            CIFVGSafety::AllowsOrderOnSymbol("XAUUSD", "XAGUSD") ||
            CIFVGSafety::IsExternalCompareSymbol("USDX", "XAGUSD", "USDX") == false)
         {
            log.Error("GOLD-ONLY TEST FAILED: external symbol order policy");
            failed++;
         }
         else if(!CIFVGSafety::AllowsOrderOnSymbol("XAUUSD", "XAUUSD"))
         {
            log.Error("GOLD-ONLY TEST FAILED: XAUUSD order should be allowed");
            failed++;
         }
         else
         {
            log.Info("GOLD-ONLY TEST PASS — no external-symbol orders");
            passed++;
         }
      }

      // R reporting (29/07 trade geometry) — does not change the RR entry gate
      {
         SSymbolSpec spec;
         IFVG_ResetSymbolSpec(spec);
         spec.tick_size = 0.01;
         spec.tick_value = 1.0;
         spec.valid = true;
         const double entry = 4019.53;
         const double sl = 4034.94;
         const double profit = -15.42;
         const double volume = 0.01;
         const double risk_money = CIFVGSafety::RiskMoneyFromStops(spec, entry, sl, volume);
         const double r = CIFVGSafety::RealizedR(profit, risk_money);
         const double old_bug_risk = volume * spec.tick_value;
         const double old_bug_r = profit / old_bug_risk;
         if(MathAbs(risk_money - 15.41) > 1e-6)
         {
            log.Error("R REPORTING TEST FAILED: risk_money=" + DoubleToString(risk_money, 5));
            failed++;
         }
         else if(MathAbs(r + 1.0) > 0.02)
         {
            log.Error("R REPORTING TEST FAILED: R=" + DoubleToString(r, 5));
            failed++;
         }
         else if(MathAbs(old_bug_r + 1542.0) > 1.0)
         {
            log.Error("R REPORTING TEST FAILED: old-bug baseline unexpected");
            failed++;
         }
         else
         {
            log.Info("R REPORTING TEST PASS — SL ≈ -1R (not -1542R)");
            passed++;
         }
         double gate_rr = 0.0;
         if(!CIFVGSafety::RewardMeetsTarget(entry, sl, 3973.30, 3.0, gate_rr) ||
            MathAbs(gate_rr - 3.0) > 0.01)
         {
            log.Error("RR GATE REGRESSION: entry RR changed");
            failed++;
         }
         else
         {
            log.Info("RR GATE UNCHANGED PASS — 1:3.00 still required");
            passed++;
         }
      }

      // Cooldown ends at exactly 8h, then entries are allowed again (IDLE)
      {
         const datetime start = D'2026.01.01 00:00';
         const datetime end = CIFVGSafety::CooldownEndFromStart(start, 8);
         const datetime expect = start + 8 * 3600;
         const bool during = CIFVGSafety::IsCooldownActive(start + 8 * 3600 - 1, end);
         const bool after = CIFVGSafety::IsCooldownActive(end, end);
         if(end != expect || !during || after)
         {
            log.Error("COOLDOWN EXPIRY TEST FAILED");
            failed++;
         }
         else
         {
            log.Info("COOLDOWN EXPIRY PASS — 8h then not active (IDLE allowed)");
            passed++;
         }
      }

      log.Info("Safety self-test: passed=" + IntegerToString(passed) + " failed=" + IntegerToString(failed));
      return failed;
   }
};

#endif

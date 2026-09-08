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

      log.Info("Safety self-test: passed=" + IntegerToString(passed) + " failed=" + IntegerToString(failed));
      return failed;
   }
};

#endif

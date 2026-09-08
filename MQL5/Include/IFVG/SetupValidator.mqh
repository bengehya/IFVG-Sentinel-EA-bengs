#ifndef IFVG_SETUPVALIDATOR_MQH
#define IFVG_SETUPVALIDATOR_MQH

#include "Config.mqh"
#include "Safety.mqh"

class CSetupValidator
{
public:
   static SGateResult Fail(const string reason)
   {
      SGateResult r;
      r.passed = false;
      r.reason = reason;
      return r;
   }

   static SGateResult Pass()
   {
      SGateResult r;
      r.passed = true;
      r.reason = "";
      return r;
   }

   static SGateResult ValidateConfluence(const SSetup &s,
                                         const CIFVGConfig &cfg,
                                         const bool cooldown_ok,
                                         const int open_positions,
                                         const double spread_points,
                                         const bool session_ok,
                                         const bool ifvg_retest_ok)
   {
      if(!cooldown_ok)
         return Fail("8H cooldown active");
      if(!CIFVGSafety::CanOpenNewPosition(open_positions, cfg.in.max_positions))
         return Fail("2 positions already open");
      if(!session_ok)
         return Fail("session not allowed");
      if(spread_points > (double)cfg.in.max_spread_points)
         return Fail("spread too high");

      if(!s.htf_bias || !IFVG_DirMatchesBias(s.direction, s.htf_bias))
      {
         if(s.htf_bias == IFVG_BIAS_NONE || s.htf_bias == IFVG_BIAS_NEUTRAL)
            return Fail("HTF context invalid");
         return Fail("direction not aligned with HTF bias");
      }
      if(!s.liquidity.active && !s.sweep.valid)
         return Fail("liquidity not identified");
      if(!s.sweep.valid)
         return Fail("liquidity sweep not confirmed");

      if(cfg.SMTIsMandatoryGate() && !s.smt.valid)
         return Fail("SMT missing");

      if(!s.cisd.valid)
         return Fail("CISD not confirmed");
      if(!s.displacement)
         return Fail("displacement not confirmed");
      if(s.fvg.id == 0 || (s.fvg.state != FVG_INVERTED && s.fvg.state != FVG_BROKEN))
         return Fail("FVG without inversion");
      if(s.ifvg.id == 0 || s.ifvg.life == IFVG_LIFE_NONE)
         return Fail("IFVG not created");
      if(!ifvg_retest_ok)
         return Fail("IFVG without retest");
      if(s.direction == IFVG_DIR_NONE)
         return Fail("direction incoherent");
      if(s.direction == IFVG_DIR_BUY && !cfg.in.allow_buy)
         return Fail("BUY disabled");
      if(s.direction == IFVG_DIR_SELL && !cfg.in.allow_sell)
         return Fail("SELL disabled");
      if(s.executed)
         return Fail("setup already executed");
      return Pass();
   }
};

#endif

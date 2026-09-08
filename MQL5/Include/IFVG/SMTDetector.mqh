#ifndef IFVG_SMTDETECTOR_MQH
#define IFVG_SMTDETECTOR_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Utils.mqh"

class CSMTDetector
{
private:
   CIFVGConfig  *m_cfg;
   CIFVGLogger  *m_log;

   bool LastSwings(const string symbol,
                   const ENUM_TIMEFRAMES tf,
                   double &sh_now, double &sh_prev,
                   double &sl_now, double &sl_prev,
                   datetime &t_high, datetime &t_low)
   {
      MqlRates rates[];
      const int need = m_cfg.in.smt_lookback + m_cfg.in.smt_swing_left + m_cfg.in.smt_swing_right + 5;
      if(!IFVG_CopyRatesSafe(symbol, tf, need, rates))
         return false;

      double highs[8];
      datetime ht[8];
      double lows[8];
      datetime lt[8];
      int nh = 0, nl = 0;
      const int n = ArraySize(rates);
      const int left = m_cfg.in.smt_swing_left;
      const int right = m_cfg.in.smt_swing_right;
      const int end = MathMin(n - left - 1, m_cfg.in.smt_lookback);

      for(int i = right; i <= end && (nh < 8 || nl < 8); i++)
      {
         if(nh < 8 && IFVG_IsSwingHigh(rates, i, left, right))
         {
            highs[nh] = rates[i].high;
            ht[nh] = rates[i].time;
            nh++;
         }
         if(nl < 8 && IFVG_IsSwingLow(rates, i, left, right))
         {
            lows[nl] = rates[i].low;
            lt[nl] = rates[i].time;
            nl++;
         }
      }
      if(nh < 2 || nl < 2)
         return false;
      sh_now = highs[0];
      sh_prev = highs[1];
      sl_now = lows[0];
      sl_prev = lows[1];
      t_high = ht[0];
      t_low = lt[0];
      return true;
   }

   bool ComparePair(const string primary,
                    const string other,
                    const ENUM_CORR_TYPE corr,
                    const ENUM_IFVG_DIR expected,
                    SSMTResult &out)
   {
      if(other == "" || other == primary)
         return false;
      if(!SymbolSelect(other, true))
      {
         out.available = false;
         out.reason = "SMT compare symbol unavailable: " + other;
         return false;
      }

      double p_hh, p_hp, p_ll, p_lp;
      datetime p_th, p_tl;
      double o_hh, o_hp, o_ll, o_lp;
      datetime o_th, o_tl;
      if(!LastSwings(primary, m_cfg.in.confirmation_tf, p_hh, p_hp, p_ll, p_lp, p_th, p_tl))
         return false;
      if(!LastSwings(other, m_cfg.in.confirmation_tf, o_hh, o_hp, o_ll, o_lp, o_th, o_tl))
         return false;

      out.available = true;
      out.compare_symbol = other;

      const bool gold_ll = (p_ll < p_lp);
      const bool gold_hh = (p_hh > p_hp);

      if(corr == CORR_POSITIVE)
      {
         const bool other_ll = (o_ll < o_lp);
         const bool other_hh = (o_hh > o_hp);
         if(expected == IFVG_DIR_BUY && gold_ll && !other_ll)
         {
            out.valid = true;
            out.direction = IFVG_DIR_BUY;
            out.time = p_tl;
            out.reason = primary + " LL not confirmed by " + other;
            return true;
         }
         if(expected == IFVG_DIR_SELL && gold_hh && !other_hh)
         {
            out.valid = true;
            out.direction = IFVG_DIR_SELL;
            out.time = p_th;
            out.reason = primary + " HH not confirmed by " + other;
            return true;
         }
      }
      else
      {
         const bool other_hh = (o_hh > o_hp);
         const bool other_ll = (o_ll < o_lp);
         if(expected == IFVG_DIR_BUY && gold_ll && !other_hh)
         {
            out.valid = true;
            out.direction = IFVG_DIR_BUY;
            out.time = p_tl;
            out.reason = primary + " LL vs inverse " + other + " no HH";
            return true;
         }
         if(expected == IFVG_DIR_SELL && gold_hh && !other_ll)
         {
            out.valid = true;
            out.direction = IFVG_DIR_SELL;
            out.time = p_th;
            out.reason = primary + " HH vs inverse " + other + " no LL";
            return true;
         }
      }
      return false;
   }

public:
   void Init(CIFVGConfig *cfg, CIFVGLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
   }

   SSMTResult Evaluate(const string primary, const ENUM_IFVG_DIR dir)
   {
      SSMTResult r;
      IFVG_ResetSMT(r);

      if(m_cfg.IsGoldOnly())
      {
         r.valid = false;
         r.available = false;
         r.status = SMT_STATUS_SKIPPED_GOLD_ONLY;
         r.direction = dir;
         r.reason = "SKIPPED_GOLD_ONLY";
         if(m_log != NULL)
            m_log.Decision("SMT = SKIPPED_GOLD_ONLY",
                           "XAUUSD-only mode — external SMT is not a mandatory gate; no fake SMT");
         return r;
      }

      const ENUM_SMT_MODE mode = m_cfg.EffectiveSMTMode();
      if(mode == SMT_DISABLED)
      {
         r.valid = true;
         r.available = true;
         r.status = SMT_STATUS_DISABLED;
         r.direction = dir;
         r.reason = "SMT disabled";
         return r;
      }

      if(ComparePair(primary, m_cfg.in.smt_symbol1, m_cfg.in.smt_corr1, dir, r))
      {
         r.status = SMT_STATUS_CONFIRMED;
         if(m_log != NULL)
            m_log.Decision("SMT confirmed", r.reason);
         return r;
      }
      SSMTResult r2;
      IFVG_ResetSMT(r2);
      if(ComparePair(primary, m_cfg.in.smt_symbol2, m_cfg.in.smt_corr2, dir, r2))
      {
         r2.status = SMT_STATUS_CONFIRMED;
         if(m_log != NULL)
            m_log.Decision("SMT confirmed", r2.reason);
         return r2;
      }

      if(mode == SMT_OPTIONAL)
      {
         r.valid = true;
         r.available = true;
         r.status = SMT_STATUS_OPTIONAL_BYPASS;
         r.direction = dir;
         r.reason = "SMT optional — not present, filter bypassed";
         if(m_log != NULL)
            m_log.Decision("SMT optional", "not present, continuing");
         return r;
      }

      r.valid = false;
      r.status = SMT_STATUS_MISSING;
      r.reason = "SMT missing";
      if(m_log != NULL)
         m_log.NoTrade("SMT missing");
      return r;
   }
};

#endif

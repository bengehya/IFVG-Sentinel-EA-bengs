#ifndef MM_DIRECTIONENGINE_MQH
#define MM_DIRECTIONENGINE_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Utils.mqh"

class CMMDirectionEngine
{
private:
   CMMConfig *m_cfg;
   CMMLogger *m_log;
   string     m_last_fp;

   bool CollectLastSwings(const string symbol, const ENUM_TIMEFRAMES tf,
                          double &h0, double &h1, double &l0, double &l1)
   {
      h0 = h1 = l0 = l1 = 0.0;
      MqlRates rates[];
      const int need = m_cfg.in.structure_lookback + m_cfg.in.swing_left + m_cfg.in.swing_right + 5;
      if(!MM_CopyRatesSafe(symbol, tf, need, rates))
         return false;
      SMMSwing highs[], lows[];
      ArrayResize(highs, 0);
      ArrayResize(lows, 0);
      const int left = m_cfg.in.swing_left;
      const int right = m_cfg.in.swing_right;
      const int n = ArraySize(rates);
      const int end = MathMin(n - left - 1, m_cfg.in.structure_lookback);
      for(int i = right; i <= end; i++)
      {
         if(MM_IsSwingHigh(rates, i, left, right))
         {
            const int k = ArraySize(highs);
            ArrayResize(highs, k + 1);
            highs[k].price = rates[i].high;
            highs[k].time = rates[i].time;
            highs[k].confirmed = true;
         }
         if(MM_IsSwingLow(rates, i, left, right))
         {
            const int k = ArraySize(lows);
            ArrayResize(lows, k + 1);
            lows[k].price = rates[i].low;
            lows[k].time = rates[i].time;
            lows[k].confirmed = true;
         }
      }
      if(ArraySize(highs) < 2 || ArraySize(lows) < 2)
         return false;
      h0 = highs[0].price;
      h1 = highs[1].price;
      l0 = lows[0].price;
      l1 = lows[1].price;
      return true;
   }

public:
   CMMDirectionEngine() { m_cfg = NULL; m_log = NULL; m_last_fp = ""; }

   void Init(CMMConfig *cfg, CMMLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
      m_last_fp = "";
   }

   bool Update(const string symbol, SMMDirection &out)
   {
      ZeroMemory(out);
      out.daily = MM_BIAS_NEUTRAL;
      out.h4 = MM_BIAS_NEUTRAL;
      out.aligned = MM_BIAS_NEUTRAL;
      out.valid = false;

      double dh0, dh1, dl0, dl1, hh0, hh1, hl0, hl1;
      if(!CollectLastSwings(symbol, MM_TF_DAILY, dh0, dh1, dl0, dl1))
         out.daily = MM_BIAS_NEUTRAL;
      else
      {
         out.d1_high = dh0;
         out.d1_low = dl0;
         out.daily = MM_BiasFromSwings(dh0, dh1, dl0, dl1);
      }

      if(!CollectLastSwings(symbol, MM_TF_H4, hh0, hh1, hl0, hl1))
         out.h4 = MM_BIAS_NEUTRAL;
      else
      {
         out.h4_high = hh0;
         out.h4_low = hl0;
         out.h4 = MM_BiasFromSwings(hh0, hh1, hl0, hl1);
      }

      out.aligned = MM_AlignBias(out.daily, out.h4);
      out.valid = (out.aligned == MM_BIAS_BULLISH || out.aligned == MM_BIAS_BEARISH);

      const string fp = MM_BiasToString(out.daily) + "|" + MM_BiasToString(out.h4) + "|" + MM_BiasToString(out.aligned);
      if(m_log != NULL && fp != m_last_fp)
      {
         m_last_fp = fp;
         m_log.Direction("Daily=" + MM_BiasToString(out.daily));
         m_log.Direction("H4=" + MM_BiasToString(out.h4));
         m_log.Direction("Decision=" + MM_BiasToString(out.aligned));
      }
      return out.valid;
   }
};

#endif

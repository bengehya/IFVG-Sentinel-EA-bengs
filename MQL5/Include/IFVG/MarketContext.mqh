#ifndef IFVG_MARKETCONTEXT_MQH
#define IFVG_MARKETCONTEXT_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Utils.mqh"

class CMarketContext
{
private:
   CIFVGConfig  *m_cfg;
   CIFVGLogger  *m_log;
   ENUM_IFVG_BIAS m_bias;
   datetime       m_last_hh;
   datetime       m_last_hl;
   datetime       m_last_lh;
   datetime       m_last_ll;
   double         m_last_swing_high;
   double         m_last_swing_low;
   bool           m_valid;

   void CollectSwings(const MqlRates &rates[],
                      SSwing &highs[],
                      SSwing &lows[],
                      const int lookback)
   {
      ArrayResize(highs, 0);
      ArrayResize(lows, 0);
      const int left = m_cfg.in.swing_left;
      const int right = m_cfg.in.swing_right;
      const int n = ArraySize(rates);
      const int end = MathMin(n - left - 1, lookback);
      for(int i = right; i <= end; i++)
      {
         if(IFVG_IsSwingHigh(rates, i, left, right))
         {
            const int k = ArraySize(highs);
            ArrayResize(highs, k + 1);
            highs[k].bar_index = i;
            highs[k].time = rates[i].time;
            highs[k].price = rates[i].high;
            highs[k].is_high = true;
            highs[k].confirmed = true;
         }
         if(IFVG_IsSwingLow(rates, i, left, right))
         {
            const int k = ArraySize(lows);
            ArrayResize(lows, k + 1);
            lows[k].bar_index = i;
            lows[k].time = rates[i].time;
            lows[k].price = rates[i].low;
            lows[k].is_high = false;
            lows[k].confirmed = true;
         }
      }
   }

public:
   CMarketContext()
   {
      m_cfg = NULL;
      m_log = NULL;
      m_bias = IFVG_BIAS_NONE;
      m_valid = false;
      m_last_swing_high = 0;
      m_last_swing_low = 0;
      m_last_hh = 0;
      m_last_hl = 0;
      m_last_lh = 0;
      m_last_ll = 0;
   }

   void Init(CIFVGConfig *cfg, CIFVGLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
   }

   bool Update(const string symbol)
   {
      m_valid = false;
      m_bias = IFVG_BIAS_NONE;
      MqlRates rates[];
      const int need = m_cfg.in.htf_structure_lookback + m_cfg.in.swing_left + m_cfg.in.swing_right + 5;
      if(!IFVG_CopyRatesSafe(symbol, m_cfg.in.htf, need, rates))
      {
         if(m_log != NULL)
            m_log.Warn("HTF rates unavailable");
         return false;
      }

      SSwing highs[], lows[];
      CollectSwings(rates, highs, lows, m_cfg.in.htf_structure_lookback);
      if(ArraySize(highs) < 2 || ArraySize(lows) < 2)
      {
         m_bias = IFVG_BIAS_NEUTRAL;
         if(m_log != NULL)
            m_log.Decision("HTF Bias", "NEUTRAL — insufficient confirmed swings");
         m_valid = false;
         return false;
      }

      const double h0 = highs[0].price;
      const double h1 = highs[1].price;
      const double l0 = lows[0].price;
      const double l1 = lows[1].price;
      m_last_swing_high = h0;
      m_last_swing_low = l0;

      const bool hh = (h0 > h1);
      const bool hl = (l0 > l1);
      const bool lh = (h0 < h1);
      const bool ll = (l0 < l1);

      if(hh && hl)
      {
         m_bias = IFVG_BIAS_BULLISH;
         m_valid = true;
         m_last_hh = highs[0].time;
         m_last_hl = lows[0].time;
      }
      else if(lh && ll)
      {
         m_bias = IFVG_BIAS_BEARISH;
         m_valid = true;
         m_last_lh = highs[0].time;
         m_last_ll = lows[0].time;
      }
      else
      {
         m_bias = IFVG_BIAS_NEUTRAL;
         m_valid = false;
      }

      if(m_log != NULL)
         m_log.Decision("HTF Bias", IFVG_BiasToString(m_bias));
      return m_valid;
   }

   ENUM_IFVG_BIAS Bias() const { return m_bias; }
   bool Valid() const { return m_valid; }
   double LastSwingHigh() const { return m_last_swing_high; }
   double LastSwingLow() const { return m_last_swing_low; }
};

#endif

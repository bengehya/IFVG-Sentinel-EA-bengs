#ifndef IFVG_SWEEPDETECTOR_MQH
#define IFVG_SWEEPDETECTOR_MQH

#include "LiquidityDetector.mqh"

class CSweepDetector
{
private:
   CIFVGConfig        *m_cfg;
   CIFVGLogger        *m_log;
   SSymbolSpec         m_spec;

public:
   void Init(CIFVGConfig *cfg, CIFVGLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
   }

   void SetSpec(const SSymbolSpec &spec) { m_spec = spec; }

   bool Detect(const string symbol,
               CLiquidityDetector &liq,
               const ENUM_IFVG_DIR expected_dir,
               SSweep &out)
   {
      ZeroMemory(out);
      out.valid = false;

      MqlRates rates[];
      const int need = MathMax(30, m_cfg.in.sweep_max_age_bars + 5);
      if(!IFVG_CopyRatesSafe(symbol, m_cfg.in.confirmation_tf, need, rates))
         return false;

      const double atr = IFVG_ATR(rates, 14, 1);
      const double min_beyond = IFVG_PointsToPrice(m_spec, (double)m_cfg.in.min_sweep_points);
      const double min_closeback = IFVG_PointsToPrice(m_spec, (double)m_cfg.in.min_sweep_closeback_points);
      const int n = ArraySize(rates);
      const int max_i = MathMin(n - 2, m_cfg.in.sweep_max_age_bars);

      for(int p = 0; p < liq.Count(); p++)
      {
         SLiquidity L = liq.At(p);
         if(!L.active || L.swept)
            continue;

         if(expected_dir == IFVG_DIR_BUY && L.side != LIQ_SELL_SIDE)
            continue;
         if(expected_dir == IFVG_DIR_SELL && L.side != LIQ_BUY_SIDE)
            continue;

         for(int i = 1; i <= max_i; i++)
         {
            const MqlRates r = rates[i];
            if(r.time < L.created)
               continue;

            bool swept = false;
            double extreme = 0.0;
            double beyond = 0.0;
            bool close_back = false;
            bool rejection = false;

            if(L.side == LIQ_SELL_SIDE)
            {
               if(r.low < L.price - min_beyond && r.close > L.price + min_closeback)
               {
                  swept = true;
                  extreme = r.low;
                  beyond = IFVG_PriceToPoints(m_spec, L.price - r.low);
                  close_back = true;
                  const double rng = IFVG_CandleRange(r);
                  rejection = (rng > 0.0 && (r.close - r.low) / rng >= 0.55 && IFVG_IsBullClose(r));
               }
            }
            else if(L.side == LIQ_BUY_SIDE)
            {
               if(r.high > L.price + min_beyond && r.close < L.price - min_closeback)
               {
                  swept = true;
                  extreme = r.high;
                  beyond = IFVG_PriceToPoints(m_spec, r.high - L.price);
                  close_back = true;
                  const double rng = IFVG_CandleRange(r);
                  rejection = (rng > 0.0 && (r.high - r.close) / rng >= 0.55 && IFVG_IsBearClose(r));
               }
            }

            if(!swept || !close_back || !rejection)
               continue;

            if(atr > 0.0 && IFVG_CandleRange(r) < atr * m_cfg.in.min_sweep_atr_mult)
               continue;

            out.valid = true;
            out.direction = (L.side == LIQ_SELL_SIDE) ? IFVG_DIR_BUY : IFVG_DIR_SELL;
            out.side = L.side;
            out.liquidity_id = L.id;
            out.level = L.price;
            out.extreme = extreme;
            out.time = r.time;
            out.bar_index = i;
            out.close_back = r.close;
            out.wick_beyond_points = beyond;
            out.rejection = true;
            liq.MarkSwept(L.id, r.time, extreme);
            if(m_log != NULL)
               m_log.Decision("Sweep confirmed",
                              IFVG_LiqToString(L.side) + " level=" + DoubleToString(L.price, m_spec.digits));
            return true;
         }
      }
      return false;
   }
};

#endif

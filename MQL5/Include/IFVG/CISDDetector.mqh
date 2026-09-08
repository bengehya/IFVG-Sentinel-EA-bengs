#ifndef IFVG_CISDDETECTOR_MQH
#define IFVG_CISDDETECTOR_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Utils.mqh"

class CCISDDetector
{
private:
   CIFVGConfig  *m_cfg;
   CIFVGLogger  *m_log;

public:
   void Init(CIFVGConfig *cfg, CIFVGLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
   }

   SCISDResult DetectCISD(const string symbol,
                          const SSweep &sweep)
   {
      SCISDResult r;
      IFVG_ResetCISD(r);
      r.setup_state = ST_SWEEP_DETECTED;

      if(!sweep.valid)
      {
         r.reason = "no valid sweep";
         return r;
      }

      MqlRates rates[];
      const int need = m_cfg.in.cisd_max_bars_after_sweep + 10;
      if(!IFVG_CopyRatesSafe(symbol, m_cfg.in.confirmation_tf, need, rates))
      {
         r.reason = "CISD rates unavailable";
         return r;
      }

      int sweep_i = -1;
      const int n = ArraySize(rates);
      for(int i = 1; i < n; i++)
      {
         if(rates[i].time == sweep.time)
         {
            sweep_i = i;
            break;
         }
      }
      if(sweep_i < 0)
      {
         r.reason = "sweep bar not found";
         return r;
      }

      const double atr = IFVG_ATR(rates, 14, 1);
      const double min_body = atr * m_cfg.in.cisd_min_body_atr;
      int opposing = -1;

      if(sweep.direction == IFVG_DIR_BUY)
      {
         for(int i = sweep_i; i < n; i++)
         {
            if(IFVG_IsBearClose(rates[i]))
            {
               opposing = i;
               break;
            }
         }
      }
      else
      {
         for(int i = sweep_i; i < n; i++)
         {
            if(IFVG_IsBullClose(rates[i]))
            {
               opposing = i;
               break;
            }
         }
      }

      if(opposing < 0)
      {
         r.reason = "no opposing delivery candle";
         return r;
      }

      const double open_ref = rates[opposing].open;
      const int last = MathMax(1, sweep_i - m_cfg.in.cisd_max_bars_after_sweep);

      for(int i = sweep_i - 1; i >= last; i--)
      {
         if(i < 1)
            break;
         const double body = IFVG_CandleBody(rates[i]);
         if(body < min_body)
            continue;
         const double rng = IFVG_CandleRange(rates[i]);
         if(rng <= 0.0)
            continue;
         const double ratio = body / rng;
         if(ratio < 0.5)
            continue;

         if(sweep.direction == IFVG_DIR_BUY)
         {
            if(IFVG_IsBullClose(rates[i]) && rates[i].close > open_ref && rates[i].close > rates[sweep_i].high)
            {
               r.valid = true;
               r.direction = IFVG_DIR_BUY;
               r.timestamp = rates[i].time;
               r.confirmation_level = rates[i].close;
               r.body_ratio = ratio;
               r.setup_state = ST_CISD_VALIDATED;
               r.reason = "bullish CISD close through opposing open and sweep high";
               if(m_log != NULL)
                  m_log.Decision("CISD confirmed", r.reason);
               return r;
            }
         }
         else if(sweep.direction == IFVG_DIR_SELL)
         {
            if(IFVG_IsBearClose(rates[i]) && rates[i].close < open_ref && rates[i].close < rates[sweep_i].low)
            {
               r.valid = true;
               r.direction = IFVG_DIR_SELL;
               r.timestamp = rates[i].time;
               r.confirmation_level = rates[i].close;
               r.body_ratio = ratio;
               r.setup_state = ST_CISD_VALIDATED;
               r.reason = "bearish CISD close through opposing open and sweep low";
               if(m_log != NULL)
                  m_log.Decision("CISD confirmed", r.reason);
               return r;
            }
         }
      }

      r.reason = "CISD not confirmed";
      return r;
   }

   bool DetectDisplacement(const string symbol,
                           const SCISDResult &cisd,
                           double &points,
                           string &why)
   {
      points = 0.0;
      why = "";
      if(!cisd.valid)
      {
         why = "no valid CISD";
         return false;
      }
      MqlRates rates[];
      if(!IFVG_CopyRatesSafe(symbol, m_cfg.in.confirmation_tf, 40, rates))
      {
         why = "displacement rates unavailable";
         return false;
      }
      const double atr = IFVG_ATR(rates, 14, 1);
      int cisd_i = -1;
      const int n = ArraySize(rates);
      for(int i = 1; i < n; i++)
      {
         if(rates[i].time == cisd.timestamp)
         {
            cisd_i = i;
            break;
         }
      }
      if(cisd_i < 0)
      {
         why = "CISD bar not found";
         return false;
      }

      const int bars = MathMax(1, m_cfg.in.displacement_min_bars);
      double move = 0.0;
      int counted = 0;
      for(int i = cisd_i; i >= 1 && counted < bars + 2; i--)
      {
         if(cisd.direction == IFVG_DIR_BUY && IFVG_IsBullClose(rates[i]))
            move += IFVG_CandleBody(rates[i]);
         else if(cisd.direction == IFVG_DIR_SELL && IFVG_IsBearClose(rates[i]))
            move += IFVG_CandleBody(rates[i]);
         else if(counted > 0)
            break;
         counted++;
      }
      points = move;
      if(atr <= 0.0)
      {
         why = "ATR unavailable";
         return false;
      }
      const double need = atr * m_cfg.in.displacement_atr_mult;
      if(move < need)
      {
         why = "body sum " + DoubleToString(move, 5) + " < ATR*mult " + DoubleToString(need, 5);
         return false;
      }
      why = "";
      return true;
   }
};

#endif

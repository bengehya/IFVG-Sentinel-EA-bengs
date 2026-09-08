#ifndef IFVG_FVGDETECTOR_MQH
#define IFVG_FVGDETECTOR_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Utils.mqh"

class CFVGDetector
{
private:
   CIFVGConfig  *m_cfg;
   CIFVGLogger  *m_log;
   SSymbolSpec   m_spec;
   SFVG          m_fvgs[IFVG_MAX_FVG];
   int           m_count;
   ulong         m_next_id;

   bool Exists(const datetime t, const ENUM_IFVG_DIR dir) const
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_fvgs[i].timestamp == t && m_fvgs[i].direction == dir)
            return true;
      }
      return false;
   }

   void Push(const SFVG &f)
   {
      if(m_count >= IFVG_MAX_FVG)
      {
         for(int i = 0; i < m_count - 1; i++)
            m_fvgs[i] = m_fvgs[i + 1];
         m_count--;
      }
      m_fvgs[m_count++] = f;
   }

public:
   CFVGDetector()
   {
      m_count = 0;
      m_next_id = 1;
   }

   void Init(CIFVGConfig *cfg, CIFVGLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
      m_count = 0;
   }

   void SetSpec(const SSymbolSpec &spec) { m_spec = spec; }

   void Scan(const string symbol, const ENUM_TIMEFRAMES tf)
   {
      MqlRates rates[];
      const int need = MathMax(60, m_cfg.in.fvg_max_age_bars + 10);
      if(!IFVG_CopyRatesSafe(symbol, tf, need, rates))
         return;

      const double min_gap = IFVG_PointsToPrice(m_spec, (double)m_cfg.in.fvg_min_points);
      const int n = ArraySize(rates);
      const int start = m_cfg.in.fvg_require_closed_bars ? 1 : 0;
      const datetime now = TimeCurrent();
      const int max_age = m_cfg.in.fvg_max_age_bars * IFVG_PeriodSeconds(tf);

      for(int i = 0; i < m_count; i++)
      {
         if(!m_fvgs[i].active)
            continue;
         if(now - m_fvgs[i].timestamp > max_age && m_fvgs[i].state != FVG_INVERTED)
         {
            m_fvgs[i].state = FVG_INVALIDATED;
            m_fvgs[i].active = false;
         }
      }

      for(int i = start + 1; i < n - 2; i++)
      {
         if(rates[i - 1].low > rates[i + 1].high)
         {
            const double hi = rates[i - 1].low;
            const double lo = rates[i + 1].high;
            if(hi - lo < min_gap)
               continue;
            if(Exists(rates[i].time, IFVG_DIR_BUY))
               continue;
            SFVG f;
            ZeroMemory(f);
            f.id = m_next_id++;
            f.direction = IFVG_DIR_BUY;
            f.state = FVG_CREATED;
            f.timeframe = tf;
            f.high = hi;
            f.low = lo;
            f.timestamp = rates[i].time;
            f.active = true;
            Push(f);
            if(m_log != NULL && m_cfg.in.debug_mode)
               m_log.Debug("bullish FVG " + DoubleToString(lo, m_spec.digits) + "-" + DoubleToString(hi, m_spec.digits));
         }
         if(rates[i - 1].high < rates[i + 1].low)
         {
            const double hi = rates[i + 1].low;
            const double lo = rates[i - 1].high;
            if(hi - lo < min_gap)
               continue;
            if(Exists(rates[i].time, IFVG_DIR_SELL))
               continue;
            SFVG f;
            ZeroMemory(f);
            f.id = m_next_id++;
            f.direction = IFVG_DIR_SELL;
            f.state = FVG_CREATED;
            f.timeframe = tf;
            f.high = hi;
            f.low = lo;
            f.timestamp = rates[i].time;
            f.active = true;
            Push(f);
         }
      }

      UpdateLifecycle(rates);
   }

   void UpdateLifecycle(const MqlRates &rates[])
   {
      if(ArraySize(rates) < 3)
         return;
      for(int i = 0; i < m_count; i++)
      {
         if(!m_fvgs[i].active)
            continue;
         if(m_fvgs[i].state == FVG_INVERTED || m_fvgs[i].state == FVG_INVALIDATED)
            continue;

         bool tested = false;
         bool broken = false;
         datetime broken_at = 0;

         for(int b = 1; b < ArraySize(rates); b++)
         {
            if(rates[b].time <= m_fvgs[i].timestamp)
               break;
            const double h = rates[b].high;
            const double l = rates[b].low;
            const double c = rates[b].close;

            if(h >= m_fvgs[i].low && l <= m_fvgs[i].high)
               tested = true;

            if(m_fvgs[i].direction == IFVG_DIR_BUY)
            {
               if(m_cfg.in.ifvg_require_close_through)
               {
                  if(c < m_fvgs[i].low)
                  {
                     broken = true;
                     broken_at = rates[b].time;
                     break;
                  }
               }
               else if(l < m_fvgs[i].low && c < m_fvgs[i].low)
               {
                  broken = true;
                  broken_at = rates[b].time;
                  break;
               }
            }
            else
            {
               if(m_cfg.in.ifvg_require_close_through)
               {
                  if(c > m_fvgs[i].high)
                  {
                     broken = true;
                     broken_at = rates[b].time;
                     break;
                  }
               }
               else if(h > m_fvgs[i].high && c > m_fvgs[i].high)
               {
                  broken = true;
                  broken_at = rates[b].time;
                  break;
               }
            }
         }

         if(tested && m_fvgs[i].state == FVG_CREATED)
            m_fvgs[i].state = FVG_TESTED;
         if(broken)
         {
            m_fvgs[i].state = FVG_BROKEN;
            m_fvgs[i].inverted = true;
            m_fvgs[i].inverted_at = broken_at;
            m_fvgs[i].state = FVG_INVERTED;
         }
      }
   }

   bool LatestInverted(const ENUM_IFVG_DIR original_dir, SFVG &out) const
   {
      datetime newest = 0;
      int idx = -1;
      for(int i = 0; i < m_count; i++)
      {
         if(!m_fvgs[i].active)
            continue;
         if(m_fvgs[i].state != FVG_INVERTED)
            continue;
         if(m_fvgs[i].direction != original_dir)
            continue;
         if(m_fvgs[i].inverted_at >= newest)
         {
            newest = m_fvgs[i].inverted_at;
            idx = i;
         }
      }
      if(idx < 0)
         return false;
      out = m_fvgs[idx];
      return true;
   }

   bool HasAnyActiveFVG() const
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_fvgs[i].active && (m_fvgs[i].state == FVG_CREATED || m_fvgs[i].state == FVG_TESTED))
            return true;
      }
      return false;
   }

   string ExplainNoInvertedFVG(const ENUM_IFVG_DIR original_dir) const
   {
      int opposing_plain = 0;
      int inverted_wrong_dir = 0;
      for(int i = 0; i < m_count; i++)
      {
         if(!m_fvgs[i].active)
            continue;
         if(m_fvgs[i].direction == original_dir)
         {
            if(m_fvgs[i].state == FVG_CREATED || m_fvgs[i].state == FVG_TESTED)
               opposing_plain++;
         }
         else if(m_fvgs[i].state == FVG_INVERTED)
            inverted_wrong_dir++;
      }
      if(opposing_plain > 0)
         return "opposing FVG exists but no close-through inversion";
      if(inverted_wrong_dir > 0)
         return "inverted FVG exists but wrong direction for this setup";
      if(HasAnyActiveFVG())
         return "FVG present but not opposing / not inverted";
      if(m_count <= 0)
         return "no FVG detected";
      return "no inverted opposing FVG";
   }

   int Count() const { return m_count; }
   SFVG At(const int i) const { return m_fvgs[i]; }
};

#endif

#ifndef IFVG_IFVGMANAGER_MQH
#define IFVG_IFVGMANAGER_MQH

#include "FVGDetector.mqh"

class CIFVGManager
{
private:
   CIFVGConfig  *m_cfg;
   CIFVGLogger  *m_log;
   SSymbolSpec   m_spec;
   SIFVG         m_zones[IFVG_MAX_FVG];
   int           m_count;
   ulong         m_next_id;
   ulong         m_used_ids[IFVG_MAX_USED_SETUP_IDS];
   int           m_used_n;

   int FindBySource(const ulong fvg_id) const
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_zones[i].source_fvg_id == fvg_id)
            return i;
      }
      return -1;
   }

public:
   CIFVGManager()
   {
      m_count = 0;
      m_next_id = 1;
      m_used_n = 0;
   }

   void Init(CIFVGConfig *cfg, CIFVGLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
      m_count = 0;
      m_used_n = 0;
   }

   void SetSpec(const SSymbolSpec &spec) { m_spec = spec; }

   bool RememberUsed(const ulong setup_id)
   {
      for(int i = 0; i < m_used_n; i++)
      {
         if(m_used_ids[i] == setup_id)
            return false;
      }
      if(m_used_n >= IFVG_MAX_USED_SETUP_IDS)
      {
         for(int i = 0; i < m_used_n - 1; i++)
            m_used_ids[i] = m_used_ids[i + 1];
         m_used_n--;
      }
      m_used_ids[m_used_n++] = setup_id;
      return true;
   }

   bool AlreadyUsed(const ulong setup_id) const
   {
      for(int i = 0; i < m_used_n; i++)
      {
         if(m_used_ids[i] == setup_id)
            return true;
      }
      return false;
   }

   bool CreateFromInvertedFVG(const SFVG &fvg, SIFVG &out)
   {
      ZeroMemory(out); // SIFVG has no string fields
      if(fvg.state != FVG_INVERTED || !fvg.inverted)
         return false;
      Age(TimeCurrent());
      if(FindBySource(fvg.id) >= 0)
      {
         out = m_zones[FindBySource(fvg.id)];
         return (out.life != IFVG_LIFE_INVALIDATED && out.life != IFVG_LIFE_EXPIRED && !out.traded);
      }

      SIFVG z;
      ZeroMemory(z);
      z.id = m_next_id++;
      z.source_fvg_id = fvg.id;
      z.direction = (fvg.direction == IFVG_DIR_BUY) ? IFVG_DIR_SELL : IFVG_DIR_BUY;
      z.life = IFVG_LIFE_CREATED;
      z.timeframe = fvg.timeframe;
      z.high = fvg.high;
      z.low = fvg.low;
      z.created = fvg.inverted_at;
      z.expire = z.created + (datetime)m_cfg.in.ifvg_validity_seconds;
      z.retest_count = 0;
      z.traded = false;

      if(m_count >= IFVG_MAX_FVG)
      {
         for(int i = 0; i < m_count - 1; i++)
            m_zones[i] = m_zones[i + 1];
         m_count--;
      }
      m_zones[m_count++] = z;
      out = z;
      if(m_log != NULL)
      {
         m_log.Decision("FVG inverted", IFVG_DirToString(fvg.direction) + " FVG -> " + IFVG_DirToString(z.direction) + " IFVG");
         m_log.Decision("IFVG created", DoubleToString(z.low, m_spec.digits) + "-" + DoubleToString(z.high, m_spec.digits));
      }
      return true;
   }

   void Age(const datetime now)
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_zones[i].life == IFVG_LIFE_TRADED || m_zones[i].life == IFVG_LIFE_INVALIDATED)
            continue;
         if(m_zones[i].expire > 0 && now >= m_zones[i].expire)
            m_zones[i].life = IFVG_LIFE_EXPIRED;
      }
   }

   void MarkExpired(SIFVG &z)
   {
      z.life = IFVG_LIFE_EXPIRED;
      const int idx = FindBySource(z.source_fvg_id);
      if(idx >= 0)
         m_zones[idx] = z;
   }

   bool ValidityElapsed(SIFVG &z, const datetime now)
   {
      if(z.id == 0)
         return false;
      if(z.life == IFVG_LIFE_TRADED)
         return false;

      Age(now);

      const int idx = FindBySource(z.source_fvg_id);
      if(idx >= 0 && m_zones[idx].life == IFVG_LIFE_EXPIRED)
      {
         z.life = IFVG_LIFE_EXPIRED;
         return true;
      }
      if(z.life == IFVG_LIFE_EXPIRED)
         return true;
      if(z.life != IFVG_LIFE_INVALIDATED && z.expire > 0 && now >= z.expire)
      {
         MarkExpired(z);
         return true;
      }
      return false;
   }

   static bool IsWaitingForRetestReason(const string reason)
   {
      if(StringFind(reason, "price has not returned into IFVG zone") >= 0)
         return true;
      if(reason == "IFVG without retest")
         return true;
      return false;
   }

   bool IsValidIFVGRetest(const SIFVG &z,
                          const MqlRates &bar,
                          const datetime now,
                          string &reason) const
   {
      reason = "";
      if(z.life == IFVG_LIFE_TRADED)
      {
         reason = "IFVG already traded";
         return false;
      }
      if(z.life == IFVG_LIFE_INVALIDATED || z.life == IFVG_LIFE_EXPIRED)
      {
         reason = "IFVG invalidated/expired";
         return false;
      }
      if(now > z.expire)
      {
         reason = "IFVG validity period elapsed";
         return false;
      }
      if(z.retest_count >= m_cfg.in.ifvg_max_retests)
      {
         reason = "IFVG max retests reached";
         return false;
      }

      const double tol = IFVG_PointsToPrice(m_spec, (double)m_cfg.in.ifvg_tolerance_points);
      const double zone_high = z.high + tol;
      const double zone_low = z.low - tol;

      const bool overlaps = (bar.low <= zone_high && bar.high >= zone_low);
      if(!overlaps)
      {
         reason = "price has not returned into IFVG zone";
         return false;
      }

      if(z.direction == IFVG_DIR_BUY)
      {
         if(bar.close < zone_low)
         {
            reason = "bullish IFVG invalidated by close below zone";
            return false;
         }
      }
      else if(z.direction == IFVG_DIR_SELL)
      {
         if(bar.close > zone_high)
         {
            reason = "bearish IFVG invalidated by close above zone";
            return false;
         }
      }
      else
      {
         reason = "IFVG direction none";
         return false;
      }
      return true;
   }

   bool UpdateRetest(const string symbol, SIFVG &z)
   {
      if(ValidityElapsed(z, TimeCurrent()))
         return false;

      MqlRates rates[];
      if(!IFVG_CopyRatesSafe(symbol, m_cfg.in.entry_tf, 5, rates))
         return false;
      if(ArraySize(rates) < 2)
         return false;

      string reason = "";
      const MqlRates bar = rates[1];
      if(bar.time <= z.created)
         return false;
      if(z.last_retest == bar.time)
         return (z.life == IFVG_LIFE_RETEST);

      if(!IsValidIFVGRetest(z, bar, TimeCurrent(), reason))
      {
         if(StringFind(reason, "invalidated") >= 0)
            z.life = IFVG_LIFE_INVALIDATED;
         const int idx = FindBySource(z.source_fvg_id);
         if(idx >= 0)
            m_zones[idx] = z;
         return false;
      }

      z.retest_count++;
      z.last_retest = bar.time;
      z.life = IFVG_LIFE_RETEST;
      const int idx = FindBySource(z.source_fvg_id);
      if(idx >= 0)
         m_zones[idx] = z;
      if(m_log != NULL)
         m_log.Decision("Retest confirmed", "count=" + IntegerToString(z.retest_count));
      return true;
   }

   void MarkTraded(SIFVG &z)
   {
      z.life = IFVG_LIFE_TRADED;
      z.traded = true;
      const int idx = FindBySource(z.source_fvg_id);
      if(idx >= 0)
         m_zones[idx] = z;
   }

   void MarkWaiting(SIFVG &z)
   {
      if(z.life == IFVG_LIFE_CREATED)
         z.life = IFVG_LIFE_WAITING_RETEST;
      const int idx = FindBySource(z.source_fvg_id);
      if(idx >= 0)
         m_zones[idx] = z;
      if(m_log != NULL)
         m_log.Decision("Waiting for retest", "");
   }
};

#endif

#ifndef IFVG_PDARRAY_MQH
#define IFVG_PDARRAY_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Utils.mqh"

class CPDArray
{
private:
   CIFVGConfig  *m_cfg;
   CIFVGLogger  *m_log;
   SPDZone       m_zones[IFVG_MAX_PD_ZONES];
   int           m_count;
   ulong         m_next_id;

   void Expire(const datetime now, const ENUM_TIMEFRAMES tf)
   {
      const int bar_sec = IFVG_PeriodSeconds(tf);
      const int max_age = m_cfg.in.pd_expire_bars * bar_sec;
      for(int i = 0; i < m_count; i++)
      {
         if(m_zones[i].status != ZONE_STATUS_ACTIVE)
            continue;
         if(now - m_zones[i].created > max_age)
            m_zones[i].status = ZONE_STATUS_EXPIRED;
         if(m_zones[i].expire > 0 && now >= m_zones[i].expire)
            m_zones[i].status = ZONE_STATUS_EXPIRED;
      }
   }

   void InvalidateByClose(const MqlRates &rates[])
   {
      if(ArraySize(rates) < 2)
         return;
      const double c = rates[1].close;
      for(int i = 0; i < m_count; i++)
      {
         if(m_zones[i].status != ZONE_STATUS_ACTIVE)
            continue;
         if(m_zones[i].direction == IFVG_DIR_BUY && c < m_zones[i].low)
            m_zones[i].status = ZONE_STATUS_INVALIDATED;
         if(m_zones[i].direction == IFVG_DIR_SELL && c > m_zones[i].high)
            m_zones[i].status = ZONE_STATUS_INVALIDATED;
      }
   }

   bool AddZone(const SPDZone &z)
   {
      if(m_count >= IFVG_MAX_PD_ZONES)
      {
         for(int i = 0; i < m_count - 1; i++)
            m_zones[i] = m_zones[i + 1];
         m_count--;
      }
      m_zones[m_count++] = z;
      return true;
   }

   bool ZoneExists(const ENUM_ZONE_TYPE type, const datetime t, const double high, const double low) const
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_zones[i].type == type && m_zones[i].created == t &&
            MathAbs(m_zones[i].high - high) < 1e-8 && MathAbs(m_zones[i].low - low) < 1e-8)
            return true;
      }
      return false;
   }

public:
   CPDArray()
   {
      m_count = 0;
      m_next_id = 1;
      m_cfg = NULL;
      m_log = NULL;
   }

   void Init(CIFVGConfig *cfg, CIFVGLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
      m_count = 0;
   }

   void Scan(const string symbol, const ENUM_TIMEFRAMES tf)
   {
      MqlRates rates[];
      const int need = MathMax(80, m_cfg.in.pd_expire_bars + 20);
      if(!IFVG_CopyRatesSafe(symbol, tf, need, rates))
         return;

      Expire(TimeCurrent(), tf);
      InvalidateByClose(rates);

      const double atr = IFVG_ATR(rates, 14, 1);
      if(atr <= 0.0)
         return;

      const int n = ArraySize(rates);
      for(int i = 3; i < n - 5; i++)
      {
         if(rates[i].low > rates[i + 2].high)
         {
            const double hi = rates[i].low;
            const double lo = rates[i + 2].high;
            if(!ZoneExists(ZONE_FVG, rates[i + 1].time, hi, lo))
            {
               SPDZone z;
               ZeroMemory(z);
               z.type = ZONE_FVG;
               z.direction = IFVG_DIR_BUY;
               z.status = ZONE_STATUS_ACTIVE;
               z.timeframe = tf;
               z.high = hi;
               z.low = lo;
               z.created = rates[i + 1].time;
               z.expire = z.created + (datetime)(m_cfg.in.pd_expire_bars * IFVG_PeriodSeconds(tf));
               z.id = m_next_id++;
               AddZone(z);
            }
         }
         if(rates[i].high < rates[i + 2].low)
         {
            const double hi = rates[i + 2].low;
            const double lo = rates[i].high;
            if(!ZoneExists(ZONE_FVG, rates[i + 1].time, hi, lo))
            {
               SPDZone z;
               ZeroMemory(z);
               z.type = ZONE_FVG;
               z.direction = IFVG_DIR_SELL;
               z.status = ZONE_STATUS_ACTIVE;
               z.timeframe = tf;
               z.high = hi;
               z.low = lo;
               z.created = rates[i + 1].time;
               z.expire = z.created + (datetime)(m_cfg.in.pd_expire_bars * IFVG_PeriodSeconds(tf));
               z.id = m_next_id++;
               AddZone(z);
            }
         }
      }

      const int impulse = MathMax(2, m_cfg.in.ob_impulse_bars);
      for(int i = 1; i < n - impulse - 2; i++)
      {
         double move = 0.0;
         bool up = true;
         bool down = true;
         for(int k = 0; k < impulse; k++)
         {
            if(!IFVG_IsBullClose(rates[i + k]))
               up = false;
            if(!IFVG_IsBearClose(rates[i + k]))
               down = false;
            move += IFVG_CandleBody(rates[i + k]);
         }
         if(move < atr * m_cfg.in.ob_displacement_atr)
            continue;

         if(up)
         {
            int ob = i + impulse;
            while(ob < n - 1 && IFVG_IsBullClose(rates[ob]))
               ob++;
            if(ob >= n)
               continue;
            SPDZone z;
            ZeroMemory(z);
            z.type = ZONE_ORDER_BLOCK;
            z.direction = IFVG_DIR_BUY;
            z.status = ZONE_STATUS_ACTIVE;
            z.timeframe = tf;
            z.high = rates[ob].high;
            z.low = rates[ob].low;
            z.created = rates[ob].time;
            z.expire = z.created + (datetime)(m_cfg.in.pd_expire_bars * IFVG_PeriodSeconds(tf));
            z.id = m_next_id++;
            if(!ZoneExists(ZONE_ORDER_BLOCK, z.created, z.high, z.low))
               AddZone(z);
         }
         if(down)
         {
            int ob = i + impulse;
            while(ob < n - 1 && IFVG_IsBearClose(rates[ob]))
               ob++;
            if(ob >= n)
               continue;
            SPDZone z;
            ZeroMemory(z);
            z.type = ZONE_ORDER_BLOCK;
            z.direction = IFVG_DIR_SELL;
            z.status = ZONE_STATUS_ACTIVE;
            z.timeframe = tf;
            z.high = rates[ob].high;
            z.low = rates[ob].low;
            z.created = rates[ob].time;
            z.expire = z.created + (datetime)(m_cfg.in.pd_expire_bars * IFVG_PeriodSeconds(tf));
            z.id = m_next_id++;
            if(!ZoneExists(ZONE_ORDER_BLOCK, z.created, z.high, z.low))
               AddZone(z);
         }
      }
   }

   bool HasActiveZone(const ENUM_IFVG_DIR dir, SPDZone &out) const
   {
      datetime newest = 0;
      int idx = -1;
      for(int i = 0; i < m_count; i++)
      {
         if(m_zones[i].status != ZONE_STATUS_ACTIVE)
            continue;
         if(m_zones[i].direction != dir)
            continue;
         if(m_zones[i].created >= newest)
         {
            newest = m_zones[i].created;
            idx = i;
         }
      }
      if(idx < 0)
         return false;
      out = m_zones[idx];
      return true;
   }

   int ActiveCount(const ENUM_IFVG_DIR dir) const
   {
      int c = 0;
      for(int i = 0; i < m_count; i++)
      {
         if(m_zones[i].status == ZONE_STATUS_ACTIVE && m_zones[i].direction == dir)
            c++;
      }
      return c;
   }
};

#endif

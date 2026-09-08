#ifndef IFVG_LIQUIDITYDETECTOR_MQH
#define IFVG_LIQUIDITYDETECTOR_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Utils.mqh"

class CLiquidityDetector
{
private:
   CIFVGConfig  *m_cfg;
   CIFVGLogger  *m_log;
   SSymbolSpec   m_spec;
   SLiquidity    m_pool[IFVG_MAX_LIQUIDITY];
   int           m_count;
   ulong         m_next_id;

   int FindByPriceSide(const ENUM_LIQ_SIDE side, const double price, const double tol) const
   {
      for(int i = 0; i < m_count; i++)
      {
         if(!m_pool[i].active)
            continue;
         if(m_pool[i].side != side)
            continue;
         if(MathAbs(m_pool[i].price - price) <= tol)
            return i;
      }
      return -1;
   }

   void AddOrMerge(const ENUM_LIQ_SIDE side,
                   const ENUM_LIQ_KIND kind,
                   const double price,
                   const datetime t)
   {
      const double eq = IFVG_PointsToPrice(m_spec, (double)m_cfg.in.equal_points);
      const int existing = FindByPriceSide(side, price, eq);
      if(existing >= 0)
      {
         m_pool[existing].kind = LIQ_KIND_EQUAL;
         m_pool[existing].touch_count++;
         m_pool[existing].last_touch = t;
         const double blended = 0.5 * (m_pool[existing].price + price);
         m_pool[existing].price = blended;
         return;
      }
      if(m_count >= IFVG_MAX_LIQUIDITY)
      {
         for(int i = 0; i < m_count - 1; i++)
            m_pool[i] = m_pool[i + 1];
         m_count--;
      }
      SLiquidity l;
      ZeroMemory(l);
      l.side = side;
      l.kind = kind;
      l.price = price;
      l.tolerance = eq;
      l.created = t;
      l.last_touch = t;
      l.touch_count = 1;
      l.swept = false;
      l.active = true;
      l.id = m_next_id++;
      m_pool[m_count++] = l;
   }

public:
   CLiquidityDetector()
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

   void SetSpec(const SSymbolSpec &spec) { m_spec = spec; }

   void Scan(const string symbol)
   {
      MqlRates rates[];
      const int need = 200;
      if(!IFVG_CopyRatesSafe(symbol, m_cfg.in.confirmation_tf, need, rates))
         return;

      const int left = m_cfg.in.swing_left;
      const int right = m_cfg.in.swing_right;
      const int n = ArraySize(rates);
      const int expire_sec = m_cfg.in.liq_expire_bars * IFVG_PeriodSeconds(m_cfg.in.confirmation_tf);
      const datetime now = TimeCurrent();

      for(int i = 0; i < m_count; i++)
      {
         if(!m_pool[i].active)
            continue;
         if(now - m_pool[i].created > expire_sec)
            m_pool[i].active = false;
      }

      for(int i = right; i < n - left; i++)
      {
         if(IFVG_IsSwingHigh(rates, i, left, right))
            AddOrMerge(LIQ_BUY_SIDE, LIQ_KIND_SWING, rates[i].high, rates[i].time);
         if(IFVG_IsSwingLow(rates, i, left, right))
            AddOrMerge(LIQ_SELL_SIDE, LIQ_KIND_SWING, rates[i].low, rates[i].time);
      }

      if(n > 50)
      {
         double old_high = rates[n - 1].high;
         double old_low = rates[n - 1].low;
         datetime th = rates[n - 1].time;
         datetime tl = rates[n - 1].time;
         const int from = MathMin(n - 1, 80);
         for(int i = from; i < n; i++)
         {
            if(rates[i].high >= old_high)
            {
               old_high = rates[i].high;
               th = rates[i].time;
            }
            if(rates[i].low <= old_low)
            {
               old_low = rates[i].low;
               tl = rates[i].time;
            }
         }
         AddOrMerge(LIQ_BUY_SIDE, LIQ_KIND_OLD_EXTREME, old_high, th);
         AddOrMerge(LIQ_SELL_SIDE, LIQ_KIND_OLD_EXTREME, old_low, tl);
      }
   }

   bool BestResting(const ENUM_LIQ_SIDE side, SLiquidity &out) const
   {
      int idx = -1;
      datetime newest = 0;
      for(int i = 0; i < m_count; i++)
      {
         if(!m_pool[i].active || m_pool[i].swept)
            continue;
         if(m_pool[i].side != side)
            continue;
         if(m_pool[i].created >= newest)
         {
            newest = m_pool[i].created;
            idx = i;
         }
      }
      if(idx < 0)
         return false;
      out = m_pool[idx];
      return true;
   }

   int FindIndexById(const ulong id) const
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_pool[i].id == id)
            return i;
      }
      return -1;
   }

   bool MarkSwept(const ulong id, const datetime when, const double extreme)
   {
      const int i = FindIndexById(id);
      if(i < 0)
         return false;
      m_pool[i].swept = true;
      m_pool[i].swept_at = when;
      m_pool[i].swept_extreme = extreme;
      return true;
   }

   int Count() const { return m_count; }

   SLiquidity At(const int i) const { return m_pool[i]; }
};

#endif

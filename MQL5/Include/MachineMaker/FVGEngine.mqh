#ifndef MM_FVGENGINE_MQH
#define MM_FVGENGINE_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "FibonacciEngine.mqh"
#include "Utils.mqh"
#include "BacktestStats.mqh"

class CMMFVGEngine
{
private:
   CMMConfig         *m_cfg;
   CMMLogger         *m_log;
   CMMBacktestStats  *m_stats;
   SMMSymbolSpec      m_spec;
   SMMFVG             m_fvgs[MM_MAX_FVG];
   int                m_count;
   ulong              m_next_id;

   int PriceDigits() const { return (m_spec.digits > 0 ? m_spec.digits : 5); }

   int AgeBars(const datetime ts, const datetime now) const
   {
      const int step = MM_PeriodSeconds(MM_TF_M15);
      if(step <= 0 || now <= ts)
         return 0;
      return (int)((now - ts) / step);
   }

   void LogDetected(const SMMFVG &f, const double fib50)
   {
      if(m_log == NULL)
         return;
      const int d = PriceDigits();
      m_log.Fvg("[DETECTED]");
      m_log.Fvg("ID=" + IntegerToString((long)f.id));
      m_log.Fvg("Direction=" + MM_DirToString(f.direction));
      m_log.Fvg("High=" + DoubleToString(f.high, d));
      m_log.Fvg("Low=" + DoubleToString(f.low, d));
      m_log.Fvg("Mid=" + DoubleToString(f.mid, d));
      m_log.Fvg("Fib50=" + DoubleToString(fib50, d));
      m_log.Fvg("CorrectSide=" + (f.in_discount_or_premium ? "YES" : "NO"));
      m_log.Fvg("Timestamp=" + TimeToString(f.timestamp, TIME_DATE | TIME_SECONDS));
      if(f.in_discount_or_premium)
         return;
      m_log.Fvg("[WRONG_SIDE]");
      m_log.Fvg("ID=" + IntegerToString((long)f.id));
      m_log.Fvg("Direction=" + MM_DirToString(f.direction));
      m_log.Fvg("High=" + DoubleToString(f.high, d));
      m_log.Fvg("Low=" + DoubleToString(f.low, d));
      m_log.Fvg("Fib50=" + DoubleToString(fib50, d));
   }

   void AccountNewFvg(const SMMFVG &f, const double fib50)
   {
      if(m_stats != NULL)
      {
         m_stats.OnFvgDetected();
         if(f.in_discount_or_premium)
            m_stats.OnFvgCorrectSide();
      }
      LogDetected(f, fib50);
   }

   void ApplyLife(const int i, const ENUM_MM_FVG_LIFE life, const string reason)
   {
      if(i < 0 || i >= m_count)
         return;
      const ENUM_MM_FVG_LIFE old = m_fvgs[i].life;
      m_fvgs[i].life = life;
      if(old != MM_FVG_VALID)
         return;
      if(life == MM_FVG_INVALIDATED)
      {
         if(m_stats != NULL)
            m_stats.OnFvgInvalidated();
         if(m_log != NULL)
         {
            m_log.Fvg("[INVALIDATED]");
            m_log.Fvg("ID=" + IntegerToString((long)m_fvgs[i].id));
            m_log.Fvg("Direction=" + MM_DirToString(m_fvgs[i].direction));
            m_log.Fvg("Reason=" + reason);
         }
      }
      else if(life == MM_FVG_EXPIRED)
      {
         if(m_stats != NULL)
            m_stats.OnFvgExpired();
         if(m_log != NULL)
         {
            m_log.Fvg("[EXPIRED]");
            m_log.Fvg("ID=" + IntegerToString((long)m_fvgs[i].id));
            m_log.Fvg("Direction=" + MM_DirToString(m_fvgs[i].direction));
            m_log.Fvg("AgeBars=" + IntegerToString(AgeBars(m_fvgs[i].timestamp, TimeCurrent())));
         }
      }
   }

   bool Exists(const datetime t, const ENUM_MM_DIR dir) const
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_fvgs[i].timestamp == t && m_fvgs[i].direction == dir)
            return true;
      }
      return false;
   }

   void Push(const SMMFVG &f)
   {
      if(m_count >= MM_MAX_FVG)
      {
         for(int i = 0; i < m_count - 1; i++)
            m_fvgs[i] = m_fvgs[i + 1];
         m_count--;
      }
      m_fvgs[m_count++] = f;
   }

public:
   CMMFVGEngine()
   {
      m_count = 0;
      m_next_id = 1;
      m_cfg = NULL;
      m_log = NULL;
      m_stats = NULL;
   }

   void Init(CMMConfig *cfg, CMMLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
      m_count = 0;
   }

   void SetStats(CMMBacktestStats *stats) { m_stats = stats; }
   void SetSpec(const SMMSymbolSpec &spec) { m_spec = spec; }
   int Count() const { return m_count; }
   SMMFVG At(const int i) const { return m_fvgs[i]; }

   static bool ThreeCandleBullish(const MqlRates &c1, const MqlRates &c3, const double min_gap,
                                  double &hi, double &lo)
   {
      if(c3.low <= c1.high)
         return false;
      hi = c3.low;
      lo = c1.high;
      return (hi - lo >= min_gap);
   }

   static bool ThreeCandleBearish(const MqlRates &c1, const MqlRates &c3, const double min_gap,
                                  double &hi, double &lo)
   {
      if(c3.high >= c1.low)
         return false;
      hi = c1.low;
      lo = c3.high;
      return (hi - lo >= min_gap);
   }

   static bool CompletelyBroken(const ENUM_MM_DIR dir, const double fvg_high, const double fvg_low, const double close)
   {
      if(dir == MM_DIR_BUY)
         return (close < fvg_low);
      if(dir == MM_DIR_SELL)
         return (close > fvg_high);
      return false;
   }

   void Scan(const string symbol, const SMMFib &fib, const ENUM_MM_DIR dir)
   {
      MqlRates rates[];
      const int need = MathMax(60, m_cfg.in.fvg_max_age_bars + 10);
      if(!MM_CopyRatesSafe(symbol, MM_TF_M15, need, rates))
         return;
      const double min_gap = MM_PointsToPrice(m_spec, (double)m_cfg.in.fvg_min_points);
      const int n = ArraySize(rates);
      const datetime now = TimeCurrent();
      const int max_age = m_cfg.in.fvg_max_age_bars * MM_PeriodSeconds(MM_TF_M15);

      for(int i = 0; i < m_count; i++)
      {
         if(m_fvgs[i].life != MM_FVG_VALID)
            continue;
         if(max_age > 0 && now - m_fvgs[i].timestamp > max_age)
            ApplyLife(i, MM_FVG_EXPIRED, "max age");
      }

      // Closed candles only: start at index 1 (current unfinished bar skipped).
      for(int i = 2; i < n - 1; i++)
      {
         const MqlRates c1 = rates[i + 1];
         const MqlRates c3 = rates[i - 1];
         double hi = 0.0, lo = 0.0;
         if(dir == MM_DIR_BUY || dir == MM_DIR_NONE)
         {
            if(ThreeCandleBullish(c1, c3, min_gap, hi, lo) && !Exists(rates[i].time, MM_DIR_BUY))
            {
               SMMFVG f;
               MM_ResetFVG(f);
               f.id = m_next_id++;
               f.direction = MM_DIR_BUY;
               f.life = MM_FVG_VALID;
               f.high = hi;
               f.low = lo;
               f.mid = 0.5 * (hi + lo);
               f.timestamp = rates[i].time;
               f.in_discount_or_premium = CMMFibonacciEngine::FvgOnCorrectSide(MM_DIR_BUY, fib, hi, lo);
               Push(f);
               AccountNewFvg(f, fib.fib_50);
            }
         }
         if(dir == MM_DIR_SELL || dir == MM_DIR_NONE)
         {
            if(ThreeCandleBearish(c1, c3, min_gap, hi, lo) && !Exists(rates[i].time, MM_DIR_SELL))
            {
               SMMFVG f;
               MM_ResetFVG(f);
               f.id = m_next_id++;
               f.direction = MM_DIR_SELL;
               f.life = MM_FVG_VALID;
               f.high = hi;
               f.low = lo;
               f.mid = 0.5 * (hi + lo);
               f.timestamp = rates[i].time;
               f.in_discount_or_premium = CMMFibonacciEngine::FvgOnCorrectSide(MM_DIR_SELL, fib, hi, lo);
               Push(f);
               AccountNewFvg(f, fib.fib_50);
            }
         }
      }

      for(int b = 1; b < n; b++)
      {
         for(int i = 0; i < m_count; i++)
         {
            if(m_fvgs[i].life != MM_FVG_VALID)
               continue;
            if(rates[b].time <= m_fvgs[i].timestamp)
               continue;
            if(CompletelyBroken(m_fvgs[i].direction, m_fvgs[i].high, m_fvgs[i].low, rates[b].close))
               ApplyLife(i, MM_FVG_INVALIDATED, "full break through FVG");
         }
      }
   }

   bool LatestValidInZone(const ENUM_MM_DIR dir, SMMFVG &out) const
   {
      datetime newest = 0;
      int idx = -1;
      for(int i = 0; i < m_count; i++)
      {
         if(m_fvgs[i].life != MM_FVG_VALID)
            continue;
         if(m_fvgs[i].direction != dir)
            continue;
         if(!m_fvgs[i].in_discount_or_premium)
            continue;
         if(m_fvgs[i].timestamp >= newest)
         {
            newest = m_fvgs[i].timestamp;
            idx = i;
         }
      }
      if(idx < 0)
         return false;
      out = m_fvgs[idx];
      return true;
   }

   bool GetById(const ulong id, SMMFVG &out) const
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_fvgs[i].id == id)
         {
            out = m_fvgs[i];
            return true;
         }
      }
      return false;
   }

   void MarkLife(const ulong id, const ENUM_MM_FVG_LIFE life, const string reason = "")
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_fvgs[i].id == id)
         {
            ApplyLife(i, life, (reason == "" ? "state-machine" : reason));
            return;
         }
      }
   }
};

#endif

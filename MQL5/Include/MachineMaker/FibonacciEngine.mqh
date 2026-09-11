#ifndef MM_FIBONACCIENGINE_MQH
#define MM_FIBONACCIENGINE_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Logger.mqh"
#include "Utils.mqh"

class CMMFibonacciEngine
{
public:
   // Most recent confirmed H4 swing high / swing low in the structure lookback.
   // Same fractal test as DirectionEngine (MM_IsSwingHigh / MM_IsSwingLow).
   // Series array: index 0 is the forming bar; it may sit on the right side of a just-confirmed swing.
   static bool LastConfirmedSwingHighLowFromRates(const MqlRates &rates[],
                                                  const int lookback,
                                                  const int left,
                                                  const int right,
                                                  double &last_high,
                                                  double &last_low)
   {
      last_high = 0.0;
      last_low = 0.0;
      if(lookback < 1 || left < 1 || right < 1)
         return false;
      const int n = ArraySize(rates);
      const int end = MathMin(n - left - 1, lookback);
      bool have_high = false;
      bool have_low = false;
      for(int i = right; i <= end; i++)
      {
         if(!have_high && MM_IsSwingHigh(rates, i, left, right))
         {
            last_high = rates[i].high;
            have_high = true;
         }
         if(!have_low && MM_IsSwingLow(rates, i, left, right))
         {
            last_low = rates[i].low;
            have_low = true;
         }
         if(have_high && have_low)
            break;
      }
      return (have_high && have_low && last_high > last_low);
   }

   static bool LastConfirmedSwingHighLow(const string symbol, const ENUM_TIMEFRAMES tf,
                                         const int lookback, const int left, const int right,
                                         double &last_high, double &last_low)
   {
      last_high = 0.0;
      last_low = 0.0;
      if(lookback < 1 || left < 1 || right < 1)
         return false;
      MqlRates rates[];
      const int need = lookback + left + right + 5;
      if(!MM_CopyRatesSafe(symbol, tf, need, rates))
         return false;
      return LastConfirmedSwingHighLowFromRates(rates, lookback, left, right, last_high, last_low);
   }

   static bool Build(const ENUM_MM_DIR dir, const double last_high, const double last_low, SMMFib &fib)
   {
      ZeroMemory(fib);
      fib.direction = dir;
      fib.swing_high = last_high;
      fib.swing_low = last_low;
      if(last_high <= last_low || dir == MM_DIR_NONE)
         return false;
      const double range = last_high - last_low;
      fib.fib_50 = last_low + 0.50 * range;
      // 0.62 is the retracement from the impulse END toward the START
      // so it sits on the same side as discount (bull) / premium (bear).
      if(dir == MM_DIR_BUY)
      {
         fib.fib_00 = last_high;
         fib.fib_100 = last_low;
         fib.fib_62 = last_high - 0.62 * range;
      }
      else
      {
         fib.fib_00 = last_low;
         fib.fib_100 = last_high;
         fib.fib_62 = last_low + 0.62 * range;
      }
      fib.valid = true;
      return true;
   }

   static bool BuildFromLastConfirmedSwings(const string symbol, const ENUM_MM_DIR dir,
                                            const int lookback, const int left, const int right,
                                            SMMFib &fib)
   {
      double last_high = 0.0;
      double last_low = 0.0;
      if(!LastConfirmedSwingHighLow(symbol, MM_TF_H4, lookback, left, right, last_high, last_low))
      {
         ZeroMemory(fib);
         fib.direction = dir;
         return false;
      }
      return Build(dir, last_high, last_low, fib);
   }

   static void LogOnce(CMMLogger *log, const SMMFib &fib, string &fp)
   {
      if(!fib.valid || log == NULL)
         return;
      const string now = MM_FIB_METHOD + "|" +
                          DoubleToString(fib.swing_high, 5) + "|" + DoubleToString(fib.swing_low, 5) + "|" +
                          DoubleToString(fib.fib_50, 5) + "|" + DoubleToString(fib.fib_62, 5);
      if(now == fp)
         return;
      fp = now;
      log.Fib("Method=" + MM_FIB_METHOD);
      log.Fib("LastHigh=" + DoubleToString(fib.swing_high, 5));
      log.Fib("LastLow=" + DoubleToString(fib.swing_low, 5));
      log.Fib("50%=" + DoubleToString(fib.fib_50, 5));
      log.Fib("62%=" + DoubleToString(fib.fib_62, 5));
      log.Fib("Direction=" + MM_DirToString(fib.direction));
   }

   static bool FvgOnCorrectSide(const ENUM_MM_DIR dir, const SMMFib &fib, const double fvg_high, const double fvg_low)
   {
      if(!fib.valid)
         return false;
      if(dir == MM_DIR_BUY)
         return (fvg_high < fib.fib_50);
      if(dir == MM_DIR_SELL)
         return (fvg_low > fib.fib_50);
      return false;
   }
};

#endif

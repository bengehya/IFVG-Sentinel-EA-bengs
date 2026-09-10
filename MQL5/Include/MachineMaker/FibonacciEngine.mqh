#ifndef MM_FIBONACCIENGINE_MQH
#define MM_FIBONACCIENGINE_MQH

#include "Types.mqh"
#include "Logger.mqh"

class CMMFibonacciEngine
{
public:
   static bool Build(const ENUM_MM_DIR dir, const double swing_high, const double swing_low, SMMFib &fib)
   {
      ZeroMemory(fib);
      fib.direction = dir;
      fib.swing_high = swing_high;
      fib.swing_low = swing_low;
      if(swing_high <= swing_low || dir == MM_DIR_NONE)
         return false;
      const double range = swing_high - swing_low;
      fib.fib_50 = swing_low + 0.50 * range;
      // 0.62 is the retracement from the impulse END toward the START
      // so it sits on the same side as discount (bull) / premium (bear).
      if(dir == MM_DIR_BUY)
      {
         fib.fib_00 = swing_high;
         fib.fib_100 = swing_low;
         fib.fib_62 = swing_high - 0.62 * range;
      }
      else
      {
         fib.fib_00 = swing_low;
         fib.fib_100 = swing_high;
         fib.fib_62 = swing_low + 0.62 * range;
      }
      fib.valid = true;
      return true;
   }

   static void LogOnce(CMMLogger *log, const SMMFib &fib, string &fp)
   {
      if(!fib.valid || log == NULL)
         return;
      const string now = DoubleToString(fib.swing_high, 5) + "|" + DoubleToString(fib.swing_low, 5) + "|" +
                         DoubleToString(fib.fib_50, 5) + "|" + DoubleToString(fib.fib_62, 5);
      if(now == fp)
         return;
      fp = now;
      log.Fib("SwingHigh=" + DoubleToString(fib.swing_high, 5));
      log.Fib("SwingLow=" + DoubleToString(fib.swing_low, 5));
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

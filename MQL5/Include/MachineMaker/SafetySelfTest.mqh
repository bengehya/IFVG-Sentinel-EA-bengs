#ifndef MM_SAFETYSELFTEST_MQH
#define MM_SAFETYSELFTEST_MQH

#include "Safety.mqh"
#include "Logger.mqh"
#include "FibonacciEngine.mqh"
#include "EntryModels.mqh"

class CMMSafetySelfTest
{
public:
   static int Run(CMMLogger &log)
   {
      int failed = 0;
      int passed = 0;
      if(MathAbs(CMMSafety::ClampLotHardCap(0.05) - 0.01) > 1e-12)
      { log.Error("SELFTEST lot cap"); failed++; }
      else passed++;

      if(CMMSafety::CanOpenNewPosition(2, 2))
      { log.Error("SELFTEST max positions"); failed++; }
      else passed++;

      const datetime start = D'2024.01.01 00:00';
      const datetime end = CMMSafety::CooldownEndFromStart(start, 8);
      if(end - start != 8 * 3600 || !CMMSafety::IsCooldownActive(end - 1, end))
      { log.Error("SELFTEST cooldown"); failed++; }
      else passed++;

      if(!CMMSafety::CapitalTargetReached(50.0, 5.0, 250.0, 250.0) ||
         CMMSafety::CapitalTargetReached(50.0, 5.0, 249.0, 249.0))
      { log.Error("SELFTEST 5x capital"); failed++; }
      else passed++;

      SMMFib fib;
      CMMFibonacciEngine::Build(MM_DIR_BUY, 2000.0, 1000.0, fib);
      if(MathAbs(fib.fib_50 - 1500.0) > 1e-9 || MathAbs(fib.fib_62 - 1380.0) > 1e-9)
      { log.Error("SELFTEST fib bull"); failed++; }
      else passed++;

      double rr = 0.0;
      if(!CMMSafety::RewardMeetsTarget(100, 90, 140, 4.0, rr) || MathAbs(rr - 4.0) > 1e-9)
      { log.Error("SELFTEST RR 1:4"); failed++; }
      else passed++;
      if(CMMSafety::RewardMeetsTarget(100, 90, 130, 4.0, rr))
      { log.Error("SELFTEST RR 1:3 rejected"); failed++; }
      else passed++;

      log.Info("Safety self-test: passed=" + IntegerToString(passed) + " failed=" + IntegerToString(failed));
      return failed;
   }
};

#endif

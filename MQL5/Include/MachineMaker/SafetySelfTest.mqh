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
      if(MathAbs(CMMSafety::AllowedRiskMoney(50.0, 2.0) - 1.0) > 1e-12 ||
         MathAbs(CMMSafety::AllowedRiskMoney(200.0, 2.0) - 4.0) > 1e-12 ||
         MathAbs(CMMSafety::AllowedRiskMoney(1000.0, 2.0) - 20.0) > 1e-12 ||
         MathAbs(CMMSafety::AllowedRiskMoney(5000.0, 2.0) - 100.0) > 1e-12 ||
         MathAbs(CMMSafety::AllowedRiskMoney(980.0, 2.0) - 19.60) > 1e-12)
      { log.Error("SELFTEST risk percent"); failed++; }
      else passed++;

      if(CMMSafety::CanOpenNewPosition(2, 2))
      { log.Error("SELFTEST max positions"); failed++; }
      else passed++;

      const datetime start = D'2024.01.01 00:00';
      const datetime end = CMMSafety::CooldownEndFromStart(start, 8);
      if(end - start != 8 * 3600 || !CMMSafety::IsCooldownActive(end - 1, end))
      { log.Error("SELFTEST cooldown"); failed++; }
      else passed++;

      SMMSymbolSpec spec;
      MM_ResetSpec(spec);
      spec.valid = true;
      spec.tick_size = 0.01;
      spec.tick_value = 1.0;
      spec.volume_min = 0.01;
      spec.volume_step = 0.01;
      spec.volume_max = 5.0;
      double theo = 0.0, actual = 0.0;
      string rej = "";
      const double lot_big = CMMSafety::LotFromAllowedRisk(spec, 5.0, 100.0, 0.0, theo, actual, rej);
      if(lot_big <= 0.01 + 1e-12 || lot_big > spec.volume_max + 1e-12 || rej != "")
      { log.Error("SELFTEST lot may exceed 0.01"); failed++; }
      else passed++;

      const double lot_small_sl = CMMSafety::LotFromAllowedRisk(spec, 5.0, 20.0, 0.0, theo, actual, rej);
      const double lot_large_sl = CMMSafety::LotFromAllowedRisk(spec, 20.0, 20.0, 0.0, theo, actual, rej);
      if(MathAbs(lot_small_sl - 0.04) > 1e-12 || MathAbs(lot_large_sl - 0.01) > 1e-12)
      { log.Error("SELFTEST lot scales with SL distance"); failed++; }
      else passed++;

      const double lot_min = CMMSafety::LotFromAllowedRisk(spec, 18.0, 10.0, 0.0, theo, actual, rej);
      if(lot_min > 0.0 || StringFind(rej, "minimum lot exceeds") < 0)
      { log.Error("SELFTEST min lot exceeds risk"); failed++; }
      else passed++;

      const double lot_step = CMMSafety::LotFromAllowedRisk(spec, 10.0, 37.0, 0.0, theo, actual, rej);
      if(MathAbs(lot_step - 0.03) > 1e-12 || rej != "")
      { log.Error("SELFTEST volume step"); failed++; }
      else passed++;

      spec.volume_max = 0.10;
      const double lot_cap = CMMSafety::LotFromAllowedRisk(spec, 1.0, 50.0, 0.0, theo, actual, rej);
      if(MathAbs(lot_cap - 0.10) > 1e-12 || rej != "")
      { log.Error("SELFTEST volume max"); failed++; }
      else passed++;
      spec.volume_max = 5.0;

      SMMFib fib;
      CMMFibonacciEngine::Build(MM_DIR_BUY, 2000.0, 1000.0, fib);
      if(MathAbs(fib.fib_50 - 1500.0) > 1e-9 || MathAbs(fib.fib_62 - 1380.0) > 1e-9)
      { log.Error("SELFTEST fib bull"); failed++; }
      else passed++;

      MqlRates bars[];
      ArrayResize(bars, 4);
      ArraySetAsSeries(bars, true);
      bars[0].high = 1.0;  bars[0].low = 0.5;
      bars[1].high = 12.0; bars[1].low = 8.0;
      bars[2].high = 11.0; bars[2].low = 7.0;
      bars[3].high = 10.0; bars[3].low = 9.0;
      double last_high = 0.0, last_low = 0.0;
      if(!CMMFibonacciEngine::LastHighLastLowFromRates(bars, last_high, last_low) ||
         MathAbs(last_high - 12.0) > 1e-12 || MathAbs(last_low - 7.0) > 1e-12)
      { log.Error("SELFTEST last high/low"); failed++; }
      else passed++;

      bars[1].high = 11.0; bars[1].low = 5.0;
      bars[2].high = 20.0; bars[2].low = 8.0;
      double inv_high = 0.0, inv_low = 0.0;
      if(!CMMFibonacciEngine::LastHighLastLowFromRates(bars, inv_high, inv_low) ||
         MathAbs(inv_high - 20.0) > 1e-12 || MathAbs(inv_low - 5.0) > 1e-12)
      { log.Error("SELFTEST last high/low inverted time"); failed++; }
      else passed++;

      MqlRates empty[];
      if(CMMFibonacciEngine::LastHighLastLowFromRates(empty, last_high, last_low))
      { log.Error("SELFTEST last high/low empty"); failed++; }
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

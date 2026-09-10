#ifndef MM_RISKENGINE_MQH
#define MM_RISKENGINE_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Safety.mqh"
#include "SymbolProvider.mqh"

class CMMRiskEngine
{
private:
   CMMConfig *m_cfg;
   CMMLogger *m_log;

   ENUM_MM_SL_REASON ChooseSL(const ENUM_MM_DIR dir, const double entry, const double raw_sl, const double fib62,
                              const SMMSymbolSpec &spec, const double allowed, double &final_sl)
   {
      final_sl = raw_sl;
      double prot = fib62;
      const double buffer = MM_PointsToPrice(spec, (double)m_cfg.in.sl_buffer_points);
      if(dir == MM_DIR_BUY)
         prot = fib62 - buffer;
      else
         prot = fib62 + buffer;
      prot = MM_NormalizePrice(spec, prot);

      const double raw_dist = MathAbs(entry - raw_sl);
      const double prot_dist = MathAbs(entry - prot);
      const bool prot_side_ok = ((dir == MM_DIR_BUY && prot < entry) || (dir == MM_DIR_SELL && prot > entry));
      if(!prot_side_ok)
         return MM_SL_FVG_NORMAL;

      const double minlot_raw = CMMSafety::RiskMoneyFromDistance(spec, raw_dist, spec.volume_min);
      if(raw_dist + 1e-12 < prot_dist)
      {
         final_sl = prot;
         return MM_SL_FIB62_SMALL;
      }
      if(minlot_raw > allowed + 1e-8 && prot_dist + 1e-12 < raw_dist)
      {
         final_sl = prot;
         return MM_SL_FIB62_LARGE;
      }
      return MM_SL_FVG_NORMAL;
   }

public:
   void Init(CMMConfig *cfg, CMMLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
   }

   bool BuildPlan(const SMMSymbolSpec &spec, const CMMSymbolProvider &sym,
                  const ENUM_MM_DIR dir, const SMMFVG &fvg, const SMMFib &fib,
                  const double entry_raw, const ENUM_MM_ENTRY_MODEL model, SMMEntryPlan &plan)
   {
      MM_ResetPlan(plan);
      plan.direction = dir;
      plan.model = model;
      plan.fvg_id = fvg.id;
      plan.entry = MM_NormalizePrice(spec, entry_raw);

      const double buffer = MM_PointsToPrice(spec, (double)m_cfg.in.sl_buffer_points);
      if(dir == MM_DIR_BUY)
         plan.raw_sl = MM_NormalizePrice(spec, fvg.low - buffer);
      else
         plan.raw_sl = MM_NormalizePrice(spec, fvg.high + buffer);

      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      const string ccy = AccountInfoString(ACCOUNT_CURRENCY);
      const double allowed = m_cfg.AllowedRiskMoney(equity);

      double final_sl = plan.raw_sl;
      plan.sl_reason = ChooseSL(dir, plan.entry, plan.raw_sl, fib.fib_62, spec, allowed, final_sl);
      plan.sl = MM_NormalizePrice(spec, final_sl);

      const double stop_level = sym.MinStopDistance();
      plan.risk_distance = MathAbs(plan.entry - plan.sl);
      if(plan.risk_distance < stop_level)
      {
         plan.reject_reason = "SL inside broker stops level";
         return false;
      }

      if(dir == MM_DIR_BUY)
         plan.tp = plan.entry + plan.risk_distance * m_cfg.in.target_rr;
      else
         plan.tp = plan.entry - plan.risk_distance * m_cfg.in.target_rr;
      plan.tp = MM_NormalizePrice(spec, plan.tp);

      if(!CMMSafety::StopsConsistent(dir, plan.entry, plan.sl, plan.tp))
      {
         plan.reject_reason = "stops inconsistent with direction";
         return false;
      }
      if(!CMMSafety::RewardMeetsTarget(plan.entry, plan.sl, plan.tp, m_cfg.in.target_rr, plan.rr_actual))
      {
         plan.reject_reason = "RR insufficient";
         return false;
      }
      if(plan.rr_actual + 1e-9 < MM_HARD_TARGET_RR)
      {
         plan.reject_reason = "RR insufficient";
         return false;
      }

      string lot_reject = "";
      plan.lot = CMMSafety::LotFromAllowedRisk(spec, plan.risk_distance, allowed, m_cfg.in.max_lot,
                                               plan.theoretical_lot, plan.expected_risk, lot_reject);
      if(m_log != NULL)
      {
         m_log.Sl("FVG size=" + DoubleToString(fvg.high - fvg.low, spec.digits));
         m_log.Sl("SwingHigh=" + DoubleToString(fib.swing_high, spec.digits));
         m_log.Sl("SwingLow=" + DoubleToString(fib.swing_low, spec.digits));
         m_log.Sl("0.50=" + DoubleToString(fib.fib_50, spec.digits));
         m_log.Sl("0.62=" + DoubleToString(fib.fib_62, spec.digits));
         m_log.Sl("raw SL=" + DoubleToString(plan.raw_sl, spec.digits));
         m_log.Sl("final SL=" + DoubleToString(plan.sl, spec.digits));
         m_log.Sl("reason=" + MM_SlReasonToString(plan.sl_reason));
         m_log.Risk("Equity=" + DoubleToString(equity, 2));
         m_log.Risk("RiskPercent=" + DoubleToString(m_cfg.in.risk_percent, 2));
         m_log.Risk("AllowedRisk=" + DoubleToString(allowed, 2));
         m_log.Risk("AccountCurrency=" + ccy);
         m_log.Risk("Entry=" + DoubleToString(plan.entry, spec.digits));
         m_log.Risk("SL=" + DoubleToString(plan.sl, spec.digits));
         m_log.Risk("RiskDistance=" + DoubleToString(plan.risk_distance, spec.digits));
         m_log.Risk("TheoreticalLot=" + DoubleToString(plan.theoretical_lot, 5));
         m_log.Risk("FinalLot=" + DoubleToString(plan.lot, 5));
         m_log.Risk("ExpectedRisk=" + DoubleToString(plan.expected_risk, 2));
         m_log.Risk("VolumeMin=" + DoubleToString(spec.volume_min, 5));
         m_log.Risk("VolumeMax=" + DoubleToString(spec.volume_max, 5));
         m_log.Risk("VolumeStep=" + DoubleToString(spec.volume_step, 5));
      }
      if(plan.lot <= 0.0)
      {
         plan.reject_reason = (lot_reject == "" ? "invalid volume" : lot_reject);
         return false;
      }
      plan.valid = true;
      return true;
   }
};

#endif

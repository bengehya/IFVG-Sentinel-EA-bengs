#ifndef IFVG_RISKMANAGER_MQH
#define IFVG_RISKMANAGER_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Safety.mqh"
#include "SymbolProvider.mqh"

class CRiskManager
{
private:
   CIFVGConfig     *m_cfg;
   CIFVGLogger     *m_log;

public:
   void Init(CIFVGConfig *cfg, CIFVGLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
   }

   bool BuildPlan(const SSymbolSpec &spec,
                  const CSymbolProvider &sym,
                  const SSetup &setup,
                  const double entry,
                  SEntryPlan &plan)
   {
      IFVG_ResetPlan(plan);
      plan.direction = setup.direction;
      plan.setup_id = setup.setup_id;
      plan.entry = IFVG_NormalizePrice(spec, entry);

      const double buffer = IFVG_PointsToPrice(spec, (double)m_cfg.in.sl_buffer_points);
      double sl = 0.0;
      if(setup.direction == IFVG_DIR_BUY)
         sl = setup.sweep.extreme - buffer;
      else if(setup.direction == IFVG_DIR_SELL)
         sl = setup.sweep.extreme + buffer;
      else
      {
         plan.reject_reason = "no direction for SL";
         return false;
      }

      sl = IFVG_NormalizePrice(spec, sl);
      const double min_sl = IFVG_PointsToPrice(spec, (double)m_cfg.in.min_sl_points);
      const double stop_level = sym.MinStopDistance();
      double risk = MathAbs(plan.entry - sl);
      if(risk < min_sl)
      {
         if(setup.direction == IFVG_DIR_BUY)
            sl = plan.entry - min_sl;
         else
            sl = plan.entry + min_sl;
         sl = IFVG_NormalizePrice(spec, sl);
         risk = MathAbs(plan.entry - sl);
      }
      if(risk < stop_level)
      {
         plan.reject_reason = "SL inside broker stops level";
         return false;
      }

      double tp = 0.0;
      if(setup.direction == IFVG_DIR_BUY)
         tp = plan.entry + risk * m_cfg.in.target_rr;
      else
         tp = plan.entry - risk * m_cfg.in.target_rr;
      tp = IFVG_NormalizePrice(spec, tp);

      if(!CIFVGSafety::StopsConsistent(setup.direction, plan.entry, sl, tp))
      {
         plan.reject_reason = "stops inconsistent with direction";
         return false;
      }

      double actual_rr = 0.0;
      if(!CIFVGSafety::RewardMeetsTarget(plan.entry, sl, tp, m_cfg.in.target_rr, actual_rr))
      {
         plan.reject_reason = "RR insufficient";
         if(m_log != NULL)
            m_log.NoTrade("RR insufficient");
         return false;
      }

      string lot_reject = "";
      const double lot = CIFVGSafety::ApplyVolumeConstraints(spec, IFVG_HARD_MAX_LOT, m_cfg.in.max_lot, lot_reject);
      if(lot <= 0.0)
      {
         plan.reject_reason = (lot_reject == "" ? "invalid volume" : lot_reject);
         return false;
      }

      plan.sl = sl;
      plan.tp = tp;
      plan.risk_distance = risk;
      plan.rr_actual = actual_rr;
      plan.lot = lot;
      plan.valid = true;
      if(m_log != NULL)
      {
         m_log.Decision("RR", "1:" + DoubleToString(actual_rr, 2));
         m_log.Decision("Lot", DoubleToString(lot, 2));
      }
      return true;
   }
};

#endif

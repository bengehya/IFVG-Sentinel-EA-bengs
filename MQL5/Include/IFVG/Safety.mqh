#ifndef IFVG_SAFETY_MQH
#define IFVG_SAFETY_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Hard safety policy. These functions are the last line of defense.|
//| Inputs may request more risk; this module always wins.           |
//+------------------------------------------------------------------+
class CIFVGSafety
{
public:
   static double ClampLotHardCap(const double requested_lot)
   {
      if(requested_lot <= 0.0)
         return 0.0;
      return MathMin(requested_lot, IFVG_HARD_MAX_LOT);
   }

   static double ClampLotInput(const double input_max_lot)
   {
      if(input_max_lot <= 0.0)
         return IFVG_HARD_MAX_LOT;
      return MathMin(input_max_lot, IFVG_HARD_MAX_LOT);
   }

   static int ClampMaxPositions(const int input_max_positions)
   {
      int v = input_max_positions;
      if(v <= 0)
         v = IFVG_HARD_MAX_POSITIONS;
      if(v > IFVG_HARD_MAX_POSITIONS)
         v = IFVG_HARD_MAX_POSITIONS;
      return v;
   }

   static int ClampConsecSL(const int input_limit)
   {
      if(input_limit < IFVG_HARD_MIN_CONSEC_SL)
         return IFVG_HARD_MIN_CONSEC_SL;
      return input_limit;
   }

   static int ClampCooldownHours(const int input_hours)
   {
      if(input_hours < IFVG_HARD_MIN_COOLDOWN_H)
         return IFVG_HARD_MIN_COOLDOWN_H;
      return input_hours;
   }

   static bool CanOpenNewPosition(const int open_positions, const int max_positions)
   {
      const int cap = ClampMaxPositions(max_positions);
      if(open_positions < 0)
         return false;
      return (open_positions < cap);
   }

   static bool IsCooldownActive(const datetime now, const datetime cooldown_end)
   {
      if(cooldown_end <= 0)
         return false;
      return (now < cooldown_end);
   }

   static datetime CooldownEndFromStart(const datetime start, const int hours)
   {
      const int h = ClampCooldownHours(hours);
      return start + (datetime)(h * IFVG_SECONDS_PER_HOUR);
   }

   static int OnPositionClosedSL(const int consecutive_losses)
   {
      return consecutive_losses + 1;
   }

   static int OnPositionClosedWin(const int)
   {
      return 0;
   }

   static bool ShouldEnterCooldown(const int consecutive_losses, const int limit)
   {
      return (consecutive_losses >= ClampConsecSL(limit));
   }

   static bool VolumeRespectsHardCap(const double lot)
   {
      if(lot <= 0.0)
         return false;
      return (lot <= IFVG_HARD_MAX_LOT + 1e-12);
   }

   static bool BrokerAllowsHardCap(const SSymbolSpec &spec)
   {
      if(!spec.valid)
         return false;
      if(spec.volume_min - IFVG_HARD_MAX_LOT > 1e-12)
         return false;
      return true;
   }

   static double ApplyVolumeConstraints(const SSymbolSpec &spec,
                                        const double calculated_lot,
                                        const double input_max_lot,
                                        string &reject)
   {
      reject = "";
      if(!BrokerAllowsHardCap(spec))
      {
         reject = "broker volume_min exceeds hard cap 0.01";
         return 0.0;
      }

      double lot = calculated_lot;
      if(lot <= 0.0)
         lot = spec.volume_min;

      lot = MathMin(lot, ClampLotInput(input_max_lot));
      lot = ClampLotHardCap(lot);
      lot = IFVG_NormalizeVolume(spec, lot);

      if(lot + 1e-12 < spec.volume_min)
      {
         reject = "normalized lot below volume_min";
         return 0.0;
      }
      if(lot - spec.volume_max > 1e-12)
      {
         reject = "lot above volume_max";
         return 0.0;
      }
      if(!VolumeRespectsHardCap(lot))
      {
         reject = "lot exceeds hard cap 0.01";
         return 0.0;
      }
      return lot;
   }

   static bool RewardMeetsTarget(const double entry,
                                 const double sl,
                                 const double tp,
                                 const double target_rr,
                                 double &actual_rr)
   {
      actual_rr = 0.0;
      const double risk = MathAbs(entry - sl);
      const double reward = MathAbs(tp - entry);
      if(risk <= 0.0)
         return false;
      actual_rr = reward / risk;
      return (actual_rr + 1e-9 >= target_rr);
   }

   static bool AllowsOrderOnSymbol(const string trading_symbol, const string order_symbol)
   {
      if(trading_symbol == "" || order_symbol == "")
         return false;
      return (trading_symbol == order_symbol);
   }

   static bool IsExternalCompareSymbol(const string order_symbol,
                                       const string smt_symbol1,
                                       const string smt_symbol2)
   {
      if(order_symbol == "")
         return false;
      if(smt_symbol1 != "" && order_symbol == smt_symbol1)
         return true;
      if(smt_symbol2 != "" && order_symbol == smt_symbol2)
         return true;
      return false;
   }

   static bool StopsConsistent(const ENUM_IFVG_DIR dir,
                               const double entry,
                               const double sl,
                               const double tp)
   {
      if(dir == IFVG_DIR_BUY)
         return (sl < entry && tp > entry);
      if(dir == IFVG_DIR_SELL)
         return (sl > entry && tp < entry);
      return false;
   }

   // Reporting only. Does not change the RR entry gate (RewardMeetsTarget).
   static double RiskMoneyFromDistance(const SSymbolSpec &spec,
                                       const double risk_distance,
                                       const double volume)
   {
      if(spec.tick_size <= 0.0 || spec.tick_value <= 0.0)
         return 0.0;
      if(risk_distance <= 0.0 || volume <= 0.0)
         return 0.0;
      return (risk_distance / spec.tick_size) * spec.tick_value * volume;
   }

   static double RiskMoneyFromStops(const SSymbolSpec &spec,
                                    const double entry,
                                    const double sl,
                                    const double volume)
   {
      return RiskMoneyFromDistance(spec, MathAbs(entry - sl), volume);
   }

   static double RealizedR(const double profit, const double risk_money)
   {
      if(risk_money <= 0.0)
         return 0.0;
      return profit / risk_money;
   }

   static double AllowedRiskMoney(const bool use_percent,
                                    const double risk_money,
                                    const double risk_percent,
                                    const double balance)
   {
      if(use_percent)
      {
         if(balance <= 0.0 || risk_percent <= 0.0)
            return 0.0;
         return balance * risk_percent / 100.0;
      }
      if(risk_money <= 0.0)
         return IFVG_DEFAULT_RISK_MONEY;
      return risk_money;
   }

   static double TheoreticalLotFromRisk(const SSymbolSpec &spec,
                                       const double risk_distance,
                                       const double allowed_risk)
   {
      if(spec.tick_size <= 0.0 || spec.tick_value <= 0.0)
         return 0.0;
      if(risk_distance <= 0.0 || allowed_risk <= 0.0)
         return 0.0;
      const double risk_per_lot = (risk_distance / spec.tick_size) * spec.tick_value;
      if(risk_per_lot <= 0.0)
         return 0.0;
      return allowed_risk / risk_per_lot;
   }

   static double LotFromAllowedRisk(const SSymbolSpec &spec,
                                     const double risk_distance,
                                     const double allowed_risk,
                                     double &theoretical_lot,
                                     double &actual_risk,
                                     string &reject)
   {
      reject = "";
      theoretical_lot = 0.0;
      actual_risk = 0.0;
      if(!BrokerAllowsHardCap(spec))
      {
         reject = "broker volume_min exceeds hard cap 0.01";
         return 0.0;
      }

      theoretical_lot = TheoreticalLotFromRisk(spec, risk_distance, allowed_risk);
      if(theoretical_lot <= 0.0)
      {
         reject = "calculated lot below broker minimum";
         return 0.0;
      }

      const double min_lot_risk = RiskMoneyFromDistance(spec, risk_distance, spec.volume_min);
      double lot = theoretical_lot;
      lot = MathMin(lot, IFVG_HARD_MAX_LOT);

      if(lot + 1e-12 < spec.volume_min)
      {
         if(min_lot_risk > allowed_risk + 1e-8)
         {
            reject = "minimum lot exceeds risk limit";
            actual_risk = min_lot_risk;
            return 0.0;
         }
         lot = spec.volume_min;
      }

      lot = IFVG_NormalizeVolume(spec, lot);
      lot = ClampLotHardCap(lot);

      if(lot + 1e-12 < spec.volume_min)
      {
         if(min_lot_risk > allowed_risk + 1e-8)
         {
            reject = "minimum lot exceeds risk limit";
            actual_risk = min_lot_risk;
            return 0.0;
         }
         reject = "calculated lot below broker minimum";
         return 0.0;
      }

      actual_risk = RiskMoneyFromDistance(spec, risk_distance, lot);
      if(actual_risk > allowed_risk + 1e-8)
      {
         reject = "minimum lot exceeds risk limit";
         return 0.0;
      }
      if(!VolumeRespectsHardCap(lot))
      {
         reject = "lot exceeds hard cap 0.01";
         return 0.0;
      }
      return lot;
   }

   static bool MarginIsSufficient(const string symbol,
                                   const ENUM_ORDER_TYPE order_type,
                                   const double lot,
                                   const double price,
                                   const double free_margin,
                                   double &margin_required,
                                   string &reject)
   {
      reject = "";
      margin_required = 0.0;
      if(lot <= 0.0 || price <= 0.0)
      {
         reject = "insufficient margin";
         return false;
      }
      if(!OrderCalcMargin(order_type, symbol, lot, price, margin_required))
      {
         reject = "insufficient margin";
         return false;
      }
      if(margin_required > free_margin + 1e-8)
      {
         reject = "insufficient margin";
         return false;
      }
      return true;
   }
};

#endif

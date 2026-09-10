#ifndef MM_SAFETY_MQH
#define MM_SAFETY_MQH

#include "Constants.mqh"
#include "Types.mqh"
#include "Utils.mqh"

class CMMSafety
{
public:
   static double EffectiveMaxVolume(const SMMSymbolSpec &spec, const double input_max_lot)
   {
      if(!spec.valid || spec.volume_max <= 0.0)
         return 0.0;
      if(input_max_lot > 0.0)
         return MathMin(input_max_lot, spec.volume_max);
      return spec.volume_max;
   }

   static double ClampToBrokerVolume(const SMMSymbolSpec &spec, const double lot, const double input_max_lot)
   {
      if(lot <= 0.0)
         return 0.0;
      const double cap = EffectiveMaxVolume(spec, input_max_lot);
      if(cap <= 0.0)
         return 0.0;
      return MathMin(lot, cap);
   }

   static int ClampMaxPositions(const int input_max_positions)
   {
      int v = input_max_positions;
      if(v <= 0)
         v = MM_HARD_MAX_POSITIONS;
      if(v > MM_HARD_MAX_POSITIONS)
         v = MM_HARD_MAX_POSITIONS;
      return v;
   }

   static int ClampConsecSL(const int input_limit)
   {
      if(input_limit < MM_HARD_MIN_CONSEC_SL)
         return MM_HARD_MIN_CONSEC_SL;
      return input_limit;
   }

   static int ClampCooldownHours(const int input_hours)
   {
      if(input_hours < MM_HARD_MIN_COOLDOWN_H)
         return MM_HARD_MIN_COOLDOWN_H;
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
      return start + (datetime)(ClampCooldownHours(hours) * MM_SECONDS_PER_HOUR);
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

   static bool VolumeRespectsBroker(const SMMSymbolSpec &spec, const double lot, const double input_max_lot)
   {
      if(lot <= 0.0 || !spec.valid)
         return false;
      if(lot + 1e-12 < spec.volume_min)
         return false;
      const double cap = EffectiveMaxVolume(spec, input_max_lot);
      if(cap <= 0.0)
         return false;
      return (lot <= cap + 1e-12);
   }

   static bool BrokerVolumeUsable(const SMMSymbolSpec &spec)
   {
      if(!spec.valid)
         return false;
      if(spec.volume_min <= 0.0 || spec.volume_max <= 0.0)
         return false;
      if(spec.volume_min - spec.volume_max > 1e-12)
         return false;
      if(spec.tick_size <= 0.0 || spec.tick_value <= 0.0)
         return false;
      return true;
   }

   static bool RewardMeetsTarget(const double entry, const double sl, const double tp,
                                 const double target_rr, double &actual_rr)
   {
      actual_rr = 0.0;
      const double risk = MathAbs(entry - sl);
      const double reward = MathAbs(tp - entry);
      if(risk <= 0.0)
         return false;
      actual_rr = reward / risk;
      return (actual_rr + 1e-9 >= target_rr);
   }

   static bool StopsConsistent(const ENUM_MM_DIR dir, const double entry, const double sl, const double tp)
   {
      if(dir == MM_DIR_BUY)
         return (sl < entry && tp > entry);
      if(dir == MM_DIR_SELL)
         return (sl > entry && tp < entry);
      return false;
   }

   static double RiskMoneyFromDistance(const SMMSymbolSpec &spec, const double risk_distance, const double volume)
   {
      if(spec.tick_size <= 0.0 || spec.tick_value <= 0.0)
         return 0.0;
      if(risk_distance <= 0.0 || volume <= 0.0)
         return 0.0;
      return (risk_distance / spec.tick_size) * spec.tick_value * volume;
   }

   static double RealizedR(const double profit, const double risk_money)
   {
      if(risk_money <= 0.0)
         return 0.0;
      return profit / risk_money;
   }

   static double AllowedRiskMoney(const double equity, const double risk_percent)
   {
      if(equity <= 0.0 || risk_percent <= 0.0)
         return 0.0;
      return equity * risk_percent / 100.0;
   }

   static double TheoreticalLotFromRisk(const SMMSymbolSpec &spec, const double risk_distance, const double allowed_risk)
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

   static double LotFromAllowedRisk(const SMMSymbolSpec &spec,
                                    const double risk_distance,
                                    const double allowed_risk,
                                    const double input_max_lot,
                                    double &theoretical_lot,
                                    double &actual_risk,
                                    string &reject)
   {
      reject = "";
      theoretical_lot = 0.0;
      actual_risk = 0.0;
      if(!BrokerVolumeUsable(spec))
      {
         reject = "broker volume spec unusable";
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
      lot = ClampToBrokerVolume(spec, lot, input_max_lot);
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
      lot = MM_NormalizeVolume(spec, lot);
      lot = ClampToBrokerVolume(spec, lot, input_max_lot);
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
      if(!VolumeRespectsBroker(spec, lot, input_max_lot))
      {
         reject = "lot exceeds broker volume max";
         return 0.0;
      }
      return lot;
   }
};

#endif

#ifndef MM_CONFIG_MQH
#define MM_CONFIG_MQH

#include "Safety.mqh"

struct SMMInputs
{
   string          symbol;
   double          max_lot;
   double          risk_percent;
   double          target_rr;
   int             max_positions;
   int             consec_sl_limit;
   int             cooldown_hours;
   int             sl_buffer_points;
   int             fvg_min_points;
   int             fvg_max_age_bars;
   int             swing_left;
   int             swing_right;
   int             structure_lookback;
   long            magic;
   bool            enable_dashboard;
   bool            enable_logs;
   bool            enable_file_logs;
   bool            debug_mode;
};

class CMMConfig
{
public:
   SMMInputs in;

   void ApplySafetyClamps()
   {
      if(in.max_lot < 0.0)
         in.max_lot = 0.0;
      in.max_positions = CMMSafety::ClampMaxPositions(in.max_positions);
      in.consec_sl_limit = CMMSafety::ClampConsecSL(in.consec_sl_limit);
      in.cooldown_hours = CMMSafety::ClampCooldownHours(in.cooldown_hours);
      if(in.target_rr < MM_HARD_TARGET_RR)
         in.target_rr = MM_HARD_TARGET_RR;
      if(in.risk_percent <= 0.0)
         in.risk_percent = MM_DEFAULT_RISK_PERCENT;
      if(in.magic <= 0)
         in.magic = MM_MAGIC;
      if(in.swing_left < 1)
         in.swing_left = 2;
      if(in.swing_right < 1)
         in.swing_right = 2;
      if(in.structure_lookback < 10)
         in.structure_lookback = 80;
      if(in.fvg_max_age_bars <= 0)
         in.fvg_max_age_bars = 40;
   }

   double AllowedRiskMoney(const double equity) const
   {
      return CMMSafety::AllowedRiskMoney(equity, in.risk_percent);
   }
};

#endif

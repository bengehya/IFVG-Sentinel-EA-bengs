#ifndef IFVG_CONFIG_MQH
#define IFVG_CONFIG_MQH

#include "Safety.mqh"

struct SIFVGInputs
{
   string            symbol;
   ENUM_TIMEFRAMES   htf;
   ENUM_TIMEFRAMES   confirmation_tf;
   ENUM_TIMEFRAMES   entry_tf;

   bool              use_smt_filter;
   ENUM_SMT_MODE     smt_mode;
   string            smt_symbol1;
   string            smt_symbol2;
   ENUM_CORR_TYPE    smt_corr1;
   ENUM_CORR_TYPE    smt_corr2;
   int               smt_lookback;
   int               smt_swing_left;
   int               smt_swing_right;

   double            max_lot;
   double            target_rr;
   int               max_positions;

   int               consec_sl_limit;
   int               cooldown_hours;

   int               max_spread_points;
   int               session_start_hour;
   int               session_start_minute;
   int               session_end_hour;
   int               session_end_minute;
   ENUM_SESSION_TZ   session_timezone;
   int               utc_offset_hours;
   bool              trade_london;
   bool              trade_ny;
   bool              trade_asian;

   int               swing_left;
   int               swing_right;
   int               equal_points;
   int               liq_expire_bars;
   int               min_sweep_points;
   int               min_sweep_closeback_points;
   double            min_sweep_atr_mult;
   int               sweep_max_age_bars;

   int               htf_structure_lookback;
   int               pd_expire_bars;
   double            ob_displacement_atr;
   int               ob_impulse_bars;

   double            cisd_min_body_atr;
   int               cisd_max_bars_after_sweep;

   double            displacement_atr_mult;
   int               displacement_min_bars;

   int               fvg_min_points;
   int               fvg_max_age_bars;
   bool              fvg_require_closed_bars;

   int               ifvg_tolerance_points;
   int               ifvg_max_retests;
   int               ifvg_validity_seconds;
   bool              ifvg_require_close_through;

   int               sl_buffer_points;
   int               min_sl_points;

   bool              use_risk_percent;
   double            risk_money;
   double            risk_percent;

   long              magic;
   bool              enable_dashboard;
   bool              enable_logs;
   bool              enable_file_logs;
   bool              debug_mode;
   bool              allow_buy;
   bool              allow_sell;
   bool              gold_only_mode;
};

class CIFVGConfig
{
public:
   SIFVGInputs in;

   void ApplySafetyClamps()
   {
      in.max_lot = CIFVGSafety::ClampLotInput(in.max_lot);
      in.max_positions = CIFVGSafety::ClampMaxPositions(in.max_positions);
      in.consec_sl_limit = CIFVGSafety::ClampConsecSL(in.consec_sl_limit);
      in.cooldown_hours = CIFVGSafety::ClampCooldownHours(in.cooldown_hours);
      in.htf = IFVG_HTF_TIMEFRAME;
      in.confirmation_tf = IFVG_SETUP_TIMEFRAME;
      in.entry_tf = IFVG_EXECUTION_TIMEFRAME;
      if(in.risk_money <= 0.0)
         in.risk_money = IFVG_DEFAULT_RISK_MONEY;
      if(in.risk_percent <= 0.0)
         in.risk_percent = 5.0;
      if(in.target_rr < 3.0)
         in.target_rr = 3.0;
      if(in.magic <= 0)
         in.magic = IFVG_SENTINEL_MAGIC;
      if(!in.use_smt_filter)
         in.smt_mode = SMT_DISABLED;
      else if(in.smt_mode != SMT_OPTIONAL && in.smt_mode != SMT_DISABLED)
         in.smt_mode = SMT_REQUIRED;
   }

   ENUM_SMT_MODE EffectiveSMTMode() const
   {
      if(in.gold_only_mode)
         return SMT_DISABLED;
      if(!in.use_smt_filter)
         return SMT_DISABLED;
      return in.smt_mode;
   }

   bool IsGoldOnly() const
   {
      return in.gold_only_mode;
   }

   bool SMTIsMandatoryGate() const
   {
      if(in.gold_only_mode)
         return false;
      return (EffectiveSMTMode() == SMT_REQUIRED);
   }

   ENUM_IFVG_RISK_MODE RiskMode() const
   {
      return in.use_risk_percent ? RISK_PERCENT : RISK_FIXED_MONEY;
   }

   double AllowedRiskMoney(const double balance) const
   {
      return CIFVGSafety::AllowedRiskMoney(in.use_risk_percent, in.risk_money, in.risk_percent, balance);
   }
};

#endif

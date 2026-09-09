#ifndef IFVG_TYPES_MQH
#define IFVG_TYPES_MQH

#include "Constants.mqh"

//+------------------------------------------------------------------+
//| Direction / bias                                                  |
//+------------------------------------------------------------------+
enum ENUM_IFVG_DIR
{
   IFVG_DIR_NONE  = 0,
   IFVG_DIR_BUY   = 1,
   IFVG_DIR_SELL  = -1
};

enum ENUM_IFVG_BIAS
{
   IFVG_BIAS_NONE     = 0,
   IFVG_BIAS_BULLISH  = 1,
   IFVG_BIAS_BEARISH  = -1,
   IFVG_BIAS_NEUTRAL  = 2
};

enum ENUM_SMT_MODE
{
   SMT_DISABLED  = 0,
   SMT_OPTIONAL  = 1,
   SMT_REQUIRED  = 2
};

enum ENUM_SMT_STATUS
{
   SMT_STATUS_NONE              = 0,
   SMT_STATUS_CONFIRMED         = 1,
   SMT_STATUS_MISSING           = 2,
   SMT_STATUS_DISABLED          = 3,
   SMT_STATUS_OPTIONAL_BYPASS   = 4,
   SMT_STATUS_SKIPPED_GOLD_ONLY = 5
};

enum ENUM_ZONE_TYPE
{
   ZONE_NONE         = 0,
   ZONE_ORDER_BLOCK  = 1,
   ZONE_FVG          = 2,
   ZONE_BREAKER      = 3
};

enum ENUM_ZONE_STATUS
{
   ZONE_STATUS_NONE        = 0,
   ZONE_STATUS_ACTIVE      = 1,
   ZONE_STATUS_INVALIDATED = 2,
   ZONE_STATUS_USED        = 3,
   ZONE_STATUS_EXPIRED     = 4
};

enum ENUM_LIQ_SIDE
{
   LIQ_NONE      = 0,
   LIQ_BUY_SIDE  = 1,   // BSL — highs
   LIQ_SELL_SIDE = -1   // SSL — lows
};

enum ENUM_LIQ_KIND
{
   LIQ_KIND_NONE        = 0,
   LIQ_KIND_SWING       = 1,
   LIQ_KIND_EQUAL       = 2,
   LIQ_KIND_SESSION     = 3,
   LIQ_KIND_OLD_EXTREME = 4
};

enum ENUM_FVG_STATE
{
   FVG_NONE         = 0,
   FVG_CREATED      = 1,
   FVG_TESTED       = 2,
   FVG_BROKEN       = 3,
   FVG_INVALIDATED  = 4,
   FVG_INVERTED     = 5
};

enum ENUM_IFVG_LIFE
{
   IFVG_LIFE_NONE             = 0,
   IFVG_LIFE_CREATED          = 1,
   IFVG_LIFE_WAITING_RETEST   = 2,
   IFVG_LIFE_RETEST           = 3,
   IFVG_LIFE_ENTRY_VALIDATION = 4,
   IFVG_LIFE_TRADED           = 5,
   IFVG_LIFE_INVALIDATED      = 6,
   IFVG_LIFE_EXPIRED          = 7
};

enum ENUM_SETUP_STATE
{
   ST_IDLE              = 0,
   ST_HTF_ANALYSIS      = 1,
   ST_LIQUIDITY_DETECTED= 2,
   ST_SWEEP_DETECTED    = 3,
   ST_SMT_VALIDATED     = 4,
   ST_CISD_VALIDATED    = 5,
   ST_FVG_DETECTED      = 6,
   ST_IFVG_CREATED      = 7,
   ST_WAITING_RETEST    = 8,
   ST_RETEST_DETECTED   = 9,
   ST_ENTRY_VALIDATION  = 10,
   ST_ORDER_SENT        = 11,
   ST_POSITION_ACTIVE   = 12,
   ST_POSITION_CLOSED   = 13,
   ST_SETUP_INVALIDATED = 14,
   ST_COOLDOWN          = 15
};

enum ENUM_IFVG_RISK_MODE
{
   RISK_FIXED_MONEY = 0,
   RISK_PERCENT     = 1
};

enum ENUM_EA_STATUS
{
   EA_WAITING      = 0,
   EA_ANALYZING    = 1,
   EA_SETUP_FOUND  = 2,
   EA_TRADE_ACTIVE = 3,
   EA_COOLDOWN     = 4
};

enum ENUM_SESSION_TZ
{
   TZ_SERVER = 0,
   TZ_UTC    = 1,
   TZ_LONDON = 2,
   TZ_NY     = 3,
   TZ_ASIAN  = 4
};

enum ENUM_CORR_TYPE
{
   CORR_POSITIVE = 1,   // XAU vs XAG
   CORR_INVERSE  = -1   // XAU vs DXY
};

//+------------------------------------------------------------------+
struct SSymbolSpec
{
   string            symbol;
   int               digits;
   int               stops_level;
   int               freeze_level;
   int               trade_mode;
   int               filling_mode;
   double            point;
   double            tick_size;
   double            tick_value;
   double            volume_min;
   double            volume_max;
   double            volume_step;
   double            trade_contract_size;
   datetime          session_open;
   datetime          session_close;
   bool              valid;
};

struct SPDZone
{
   ENUM_ZONE_TYPE    type;
   ENUM_IFVG_DIR     direction;
   ENUM_ZONE_STATUS  status;
   ENUM_TIMEFRAMES   timeframe;
   double            high;
   double            low;
   datetime          created;
   datetime          expire;
   ulong             id;
};

struct SSwing
{
   int               bar_index;
   datetime          time;
   double            price;
   bool              is_high;
   bool              confirmed;
};

struct SLiquidity
{
   ENUM_LIQ_SIDE     side;
   ENUM_LIQ_KIND     kind;
   double            price;
   double            tolerance;
   datetime          created;
   datetime          last_touch;
   int               touch_count;
   bool              swept;
   datetime          swept_at;
   double            swept_extreme;
   ulong             id;
   bool              active;
};

struct SSweep
{
   bool              valid;
   ENUM_IFVG_DIR     direction;
   ENUM_LIQ_SIDE     side;
   ulong             liquidity_id;
   double            level;
   double            extreme;
   datetime          time;
   int               bar_index;
   double            close_back;
   double            wick_beyond_points;
   bool              rejection;
};

struct SSMTResult
{
   bool              valid;
   bool              available;
   ENUM_SMT_STATUS   status;
   ENUM_IFVG_DIR     direction;
   string            compare_symbol;
   datetime          time;
   string            reason;
};

struct SCISDResult
{
   bool              valid;
   ENUM_IFVG_DIR     direction;
   datetime          timestamp;
   double            confirmation_level;
   double            body_ratio;
   ENUM_SETUP_STATE  setup_state;
   string            reason;
};

struct SFVG
{
   ulong             id;
   ENUM_IFVG_DIR     direction;
   ENUM_FVG_STATE    state;
   ENUM_TIMEFRAMES   timeframe;
   double            high;
   double            low;
   datetime          timestamp;
   datetime          inverted_at;
   bool              inverted;
   int               retest_count;
   bool              active;
};

struct SIFVG
{
   ulong             id;
   ulong             source_fvg_id;
   ENUM_IFVG_DIR     direction;
   ENUM_IFVG_LIFE    life;
   ENUM_TIMEFRAMES   timeframe;
   double            high;
   double            low;
   datetime          created;
   datetime          expire;
   int               retest_count;
   datetime          last_retest;
   bool              traded;
};

struct SSetup
{
   ulong             setup_id;
   ENUM_SETUP_STATE  state;
   ENUM_IFVG_DIR     direction;
   ENUM_IFVG_BIAS    htf_bias;
   SLiquidity        liquidity;
   SSweep            sweep;
   SSMTResult        smt;
   SCISDResult       cisd;
   SFVG              fvg;
   SIFVG             ifvg;
   bool              displacement;
   double            displacement_points;
   datetime          created;
   datetime          last_update;
   bool              executed;
   string            last_reject;
};

struct SEntryPlan
{
   bool              valid;
   ENUM_IFVG_DIR     direction;
   ulong             setup_id;
   double            entry;
   double            sl;
   double            tp;
   double            risk_distance;
   double            rr_actual;
   double            lot;
   double            theoretical_lot;
   double            expected_risk_money;
   double            margin_required;
   string            reject_reason;
};

struct SGateResult
{
   bool              passed;
   string            reason;
};

struct SBacktestSnapshot
{
   int               trades;
   int               wins;
   int               losses;
   int               setups_valid;
   int               setups_rejected;
   double            gross_profit;
   double            gross_loss;
   double            max_dd;
   double            peak_equity;
   double            total_r;
   double            sum_r_wins;
   int               max_consec_loss;
   int               consec_loss;
   double            target_rr;
};

void IFVG_ResetSymbolSpec(SSymbolSpec &s)
{
   s.symbol = "";
   s.digits = 0;
   s.stops_level = 0;
   s.freeze_level = 0;
   s.trade_mode = 0;
   s.filling_mode = 0;
   s.point = 0.0;
   s.tick_size = 0.0;
   s.tick_value = 0.0;
   s.volume_min = 0.0;
   s.volume_max = 0.0;
   s.volume_step = 0.0;
   s.trade_contract_size = 0.0;
   s.session_open = 0;
   s.session_close = 0;
   s.valid = false;
}

void IFVG_ResetSMT(SSMTResult &r)
{
   r.valid = false;
   r.available = false;
   r.status = SMT_STATUS_NONE;
   r.direction = IFVG_DIR_NONE;
   r.compare_symbol = "";
   r.time = 0;
   r.reason = "";
}

void IFVG_ResetCISD(SCISDResult &r)
{
   r.valid = false;
   r.direction = IFVG_DIR_NONE;
   r.timestamp = 0;
   r.confirmation_level = 0.0;
   r.body_ratio = 0.0;
   r.setup_state = ST_IDLE;
   r.reason = "";
}

void IFVG_ResetPlan(SEntryPlan &p)
{
   p.valid = false;
   p.direction = IFVG_DIR_NONE;
   p.setup_id = 0;
   p.entry = 0.0;
   p.sl = 0.0;
   p.tp = 0.0;
   p.risk_distance = 0.0;
   p.rr_actual = 0.0;
   p.lot = 0.0;
   p.theoretical_lot = 0.0;
   p.expected_risk_money = 0.0;
   p.margin_required = 0.0;
   p.reject_reason = "";
}

void IFVG_ResetSetup(SSetup &s)
{
   s.setup_id = 0;
   s.state = ST_IDLE;
   s.direction = IFVG_DIR_NONE;
   s.htf_bias = IFVG_BIAS_NONE;
   ZeroMemory(s.liquidity);
   ZeroMemory(s.sweep);
   IFVG_ResetSMT(s.smt);
   IFVG_ResetCISD(s.cisd);
   ZeroMemory(s.fvg);
   ZeroMemory(s.ifvg);
   s.displacement = false;
   s.displacement_points = 0.0;
   s.created = 0;
   s.last_update = 0;
   s.executed = false;
   s.last_reject = "";
}

#endif

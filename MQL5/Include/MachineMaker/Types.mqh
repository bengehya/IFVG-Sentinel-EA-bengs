#ifndef MM_TYPES_MQH
#define MM_TYPES_MQH

#include "Constants.mqh"

enum ENUM_MM_DIR
{
   MM_DIR_NONE = 0,
   MM_DIR_BUY  = 1,
   MM_DIR_SELL = -1
};

enum ENUM_MM_BIAS
{
   MM_BIAS_NONE    = 0,
   MM_BIAS_BULLISH = 1,
   MM_BIAS_BEARISH = -1,
   MM_BIAS_NEUTRAL = 2
};

enum ENUM_MM_STATE
{
   MM_ST_IDLE                 = 0,
   MM_ST_ANALYZING_DIRECTION  = 1,
   MM_ST_WAITING_FOR_FVG      = 2,
   MM_ST_WAITING_FOR_RETEST   = 3,
   MM_ST_ENTRY_VALIDATION     = 4,
   MM_ST_ORDER_SENT           = 5,
   MM_ST_POSITION_ACTIVE      = 6,
   MM_ST_COOLDOWN             = 7,
   MM_ST_WITHDRAWAL_REQUIRED  = 8
};

enum ENUM_MM_FVG_LIFE
{
   MM_FVG_NONE        = 0,
   MM_FVG_VALID       = 1,
   MM_FVG_INVALIDATED = 2,
   MM_FVG_EXPIRED     = 3,
   MM_FVG_TRADED      = 4
};

enum ENUM_MM_ENTRY_MODEL
{
   MM_MODEL_NONE  = 0,
   MM_MODEL_WICK  = 1,
   MM_MODEL_MID   = 2
};

enum ENUM_MM_SL_REASON
{
   MM_SL_NONE          = 0,
   MM_SL_FVG_NORMAL    = 1,
   MM_SL_FIB62_LARGE   = 2,
   MM_SL_FIB62_SMALL   = 3
};

struct SMMSymbolSpec
{
   string   symbol;
   int      digits;
   int      stops_level;
   int      freeze_level;
   int      trade_mode;
   int      filling_mode;
   double   point;
   double   tick_size;
   double   tick_value;
   double   volume_min;
   double   volume_max;
   double   volume_step;
   double   trade_contract_size;
   bool     valid;
};

struct SMMSwing
{
   int      bar_index;
   datetime time;
   double   price;
   bool     is_high;
   bool     confirmed;
};

struct SMMDirection
{
   ENUM_MM_BIAS daily;
   ENUM_MM_BIAS h4;
   ENUM_MM_BIAS aligned;
   bool         valid;
   double       d1_high;
   double       d1_low;
   double       h4_high;
   double       h4_low;
};

struct SMMFib
{
   bool     valid;
   ENUM_MM_DIR direction;
   double   swing_high;
   double   swing_low;
   double   fib_00;
   double   fib_50;
   double   fib_62;
   double   fib_100;
};

struct SMMFVG
{
   ulong             id;
   ENUM_MM_DIR       direction;
   ENUM_MM_FVG_LIFE  life;
   double            high;
   double            low;
   double            mid;
   datetime          timestamp;
   bool              in_discount_or_premium;
};

struct SMMEntryPlan
{
   bool                 valid;
   ENUM_MM_DIR          direction;
   ENUM_MM_ENTRY_MODEL  model;
   ulong                fvg_id;
   double               entry;
   double               sl;
   double               tp;
   double               raw_sl;
   double               risk_distance;
   double               rr_actual;
   double               lot;
   double               theoretical_lot;
   double               expected_risk;
   ENUM_MM_SL_REASON    sl_reason;
   string               reject_reason;
};

struct SMMSetup
{
   ulong                setup_id;
   ENUM_MM_STATE        state;
   ENUM_MM_DIR          direction;
   SMMDirection         dir;
   SMMFib               fib;
   SMMFVG               fvg;
   SMMEntryPlan         plan;
   string               last_reject;
   string               last_wait_fp;
};

struct SMMStats
{
   int    trades;
   int    wins;
   int    losses;
   int    setups_valid;
   int    setups_rejected;
   int    fvgs_seen;
   int    fvgs_invalidated;
   int    model1;
   int    model2;
   int    withdrawal_locks;
   double gross_profit;
   double gross_loss;
   double max_dd;
   double peak_equity;
   double total_r;
   int    max_consec_loss;
   int    consec_loss;
   double start_balance;
   double target_rr;
};

void MM_ResetSpec(SMMSymbolSpec &s)
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
   s.valid = false;
}

void MM_ResetPlan(SMMEntryPlan &p)
{
   p.valid = false;
   p.direction = MM_DIR_NONE;
   p.model = MM_MODEL_NONE;
   p.fvg_id = 0;
   p.entry = 0.0;
   p.sl = 0.0;
   p.tp = 0.0;
   p.raw_sl = 0.0;
   p.risk_distance = 0.0;
   p.rr_actual = 0.0;
   p.lot = 0.0;
   p.theoretical_lot = 0.0;
   p.expected_risk = 0.0;
   p.sl_reason = MM_SL_NONE;
   p.reject_reason = "";
}

void MM_ResetFVG(SMMFVG &f)
{
   f.id = 0;
   f.direction = MM_DIR_NONE;
   f.life = MM_FVG_NONE;
   f.high = 0.0;
   f.low = 0.0;
   f.mid = 0.0;
   f.timestamp = 0;
   f.in_discount_or_premium = false;
}

void MM_ResetSetup(SMMSetup &s)
{
   s.setup_id = 0;
   s.state = MM_ST_IDLE;
   s.direction = MM_DIR_NONE;
   ZeroMemory(s.dir);
   ZeroMemory(s.fib);
   MM_ResetFVG(s.fvg);
   MM_ResetPlan(s.plan);
   s.last_reject = "";
   s.last_wait_fp = "";
}

#endif

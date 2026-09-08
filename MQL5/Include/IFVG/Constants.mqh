#ifndef IFVG_CONSTANTS_MQH
#define IFVG_CONSTANTS_MQH

//+------------------------------------------------------------------+
//| IFVG Sentinel — hardcoded safety ceilings (cannot be bypassed)   |
//| Priority: capital safety > lot cap > position cap > cooldown     |
//+------------------------------------------------------------------+
#define IFVG_EA_NAME                 "IFVG Sentinel EA"
#define IFVG_EA_VERSION              "1.0.2"
#define IFVG_LOG_PREFIX              "[IFVG] "

#define IFVG_SENTINEL_MAGIC          26090817

#define IFVG_HARD_MAX_LOT            0.01
#define IFVG_HARD_MAX_POSITIONS      2
#define IFVG_HARD_MIN_CONSEC_SL      2
#define IFVG_HARD_MIN_COOLDOWN_H     8

#define IFVG_MAX_SWINGS              64
#define IFVG_MAX_LIQUIDITY           48
#define IFVG_MAX_PD_ZONES            32
#define IFVG_MAX_FVG                 32
#define IFVG_MAX_SETUPS              16
#define IFVG_MAX_USED_SETUP_IDS      256
#define IFVG_MAX_REJECT_REASONS      24

#define IFVG_GV_PREFIX               "IFVG_SENTINEL_"
#define IFVG_GV_COOLDOWN_START       "CD_START"
#define IFVG_GV_COOLDOWN_END         "CD_END"
#define IFVG_GV_CONSEC_SL            "CONSEC_SL"
#define IFVG_GV_LAST_SETUP           "LAST_SETUP"
#define IFVG_GV_STATS_TRADES         "ST_TRADES"

#define IFVG_DASH_PREFIX             "IFVG_DASH_"

#define IFVG_SECONDS_PER_HOUR        3600
#define IFVG_PRICE_EPS_POINTS        0.1

#endif

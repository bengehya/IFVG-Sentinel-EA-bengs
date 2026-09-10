#ifndef MM_CONSTANTS_MQH
#define MM_CONSTANTS_MQH

#define MM_EA_NAME                   "MACHINE MAKER"
#define MM_EA_VERSION                "1.1.0"
#define MM_LOG_PREFIX                "[MACHINE MAKER] "

#define MM_MAGIC                     26091001

#define MM_HARD_MAX_POSITIONS        2
#define MM_HARD_MIN_CONSEC_SL        2
#define MM_HARD_MIN_COOLDOWN_H       8
#define MM_HARD_TARGET_RR            4.0
#define MM_DEFAULT_RISK_PERCENT      2.0

#define MM_TF_DAILY                  PERIOD_D1
#define MM_TF_H4                     PERIOD_H4
#define MM_TF_M15                    PERIOD_M15

#define MM_MAX_FVG                   32
#define MM_SECONDS_PER_HOUR          3600

#define MM_GV_PREFIX                 "MM_MAKER_"
#define MM_GV_CONSEC_SL              "CONSEC_SL"
#define MM_GV_COOLDOWN_START         "CD_START"
#define MM_GV_COOLDOWN_END           "CD_END"

#define MM_DASH_PREFIX               "MM_DASH_"

#endif

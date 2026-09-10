#ifndef MM_UTILS_MQH
#define MM_UTILS_MQH

#include "Types.mqh"

double MM_PointsToPrice(const SMMSymbolSpec &spec, const double points)
{
   if(spec.point <= 0.0)
      return 0.0;
   return points * spec.point;
}

double MM_NormalizePrice(const SMMSymbolSpec &spec, const double price)
{
   if(spec.tick_size > 0.0)
      return MathRound(price / spec.tick_size) * spec.tick_size;
   return NormalizeDouble(price, spec.digits);
}

double MM_NormalizeVolume(const SMMSymbolSpec &spec, double volume)
{
   if(spec.volume_step > 0.0)
      volume = MathFloor(volume / spec.volume_step + 1e-12) * spec.volume_step;
   return NormalizeDouble(volume, 8);
}

string MM_DirToString(const ENUM_MM_DIR dir)
{
   if(dir == MM_DIR_BUY)
      return "BUY";
   if(dir == MM_DIR_SELL)
      return "SELL";
   return "NONE";
}

string MM_BiasToString(const ENUM_MM_BIAS bias)
{
   if(bias == MM_BIAS_BULLISH)
      return "BULLISH";
   if(bias == MM_BIAS_BEARISH)
      return "BEARISH";
   if(bias == MM_BIAS_NEUTRAL)
      return "NEUTRAL";
   return "NONE";
}

string MM_StateToString(const ENUM_MM_STATE st)
{
   switch(st)
   {
      case MM_ST_IDLE:                return "IDLE";
      case MM_ST_ANALYZING_DIRECTION: return "ANALYZING_DIRECTION";
      case MM_ST_WAITING_FOR_FVG:     return "WAITING_FOR_FVG";
      case MM_ST_WAITING_FOR_RETEST:  return "WAITING_FOR_RETEST";
      case MM_ST_ENTRY_VALIDATION:    return "ENTRY_VALIDATION";
      case MM_ST_ORDER_SENT:          return "ORDER_SENT";
      case MM_ST_POSITION_ACTIVE:     return "POSITION_ACTIVE";
      case MM_ST_COOLDOWN:            return "COOLDOWN";
      case MM_ST_WITHDRAWAL_REQUIRED: return "WITHDRAWAL_REQUIRED";
   }
   return "UNKNOWN";
}

string MM_SlReasonToString(const ENUM_MM_SL_REASON r)
{
   if(r == MM_SL_FVG_NORMAL)
      return "normal FVG SL";
   if(r == MM_SL_FIB62_LARGE)
      return "large FVG — 0.62 because FVG SL exceeds monetary risk";
   if(r == MM_SL_FIB62_SMALL)
      return "small FVG — 0.62 structural protection";
   return "none";
}

bool MM_IsGoldSymbol(const string symbol)
{
   string u = symbol;
   StringToUpper(u);
   if(StringFind(u, "XAU") >= 0)
      return true;
   if(StringFind(u, "GOLD") >= 0)
      return true;
   return false;
}

string MM_SanitizeGvName(const string raw)
{
   string out = raw;
   StringReplace(out, ".", "_");
   StringReplace(out, " ", "_");
   StringReplace(out, "-", "_");
   StringReplace(out, "/", "_");
   StringReplace(out, "#", "_");
   return out;
}

int MM_PeriodSeconds(const ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 60;
      case PERIOD_M5:  return 300;
      case PERIOD_M15: return 900;
      case PERIOD_H1:  return 3600;
      case PERIOD_H4:  return 14400;
      case PERIOD_D1:  return 86400;
      case PERIOD_CURRENT: return 0;
   }
   return 0;
}

bool MM_CopyRatesSafe(const string symbol, const ENUM_TIMEFRAMES tf, const int count, MqlRates &rates[])
{
   if(tf == PERIOD_CURRENT)
      return false;
   ArraySetAsSeries(rates, true);
   const int got = CopyRates(symbol, tf, 0, count, rates);
   return (got >= count || got > 10);
}

bool MM_CopyTimeSafe(const string symbol, const ENUM_TIMEFRAMES tf, datetime &times[])
{
   if(tf == PERIOD_CURRENT)
      return false;
   return (CopyTime(symbol, tf, 0, 1, times) >= 1);
}

bool MM_IsSwingHigh(const MqlRates &rates[], const int index, const int left, const int right)
{
   const int n = ArraySize(rates);
   if(index - right < 0 || index + left >= n)
      return false;
   const double px = rates[index].high;
   for(int i = 1; i <= left; i++)
   {
      if(rates[index + i].high >= px)
         return false;
   }
   for(int i = 1; i <= right; i++)
   {
      if(rates[index - i].high > px)
         return false;
   }
   return true;
}

bool MM_IsSwingLow(const MqlRates &rates[], const int index, const int left, const int right)
{
   const int n = ArraySize(rates);
   if(index - right < 0 || index + left >= n)
      return false;
   const double px = rates[index].low;
   for(int i = 1; i <= left; i++)
   {
      if(rates[index + i].low <= px)
         return false;
   }
   for(int i = 1; i <= right; i++)
   {
      if(rates[index - i].low < px)
         return false;
   }
   return true;
}

ENUM_MM_BIAS MM_BiasFromSwings(const double h0, const double h1, const double l0, const double l1)
{
   const bool hh = (h0 > h1);
   const bool hl = (l0 > l1);
   const bool lh = (h0 < h1);
   const bool ll = (l0 < l1);
   if(hh && hl)
      return MM_BIAS_BULLISH;
   if(lh && ll)
      return MM_BIAS_BEARISH;
   return MM_BIAS_NEUTRAL;
}

ENUM_MM_BIAS MM_AlignBias(const ENUM_MM_BIAS daily, const ENUM_MM_BIAS h4)
{
   if(daily == MM_BIAS_BULLISH && h4 == MM_BIAS_BULLISH)
      return MM_BIAS_BULLISH;
   if(daily == MM_BIAS_BEARISH && h4 == MM_BIAS_BEARISH)
      return MM_BIAS_BEARISH;
   return MM_BIAS_NEUTRAL;
}

#endif

#ifndef IFVG_UTILS_MQH
#define IFVG_UTILS_MQH

#include "Types.mqh"

//+------------------------------------------------------------------+
double IFVG_PointsToPrice(const SSymbolSpec &spec, const double points)
{
   if(spec.point <= 0.0)
      return 0.0;
   return points * spec.point;
}

double IFVG_PriceToPoints(const SSymbolSpec &spec, const double price_distance)
{
   if(spec.point <= 0.0)
      return 0.0;
   return MathAbs(price_distance) / spec.point;
}

double IFVG_NormalizePrice(const SSymbolSpec &spec, const double price)
{
   if(spec.tick_size > 0.0)
      return MathRound(price / spec.tick_size) * spec.tick_size;
   return NormalizeDouble(price, spec.digits);
}

double IFVG_NormalizeVolume(const SSymbolSpec &spec, double volume)
{
   if(spec.volume_step > 0.0)
      volume = MathFloor(volume / spec.volume_step + 1e-12) * spec.volume_step;
   volume = NormalizeDouble(volume, 8);
   return volume;
}

string IFVG_DirToString(const ENUM_IFVG_DIR dir)
{
   if(dir == IFVG_DIR_BUY)
      return "BUY";
   if(dir == IFVG_DIR_SELL)
      return "SELL";
   return "NONE";
}

string IFVG_BiasToString(const ENUM_IFVG_BIAS bias)
{
   if(bias == IFVG_BIAS_BULLISH)
      return "BULLISH";
   if(bias == IFVG_BIAS_BEARISH)
      return "BEARISH";
   if(bias == IFVG_BIAS_NEUTRAL)
      return "NEUTRAL";
   return "NONE";
}

string IFVG_StateToString(const ENUM_SETUP_STATE st)
{
   switch(st)
   {
      case ST_IDLE:               return "IDLE";
      case ST_HTF_ANALYSIS:       return "HTF_ANALYSIS";
      case ST_LIQUIDITY_DETECTED: return "LIQUIDITY_DETECTED";
      case ST_SWEEP_DETECTED:     return "SWEEP_DETECTED";
      case ST_SMT_VALIDATED:      return "SMT_VALIDATED";
      case ST_CISD_VALIDATED:     return "CISD_VALIDATED";
      case ST_FVG_DETECTED:       return "FVG_DETECTED";
      case ST_IFVG_CREATED:       return "IFVG_CREATED";
      case ST_WAITING_RETEST:     return "WAITING_RETEST";
      case ST_RETEST_DETECTED:    return "RETEST_DETECTED";
      case ST_ENTRY_VALIDATION:   return "ENTRY_VALIDATION";
      case ST_ORDER_SENT:         return "ORDER_SENT";
      case ST_POSITION_ACTIVE:    return "POSITION_ACTIVE";
      case ST_POSITION_CLOSED:    return "POSITION_CLOSED";
      case ST_SETUP_INVALIDATED:  return "SETUP_INVALIDATED";
      case ST_COOLDOWN:           return "COOLDOWN";
   }
   return "UNKNOWN";
}

string IFVG_StatusToString(const ENUM_EA_STATUS st)
{
   switch(st)
   {
      case EA_WAITING:      return "WAITING";
      case EA_ANALYZING:    return "ANALYZING";
      case EA_SETUP_FOUND:  return "SETUP FOUND";
      case EA_TRADE_ACTIVE: return "TRADE ACTIVE";
      case EA_COOLDOWN:     return "COOLDOWN";
   }
   return "UNKNOWN";
}

string IFVG_LiqToString(const ENUM_LIQ_SIDE side)
{
   if(side == LIQ_BUY_SIDE)
      return "BUY-SIDE";
   if(side == LIQ_SELL_SIDE)
      return "SELL-SIDE";
   return "NONE";
}

bool IFVG_DirMatchesBias(const ENUM_IFVG_DIR dir, const ENUM_IFVG_BIAS bias)
{
   if(dir == IFVG_DIR_BUY && bias == IFVG_BIAS_BULLISH)
      return true;
   if(dir == IFVG_DIR_SELL && bias == IFVG_BIAS_BEARISH)
      return true;
   return false;
}

ulong IFVG_BuildSetupId(const string symbol,
                        const ENUM_IFVG_DIR dir,
                        const datetime sweep_time,
                        const double liq_price,
                        const datetime ifvg_time)
{
   const long p = (long)MathRound(liq_price * 100000.0);
   string key = symbol + "|" + IntegerToString((int)dir) + "|" +
                IntegerToString((long)sweep_time) + "|" +
                IntegerToString(p) + "|" +
                IntegerToString((long)ifvg_time);
   ulong hash = 2166136261;
   const int n = StringLen(key);
   for(int i = 0; i < n; i++)
   {
      hash ^= (uchar)StringGetCharacter(key, i);
      hash *= 16777619;
   }
   if(hash == 0)
      hash = 1;
   return hash;
}

string IFVG_SanitizeGvName(const string raw)
{
   string out = raw;
   StringReplace(out, ".", "_");
   StringReplace(out, " ", "_");
   StringReplace(out, "-", "_");
   StringReplace(out, "/", "_");
   StringReplace(out, "#", "_");
   return out;
}

int IFVG_PeriodSeconds(const ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 60;
      case PERIOD_M2:  return 120;
      case PERIOD_M3:  return 180;
      case PERIOD_M4:  return 240;
      case PERIOD_M5:  return 300;
      case PERIOD_M6:  return 360;
      case PERIOD_M10: return 600;
      case PERIOD_M12: return 720;
      case PERIOD_M15: return 900;
      case PERIOD_M20: return 1200;
      case PERIOD_M30: return 1800;
      case PERIOD_H1:  return 3600;
      case PERIOD_H2:  return 7200;
      case PERIOD_H3:  return 10800;
      case PERIOD_H4:  return 14400;
      case PERIOD_H6:  return 21600;
      case PERIOD_H8:  return 28800;
      case PERIOD_H12: return 43200;
      case PERIOD_D1:  return 86400;
      case PERIOD_W1:  return 604800;
      case PERIOD_MN1: return 2592000;
   }
   return PeriodSeconds(tf);
}

bool IFVG_CopyRatesSafe(const string symbol,
                        const ENUM_TIMEFRAMES tf,
                        const int count,
                        MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);
   const int got = CopyRates(symbol, tf, 0, count, rates);
   return (got >= count || got > 10);
}

double IFVG_ATR(const MqlRates &rates[], const int period, const int start_shift = 1)
{
   if(period <= 0)
      return 0.0;
   const int n = ArraySize(rates);
   if(n < start_shift + period + 1)
      return 0.0;
   double sum = 0.0;
   for(int i = start_shift; i < start_shift + period; i++)
   {
      const double tr1 = rates[i].high - rates[i].low;
      const double tr2 = MathAbs(rates[i].high - rates[i + 1].close);
      const double tr3 = MathAbs(rates[i].low - rates[i + 1].close);
      sum += MathMax(tr1, MathMax(tr2, tr3));
   }
   return sum / (double)period;
}

bool IFVG_IsSwingHigh(const MqlRates &rates[], const int index, const int left, const int right)
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

bool IFVG_IsSwingLow(const MqlRates &rates[], const int index, const int left, const int right)
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

double IFVG_CandleBody(const MqlRates &r)
{
   return MathAbs(r.close - r.open);
}

double IFVG_CandleRange(const MqlRates &r)
{
   return (r.high - r.low);
}

bool IFVG_IsBullClose(const MqlRates &r)
{
   return (r.close > r.open);
}

bool IFVG_IsBearClose(const MqlRates &r)
{
   return (r.close < r.open);
}

#endif

#ifndef MM_ENTRYMODELS_MQH
#define MM_ENTRYMODELS_MQH

#include "Types.mqh"
#include "FVGEngine.mqh"

class CMMEntryModels
{
public:
   static bool WickIntoZone(const double high, const double low, const double fvg_high, const double fvg_low)
   {
      return (low <= fvg_high && high >= fvg_low);
   }

   static bool Model1(const ENUM_MM_DIR dir, const MqlRates &candle,
                      const double fvg_high, const double fvg_low,
                      bool &wick_in, bool &close_outside)
   {
      wick_in = WickIntoZone(candle.high, candle.low, fvg_high, fvg_low);
      close_outside = false;
      if(!wick_in)
         return false;
      if(CMMFVGEngine::CompletelyBroken(dir, fvg_high, fvg_low, candle.close))
         return false;
      const bool close_inside = (candle.close <= fvg_high && candle.close >= fvg_low);
      if(close_inside)
         return false;
      if(dir == MM_DIR_BUY)
         close_outside = (candle.close > fvg_high);
      else if(dir == MM_DIR_SELL)
         close_outside = (candle.close < fvg_low);
      return close_outside;
   }

   static bool Model2(const ENUM_MM_DIR dir, const MqlRates &candle,
                      const double fvg_high, const double fvg_low,
                      bool &touch50, bool &close_outside50)
   {
      const double mid = 0.5 * (fvg_high + fvg_low);
      touch50 = (candle.low <= mid && candle.high >= mid);
      close_outside50 = false;
      if(!touch50)
         return false;
      if(CMMFVGEngine::CompletelyBroken(dir, fvg_high, fvg_low, candle.close))
         return false;
      if(dir == MM_DIR_BUY)
         close_outside50 = (candle.close > mid);
      else if(dir == MM_DIR_SELL)
         close_outside50 = (candle.close < mid);
      return close_outside50;
   }

   static ENUM_MM_ENTRY_MODEL Detect(const ENUM_MM_DIR dir, const MqlRates &candle,
                                     const double fvg_high, const double fvg_low,
                                     bool &wick_in, bool &close_out,
                                     bool &touch50, bool &close50)
   {
      wick_in = false;
      close_out = false;
      touch50 = false;
      close50 = false;
      if(Model1(dir, candle, fvg_high, fvg_low, wick_in, close_out))
         return MM_MODEL_WICK;
      if(Model2(dir, candle, fvg_high, fvg_low, touch50, close50))
         return MM_MODEL_MID;
      return MM_MODEL_NONE;
   }
};

#endif

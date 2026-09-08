#ifndef IFVG_PERSISTENCE_MQH
#define IFVG_PERSISTENCE_MQH

#include "Utils.mqh"

class CIFVGPersistence
{
private:
   string m_prefix;

   string Key(const string suffix) const
   {
      return IFVG_SanitizeGvName(m_prefix + suffix);
   }

public:
   void Init(const long magic, const string symbol)
   {
      m_prefix = IFVG_GV_PREFIX + IntegerToString((int)magic) + "_" + symbol + "_";
   }

   bool SetDouble(const string suffix, const double value)
   {
      return GlobalVariableSet(Key(suffix), value) > 0 || GlobalVariableCheck(Key(suffix));
   }

   double GetDouble(const string suffix, const double fallback = 0.0) const
   {
      const string k = Key(suffix);
      if(!GlobalVariableCheck(k))
         return fallback;
      return GlobalVariableGet(k);
   }

   bool SetTime(const string suffix, const datetime t)
   {
      return SetDouble(suffix, (double)t);
   }

   datetime GetTime(const string suffix, const datetime fallback = 0) const
   {
      return (datetime)GetDouble(suffix, (double)fallback);
   }

   bool SetInt(const string suffix, const int v)
   {
      return SetDouble(suffix, (double)v);
   }

   int GetInt(const string suffix, const int fallback = 0) const
   {
      return (int)GetDouble(suffix, (double)fallback);
   }
};

#endif

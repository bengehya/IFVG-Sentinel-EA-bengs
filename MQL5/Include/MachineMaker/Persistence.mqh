#ifndef MM_PERSISTENCE_MQH
#define MM_PERSISTENCE_MQH

#include "Utils.mqh"

class CMMPersistence
{
private:
   string m_prefix;

   string Key(const string suffix) const
   {
      return MM_SanitizeGvName(m_prefix + suffix);
   }

public:
   void Init(const long magic, const string symbol)
   {
      m_prefix = MM_GV_PREFIX + IntegerToString((int)magic) + "_" + symbol + "_";
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

   bool SetTime(const string suffix, const datetime t) { return SetDouble(suffix, (double)t); }
   datetime GetTime(const string suffix, const datetime fallback = 0) const
   {
      return (datetime)GetDouble(suffix, (double)fallback);
   }
   bool SetInt(const string suffix, const int v) { return SetDouble(suffix, (double)v); }
   int GetInt(const string suffix, const int fallback = 0) const
   {
      return (int)GetDouble(suffix, (double)fallback);
   }

   bool Delete(const string suffix)
   {
      const string k = Key(suffix);
      if(!GlobalVariableCheck(k))
         return true;
      return GlobalVariableDel(k);
   }

   // TESTER-ONLY. Deletes every Global Variable for this EA prefix:
   // CONSEC_SL, CD_START, CD_END, and RISK_<position> ledgers.
   // Live trading is a hard no-op so cooldown persistence cannot be wiped.
   int ResetTesterState()
   {
      if(!MQLInfoInteger(MQL_TESTER))
         return 0;
      const string pref = MM_SanitizeGvName(m_prefix);
      int removed = 0;
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
      {
         const string name = GlobalVariableName(i);
         if(StringFind(name, pref) != 0)
            continue;
         if(GlobalVariableDel(name))
            removed++;
      }
      return removed;
   }
};

#endif

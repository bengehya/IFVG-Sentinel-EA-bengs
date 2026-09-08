#ifndef IFVG_SYMBOLPROVIDER_MQH
#define IFVG_SYMBOLPROVIDER_MQH

#include "Logger.mqh"
#include "Utils.mqh"

class CSymbolProvider
{
private:
   SSymbolSpec   m_spec;
   CIFVGLogger  *m_log;

public:
   CSymbolProvider()
   {
      m_log = NULL;
      IFVG_ResetSymbolSpec(m_spec);
   }

   void SetLogger(CIFVGLogger *log) { m_log = log; }

   bool Refresh(const string symbol)
   {
      IFVG_ResetSymbolSpec(m_spec);
      m_spec.symbol = symbol;

      if(!SymbolSelect(symbol, true))
      {
         if(m_log != NULL)
            m_log.Error("symbol unavailable: " + symbol);
         m_spec.valid = false;
         return false;
      }

      m_spec.digits             = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      m_spec.point              = SymbolInfoDouble(symbol, SYMBOL_POINT);
      m_spec.tick_size          = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      m_spec.tick_value         = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      m_spec.volume_min         = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      m_spec.volume_max         = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      m_spec.volume_step        = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      m_spec.stops_level        = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_spec.freeze_level       = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      m_spec.trade_mode         = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      m_spec.filling_mode       = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      m_spec.trade_contract_size= SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);

      datetime from, to;
      if(SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)TimeDayOfWeek(TimeCurrent()), 0, from, to))
      {
         m_spec.session_open = from;
         m_spec.session_close = to;
      }

      m_spec.valid = (m_spec.point > 0.0 && m_spec.volume_min > 0.0);
      if(!m_spec.valid && m_log != NULL)
         m_log.Error("invalid symbol specification for " + symbol);
      return m_spec.valid;
   }

   SSymbolSpec Spec() const { return m_spec; }

   string SymbolName() const { return m_spec.symbol; }

   double Bid() const
   {
      return SymbolInfoDouble(m_spec.symbol, SYMBOL_BID);
   }

   double Ask() const
   {
      return SymbolInfoDouble(m_spec.symbol, SYMBOL_ASK);
   }

   double SpreadPoints() const
   {
      const double bid = Bid();
      const double ask = Ask();
      if(m_spec.point <= 0.0)
         return 0.0;
      return (ask - bid) / m_spec.point;
   }

   bool TradingAllowed() const
   {
      if(!m_spec.valid)
         return false;
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
         return false;
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
         return false;
      if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
         return false;
      if(m_spec.trade_mode == SYMBOL_TRADE_MODE_DISABLED)
         return false;
      return true;
   }

   ENUM_ORDER_TYPE_FILLING DetectFilling() const
   {
      const int filling = m_spec.filling_mode;
      if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         return ORDER_FILLING_IOC;
      if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         return ORDER_FILLING_FOK;
      return ORDER_FILLING_RETURN;
   }

   double MinStopDistance() const
   {
      const int lvl = MathMax(m_spec.stops_level, m_spec.freeze_level);
      return (double)lvl * m_spec.point;
   }
};

int TimeDayOfWeek(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.day_of_week;
}

#endif

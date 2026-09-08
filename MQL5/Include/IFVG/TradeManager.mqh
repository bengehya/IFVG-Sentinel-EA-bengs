#ifndef IFVG_TRADEMANAGER_MQH
#define IFVG_TRADEMANAGER_MQH

#include <Trade/Trade.mqh>
#include "Config.mqh"
#include "Logger.mqh"
#include "SymbolProvider.mqh"
#include "Safety.mqh"

class CTradeManager
{
private:
   CIFVGConfig      *m_cfg;
   CIFVGLogger      *m_log;
   CTrade            m_trade;
   ulong             m_last_setup_id;
   datetime          m_last_send_time;

   bool PreTradeChecks(const CSymbolProvider &sym, const SEntryPlan &plan, string &reason)
   {
      if(!sym.TradingAllowed())
      {
         reason = "trading disabled";
         return false;
      }
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      {
         reason = "connection failure";
         return false;
      }
      const SSymbolSpec spec = sym.Spec();
      if(!spec.valid)
      {
         reason = "symbol unavailable";
         return false;
      }
      if(!CIFVGSafety::AllowsOrderOnSymbol(m_cfg.in.symbol, spec.symbol))
      {
         reason = "external symbol orders are forbidden";
         return false;
      }
      if(CIFVGSafety::IsExternalCompareSymbol(spec.symbol, m_cfg.in.smt_symbol1, m_cfg.in.smt_symbol2))
      {
         reason = "SMT compare symbol is not tradable by this EA";
         return false;
      }
      if(spec.trade_mode == SYMBOL_TRADE_MODE_CLOSEONLY || spec.trade_mode == SYMBOL_TRADE_MODE_DISABLED)
      {
         reason = "market closed / trading disabled on symbol";
         return false;
      }
      if(!CIFVGSafety::VolumeRespectsHardCap(plan.lot))
      {
         reason = "lot exceeds hard cap 0.01";
         return false;
      }
      if(plan.lot <= 0.0)
      {
         reason = "invalid volume";
         return false;
      }
      if(plan.entry <= 0.0 || plan.sl <= 0.0 || plan.tp <= 0.0)
      {
         reason = "invalid price";
         return false;
      }
      if(!CIFVGSafety::StopsConsistent(plan.direction, plan.entry, plan.sl, plan.tp))
      {
         reason = "invalid stops";
         return false;
      }
      if(m_last_setup_id == plan.setup_id && plan.setup_id != 0)
      {
         reason = "duplicate order for same SetupID";
         return false;
      }
      if(TimeCurrent() == m_last_send_time)
      {
         reason = "duplicate order same second";
         return false;
      }
      return true;
   }

public:
   CTradeManager()
   {
      m_last_setup_id = 0;
      m_last_send_time = 0;
   }

   void Init(CIFVGConfig *cfg, CIFVGLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
      m_trade.SetExpertMagicNumber((ulong)cfg.in.magic);
      m_trade.SetDeviationInPoints(20);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
   }

   bool Open(const CSymbolProvider &sym, const SEntryPlan &plan, string &reason)
   {
      reason = "";
      if(!PreTradeChecks(sym, plan, reason))
      {
         if(m_log != NULL)
            m_log.NoTrade(reason);
         return false;
      }

      m_trade.SetTypeFilling(sym.DetectFilling());
      m_trade.SetExpertMagicNumber((ulong)m_cfg.in.magic);

      const string comment = "IFVG#" + IntegerToString((long)plan.setup_id);
      bool ok = false;
      if(plan.direction == IFVG_DIR_BUY)
         ok = m_trade.Buy(plan.lot, sym.SymbolName(), 0.0, plan.sl, plan.tp, comment);
      else if(plan.direction == IFVG_DIR_SELL)
         ok = m_trade.Sell(plan.lot, sym.SymbolName(), 0.0, plan.sl, plan.tp, comment);
      else
      {
         reason = "invalid direction";
         return false;
      }

      if(!ok)
      {
         const uint rc = m_trade.ResultRetcode();
         reason = "order failed retcode=" + IntegerToString((int)rc) + " " + m_trade.ResultRetcodeDescription();
         if(rc == TRADE_RETCODE_REQUOTE)
            reason = "requotes";
         if(rc == TRADE_RETCODE_NO_MONEY)
            reason = "insufficient margin";
         if(rc == TRADE_RETCODE_INVALID_FILL)
            reason = "incorrect filling mode";
         if(rc == TRADE_RETCODE_INVALID_VOLUME)
            reason = "invalid volume";
         if(rc == TRADE_RETCODE_INVALID_STOPS)
            reason = "invalid stops";
         if(rc == TRADE_RETCODE_MARKET_CLOSED)
            reason = "market closed";
         if(m_log != NULL)
            m_log.NoTrade(reason);
         return false;
      }

      const double filled_vol = m_trade.ResultVolume();
      if(!CIFVGSafety::VolumeRespectsHardCap(filled_vol) && filled_vol > 0.0)
      {
         if(m_log != NULL)
            m_log.Error("broker filled volume above 0.01 — closing immediately");
         ulong pos_id = 0;
         const ulong deal = m_trade.ResultDeal();
         if(deal > 0)
         {
            HistorySelect(TimeCurrent() - 60, TimeCurrent() + 5);
            if(HistoryDealSelect(deal))
               pos_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         }
         if(pos_id > 0)
            m_trade.PositionClose(pos_id);
         else
            m_trade.PositionClose(sym.SymbolName());
         reason = "filled volume exceeded hard cap";
         return false;
      }

      m_last_setup_id = plan.setup_id;
      m_last_send_time = TimeCurrent();
      if(m_log != NULL)
         m_log.Decision("Position opened",
                        "ticket=" + IntegerToString((long)m_trade.ResultOrder()) +
                        " lot=" + DoubleToString(filled_vol, 2));
      return true;
   }
};

#endif

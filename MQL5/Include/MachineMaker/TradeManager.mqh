#ifndef MM_TRADEMANAGER_MQH
#define MM_TRADEMANAGER_MQH

#include <Trade/Trade.mqh>
#include "Config.mqh"
#include "Logger.mqh"
#include "SymbolProvider.mqh"
#include "Safety.mqh"

class CMMTradeManager
{
private:
   CMMConfig *m_cfg;
   CMMLogger *m_log;
   CTrade     m_trade;
   ulong      m_last_fvg_id;
   datetime   m_last_send_time;
   ulong      m_last_position_id;
   double     m_last_fill_price;
   double     m_last_volume;

   bool PreTradeChecks(const CMMSymbolProvider &sym, const SMMEntryPlan &plan, string &reason)
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
      const SMMSymbolSpec spec = sym.Spec();
      if(!spec.valid)
      {
         reason = "symbol unavailable";
         return false;
      }
      if(!MM_IsGoldSymbol(spec.symbol))
      {
         reason = "gold-only: symbol rejected";
         return false;
      }
      if(!CMMSafety::VolumeRespectsBroker(spec, plan.lot, m_cfg.in.max_lot))
      {
         reason = "lot exceeds broker volume max";
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
      if(!CMMSafety::StopsConsistent(plan.direction, plan.entry, plan.sl, plan.tp))
      {
         reason = "invalid stops";
         return false;
      }
      if(m_last_fvg_id == plan.fvg_id && plan.fvg_id != 0)
      {
         reason = "duplicate order for same FVG";
         return false;
      }
      if(TimeCurrent() == m_last_send_time)
      {
         reason = "duplicate order same second";
         return false;
      }

      MqlTradeRequest req;
      MqlTradeCheckResult chk;
      ZeroMemory(req);
      ZeroMemory(chk);
      req.action = TRADE_ACTION_DEAL;
      req.symbol = spec.symbol;
      req.volume = plan.lot;
      req.type = (plan.direction == MM_DIR_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      req.price = plan.entry;
      req.sl = plan.sl;
      req.tp = plan.tp;
      req.magic = (ulong)m_cfg.in.magic;
      req.type_filling = sym.DetectFilling();
      if(!OrderCheck(req, chk))
      {
         if(chk.retcode == TRADE_RETCODE_NO_MONEY)
            reason = "insufficient margin";
         else if(chk.comment != "")
            reason = chk.comment;
         else
            reason = "broker OrderCheck retcode=" + IntegerToString((int)chk.retcode);
         return false;
      }
      return true;
   }

public:
   CMMTradeManager()
   {
      m_last_fvg_id = 0;
      m_last_send_time = 0;
      m_last_position_id = 0;
      m_last_fill_price = 0.0;
      m_last_volume = 0.0;
   }

   void Init(CMMConfig *cfg, CMMLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
      m_trade.SetExpertMagicNumber((ulong)cfg.in.magic);
      m_trade.SetDeviationInPoints(20);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
   }

   bool Open(const CMMSymbolProvider &sym, const SMMEntryPlan &plan, string &reason)
   {
      reason = "";
      if(!PreTradeChecks(sym, plan, reason))
      {
         if(m_log != NULL)
            m_log.NoTrade(reason);
         return false;
      }
      m_trade.SetTypeFilling(sym.DetectFilling());
      const string comment = "MM#" + IntegerToString((long)plan.fvg_id);
      bool ok = false;
      if(plan.direction == MM_DIR_BUY)
         ok = m_trade.Buy(plan.lot, sym.SymbolName(), 0.0, plan.sl, plan.tp, comment);
      else
         ok = m_trade.Sell(plan.lot, sym.SymbolName(), 0.0, plan.sl, plan.tp, comment);
      if(!ok)
      {
         const uint rc = m_trade.ResultRetcode();
         reason = "broker rejected retcode=" + IntegerToString((int)rc) + " " + m_trade.ResultRetcodeDescription();
         if(rc == TRADE_RETCODE_NO_MONEY)
            reason = "insufficient margin";
         if(m_log != NULL)
            m_log.NoTrade(reason);
         return false;
      }
      const double filled = m_trade.ResultVolume();
      if(filled > 0.0 && !CMMSafety::VolumeRespectsBroker(sym.Spec(), filled, m_cfg.in.max_lot))
      {
         if(m_log != NULL)
            m_log.Error("broker filled volume above broker/input max — closing immediately");
         m_trade.PositionClose(sym.SymbolName());
         reason = "filled volume exceeded broker volume max";
         return false;
      }
      m_last_fvg_id = plan.fvg_id;
      m_last_send_time = TimeCurrent();
      m_last_fill_price = m_trade.ResultPrice();
      m_last_volume = (filled > 0.0 ? filled : plan.lot);
      m_last_position_id = 0;
      const ulong deal = m_trade.ResultDeal();
      if(deal != 0 && HistoryDealSelect(deal))
         m_last_position_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(m_last_position_id == 0 && PositionSelect(sym.SymbolName()))
         m_last_position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      return true;
   }

   ulong LastPositionId() const { return m_last_position_id; }
   double LastFillPrice() const { return m_last_fill_price; }
   double LastVolume() const { return m_last_volume; }
};

#endif

#ifndef IFVG_ENTRYENGINE_MQH
#define IFVG_ENTRYENGINE_MQH

#include "SetupValidator.mqh"
#include "RiskManager.mqh"
#include "TradeManager.mqh"
#include "PositionManager.mqh"
#include "CooldownManager.mqh"
#include "SessionManager.mqh"
#include "IFVGManager.mqh"
#include "Logger.mqh"

class CEntryEngine
{
private:
   CIFVGConfig       *m_cfg;
   CIFVGLogger       *m_log;
   CRiskManager      *m_risk;
   CTradeManager     *m_trade;
   CPositionManager  *m_pos;
   CCooldownManager  *m_cd;
   CSessionManager   *m_session;
   CIFVGManager      *m_ifvg;
   CSymbolProvider   *m_sym;

public:
   void Init(CIFVGConfig *cfg,
             CIFVGLogger *log,
             CRiskManager *risk,
             CTradeManager *trade,
             CPositionManager *pos,
             CCooldownManager *cd,
             CSessionManager *session,
             CIFVGManager *ifvg,
             CSymbolProvider *sym)
   {
      m_cfg = cfg;
      m_log = log;
      m_risk = risk;
      m_trade = trade;
      m_pos = pos;
      m_cd = cd;
      m_session = session;
      m_ifvg = ifvg;
      m_sym = sym;
   }

   bool TryEnter(SSetup &setup, SEntryPlan &plan)
   {
      IFVG_ResetPlan(plan);
      if(m_log != NULL)
         m_log.Decision("Entry validation", "SetupID=" + IntegerToString((long)setup.setup_id));

      string reason = "";
      const datetime now = TimeCurrent();
      const bool cooldown_ok = m_cd.AllowsEntry(now, reason);
      if(!cooldown_ok)
      {
         if(m_log != NULL)
            m_log.NoTrade(reason);
         setup.last_reject = reason;
         return false;
      }

      if(!m_pos.CanOpenAnother(reason))
      {
         if(m_log != NULL)
            m_log.NoTrade(reason);
         setup.last_reject = reason;
         return false;
      }

      string sess_reason = "";
      const bool session_ok = m_session.IsSessionAllowed(now, sess_reason);
      if(!session_ok)
      {
         if(m_log != NULL)
            m_log.NoTrade(sess_reason);
         setup.last_reject = sess_reason;
         return false;
      }

      if(m_ifvg.AlreadyUsed(setup.setup_id))
      {
         if(m_log != NULL)
            m_log.NoTrade("SetupID already executed");
         setup.last_reject = "SetupID already executed";
         return false;
      }

      string retest_reason = "";
      MqlRates entry_bars[];
      if(!IFVG_CopyRatesSafe(m_sym.SymbolName(), m_cfg.in.entry_tf, 3, entry_bars) || ArraySize(entry_bars) < 2)
      {
         if(m_log != NULL)
            m_log.NoTrade("entry bars unavailable");
         return false;
      }
      const bool retest_ok = m_ifvg.IsValidIFVGRetest(setup.ifvg, entry_bars[1], now, retest_reason);
      if(!retest_ok)
      {
         if(m_log != NULL)
            m_log.NoTrade(retest_reason == "" ? "IFVG without retest" : retest_reason);
         setup.last_reject = retest_reason;
         return false;
      }

      const double spread = m_sym.SpreadPoints();
      const SGateResult gate = CSetupValidator::ValidateConfluence(setup, *m_cfg, true,
                                                                   m_pos.CountOpen(),
                                                                   spread, true, true);
      if(!gate.passed)
      {
         if(m_log != NULL)
            m_log.NoTrade(gate.reason);
         setup.last_reject = gate.reason;
         return false;
      }

      const double entry = (setup.direction == IFVG_DIR_BUY) ? m_sym.Ask() : m_sym.Bid();
      if(!m_risk.BuildPlan(m_sym.Spec(), *m_sym, setup, entry, plan))
      {
         setup.last_reject = plan.reject_reason;
         return false;
      }

      if(plan.lot > IFVG_HARD_MAX_LOT)
      {
         if(m_log != NULL)
            m_log.NoTrade("lot exceeds hard cap 0.01");
         return false;
      }

      if(!m_trade.Open(*m_sym, plan, reason))
      {
         setup.last_reject = reason;
         return false;
      }

      setup.executed = true;
      setup.state = ST_ORDER_SENT;
      m_ifvg.MarkTraded(setup.ifvg);
      m_ifvg.RememberUsed(setup.setup_id);
      return true;
   }
};

#endif

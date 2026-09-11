#ifndef MM_BACKTESTSTATS_MQH
#define MM_BACKTESTSTATS_MQH

#include "Types.mqh"
#include "Logger.mqh"
#include "Persistence.mqh"
#include "Safety.mqh"

class CMMBacktestStats
{
private:
   SMMStats         m_s;
   CMMLogger       *m_log;
   CMMPersistence  *m_store;
   SMMOpenTrade     m_open[];

   void RecalcDD()
   {
      const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > m_s.peak_equity)
         m_s.peak_equity = eq;
      const double dd = m_s.peak_equity - eq;
      if(dd > m_s.max_dd)
         m_s.max_dd = dd;
   }

   string RiskKey(const ulong position_id) const
   {
      return MM_GV_RISK_POS + IntegerToString((long)position_id);
   }

   int FindOpen(const ulong position_id) const
   {
      const int n = ArraySize(m_open);
      for(int i = 0; i < n; i++)
      {
         if(m_open[i].position_id == position_id)
            return i;
      }
      return -1;
   }

public:
   CMMBacktestStats()
   {
      m_log = NULL;
      m_store = NULL;
      ArrayResize(m_open, 0);
   }

   void Init(CMMLogger *log, const double target_rr, CMMPersistence *store)
   {
      m_log = log;
      m_store = store;
      ZeroMemory(m_s);
      ArrayResize(m_open, 0);
      m_s.target_rr = target_rr;
      m_s.start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_s.peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   }

   void OnFvgDetected() { m_s.fvgs_detected++; }
   void OnFvgCorrectSide() { m_s.fvgs_correct_side++; }
   void OnFvgSelected() { m_s.fvgs_selected++; }
   void OnFvgInvalidated() { m_s.fvgs_invalidated++; }
   void OnFvgExpired() { m_s.fvgs_expired++; }
   void OnFvgTraded() { m_s.fvgs_traded++; }
   void OnValidSetup() { m_s.setups_valid++; }
   void OnSetupRejected() { m_s.setups_rejected++; }
   void OnOrderAttempt() { m_s.order_attempts++; }
   void OnOrderRejected() { m_s.orders_rejected++; }

   void OnTradeExecuted(const ENUM_MM_ENTRY_MODEL model)
   {
      m_s.trades_executed++;
      if(model == MM_MODEL_WICK)
         m_s.model1_executed++;
      if(model == MM_MODEL_MID)
         m_s.model2_executed++;
   }

   void RememberOpen(const SMMOpenTrade &t)
   {
      if(t.position_id == 0)
         return;
      const int idx = FindOpen(t.position_id);
      if(idx >= 0)
         m_open[idx] = t;
      else
      {
         const int n = ArraySize(m_open);
         ArrayResize(m_open, n + 1);
         m_open[n] = t;
      }
      if(m_store != NULL)
         m_store.SetDouble(RiskKey(t.position_id), t.risk_money);
   }

   bool RecallRiskMoney(const ulong position_id, double &risk_money)
   {
      risk_money = 0.0;
      const int idx = FindOpen(position_id);
      if(idx >= 0 && m_open[idx].risk_money > 0.0)
      {
         risk_money = m_open[idx].risk_money;
         return true;
      }
      if(m_store != NULL)
      {
         const double stored = m_store.GetDouble(RiskKey(position_id), 0.0);
         if(stored > 0.0)
         {
            risk_money = stored;
            return true;
         }
      }
      return false;
   }

   void ForgetOpen(const ulong position_id)
   {
      const int idx = FindOpen(position_id);
      if(idx >= 0)
      {
         const int n = ArraySize(m_open);
         for(int i = idx; i < n - 1; i++)
            m_open[i] = m_open[i + 1];
         ArrayResize(m_open, n - 1);
      }
      if(m_store != NULL)
         m_store.Delete(RiskKey(position_id));
   }

   void OnClosedDeal(const double profit, const double risk_money, const bool is_loss)
   {
      m_s.trades_closed++;
      if(is_loss)
      {
         m_s.losses++;
         m_s.gross_loss += MathAbs(profit);
         m_s.consec_loss++;
         if(m_s.consec_loss > m_s.max_consec_loss)
            m_s.max_consec_loss = m_s.consec_loss;
         if(risk_money > 0.0)
            m_s.total_r += CMMSafety::RealizedR(profit, risk_money);
      }
      else
      {
         m_s.wins++;
         m_s.gross_profit += MathMax(profit, 0.0);
         m_s.consec_loss = 0;
         if(risk_money > 0.0)
            m_s.total_r += CMMSafety::RealizedR(profit, risk_money);
      }
      RecalcDD();
   }

   SMMStats Snapshot() const { return m_s; }

   void PrintReport() const
   {
      const int t = m_s.trades_closed;
      const double wr = (t > 0) ? 100.0 * m_s.wins / (double)t : 0.0;
      const double pf = (m_s.gross_loss > 0.0) ? m_s.gross_profit / m_s.gross_loss : m_s.gross_profit;
      const double expc = (t > 0) ? (m_s.gross_profit - m_s.gross_loss) / (double)t : 0.0;
      const double avg_r = (t > 0) ? m_s.total_r / (double)t : 0.0;
      const double end_bal = AccountInfoDouble(ACCOUNT_BALANCE);
      PrintFormat("%s======== BACKTEST REPORT (Target RR 1:%.1f) ========", MM_LOG_PREFIX, m_s.target_rr);
      PrintFormat("%sFVGs detected: %d", MM_LOG_PREFIX, m_s.fvgs_detected);
      PrintFormat("%sFVGs correct side: %d", MM_LOG_PREFIX, m_s.fvgs_correct_side);
      PrintFormat("%sFVGs selected: %d", MM_LOG_PREFIX, m_s.fvgs_selected);
      PrintFormat("%sFVGs invalidated: %d", MM_LOG_PREFIX, m_s.fvgs_invalidated);
      PrintFormat("%sFVGs expired: %d", MM_LOG_PREFIX, m_s.fvgs_expired);
      PrintFormat("%sValid setups: %d", MM_LOG_PREFIX, m_s.setups_valid);
      PrintFormat("%sRejected: %d", MM_LOG_PREFIX, m_s.setups_rejected);
      PrintFormat("%sEntry model1: %d", MM_LOG_PREFIX, m_s.model1_executed);
      PrintFormat("%sEntry model2: %d", MM_LOG_PREFIX, m_s.model2_executed);
      PrintFormat("%sFVGs traded: %d  Order attempts: %d  Rejected orders: %d  Executed trades: %d",
                  MM_LOG_PREFIX, m_s.fvgs_traded, m_s.order_attempts, m_s.orders_rejected, m_s.trades_executed);
      PrintFormat("%sClosed trades: %d  Wins: %d  Losses: %d  WinRate: %.2f%%", MM_LOG_PREFIX,
                  t, m_s.wins, m_s.losses, wr);
      PrintFormat("%sProfit factor: %.3f  Expectancy: %.2f", MM_LOG_PREFIX, pf, expc);
      PrintFormat("%sMax DD: %.2f  Max consec losses: %d", MM_LOG_PREFIX, m_s.max_dd, m_s.max_consec_loss);
      PrintFormat("%sAverage R: %.3f  Total R: %.3f", MM_LOG_PREFIX, avg_r, m_s.total_r);
      PrintFormat("%sStart balance: %.2f  End balance: %.2f", MM_LOG_PREFIX, m_s.start_balance, end_bal);
   }

   double OnTester() const
   {
      if(m_s.trades_closed <= 0)
         return 0.0;
      const double wr = (double)m_s.wins / (double)m_s.trades_closed;
      const double pf = (m_s.gross_loss > 0.0) ? m_s.gross_profit / m_s.gross_loss : 0.0;
      return wr * pf * m_s.total_r;
   }
};

#endif

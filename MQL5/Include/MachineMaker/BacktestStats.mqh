#ifndef MM_BACKTESTSTATS_MQH
#define MM_BACKTESTSTATS_MQH

#include "Types.mqh"
#include "Logger.mqh"

class CMMBacktestStats
{
private:
   SMMStats    m_s;
   CMMLogger  *m_log;

   void RecalcDD()
   {
      const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > m_s.peak_equity)
         m_s.peak_equity = eq;
      const double dd = m_s.peak_equity - eq;
      if(dd > m_s.max_dd)
         m_s.max_dd = dd;
   }

public:
   void Init(CMMLogger *log, const double target_rr)
   {
      m_log = log;
      ZeroMemory(m_s);
      m_s.target_rr = target_rr;
      m_s.start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_s.peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   }

   void OnValidSetup() { m_s.setups_valid++; }
   void OnRejected() { m_s.setups_rejected++; }
   void OnFvgSeen() { m_s.fvgs_seen++; }
   void OnFvgInvalidated() { m_s.fvgs_invalidated++; }
   void OnModel(const ENUM_MM_ENTRY_MODEL m)
   {
      if(m == MM_MODEL_WICK) m_s.model1++;
      if(m == MM_MODEL_MID) m_s.model2++;
   }
   void OnWithdrawalLock() { m_s.withdrawal_locks++; }

   void OnClosedDeal(const double profit, const double risk_money, const bool is_loss)
   {
      m_s.trades++;
      if(is_loss)
      {
         m_s.losses++;
         m_s.gross_loss += MathAbs(profit);
         m_s.consec_loss++;
         if(m_s.consec_loss > m_s.max_consec_loss)
            m_s.max_consec_loss = m_s.consec_loss;
         if(risk_money > 0.0)
            m_s.total_r -= MathAbs(profit) / risk_money;
      }
      else
      {
         m_s.wins++;
         m_s.gross_profit += MathMax(profit, 0.0);
         m_s.consec_loss = 0;
         if(risk_money > 0.0)
            m_s.total_r += profit / risk_money;
      }
      RecalcDD();
   }

   SMMStats Snapshot() const { return m_s; }

   void PrintReport() const
   {
      const int t = m_s.trades;
      const double wr = (t > 0) ? 100.0 * m_s.wins / (double)t : 0.0;
      const double pf = (m_s.gross_loss > 0.0) ? m_s.gross_profit / m_s.gross_loss : m_s.gross_profit;
      const double expc = (t > 0) ? (m_s.gross_profit - m_s.gross_loss) / (double)t : 0.0;
      const double avg_r = (t > 0) ? m_s.total_r / (double)t : 0.0;
      const double end_bal = AccountInfoDouble(ACCOUNT_BALANCE);
      PrintFormat("%s======== BACKTEST REPORT (Target RR 1:%.1f) ========", MM_LOG_PREFIX, m_s.target_rr);
      PrintFormat("%sTrades: %d  Wins: %d  Losses: %d  WinRate: %.2f%%", MM_LOG_PREFIX, t, m_s.wins, m_s.losses, wr);
      PrintFormat("%sProfit factor: %.3f  Expectancy: %.2f", MM_LOG_PREFIX, pf, expc);
      PrintFormat("%sMax DD: %.2f  Max consec losses: %d", MM_LOG_PREFIX, m_s.max_dd, m_s.max_consec_loss);
      PrintFormat("%sAverage R: %.3f  Total R: %.3f", MM_LOG_PREFIX, avg_r, m_s.total_r);
      PrintFormat("%sStart balance: %.2f  End balance: %.2f", MM_LOG_PREFIX, m_s.start_balance, end_bal);
      PrintFormat("%sFVGs: %d  Valid setups: %d  Invalidated: %d  Rejected: %d", MM_LOG_PREFIX,
                  m_s.fvgs_seen, m_s.setups_valid, m_s.fvgs_invalidated, m_s.setups_rejected);
      PrintFormat("%sEntry model1: %d  model2: %d  Withdrawal locks: %d", MM_LOG_PREFIX,
                  m_s.model1, m_s.model2, m_s.withdrawal_locks);
   }

   double OnTester() const
   {
      if(m_s.trades <= 0)
         return 0.0;
      const double wr = (double)m_s.wins / (double)m_s.trades;
      const double pf = (m_s.gross_loss > 0.0) ? m_s.gross_profit / m_s.gross_loss : 0.0;
      return wr * pf * m_s.total_r;
   }
};

#endif

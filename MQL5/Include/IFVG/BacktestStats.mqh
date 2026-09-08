#ifndef IFVG_BACKTESTSTATS_MQH
#define IFVG_BACKTESTSTATS_MQH

#include "Types.mqh"
#include "Logger.mqh"

class CBacktestStats
{
private:
   SBacktestSnapshot m_s;
   CIFVGLogger      *m_log;
   long              m_magic;
   string            m_symbol;
   double            m_start_balance;

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
   CBacktestStats()
   {
      ZeroMemory(m_s);
      m_log = NULL;
      m_start_balance = 0;
   }

   void Init(CIFVGLogger *log, const long magic, const string symbol, const double target_rr)
   {
      m_log = log;
      m_magic = magic;
      m_symbol = symbol;
      ZeroMemory(m_s);
      m_s.target_rr = target_rr;
      m_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_s.peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   }

   void OnValidSetup() { m_s.setups_valid++; }
   void OnRejected()   { m_s.setups_rejected++; }

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
         {
            const double r = profit / risk_money;
            m_s.total_r += r;
            m_s.sum_r_wins += r;
         }
      }
      RecalcDD();
   }

   SBacktestSnapshot Snapshot() const { return m_s; }

   void PrintReport() const
   {
      const int t = m_s.trades;
      const double wr = (t > 0) ? 100.0 * m_s.wins / (double)t : 0.0;
      const double lr = (t > 0) ? 100.0 * m_s.losses / (double)t : 0.0;
      const double pf = (m_s.gross_loss > 0.0) ? m_s.gross_profit / m_s.gross_loss : m_s.gross_profit;
      const double expc = (t > 0) ? (m_s.gross_profit - m_s.gross_loss) / (double)t : 0.0;
      const double avg_r = (t > 0) ? m_s.total_r / (double)t : 0.0;

      PrintFormat("%s======== BACKTEST REPORT (Target RR 1:%.1f) ========", IFVG_LOG_PREFIX, m_s.target_rr);
      PrintFormat("%sTrades: %d  Wins: %d  Losses: %d", IFVG_LOG_PREFIX, t, m_s.wins, m_s.losses);
      PrintFormat("%sWin rate: %.2f%%  Loss rate: %.2f%%", IFVG_LOG_PREFIX, wr, lr);
      PrintFormat("%sProfit factor: %.3f  Expectancy: %.2f", IFVG_LOG_PREFIX, pf, expc);
      PrintFormat("%sMax DD: %.2f  Max consec losses: %d", IFVG_LOG_PREFIX, m_s.max_dd, m_s.max_consec_loss);
      PrintFormat("%sAverage R: %.3f  Total R: %.3f", IFVG_LOG_PREFIX, avg_r, m_s.total_r);
      PrintFormat("%sSetups valid: %d  Setups rejected: %d", IFVG_LOG_PREFIX, m_s.setups_valid, m_s.setups_rejected);
      PrintFormat("%sDo not mix this report with another TargetRR run.", IFVG_LOG_PREFIX);
   }

   double OnTester() const
   {
      const int t = m_s.trades;
      if(t <= 0)
         return 0.0;
      const double wr = (double)m_s.wins / (double)t;
      const double pf = (m_s.gross_loss > 0.0) ? m_s.gross_profit / m_s.gross_loss : 0.0;
      return wr * pf * m_s.total_r;
   }
};

#endif

#ifndef IFVG_POSITIONMANAGER_MQH
#define IFVG_POSITIONMANAGER_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Safety.mqh"

class CPositionManager
{
private:
   CIFVGConfig  *m_cfg;
   CIFVGLogger  *m_log;
   string        m_symbol;
   long          m_magic;
   ulong         m_known_tickets[64];
   int           m_known_n;
   bool          m_known_loss[64];

   bool IsOurs(const ulong ticket) const
   {
      if(!PositionSelectByTicket(ticket))
         return false;
      if((long)PositionGetInteger(POSITION_MAGIC) != m_magic)
         return false;
      if(PositionGetString(POSITION_SYMBOL) != m_symbol)
         return false;
      return true;
   }

public:
   CPositionManager()
   {
      m_known_n = 0;
   }

   void Init(CIFVGConfig *cfg, CIFVGLogger *log, const string symbol)
   {
      m_cfg = cfg;
      m_log = log;
      m_symbol = symbol;
      m_magic = cfg.in.magic;
      Snapshot();
   }

   int CountOpen() const
   {
      int c = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         c++;
      }
      return c;
   }

   bool CanOpenAnother(string &reason) const
   {
      const int open_n = CountOpen();
      if(!CIFVGSafety::CanOpenNewPosition(open_n, m_cfg.in.max_positions))
      {
         reason = "2 positions already open";
         return false;
      }
      return true;
   }

   void Snapshot()
   {
      m_known_n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!IsOurs(ticket))
            continue;
         if(m_known_n >= 64)
            break;
         m_known_tickets[m_known_n] = ticket;
         m_known_loss[m_known_n] = false;
         m_known_n++;
      }
   }

   int SyncClosed(bool &loss_flags[], int &n_closed)
   {
      n_closed = 0;
      ArrayResize(loss_flags, 8);
      ulong still[64];
      int still_n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!IsOurs(ticket))
            continue;
         if(still_n < 64)
            still[still_n++] = ticket;
      }

      for(int k = 0; k < m_known_n; k++)
      {
         bool found = false;
         for(int s = 0; s < still_n; s++)
         {
            if(still[s] == m_known_tickets[k])
            {
               found = true;
               break;
            }
         }
         if(found)
            continue;

         bool is_loss = false;
         if(HistorySelect(TimeCurrent() - 86400 * 14, TimeCurrent() + 60))
         {
            const int deals = HistoryDealsTotal();
            for(int d = deals - 1; d >= 0; d--)
            {
               const ulong deal = HistoryDealGetTicket(d);
               if(deal == 0)
                  continue;
               if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != m_magic)
                  continue;
               if(HistoryDealGetInteger(deal, DEAL_POSITION_ID) != (long)m_known_tickets[k] &&
                  HistoryDealGetInteger(deal, DEAL_POSITION_ID) != (long)HistoryDealGetInteger(deal, DEAL_POSITION_ID))
               {
               }
               if(HistoryDealGetString(deal, DEAL_SYMBOL) != m_symbol)
                  continue;
               if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT &&
                  HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_INOUT)
                  continue;
               const double profit = HistoryDealGetDouble(deal, DEAL_PROFIT) +
                                     HistoryDealGetDouble(deal, DEAL_SWAP) +
                                     HistoryDealGetDouble(deal, DEAL_COMMISSION);
               is_loss = (profit < 0.0);
               const long reason = HistoryDealGetInteger(deal, DEAL_REASON);
               if(reason == DEAL_REASON_SL)
                  is_loss = true;
               break;
            }
         }
         if(n_closed < 8)
         {
            loss_flags[n_closed] = is_loss;
            n_closed++;
         }
      }

      m_known_n = 0;
      for(int s = 0; s < still_n; s++)
      {
         m_known_tickets[m_known_n] = still[s];
         m_known_n++;
      }
      return n_closed;
   }
};

#endif

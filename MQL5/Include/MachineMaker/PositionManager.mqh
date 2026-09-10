#ifndef MM_POSITIONMANAGER_MQH
#define MM_POSITIONMANAGER_MQH

#include "Config.mqh"
#include "Safety.mqh"

class CMMPositionManager
{
private:
   CMMConfig *m_cfg;
   string     m_symbol;
   long       m_magic;

public:
   void Init(CMMConfig *cfg, const string symbol)
   {
      m_cfg = cfg;
      m_symbol = symbol;
      m_magic = cfg.in.magic;
   }

   int CountOpen() const
   {
      int c = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
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
      if(!CMMSafety::CanOpenNewPosition(CountOpen(), m_cfg.in.max_positions))
      {
         reason = "2 positions already open";
         return false;
      }
      return true;
   }
};

#endif

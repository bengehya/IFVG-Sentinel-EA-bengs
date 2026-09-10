#ifndef MM_CAPITALGUARD_MQH
#define MM_CAPITALGUARD_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Persistence.mqh"
#include "Safety.mqh"

class CMMCapitalGuard
{
private:
   CMMConfig       *m_cfg;
   CMMLogger       *m_log;
   CMMPersistence  *m_store;
   double           m_start;
   double           m_target;
   bool             m_locked;
   string           m_last_fp;

   void Persist()
   {
      if(m_store == NULL)
         return;
      m_store.SetDouble(MM_GV_START_CAP, m_start);
      m_store.SetDouble(MM_GV_TARGET_CAP, m_target);
      m_store.SetInt(MM_GV_CAP_LOCKED, m_locked ? 1 : 0);
   }

   void LogStatus(const double balance)
   {
      if(m_log == NULL)
         return;
      const string fp = DoubleToString(m_start, 2) + "|" + DoubleToString(m_target, 2) + "|" +
                        DoubleToString(balance, 2) + "|" + IntegerToString(m_locked ? 1 : 0);
      if(fp == m_last_fp)
         return;
      m_last_fp = fp;
      m_log.Capital("StartingCapital=" + DoubleToString(m_start, 2));
      m_log.Capital("5XTarget=" + DoubleToString(m_target, 2));
      m_log.Capital("CurrentBalance=" + DoubleToString(balance, 2));
      m_log.Capital("Status=" + (m_locked ? "WITHDRAWAL_REQUIRED" : "ACTIVE"));
   }

public:
   CMMCapitalGuard()
   {
      m_cfg = NULL;
      m_log = NULL;
      m_store = NULL;
      m_start = 0.0;
      m_target = 0.0;
      m_locked = false;
      m_last_fp = "";
   }

   void Init(CMMConfig *cfg, CMMLogger *log, CMMPersistence *store)
   {
      m_cfg = cfg;
      m_log = log;
      m_store = store;
      const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(cfg.in.reset_capital_lock)
      {
         m_start = (balance > 0.0 ? balance : MM_DEFAULT_STARTING_CAPITAL);
         m_locked = false;
         if(m_log != NULL)
            m_log.Warn("CAPITAL LOCK RESET — new base=" + DoubleToString(m_start, 2) +
                       " — set InpResetCapitalLock=false after this init");
      }
      else
      {
         m_start = store.GetDouble(MM_GV_START_CAP, 0.0);
         m_locked = (store.GetInt(MM_GV_CAP_LOCKED, 0) != 0);
         if(m_start <= 0.0)
         {
            if(cfg.in.starting_capital > 0.0)
               m_start = cfg.in.starting_capital;
            else
               m_start = (balance > 0.0 ? balance : MM_DEFAULT_STARTING_CAPITAL);
         }
      }
      m_target = m_start * cfg.in.capital_multiple;
      if(!m_locked && CMMSafety::CapitalTargetReached(m_start, cfg.in.capital_multiple, balance, equity))
         m_locked = true;
      Persist();
      LogStatus(balance);
   }

   void Evaluate(const double balance, const double equity)
   {
      if(!m_locked && CMMSafety::CapitalTargetReached(m_start, m_cfg.in.capital_multiple, balance, equity))
      {
         m_locked = true;
         Persist();
      }
      LogStatus(balance);
   }

   bool Locked() const { return m_locked; }
   double StartingCapital() const { return m_start; }
   double Target() const { return m_target; }
};

#endif

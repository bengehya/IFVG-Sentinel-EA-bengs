#ifndef MM_COOLDOWNMANAGER_MQH
#define MM_COOLDOWNMANAGER_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Persistence.mqh"
#include "Safety.mqh"

class CMMCooldownManager
{
private:
   CMMConfig      *m_cfg;
   CMMLogger      *m_log;
   CMMPersistence *m_store;
   int             m_consec_sl;
   datetime        m_cd_start;
   datetime        m_cd_end;

   void Persist()
   {
      if(m_store == NULL)
         return;
      m_store.SetInt(MM_GV_CONSEC_SL, m_consec_sl);
      m_store.SetTime(MM_GV_COOLDOWN_START, m_cd_start);
      m_store.SetTime(MM_GV_COOLDOWN_END, m_cd_end);
   }

public:
   CMMCooldownManager()
   {
      m_consec_sl = 0;
      m_cd_start = 0;
      m_cd_end = 0;
   }

   void Init(CMMConfig *cfg, CMMLogger *log, CMMPersistence *store)
   {
      m_cfg = cfg;
      m_log = log;
      m_store = store;
      m_consec_sl = store.GetInt(MM_GV_CONSEC_SL, 0);
      m_cd_start = store.GetTime(MM_GV_COOLDOWN_START, 0);
      m_cd_end = store.GetTime(MM_GV_COOLDOWN_END, 0);
      if(m_cd_start > 0 && m_cd_end <= 0)
         m_cd_end = CMMSafety::CooldownEndFromStart(m_cd_start, m_cfg.in.cooldown_hours);
   }

   bool Active(const datetime now) const
   {
      return CMMSafety::IsCooldownActive(now, m_cd_end);
   }

   datetime EndTime() const { return m_cd_end; }
   int ConsecutiveSL() const { return m_consec_sl; }

   string RemainingLabel(const datetime now) const
   {
      if(!Active(now))
         return "0";
      const int s = (int)(m_cd_end - now);
      return IntegerToString(s / 3600) + "h " + IntegerToString((s % 3600) / 60) + "m";
   }

   void OnClosedTrade(const bool is_loss, const datetime now)
   {
      if(is_loss)
      {
         m_consec_sl = CMMSafety::OnPositionClosedSL(m_consec_sl);
         if(CMMSafety::ShouldEnterCooldown(m_consec_sl, m_cfg.in.consec_sl_limit))
         {
            m_cd_start = now;
            m_cd_end = CMMSafety::CooldownEndFromStart(now, m_cfg.in.cooldown_hours);
            if(m_log != NULL)
               m_log.Info("COOLDOWN 8h after 2 consecutive SL");
         }
      }
      else
         m_consec_sl = CMMSafety::OnPositionClosedWin(m_consec_sl);
      Persist();
   }

   bool AllowsEntry(const datetime now, string &reason) const
   {
      if(Active(now))
      {
         reason = "8H cooldown active";
         return false;
      }
      return true;
   }
};

#endif

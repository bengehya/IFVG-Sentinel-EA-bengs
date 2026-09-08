#ifndef IFVG_COOLDOWNMANAGER_MQH
#define IFVG_COOLDOWNMANAGER_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "Persistence.mqh"
#include "Safety.mqh"

class CCooldownManager
{
private:
   CIFVGConfig       *m_cfg;
   CIFVGLogger       *m_log;
   CIFVGPersistence  *m_store;
   int                m_consec_sl;
   datetime           m_cd_start;
   datetime           m_cd_end;

   void Persist()
   {
      if(m_store == NULL)
         return;
      m_store.SetInt(IFVG_GV_CONSEC_SL, m_consec_sl);
      m_store.SetTime(IFVG_GV_COOLDOWN_START, m_cd_start);
      m_store.SetTime(IFVG_GV_COOLDOWN_END, m_cd_end);
   }

public:
   CCooldownManager()
   {
      m_consec_sl = 0;
      m_cd_start = 0;
      m_cd_end = 0;
   }

   void Init(CIFVGConfig *cfg, CIFVGLogger *log, CIFVGPersistence *store)
   {
      m_cfg = cfg;
      m_log = log;
      m_store = store;
      Load();
   }

   void Load()
   {
      if(m_store == NULL)
         return;
      m_consec_sl = m_store.GetInt(IFVG_GV_CONSEC_SL, 0);
      m_cd_start = m_store.GetTime(IFVG_GV_COOLDOWN_START, 0);
      m_cd_end = m_store.GetTime(IFVG_GV_COOLDOWN_END, 0);
      if(m_cd_start > 0 && m_cd_end <= 0)
         m_cd_end = CIFVGSafety::CooldownEndFromStart(m_cd_start, m_cfg.in.cooldown_hours);
   }

   bool Active(const datetime now) const
   {
      return CIFVGSafety::IsCooldownActive(now, m_cd_end);
   }

   datetime EndTime() const { return m_cd_end; }
   datetime StartTime() const { return m_cd_start; }
   int ConsecutiveSL() const { return m_consec_sl; }

   int RemainingSeconds(const datetime now) const
   {
      if(!Active(now))
         return 0;
      return (int)(m_cd_end - now);
   }

   string RemainingLabel(const datetime now) const
   {
      const int s = RemainingSeconds(now);
      if(s <= 0)
         return "0";
      const int h = s / 3600;
      const int m = (s % 3600) / 60;
      return IntegerToString(h) + "h " + IntegerToString(m) + "m";
   }

   void OnClosedTrade(const bool is_loss, const datetime now)
   {
      if(is_loss)
      {
         m_consec_sl = CIFVGSafety::OnPositionClosedSL(m_consec_sl);
         if(m_log != NULL)
            m_log.Decision("Consecutive SL", IntegerToString(m_consec_sl));
         if(CIFVGSafety::ShouldEnterCooldown(m_consec_sl, m_cfg.in.consec_sl_limit))
         {
            m_cd_start = now;
            m_cd_end = CIFVGSafety::CooldownEndFromStart(now, m_cfg.in.cooldown_hours);
            if(m_log != NULL)
               m_log.Decision("COOLDOWN MODE",
                              "start=" + TimeToString(m_cd_start, TIME_DATE | TIME_MINUTES) +
                              " end=" + TimeToString(m_cd_end, TIME_DATE | TIME_MINUTES));
         }
      }
      else
      {
         m_consec_sl = CIFVGSafety::OnPositionClosedWin(m_consec_sl);
         if(m_log != NULL)
            m_log.Decision("Consecutive SL", "reset to 0 (win)");
      }
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

#ifndef IFVG_SESSIONMANAGER_MQH
#define IFVG_SESSIONMANAGER_MQH

#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Session filter. All hour inputs are interpreted in the timezone  |
//| selected by InpSessionTimezone. Conversion uses InpUtcOffsetHours|
//| as (server_time - UTC). Documented, never implicit.              |
//|                                                                   |
//| TZ_SERVER : hours are broker server clock                         |
//| TZ_UTC    : hours are UTC; server = UTC + utc_offset_hours        |
//| TZ_LONDON : UTC+0 winter / UTC+1 summer is NOT auto-DST.          |
//|             Configure utc_offset + hours explicitly.              |
//| TZ_NY     : same — no silent DST.                                 |
//| TZ_ASIAN  : same.                                                 |
//+------------------------------------------------------------------+
class CSessionManager
{
private:
   CIFVGConfig  *m_cfg;
   CIFVGLogger  *m_log;

   datetime ToUtc(const datetime server_time) const
   {
      return server_time - (datetime)(m_cfg.in.utc_offset_hours * IFVG_SECONDS_PER_HOUR);
   }

   int HourInSelectedTz(const datetime server_time, int &minute) const
   {
      datetime t = server_time;
      switch(m_cfg.in.session_timezone)
      {
         case TZ_UTC:
            t = ToUtc(server_time);
            break;
         case TZ_LONDON:
            t = ToUtc(server_time);
            break;
         case TZ_NY:
            t = ToUtc(server_time);
            break;
         case TZ_ASIAN:
            t = ToUtc(server_time);
            break;
         case TZ_SERVER:
         default:
            break;
      }
      MqlDateTime dt;
      TimeToStruct(t, dt);
      minute = dt.min;
      return dt.hour;
   }

   bool InWindow(const int hour, const int minute,
                 const int sh, const int sm, const int eh, const int em) const
   {
      const int nowm = hour * 60 + minute;
      const int startm = sh * 60 + sm;
      const int endm = eh * 60 + em;
      if(startm == endm)
         return true;
      if(startm < endm)
         return (nowm >= startm && nowm < endm);
      return (nowm >= startm || nowm < endm);
   }

public:
   void Init(CIFVGConfig *cfg, CIFVGLogger *log)
   {
      m_cfg = cfg;
      m_log = log;
   }

   bool IsSessionAllowed(const datetime server_time, string &reason) const
   {
      reason = "";
      int minute = 0;
      const int hour = HourInSelectedTz(server_time, minute);

      if(!InWindow(hour, minute,
                   m_cfg.in.session_start_hour, m_cfg.in.session_start_minute,
                   m_cfg.in.session_end_hour, m_cfg.in.session_end_minute))
      {
         reason = "outside configured trading window";
         return false;
      }

      bool named_ok = true;
      if(m_cfg.in.trade_london || m_cfg.in.trade_ny || m_cfg.in.trade_asian)
      {
         named_ok = false;
         const datetime utc = ToUtc(server_time);
         MqlDateTime dt;
         TimeToStruct(utc, dt);
         const int uh = dt.hour;
         if(m_cfg.in.trade_asian && uh >= 0 && uh < 8)
            named_ok = true;
         if(m_cfg.in.trade_london && uh >= 7 && uh < 16)
            named_ok = true;
         if(m_cfg.in.trade_ny && uh >= 12 && uh < 21)
            named_ok = true;
      }

      if(!named_ok)
      {
         reason = "outside allowed named sessions (hours in UTC, no auto-DST)";
         return false;
      }
      return true;
   }
};

#endif

#ifndef IFVG_LOGGER_MQH
#define IFVG_LOGGER_MQH

#include "Constants.mqh"

enum ENUM_IFVG_LOG_LEVEL
{
   LOG_ERROR = 0,
   LOG_WARN  = 1,
   LOG_INFO  = 2,
   LOG_DEBUG = 3
};

class CIFVGLogger
{
private:
   bool                 m_enabled;
   bool                 m_debug;
   bool                 m_to_file;
   int                  m_file;
   string               m_file_name;
   ENUM_IFVG_LOG_LEVEL  m_level;

   void WriteLine(const ENUM_IFVG_LOG_LEVEL level, const string msg)
   {
      if(!m_enabled)
         return;
      if(level > m_level)
         return;
      if(level == LOG_DEBUG && !m_debug)
         return;

      const string line = IFVG_LOG_PREFIX + msg;
      Print(line);

      if(m_to_file && m_file != INVALID_HANDLE)
      {
         const string stamped = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " " + line;
         FileWriteString(m_file, stamped + "\r\n");
         FileFlush(m_file);
      }
   }

public:
   CIFVGLogger()
   {
      m_enabled = true;
      m_debug = false;
      m_to_file = false;
      m_file = INVALID_HANDLE;
      m_file_name = "";
      m_level = LOG_INFO;
   }

   ~CIFVGLogger()
   {
      Close();
   }

   void Init(const bool enabled, const bool debug, const bool to_file, const string symbol)
   {
      m_enabled = enabled;
      m_debug = debug;
      m_level = debug ? LOG_DEBUG : LOG_INFO;
      Close();
      m_to_file = to_file;
      if(m_to_file)
      {
         m_file_name = "IFVG_Sentinel_" + symbol + "_" +
                       IntegerToString((int)TimeCurrent()) + ".log";
         m_file = FileOpen(m_file_name, FILE_WRITE | FILE_TXT | FILE_ANSI);
         if(m_file == INVALID_HANDLE)
            m_to_file = false;
      }
   }

   void Close()
   {
      if(m_file != INVALID_HANDLE)
      {
         FileClose(m_file);
         m_file = INVALID_HANDLE;
      }
   }

   void Info(const string msg)  { WriteLine(LOG_INFO, msg); }
   void Warn(const string msg)  { WriteLine(LOG_WARN, "WARN " + msg); }
   void Error(const string msg) { WriteLine(LOG_ERROR, "ERROR " + msg); }
   void Debug(const string msg) { WriteLine(LOG_DEBUG, "DEBUG " + msg); }

   void NoTrade(const string reason)
   {
      WriteLine(LOG_INFO, "NO TRADE — " + reason);
   }

   void Decision(const string stage, const string detail)
   {
      WriteLine(LOG_INFO, stage + (detail == "" ? "" : ": " + detail));
   }

   void Chain(const string name, const string verdict, const string detail = "")
   {
      if(detail == "")
         WriteLine(LOG_INFO, name + " = " + verdict);
      else
         WriteLine(LOG_INFO, name + " = " + verdict + " — " + detail);
   }
};

#endif

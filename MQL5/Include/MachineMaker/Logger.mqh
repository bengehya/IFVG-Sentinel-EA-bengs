#ifndef MM_LOGGER_MQH
#define MM_LOGGER_MQH

#include "Constants.mqh"

class CMMLogger
{
private:
   bool m_enabled;
   bool m_debug;
   bool m_to_file;
   int  m_file;

   void WritePrefixed(const string prefix, const string msg)
   {
      if(!m_enabled)
         return;
      Print(prefix + msg);
      if(m_to_file && m_file != INVALID_HANDLE)
      {
         FileWriteString(m_file, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " " + prefix + msg + "\r\n");
         FileFlush(m_file);
      }
   }

public:
   CMMLogger()
   {
      m_enabled = true;
      m_debug = false;
      m_to_file = false;
      m_file = INVALID_HANDLE;
   }

   void Init(const bool enabled, const bool debug, const bool to_file, const string symbol)
   {
      m_enabled = enabled;
      m_debug = debug;
      if(m_file != INVALID_HANDLE)
      {
         FileClose(m_file);
         m_file = INVALID_HANDLE;
      }
      m_to_file = to_file;
      if(m_to_file)
      {
         m_file = FileOpen("MachineMaker_" + symbol + "_" + IntegerToString((int)TimeCurrent()) + ".log",
                           FILE_WRITE | FILE_TXT | FILE_ANSI);
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

   void Info(const string msg)  { WritePrefixed(MM_LOG_PREFIX, msg); }
   void Warn(const string msg)  { WritePrefixed(MM_LOG_PREFIX, "WARN " + msg); }
   void Error(const string msg) { WritePrefixed(MM_LOG_PREFIX, "ERROR " + msg); }
   void Debug(const string msg) { if(m_debug) WritePrefixed(MM_LOG_PREFIX, "DEBUG " + msg); }
   void NoTrade(const string reason) { WritePrefixed(MM_LOG_PREFIX, "NO TRADE — " + reason); }
   void State(const string msg) { WritePrefixed("[MACHINE MAKER][STATE] ", msg); }
   void Direction(const string msg) { WritePrefixed("[MACHINE MAKER][DIRECTION] ", msg); }
   void Fib(const string msg) { WritePrefixed("[MACHINE MAKER][FIB] ", msg); }
   void Fvg(const string msg) { WritePrefixed("[MACHINE MAKER][FVG] ", msg); }
   void Entry(const string msg) { WritePrefixed("[MACHINE MAKER][ENTRY] ", msg); }
   void Risk(const string msg) { WritePrefixed("[MACHINE MAKER][RISK] ", msg); }
   void Capital(const string msg) { WritePrefixed("[MACHINE MAKER][CAPITAL] ", msg); }
   void Sl(const string msg) { WritePrefixed("[MACHINE MAKER][SL] ", msg); }
};

#endif

#ifndef MM_DASHBOARD_MQH
#define MM_DASHBOARD_MQH

#include "StateMachine.mqh"
#include "CooldownManager.mqh"
#include "PositionManager.mqh"

class CMMDashboard
{
private:
   bool   m_enabled;
   string m_prefix;
   int    m_x;
   int    m_y;

   void Label(const string name, const int row, const string text, const color clr, const int size = 9)
   {
      const string id = m_prefix + name;
      if(ObjectFind(0, id) < 0)
      {
         ObjectCreate(0, id, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, id, OBJPROP_XDISTANCE, m_x + 12);
      ObjectSetInteger(0, id, OBJPROP_YDISTANCE, m_y + 10 + row * 16);
      ObjectSetInteger(0, id, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, id, OBJPROP_FONTSIZE, size);
      ObjectSetString(0, id, OBJPROP_FONT, "Consolas");
      ObjectSetString(0, id, OBJPROP_TEXT, text);
   }

public:
   CMMDashboard()
   {
      m_enabled = false;
      m_prefix = MM_DASH_PREFIX;
      m_x = 12;
      m_y = 24;
   }

   void Init(const bool enabled) { m_enabled = enabled; }
   void Destroy() { ObjectsDeleteAll(0, m_prefix); }

   void Render(const string symbol, const CMMStateMachine &sm, const CMMCooldownManager &cd,
               const CMMPositionManager &pos, const CMMConfig &cfg)
   {
      if(!m_enabled)
         return;
      const SMMSetup s = sm.Setup();
      color stclr = clrSilver;
      if(s.state == MM_ST_WAITING_FOR_RETEST)
         stclr = clrGold;
      if(s.state == MM_ST_POSITION_ACTIVE)
         stclr = clrLime;
      if(s.state == MM_ST_COOLDOWN)
         stclr = clrOrangeRed;
      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      const double allowed = cfg.AllowedRiskMoney(equity);
      Label("T", 0, "MACHINE MAKER", C'201,162,39', 11);
      Label("S", 1, "Status: " + MM_StateToString(s.state), stclr, 10);
      Label("SY", 2, "Symbol: " + symbol + "  [GOLD-ONLY]", clrWhite);
      Label("D", 3, "Daily: " + MM_BiasToString(s.dir.daily) + "  H4: " + MM_BiasToString(s.dir.h4), clrWhite);
      Label("F", 4, "Fib 50/62: " + DoubleToString(s.fib.fib_50, 2) + " / " + DoubleToString(s.fib.fib_62, 2), clrWhite);
      Label("G", 5, "FVG: " + (s.fvg.id > 0 ? DoubleToString(s.fvg.low, 2) + "-" + DoubleToString(s.fvg.high, 2) : "none"), clrSilver);
      Label("P", 6, "POSITIONS: " + IntegerToString(pos.CountOpen()) + " / " + IntegerToString(cfg.in.max_positions), clrAqua);
      Label("RR", 7, "TARGET RR: 1:" + DoubleToString(cfg.in.target_rr, 1), clrAqua);
      Label("CD", 8, "Cooldown: " + cd.RemainingLabel(TimeCurrent()), cd.Active(TimeCurrent()) ? clrOrangeRed : clrSilver);
      Label("RSK", 9, "Risk: " + DoubleToString(cfg.in.risk_percent, 1) + "% of " +
            DoubleToString(equity, 2) + " = " + DoubleToString(allowed, 2) + " " +
            AccountInfoString(ACCOUNT_CURRENCY), clrLime);
      Label("RJ", 10, "Last: " + (s.last_reject == "" ? "-" : s.last_reject), clrGray);
      ChartRedraw(0);
   }
};

#endif

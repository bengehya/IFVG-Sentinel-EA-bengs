#ifndef IFVG_DASHBOARD_MQH
#define IFVG_DASHBOARD_MQH

#include "StateMachine.mqh"
#include "CooldownManager.mqh"
#include "PositionManager.mqh"

class CDashboard
{
private:
   bool              m_enabled;
   string            m_prefix;
   int               m_x;
   int               m_y;

   void Label(const string name, const int row, const string text, const color clr, const int size = 9)
   {
      const string id = m_prefix + name;
      if(ObjectFind(0, id) < 0)
      {
         ObjectCreate(0, id, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, id, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
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

   void Panel(const int height)
   {
      const string id = m_prefix + "BG";
      if(ObjectFind(0, id) < 0)
      {
         ObjectCreate(0, id, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, id, OBJPROP_BGCOLOR, C'12,16,24');
         ObjectSetInteger(0, id, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(0, id, OBJPROP_BORDER_COLOR, C'201,162,39');
         ObjectSetInteger(0, id, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, id, OBJPROP_BACK, false);
         ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, id, OBJPROP_XDISTANCE, m_x);
      ObjectSetInteger(0, id, OBJPROP_YDISTANCE, m_y);
      ObjectSetInteger(0, id, OBJPROP_XSIZE, 310);
      ObjectSetInteger(0, id, OBJPROP_YSIZE, height);
   }

   string Flag(const bool v) const { return v ? "YES" : "NO"; }

public:
   CDashboard()
   {
      m_enabled = false;
      m_prefix = IFVG_DASH_PREFIX;
      m_x = 12;
      m_y = 24;
   }

   void Init(const bool enabled)
   {
      m_enabled = enabled;
      if(!m_enabled)
         return;
      ChartSetInteger(0, CHART_FOREGROUND, false);
   }

   void Destroy()
   {
      ObjectsDeleteAll(0, m_prefix);
   }

   void Render(const string symbol,
               const CIFVGConfig &cfg,
               const CStateMachine &sm,
               const CCooldownManager &cd,
               const CPositionManager &pos)
   {
      if(!m_enabled)
         return;

      const SSetup s = sm.Setup();
      const SEntryPlan plan = sm.LastPlan();
      const datetime now = TimeCurrent();
      const ENUM_EA_STATUS st = sm.Status();
      color stclr = clrSilver;
      if(st == EA_SETUP_FOUND)
         stclr = clrGold;
      if(st == EA_TRADE_ACTIVE)
         stclr = clrLime;
      if(st == EA_COOLDOWN)
         stclr = clrOrangeRed;

      Panel(360);
      Label("T", 0, "IFVG SENTINEL", C'201,162,39', 11);
      Label("S", 1, "Status: " + IFVG_StatusToString(st), stclr, 10);
      Label("SY", 2, "Symbol: " + symbol, clrWhite);
      Label("B", 3, "HTF Bias: " + IFVG_BiasToString(s.htf_bias), clrWhite);
      Label("L", 4, "Liquidity: " + IFVG_LiqToString(s.liquidity.side), clrWhite);
      Label("SW", 5, "Sweep: " + Flag(s.sweep.valid), s.sweep.valid ? clrLime : clrSilver);
      Label("SM", 6, "SMT: " + Flag(s.smt.valid), s.smt.valid ? clrLime : clrSilver);
      Label("C", 7, "CISD: " + Flag(s.cisd.valid), s.cisd.valid ? clrLime : clrSilver);
      Label("F", 8, "FVG: " + (s.fvg.id > 0 ? EnumToString(s.fvg.state) : "NO"), clrSilver);
      Label("I", 9, "IFVG: " + (s.ifvg.id > 0 ? EnumToString(s.ifvg.life) : "NO"), clrSilver);
      Label("R", 10, "Retest: " + Flag(s.ifvg.life == IFVG_LIFE_RETEST || s.ifvg.life == IFVG_LIFE_TRADED), clrSilver);
      Label("RR", 11, "Current RR: " + (plan.valid ? ("1:" + DoubleToString(plan.rr_actual, 2)) : "-"), clrWhite);
      Label("P", 12, "POSITIONS: " + IntegerToString(pos.CountOpen()) + " / " + IntegerToString(cfg.in.max_positions), clrAqua);
      Label("LO", 13, "LOT: " + DoubleToString(cfg.in.max_lot, 2), clrAqua);
      Label("TR", 14, "TARGET RR: 1:" + DoubleToString(cfg.in.target_rr, 1), clrAqua);
      Label("CS", 15, "CONSECUTIVE SL: " + IntegerToString(cd.ConsecutiveSL()), clrWhite);
      Label("CD", 16, "Cooldown remaining: " + cd.RemainingLabel(now), cd.Active(now) ? clrOrangeRed : clrSilver);
      Label("ST", 17, "State: " + IFVG_StateToString(s.state), clrGray);
      Label("RJ", 18, "Last: " + (s.last_reject == "" ? "-" : s.last_reject), clrGray);
      ChartRedraw(0);
   }
};

#endif

#property copyright   "MACHINE MAKER"
#property link        "https://github.com"
#property version     "1.20"
#property description "MACHINE MAKER — Gold-only FVG EA. Percent-of-equity risk. Discipline over frequency."

#include <MachineMaker/Constants.mqh>
#include <MachineMaker/Types.mqh>
#include <MachineMaker/Utils.mqh>
#include <MachineMaker/Safety.mqh>
#include <MachineMaker/Logger.mqh>
#include <MachineMaker/Config.mqh>
#include <MachineMaker/Persistence.mqh>
#include <MachineMaker/SymbolProvider.mqh>
#include <MachineMaker/DirectionEngine.mqh>
#include <MachineMaker/FibonacciEngine.mqh>
#include <MachineMaker/FVGEngine.mqh>
#include <MachineMaker/EntryModels.mqh>
#include <MachineMaker/CooldownManager.mqh>
#include <MachineMaker/RiskEngine.mqh>
#include <MachineMaker/PositionManager.mqh>
#include <MachineMaker/TradeManager.mqh>
#include <MachineMaker/BacktestStats.mqh>
#include <MachineMaker/StateMachine.mqh>
#include <MachineMaker/Dashboard.mqh>
#include <MachineMaker/SafetySelfTest.mqh>

input group "=== MACHINE MAKER ==="
input string InpSymbol              = "XAUUSD";

input group "=== RISK ==="
input double InpRiskPercent         = 2.0;
input double InpMaxLot              = 0.0; // 0 = broker SYMBOL_VOLUME_MAX only
input double InpTargetRR            = 4.0;
input int    InpMaxPositions        = 2;
input int    InpSLBufferPoints      = 50;

input group "=== COOLDOWN ==="
input int    InpConsecutiveSLLimit  = 2;
input int    InpCooldownHours       = 8;

input group "=== STRUCTURE / FVG ==="
input int    InpSwingLeft           = 2;
input int    InpSwingRight          = 2;
input int    InpStructureLookback   = 80;
input int    InpFVGMinPoints        = 20;
input int    InpFVGMaxAgeBars       = 40;

input group "=== SYSTEM ==="
input long   InpMagicNumber         = MM_MAGIC;
input bool   InpEnableDashboard     = true;
input bool   InpEnableLogs          = true;
input bool   InpEnableFileLogs      = false;
input bool   InpDebugMode           = false;
input bool   InpRunSafetySelfTest   = true;

CMMConfig           g_cfg;
CMMLogger           g_log;
CMMPersistence      g_store;
CMMSymbolProvider   g_sym;
CMMDirectionEngine  g_dir;
CMMFVGEngine        g_fvg;
CMMCooldownManager  g_cd;
CMMRiskEngine       g_risk;
CMMPositionManager  g_pos;
CMMTradeManager     g_trade;
CMMBacktestStats    g_stats;
CMMStateMachine     g_sm;
CMMDashboard        g_dash;

string WorkingSymbol()
{
   if(InpSymbol == "" || InpSymbol == "current")
      return _Symbol;
   return InpSymbol;
}

void LoadInputs()
{
   g_cfg.in.symbol = WorkingSymbol();
   g_cfg.in.max_lot = InpMaxLot;
   g_cfg.in.risk_percent = InpRiskPercent;
   g_cfg.in.target_rr = InpTargetRR;
   g_cfg.in.max_positions = InpMaxPositions;
   g_cfg.in.consec_sl_limit = InpConsecutiveSLLimit;
   g_cfg.in.cooldown_hours = InpCooldownHours;
   g_cfg.in.sl_buffer_points = InpSLBufferPoints;
   g_cfg.in.fvg_min_points = InpFVGMinPoints;
   g_cfg.in.fvg_max_age_bars = InpFVGMaxAgeBars;
   g_cfg.in.swing_left = InpSwingLeft;
   g_cfg.in.swing_right = InpSwingRight;
   g_cfg.in.structure_lookback = InpStructureLookback;
   g_cfg.in.magic = InpMagicNumber;
   g_cfg.in.enable_dashboard = InpEnableDashboard;
   g_cfg.in.enable_logs = InpEnableLogs;
   g_cfg.in.enable_file_logs = InpEnableFileLogs;
   g_cfg.in.debug_mode = InpDebugMode;
   g_cfg.ApplySafetyClamps();
}

double ClosedTradeRiskDistance(const ulong deal, const bool closed_by_sl)
{
   const double close_px = HistoryDealGetDouble(deal, DEAL_PRICE);
   const ulong pos_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   double sl = 0.0;
   if(HistorySelectByPosition(pos_id))
   {
      const int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
      {
         const ulong d = HistoryDealGetTicket(i);
         if(d == 0)
            continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            const double entry = HistoryDealGetDouble(d, DEAL_PRICE);
            if(closed_by_sl)
               return MathAbs(entry - close_px);
            if(PositionSelectByTicket(pos_id))
               sl = PositionGetDouble(POSITION_SL);
            return MathAbs(entry - (sl > 0.0 ? sl : close_px));
         }
      }
   }
   return 0.0;
}

int OnInit()
{
   LoadInputs();
   const string symbol = g_cfg.in.symbol;
   g_log.Init(g_cfg.in.enable_logs, g_cfg.in.debug_mode, g_cfg.in.enable_file_logs, symbol);
   g_log.Info(MM_EA_NAME + " v" + MM_EA_VERSION + " init on " + symbol);
   g_log.Info("STRATEGY TFs locked D1/H4/M15 (chart/tester period is ignored)");
   if(MM_TF_DAILY != PERIOD_D1 || MM_TF_H4 != PERIOD_H4 || MM_TF_M15 != PERIOD_M15)
   {
      g_log.Error("internal timeframe lock mismatch");
      return INIT_FAILED;
   }
   g_log.Info("Gold-only FVG strategy. RR 1:4. RiskPercent of equity. Lot follows broker volume limits.");
   g_log.Info("AccountCurrency=" + AccountInfoString(ACCOUNT_CURRENCY) +
              " Equity=" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) +
              " RiskPercent=" + DoubleToString(g_cfg.in.risk_percent, 2));

   if(!MM_IsGoldSymbol(symbol))
   {
      g_log.Error("GOLD-ONLY: refusing non-gold symbol " + symbol);
      return INIT_FAILED;
   }
   if(InpRunSafetySelfTest && CMMSafetySelfTest::Run(g_log) > 0)
      return INIT_FAILED;
   if(g_cfg.in.target_rr < MM_HARD_TARGET_RR)
   {
      g_log.Error("TargetRR below 1:4 is not allowed");
      return INIT_FAILED;
   }

   g_sym.SetLogger(&g_log);
   if(!g_sym.Refresh(symbol))
      return INIT_FAILED;
   if(!CMMSafety::BrokerVolumeUsable(g_sym.Spec()))
   {
      g_log.Error("broker volume/tick spec unusable — refusing to trade");
      return INIT_FAILED;
   }

   g_store.Init(g_cfg.in.magic, symbol);
   g_dir.Init(&g_cfg, &g_log);
   g_fvg.Init(&g_cfg, &g_log);
   g_fvg.SetSpec(g_sym.Spec());
   g_cd.Init(&g_cfg, &g_log, &g_store);
   g_risk.Init(&g_cfg, &g_log);
   g_pos.Init(&g_cfg, symbol);
   g_trade.Init(&g_cfg, &g_log);
   g_stats.Init(&g_log, g_cfg.in.target_rr);
   g_sm.Bind(&g_cfg, &g_log, &g_dir, &g_fvg, &g_risk, &g_trade, &g_pos, &g_cd, &g_stats, &g_sym);
   g_dash.Init(g_cfg.in.enable_dashboard && !MQLInfoInteger(MQL_TESTER));
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_stats.PrintReport();
   g_dash.Destroy();
   g_log.Close();
}

void OnTick()
{
   g_sm.Process();
   g_dash.Render(g_cfg.in.symbol, g_sm, g_cd, g_pos, g_cfg);
}

void OnTimer()
{
   OnTick();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   const ulong deal = trans.deal;
   if(deal == 0 || !HistoryDealSelect(deal))
      return;
   if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != g_cfg.in.magic)
      return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != g_cfg.in.symbol)
      return;
   const long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   const double profit = HistoryDealGetDouble(deal, DEAL_PROFIT) +
                         HistoryDealGetDouble(deal, DEAL_SWAP) +
                         HistoryDealGetDouble(deal, DEAL_COMMISSION);
   const long reason = HistoryDealGetInteger(deal, DEAL_REASON);
   const bool closed_by_sl = (reason == DEAL_REASON_SL);
   const bool is_loss = (profit < 0.0) || closed_by_sl;
   const double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
   const double risk_distance = ClosedTradeRiskDistance(deal, closed_by_sl);
   const double risk_money = CMMSafety::RiskMoneyFromDistance(g_sym.Spec(), risk_distance, volume);
   g_stats.OnClosedDeal(profit, risk_money, is_loss);
   if(closed_by_sl)
      g_cd.OnClosedTrade(true, TimeCurrent());
   else if(profit > 0.0)
      g_cd.OnClosedTrade(false, TimeCurrent());
   g_sm.NotifyManagedPositionClosed();
}

double OnTester()
{
   return g_stats.OnTester();
}

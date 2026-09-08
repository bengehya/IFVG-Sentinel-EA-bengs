#property copyright   "IFVG Sentinel"
#property link        "https://github.com"
#property version     "1.00"
#property description "IFVG Sentinel EA — mechanical IFVG strategy for Deriv MT5. Discipline over frequency."

#include <IFVG/Constants.mqh>
#include <IFVG/Types.mqh>
#include <IFVG/Utils.mqh>
#include <IFVG/Safety.mqh>
#include <IFVG/Logger.mqh>
#include <IFVG/Config.mqh>
#include <IFVG/Persistence.mqh>
#include <IFVG/SymbolProvider.mqh>
#include <IFVG/SessionManager.mqh>
#include <IFVG/MarketContext.mqh>
#include <IFVG/PDArray.mqh>
#include <IFVG/LiquidityDetector.mqh>
#include <IFVG/SweepDetector.mqh>
#include <IFVG/SMTDetector.mqh>
#include <IFVG/CISDDetector.mqh>
#include <IFVG/FVGDetector.mqh>
#include <IFVG/IFVGManager.mqh>
#include <IFVG/CooldownManager.mqh>
#include <IFVG/RiskManager.mqh>
#include <IFVG/PositionManager.mqh>
#include <IFVG/TradeManager.mqh>
#include <IFVG/SetupValidator.mqh>
#include <IFVG/EntryEngine.mqh>
#include <IFVG/BacktestStats.mqh>
#include <IFVG/StateMachine.mqh>
#include <IFVG/Dashboard.mqh>
#include <IFVG/SafetySelfTest.mqh>

//--- STRATEGY
input group "=== STRATEGY ==="
input bool              InpGoldOnlyMode         = true;
input string            InpSymbol               = "XAUUSD";
input ENUM_TIMEFRAMES   InpHTF_Timeframe        = PERIOD_H4;
input ENUM_TIMEFRAMES   InpConfirmation_Timeframe = PERIOD_M15;
input ENUM_TIMEFRAMES   InpEntry_Timeframe      = PERIOD_M1;
input bool              InpAllowBuy             = true;
input bool              InpAllowSell            = true;

//--- SMT
input group "=== SMT ==="
input bool              InpUseSMTFilter         = true;
input ENUM_SMT_MODE     InpSMTMode              = SMT_REQUIRED;
input string            InpSMTSymbol1           = "XAGUSD";
input ENUM_CORR_TYPE    InpSMTCorr1             = CORR_POSITIVE;
input string            InpSMTSymbol2           = "USDX";
input ENUM_CORR_TYPE    InpSMTCorr2             = CORR_INVERSE;
input int               InpSMTLookback          = 80;
input int               InpSMTSwingLeft         = 2;
input int               InpSMTSwingRight        = 2;

//--- RISK (hard-capped in code: MaxLot<=0.01, MaxPositions<=2)
input group "=== RISK ==="
input double            InpMaxLot               = 0.01;
input double            InpTargetRR             = 3.0;
input int               InpMaxPositions         = 2;
input int               InpSLBufferPoints       = 50;
input int               InpMinSLPoints          = 100;

//--- COOLDOWN (hard floor: ConsecutiveSLLimit>=2, CooldownHours>=8)
input group "=== COOLDOWN ==="
input int               InpConsecutiveSLLimit   = 2;
input int               InpCooldownHours        = 8;

//--- MARKET FILTER
input group "=== MARKET FILTER ==="
input int               InpMaxSpreadPoints      = 80;
input int               InpTradingSessionStartHour = 7;
input int               InpTradingSessionStartMinute = 0;
input int               InpTradingSessionEndHour = 21;
input int               InpTradingSessionEndMinute = 0;
input ENUM_SESSION_TZ   InpSessionTimezone      = TZ_UTC;
input int               InpUtcOffsetHours       = 0; // server = UTC + this value
input bool              InpTradeLondon          = true;
input bool              InpTradeNewYork         = true;
input bool              InpTradeAsian           = false;

//--- STRUCTURE / LIQUIDITY / SWEEP
input group "=== STRUCTURE ==="
input int               InpSwingLeft            = 2;
input int               InpSwingRight           = 2;
input int               InpHTFStructureLookback = 80;
input int               InpEqualPoints          = 80;
input int               InpLiqExpireBars        = 80;
input int               InpMinSweepPoints       = 20;
input int               InpMinSweepClosebackPoints = 5;
input double            InpMinSweepATRMult      = 0.6;
input int               InpSweepMaxAgeBars      = 12;
input int               InpPDExpireBars         = 60;
input double            InpOBDisplacementATR    = 1.2;
input int               InpOBImpulseBars        = 3;

//--- CISD / DISPLACEMENT
input group "=== CISD / DISPLACEMENT ==="
input double            InpCISDMinBodyATR       = 0.4;
input int               InpCISDMaxBarsAfterSweep = 8;
input double            InpDisplacementATRMult  = 1.0;
input int               InpDisplacementMinBars  = 1;

//--- FVG / IFVG
input group "=== IFVG ==="
input int               InpFVGMinPoints         = 20;
input int               InpFVGMaxAgeBars        = 40;
input bool              InpFVGRequireClosedBars = true;
input int               InpIFVG_Tolerance       = 30;
input int               InpIFVG_MaxRetests      = 2;
input int               InpIFVG_ValidityPeriod  = 14400; // seconds
input bool              InpIFVGRequireCloseThrough = true;

//--- SYSTEM
input group "=== SYSTEM ==="
input long              InpMagicNumber          = IFVG_SENTINEL_MAGIC;
input bool              InpEnableDashboard      = true;
input bool              InpEnableLogs           = true;
input bool              InpEnableFileLogs       = false;
input bool              InpDebugMode            = false;
input bool              InpRunSafetySelfTest    = true;

CIFVGConfig          g_cfg;
CIFVGLogger          g_log;
CIFVGPersistence     g_store;
CSymbolProvider      g_sym;
CSessionManager      g_session;
CMarketContext       g_htf;
CPDArray             g_pd;
CLiquidityDetector   g_liq;
CSweepDetector       g_sweep;
CSMTDetector         g_smt;
CCISDDetector        g_cisd;
CFVGDetector         g_fvg;
CIFVGManager         g_ifvg;
CCooldownManager     g_cd;
CRiskManager         g_risk;
CPositionManager     g_pos;
CTradeManager        g_trade;
CEntryEngine         g_entry;
CBacktestStats       g_stats;
CStateMachine        g_sm;
CDashboard           g_dash;

string WorkingSymbol()
{
   if(InpSymbol == "" || InpSymbol == "current")
      return _Symbol;
   return InpSymbol;
}

void LoadInputs()
{
   g_cfg.in.symbol = WorkingSymbol();
   g_cfg.in.gold_only_mode = InpGoldOnlyMode;
   g_cfg.in.htf = InpHTF_Timeframe;
   g_cfg.in.confirmation_tf = InpConfirmation_Timeframe;
   g_cfg.in.entry_tf = InpEntry_Timeframe;
   g_cfg.in.use_smt_filter = InpUseSMTFilter;
   g_cfg.in.smt_mode = InpSMTMode;
   g_cfg.in.smt_symbol1 = InpSMTSymbol1;
   g_cfg.in.smt_symbol2 = InpSMTSymbol2;
   g_cfg.in.smt_corr1 = InpSMTCorr1;
   g_cfg.in.smt_corr2 = InpSMTCorr2;
   g_cfg.in.smt_lookback = InpSMTLookback;
   g_cfg.in.smt_swing_left = InpSMTSwingLeft;
   g_cfg.in.smt_swing_right = InpSMTSwingRight;
   g_cfg.in.max_lot = InpMaxLot;
   g_cfg.in.target_rr = InpTargetRR;
   g_cfg.in.max_positions = InpMaxPositions;
   g_cfg.in.consec_sl_limit = InpConsecutiveSLLimit;
   g_cfg.in.cooldown_hours = InpCooldownHours;
   g_cfg.in.max_spread_points = InpMaxSpreadPoints;
   g_cfg.in.session_start_hour = InpTradingSessionStartHour;
   g_cfg.in.session_start_minute = InpTradingSessionStartMinute;
   g_cfg.in.session_end_hour = InpTradingSessionEndHour;
   g_cfg.in.session_end_minute = InpTradingSessionEndMinute;
   g_cfg.in.session_timezone = InpSessionTimezone;
   g_cfg.in.utc_offset_hours = InpUtcOffsetHours;
   g_cfg.in.trade_london = InpTradeLondon;
   g_cfg.in.trade_ny = InpTradeNewYork;
   g_cfg.in.trade_asian = InpTradeAsian;
   g_cfg.in.swing_left = InpSwingLeft;
   g_cfg.in.swing_right = InpSwingRight;
   g_cfg.in.equal_points = InpEqualPoints;
   g_cfg.in.liq_expire_bars = InpLiqExpireBars;
   g_cfg.in.min_sweep_points = InpMinSweepPoints;
   g_cfg.in.min_sweep_closeback_points = InpMinSweepClosebackPoints;
   g_cfg.in.min_sweep_atr_mult = InpMinSweepATRMult;
   g_cfg.in.sweep_max_age_bars = InpSweepMaxAgeBars;
   g_cfg.in.htf_structure_lookback = InpHTFStructureLookback;
   g_cfg.in.pd_expire_bars = InpPDExpireBars;
   g_cfg.in.ob_displacement_atr = InpOBDisplacementATR;
   g_cfg.in.ob_impulse_bars = InpOBImpulseBars;
   g_cfg.in.cisd_min_body_atr = InpCISDMinBodyATR;
   g_cfg.in.cisd_max_bars_after_sweep = InpCISDMaxBarsAfterSweep;
   g_cfg.in.displacement_atr_mult = InpDisplacementATRMult;
   g_cfg.in.displacement_min_bars = InpDisplacementMinBars;
   g_cfg.in.fvg_min_points = InpFVGMinPoints;
   g_cfg.in.fvg_max_age_bars = InpFVGMaxAgeBars;
   g_cfg.in.fvg_require_closed_bars = InpFVGRequireClosedBars;
   g_cfg.in.ifvg_tolerance_points = InpIFVG_Tolerance;
   g_cfg.in.ifvg_max_retests = InpIFVG_MaxRetests;
   g_cfg.in.ifvg_validity_seconds = InpIFVG_ValidityPeriod;
   g_cfg.in.ifvg_require_close_through = InpIFVGRequireCloseThrough;
   g_cfg.in.sl_buffer_points = InpSLBufferPoints;
   g_cfg.in.min_sl_points = InpMinSLPoints;
   g_cfg.in.magic = InpMagicNumber;
   g_cfg.in.enable_dashboard = InpEnableDashboard;
   g_cfg.in.enable_logs = InpEnableLogs;
   g_cfg.in.enable_file_logs = InpEnableFileLogs;
   g_cfg.in.debug_mode = InpDebugMode;
   g_cfg.in.allow_buy = InpAllowBuy;
   g_cfg.in.allow_sell = InpAllowSell;
   g_cfg.ApplySafetyClamps();
}

int OnInit()
{
   LoadInputs();
   const string symbol = g_cfg.in.symbol;

   g_log.Init(g_cfg.in.enable_logs, g_cfg.in.debug_mode, g_cfg.in.enable_file_logs, symbol);
   g_log.Info(IFVG_EA_NAME + " v" + IFVG_EA_VERSION + " init on " + symbol);
   if(g_cfg.IsGoldOnly())
      g_log.Info("GOLD-ONLY MODE: trading " + symbol +
                 " only. External SMT (XAGUSD/USDX) is not a mandatory gate. No fake SMT is computed.");
   else
      g_log.Info("MULTI-SYMBOL SMT MODE: external compare symbols may be used as a filter, never as tradable instruments.");
   g_log.Info("Magic=" + IntegerToString((int)g_cfg.in.magic) +
              " MaxLot=" + DoubleToString(g_cfg.in.max_lot, 2) +
              " MaxPos=" + IntegerToString(g_cfg.in.max_positions) +
              " TargetRR=1:" + DoubleToString(g_cfg.in.target_rr, 1) +
              " CooldownH=" + IntegerToString(g_cfg.in.cooldown_hours));

   if(InpRunSafetySelfTest)
   {
      const int failed = CIFVGSafetySelfTest::Run(g_log);
      if(failed > 0)
      {
         g_log.Error("safety self-test failed — EA will not trade");
         return INIT_FAILED;
      }
   }

   if(g_cfg.in.target_rr < 3.0)
   {
      g_log.Error("TargetRR below 3.0 is not allowed");
      return INIT_FAILED;
   }

   g_sym.SetLogger(&g_log);
   if(!g_sym.Refresh(symbol))
      return INIT_FAILED;

   const SSymbolSpec spec = g_sym.Spec();
   g_log.Info("digits=" + IntegerToString(spec.digits) +
              " point=" + DoubleToString(spec.point, spec.digits) +
              " tick=" + DoubleToString(spec.tick_size, spec.digits) +
              " vol[" + DoubleToString(spec.volume_min, 2) + "," + DoubleToString(spec.volume_max, 2) +
              "] step=" + DoubleToString(spec.volume_step, 2) +
              " stops=" + IntegerToString(spec.stops_level) +
              " freeze=" + IntegerToString(spec.freeze_level) +
              " fill=" + IntegerToString(spec.filling_mode));

   if(!CIFVGSafety::BrokerAllowsHardCap(spec))
   {
      g_log.Error("broker volume_min > 0.01 — refusing to trade rather than exceed hard cap");
      return INIT_FAILED;
   }

   g_store.Init(g_cfg.in.magic, symbol);
   g_session.Init(&g_cfg, &g_log);
   g_htf.Init(&g_cfg, &g_log);
   g_pd.Init(&g_cfg, &g_log);
   g_liq.Init(&g_cfg, &g_log);
   g_liq.SetSpec(spec);
   g_sweep.Init(&g_cfg, &g_log);
   g_sweep.SetSpec(spec);
   g_smt.Init(&g_cfg, &g_log);
   g_cisd.Init(&g_cfg, &g_log);
   g_fvg.Init(&g_cfg, &g_log);
   g_fvg.SetSpec(spec);
   g_ifvg.Init(&g_cfg, &g_log);
   g_ifvg.SetSpec(spec);
   g_cd.Init(&g_cfg, &g_log, &g_store);
   g_risk.Init(&g_cfg, &g_log);
   g_pos.Init(&g_cfg, &g_log, symbol);
   g_trade.Init(&g_cfg, &g_log);
   g_entry.Init(&g_cfg, &g_log, &g_risk, &g_trade, &g_pos, &g_cd, &g_session, &g_ifvg, &g_sym);
   g_stats.Init(&g_log, g_cfg.in.magic, symbol, g_cfg.in.target_rr);
   g_sm.Bind(&g_cfg, &g_log, &g_htf, &g_pd, &g_liq, &g_sweep, &g_smt, &g_cisd, &g_fvg, &g_ifvg,
             &g_entry, &g_stats, &g_sym);
   g_dash.Init(g_cfg.in.enable_dashboard && !MQLInfoInteger(MQL_TESTER));

   if(g_cd.Active(TimeCurrent()))
   {
      g_log.Info("restored cooldown until " + TimeToString(g_cd.EndTime(), TIME_DATE | TIME_MINUTES));
      g_sm.ForceCooldownStatus();
   }

   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_stats.PrintReport();
   g_dash.Destroy();
   g_log.Info("deinit reason=" + IntegerToString(reason));
   g_log.Close();
}

void OnTimer()
{
   g_sym.Refresh(g_cfg.in.symbol);
   const SSymbolSpec spec = g_sym.Spec();
   g_liq.SetSpec(spec);
   g_sweep.SetSpec(spec);
   g_fvg.SetSpec(spec);
   g_ifvg.SetSpec(spec);
   g_dash.Render(g_cfg.in.symbol, g_cfg, g_sm, g_cd, g_pos);
}

void OnTick()
{
   if(!g_sym.Spec().valid)
      return;

   bool losses[];
   int nclosed = 0;
   g_pos.SyncClosed(losses, nclosed);

   const bool cd = g_cd.Active(TimeCurrent());
   if(cd)
      g_sm.ForceCooldownStatus();

   g_sm.Process(cd);

   static datetime last_dash = 0;
   if(TimeCurrent() != last_dash)
   {
      last_dash = TimeCurrent();
      g_dash.Render(g_cfg.in.symbol, g_cfg, g_sm, g_cd, g_pos);
   }
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

   double risk_money = 0.0;
   const double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
   const SSymbolSpec spec = g_sym.Spec();
   if(spec.tick_size > 0.0 && spec.tick_value > 0.0)
      risk_money = volume * spec.tick_value;

   g_stats.OnClosedDeal(profit, risk_money, is_loss);
   if(closed_by_sl)
      g_cd.OnClosedTrade(true, TimeCurrent());
   else if(profit > 0.0)
      g_cd.OnClosedTrade(false, TimeCurrent());
   g_pos.Snapshot();
   g_log.Decision("Position closed",
                  "profit=" + DoubleToString(profit, 2) +
                  " reason=" + IntegerToString((int)reason) +
                  (is_loss ? " LOSS" : " WIN"));
}

double OnTester()
{
   g_stats.PrintReport();
   return g_stats.OnTester();
}

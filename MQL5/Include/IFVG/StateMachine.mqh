#ifndef IFVG_STATEMACHINE_MQH
#define IFVG_STATEMACHINE_MQH

#include "MarketContext.mqh"
#include "PDArray.mqh"
#include "LiquidityDetector.mqh"
#include "SweepDetector.mqh"
#include "SMTDetector.mqh"
#include "CISDDetector.mqh"
#include "FVGDetector.mqh"
#include "IFVGManager.mqh"
#include "EntryEngine.mqh"
#include "BacktestStats.mqh"

class CStateMachine
{
private:
   CIFVGConfig        *m_cfg;
   CIFVGLogger        *m_log;
   CMarketContext     *m_htf;
   CPDArray           *m_pd;
   CLiquidityDetector *m_liq;
   CSweepDetector     *m_sweep;
   CSMTDetector       *m_smt;
   CCISDDetector      *m_cisd;
   CFVGDetector       *m_fvg;
   CIFVGManager       *m_ifvg;
   CEntryEngine       *m_entry;
   CBacktestStats     *m_stats;
   CSymbolProvider    *m_sym;
   SSetup              m_setup;
   ENUM_EA_STATUS      m_status;
   SEntryPlan          m_last_plan;
   datetime            m_last_bar;
   string              m_last_diag_fp;
   double              m_remembered_risk_distance;
   double              m_remembered_lot;
   double              m_remembered_entry;
   double              m_remembered_sl;

   void ResetSetup(const ENUM_SETUP_STATE st)
   {
      IFVG_ResetSetup(m_setup);
      m_setup.state = st;
      m_setup.created = TimeCurrent();
      IFVG_ResetPlan(m_last_plan);
   }

   void Diag(const string name, const string verdict, const string detail)
   {
      if(m_log == NULL)
         return;
      const string fp = name + "=" + verdict + "|" + detail;
      if(fp == m_last_diag_fp)
         return;
      m_last_diag_fp = fp;
      m_log.Chain(name, verdict, detail);
   }

   void DumpChain(const string entry_v,
                  const string rr_v,
                  const string final_v,
                  const string detail)
   {
      if(m_log == NULL)
         return;
      const bool pd_ok = (m_setup.direction != IFVG_DIR_NONE);
      string smt_v = IFVG_SmtStatusToString(m_setup.smt.status);
      if(m_cfg.IsGoldOnly() && m_setup.smt.status == SMT_STATUS_SKIPPED_GOLD_ONLY)
         smt_v = "SKIPPED_GOLD_ONLY";
      else if(m_setup.smt.status == SMT_STATUS_NONE && !m_cfg.SMTIsMandatoryGate())
         smt_v = (m_cfg.IsGoldOnly() ? "SKIPPED_GOLD_ONLY" : smt_v);

      const string inv = (m_setup.fvg.state == FVG_INVERTED || m_setup.fvg.state == FVG_BROKEN) ? "PASS" : "FAIL";
      const string fvg = (m_setup.fvg.id > 0) ? "PASS" : "FAIL";
      const string ifvg = (m_setup.ifvg.id > 0 && m_setup.ifvg.life != IFVG_LIFE_NONE) ? "PASS" : "FAIL";
      const string retest = (m_setup.ifvg.life == IFVG_LIFE_RETEST || m_setup.ifvg.life == IFVG_LIFE_TRADED) ? "PASS" : "FAIL";
      const string fp = IFVG_Gate(m_htf.Valid()) + "|" + IFVG_Gate(pd_ok) + "|" +
                        IFVG_Gate(m_setup.liquidity.active) + "|" + IFVG_Gate(m_setup.sweep.valid) + "|" +
                        smt_v + "|" + IFVG_Gate(m_setup.cisd.valid) + "|" +
                        IFVG_Gate(m_setup.displacement) + "|" + fvg + "|" + inv + "|" + ifvg + "|" +
                        retest + "|" + entry_v + "|" + rr_v + "|" + final_v;
      if(fp == m_last_diag_fp)
         return;
      m_last_diag_fp = fp;
      m_log.Chain("HTF", IFVG_Gate(m_htf.Valid()), IFVG_BiasToString(m_setup.htf_bias));
      m_log.Chain("PD ARRAY", IFVG_Gate(pd_ok), "");
      m_log.Chain("LIQUIDITY", IFVG_Gate(m_setup.liquidity.active), IFVG_LiqToString(m_setup.liquidity.side));
      m_log.Chain("SWEEP", IFVG_Gate(m_setup.sweep.valid), "");
      m_log.Chain("SMT", smt_v, m_setup.smt.reason);
      m_log.Chain("CISD", IFVG_Gate(m_setup.cisd.valid), m_setup.cisd.reason);
      m_log.Chain("DISPLACEMENT", IFVG_Gate(m_setup.displacement),
                  m_setup.displacement ? DoubleToString(m_setup.displacement_points, 5) : "");
      m_log.Chain("FVG", fvg, "");
      m_log.Chain("INVERSION", inv, "");
      m_log.Chain("IFVG", ifvg, "");
      m_log.Chain("RETEST", retest, "");
      m_log.Chain("ENTRY GATES", entry_v, "");
      m_log.Chain("RR", rr_v, "");
      m_log.Chain("FINAL DECISION", final_v, detail);
   }

   void Invalidate(const string why)
   {
      DumpChain("-", "-", "NO TRADE", why);
      if(m_log != NULL)
         m_log.Decision("SETUP_INVALIDATED", why);
      m_setup.state = ST_SETUP_INVALIDATED;
      m_setup.last_reject = why;
      if(m_stats != NULL)
         m_stats.OnRejected();
      ResetSetup(ST_IDLE);
      m_status = EA_WAITING;
   }

   void InvalidateExpiredIFVG()
   {
      const ulong sid = m_setup.setup_id;
      if(m_log != NULL)
      {
         m_log.Info("EXPIRED — SetupID=" + IntegerToString((long)sid));
         m_log.State("INVALIDATE — reason=IFVG_VALIDITY_EXPIRED");
      }
      m_setup.last_reject = "IFVG_VALIDITY_EXPIRED";
      m_setup.ifvg.life = IFVG_LIFE_EXPIRED;
      if(m_ifvg != NULL)
         m_ifvg.MarkExpired(m_setup.ifvg);
      if(m_stats != NULL)
         m_stats.OnRejected();
      if(m_log != NULL)
         m_log.State("CLEAR ACTIVE SETUP");
      ResetSetup(ST_IDLE);
      m_status = EA_WAITING;
      if(m_log != NULL)
         m_log.State("IDLE — waiting for new setup");
   }

   bool ExpireActiveSetupIfNeeded()
   {
      if(m_setup.ifvg.id == 0)
         return false;
      if(m_ifvg == NULL)
         return false;
      if(!m_ifvg.ValidityElapsed(m_setup.ifvg, TimeCurrent()))
         return false;
      InvalidateExpiredIFVG();
      return true;
   }

   void LogWaitingForRetestOnce()
   {
      const string fp = "WAITING_FOR_RETEST|" + IntegerToString((long)m_setup.setup_id);
      if(fp == m_last_diag_fp)
         return;
      m_last_diag_fp = fp;
      if(m_log != NULL)
         m_log.Decision("WAITING_FOR_RETEST", "SetupID=" + IntegerToString((long)m_setup.setup_id));
   }

   void ResumeWaitingForRetest()
   {
      m_setup.state = ST_WAITING_RETEST;
      m_status = EA_SETUP_FOUND;
      LogWaitingForRetestOnce();
   }

   void RememberPlanRisk()
   {
      if(m_last_plan.risk_distance > 0.0)
      {
         m_remembered_risk_distance = m_last_plan.risk_distance;
         m_remembered_lot = m_last_plan.lot;
         m_remembered_entry = m_last_plan.entry;
         m_remembered_sl = m_last_plan.sl;
      }
   }

   void GoIdle(const string why)
   {
      if(m_log != NULL)
         m_log.Decision("STATE IDLE", why);
      ResetSetup(ST_IDLE);
      m_status = EA_WAITING;
   }

   bool StageWindowExpired(const datetime from, const int max_bars) const
   {
      if(m_sym == NULL || m_cfg == NULL)
         return false;
      return IFVG_ConfirmationWindowExpired(m_sym.SymbolName(), m_cfg.in.confirmation_tf, from, max_bars);
   }

public:
   CStateMachine()
   {
      m_status = EA_WAITING;
      m_last_bar = 0;
      m_last_diag_fp = "";
      m_remembered_risk_distance = 0.0;
      m_remembered_lot = 0.0;
      m_remembered_entry = 0.0;
      m_remembered_sl = 0.0;
      IFVG_ResetSetup(m_setup);
      m_setup.state = ST_IDLE;
   }

   void Bind(CIFVGConfig *cfg,
             CIFVGLogger *log,
             CMarketContext *htf,
             CPDArray *pd,
             CLiquidityDetector *liq,
             CSweepDetector *sweep,
             CSMTDetector *smt,
             CCISDDetector *cisd,
             CFVGDetector *fvg,
             CIFVGManager *ifvg,
             CEntryEngine *entry,
             CBacktestStats *stats,
             CSymbolProvider *sym)
   {
      m_cfg = cfg;
      m_log = log;
      m_htf = htf;
      m_pd = pd;
      m_liq = liq;
      m_sweep = sweep;
      m_smt = smt;
      m_cisd = cisd;
      m_fvg = fvg;
      m_ifvg = ifvg;
      m_entry = entry;
      m_stats = stats;
      m_sym = sym;
   }

   ENUM_EA_STATUS Status() const { return m_status; }
   SSetup Setup() const { return m_setup; }
   SEntryPlan LastPlan() const { return m_last_plan; }

   double RememberedRiskDistance() const { return m_remembered_risk_distance; }
   double RememberedLot() const { return m_remembered_lot; }
   double RememberedEntry() const { return m_remembered_entry; }
   double RememberedSL() const { return m_remembered_sl; }

   void ForceCooldownStatus()
   {
      m_status = EA_COOLDOWN;
      m_setup.state = ST_COOLDOWN;
   }

   void NotifyManagedPositionClosed()
   {
      RememberPlanRisk();
      if(m_setup.state == ST_ORDER_SENT ||
         m_setup.state == ST_POSITION_ACTIVE ||
         m_setup.state == ST_POSITION_CLOSED)
      {
         GoIdle("position closed → IDLE");
      }
   }

   void Process(const bool cooldown_active, const int open_positions)
   {
      if(cooldown_active)
      {
         m_status = EA_COOLDOWN;
         m_setup.state = ST_COOLDOWN;
         return;
      }

      if(m_setup.state == ST_COOLDOWN)
         GoIdle("cooldown expired → IDLE");

      const string symbol = m_sym.SymbolName();
      datetime t[];
      if(CopyTime(symbol, m_cfg.in.confirmation_tf, 0, 1, t) <= 0)
         return;

      const bool new_bar = (t[0] != m_last_bar);
      if(new_bar)
         m_last_bar = t[0];

      if(m_setup.state == ST_ORDER_SENT || m_setup.state == ST_POSITION_ACTIVE)
      {
         if(open_positions > 0)
         {
            m_setup.state = ST_POSITION_ACTIVE;
            m_status = EA_TRADE_ACTIVE;
            return;
         }
         if(m_setup.state == ST_POSITION_ACTIVE)
         {
            RememberPlanRisk();
            GoIdle("position closed → IDLE");
         }
         else if(!new_bar)
         {
            m_status = EA_TRADE_ACTIVE;
            return;
         }
         else
         {
            RememberPlanRisk();
            GoIdle("order sent but no position — resume search");
         }
      }

      const bool tick_state = (m_setup.state == ST_WAITING_RETEST ||
                               m_setup.state == ST_RETEST_DETECTED ||
                               m_setup.state == ST_ENTRY_VALIDATION);
      if(!new_bar && !tick_state)
         return;

      if(tick_state && ExpireActiveSetupIfNeeded())
         return;

      m_status = EA_ANALYZING;
      if(m_setup.state == ST_IDLE || m_setup.state == ST_SETUP_INVALIDATED)
      {
         ResetSetup(ST_HTF_ANALYSIS);
      }

      if(m_setup.state == ST_HTF_ANALYSIS)
      {
         if(!m_htf.Update(symbol))
         {
            Diag("HTF", "FAIL", "insufficient structure / NEUTRAL");
            m_status = EA_WAITING;
            return;
         }
         m_setup.htf_bias = m_htf.Bias();
         m_pd.Scan(symbol, m_cfg.in.confirmation_tf);
         m_setup.state = ST_LIQUIDITY_DETECTED;
      }

      if(m_setup.state == ST_LIQUIDITY_DETECTED)
      {
         m_liq.Scan(symbol);
         const ENUM_IFVG_DIR dir = (m_setup.htf_bias == IFVG_BIAS_BULLISH) ? IFVG_DIR_BUY :
                                   (m_setup.htf_bias == IFVG_BIAS_BEARISH) ? IFVG_DIR_SELL : IFVG_DIR_NONE;
         if(dir == IFVG_DIR_NONE)
         {
            Invalidate("HTF context invalid");
            return;
         }
         m_setup.direction = dir;
         SPDZone pd;
         if(!m_pd.HasActiveZone(dir, pd))
         {
            Diag("PD ARRAY", "FAIL", "no active PD zone in setup direction");
            m_status = EA_WAITING;
            m_setup.state = ST_IDLE;
            return;
         }
         const ENUM_LIQ_SIDE need = (dir == IFVG_DIR_BUY) ? LIQ_SELL_SIDE : LIQ_BUY_SIDE;
         if(!m_liq.BestResting(need, m_setup.liquidity))
         {
            Diag("LIQUIDITY", "FAIL", "no resting pool");
            m_status = EA_WAITING;
            m_setup.state = ST_IDLE;
            return;
         }
         if(m_log != NULL)
            m_log.Decision("Liquidity detected", IFVG_LiqToString(m_setup.liquidity.side));
         m_setup.state = ST_SWEEP_DETECTED;
      }

      if(m_setup.state == ST_SWEEP_DETECTED)
      {
         if(!m_sweep.Detect(symbol, *m_liq, m_setup.direction, m_setup.sweep))
         {
            Diag("SWEEP", "FAIL", "no valid sweep yet");
            m_status = EA_WAITING;
            m_setup.state = ST_LIQUIDITY_DETECTED;
            return;
         }
         m_setup.state = ST_SMT_VALIDATED;
      }

      if(m_setup.state == ST_SMT_VALIDATED)
      {
         m_setup.smt = m_smt.Evaluate(symbol, m_setup.direction);
         if(m_cfg.SMTIsMandatoryGate() && !m_setup.smt.valid)
         {
            Invalidate("SMT missing");
            return;
         }
         m_setup.state = ST_CISD_VALIDATED;
      }

      if(m_setup.state == ST_CISD_VALIDATED)
      {
         m_setup.cisd = m_cisd.DetectCISD(symbol, m_setup.sweep);
         if(!m_setup.cisd.valid)
         {
            const bool expired = (m_setup.cisd.reason == "sweep bar not found") ||
                                 StageWindowExpired(m_setup.sweep.time, m_cfg.in.cisd_max_bars_after_sweep);
            if(expired)
            {
               Invalidate("CISD not confirmed: " + m_setup.cisd.reason);
               return;
            }
            DumpChain("-", "-", "NO TRADE", "CISD not confirmed: " + m_setup.cisd.reason);
            m_status = EA_WAITING;
            return;
         }
         double pts = 0.0;
         string disp_why = "";
         m_setup.displacement = m_cisd.DetectDisplacement(symbol, m_setup.cisd, pts, disp_why);
         m_setup.displacement_points = pts;
         if(!m_setup.displacement)
         {
            const int disp_bars = MathMax(1, m_cfg.in.displacement_min_bars) + 2;
            const bool expired = (disp_why == "CISD bar not found") ||
                                 StageWindowExpired(m_setup.cisd.timestamp, disp_bars);
            if(expired)
            {
               Invalidate("DISPLACEMENT FAIL — " + disp_why);
               return;
            }
            DumpChain("-", "-", "NO TRADE", "DISPLACEMENT FAIL — " + disp_why);
            m_status = EA_WAITING;
            return;
         }
         m_setup.state = ST_FVG_DETECTED;
      }

      if(m_setup.state == ST_FVG_DETECTED)
      {
         m_fvg.Scan(symbol, m_cfg.in.confirmation_tf);
         const ENUM_IFVG_DIR orig = (m_setup.direction == IFVG_DIR_BUY) ? IFVG_DIR_SELL : IFVG_DIR_BUY;
         if(!m_fvg.LatestInverted(orig, m_setup.fvg))
         {
            const string why = m_fvg.ExplainNoInvertedFVG(orig);
            const bool expired = StageWindowExpired(m_setup.sweep.time, m_cfg.in.fvg_max_age_bars);
            if(expired)
            {
               const bool no_fvg = (StringFind(why, "no FVG") >= 0);
               Invalidate((no_fvg ? "FVG FAIL — " : "INVERSION FAIL — ") + why);
               return;
            }
            DumpChain("-", "-", "NO TRADE", "INVERSION FAIL — " + why);
            m_status = EA_WAITING;
            return;
         }
         if(m_log != NULL)
            m_log.Decision("FVG detected", "inverted source");
         m_setup.state = ST_IFVG_CREATED;
      }

      if(m_setup.state == ST_IFVG_CREATED)
      {
         if(!m_ifvg.CreateFromInvertedFVG(m_setup.fvg, m_setup.ifvg))
         {
            DumpChain("-", "-", "NO TRADE", "IFVG creation failed from inverted FVG");
            Invalidate("IFVG not created");
            return;
         }
         m_setup.setup_id = IFVG_BuildSetupId(symbol, m_setup.direction,
                                              m_setup.sweep.time, m_setup.liquidity.price,
                                              m_setup.ifvg.created);
         if(m_ifvg.AlreadyUsed(m_setup.setup_id))
         {
            Invalidate("SetupID already executed");
            return;
         }
         m_ifvg.MarkWaiting(m_setup.ifvg);
         m_setup.state = ST_WAITING_RETEST;
         m_status = EA_SETUP_FOUND;
         if(ExpireActiveSetupIfNeeded())
            return;
         LogWaitingForRetestOnce();
         DumpChain("FAIL", "-", "NO TRADE", "IFVG exists — waiting for valid retest");
      }

      if(m_setup.state == ST_WAITING_RETEST)
      {
         m_status = EA_SETUP_FOUND;
         if(!m_ifvg.UpdateRetest(symbol, m_setup.ifvg))
         {
            if(m_setup.ifvg.life == IFVG_LIFE_EXPIRED)
            {
               InvalidateExpiredIFVG();
               return;
            }
            if(m_setup.ifvg.life == IFVG_LIFE_INVALIDATED)
            {
               DumpChain("FAIL", "-", "NO TRADE", "IFVG invalidated/expired before retest");
               Invalidate("IFVG invalidated before retest");
               return;
            }
            LogWaitingForRetestOnce();
            return;
         }
         m_setup.state = ST_RETEST_DETECTED;
      }

      if(m_setup.state == ST_RETEST_DETECTED)
      {
         m_last_diag_fp = "RETEST_DETECTED|" + IntegerToString((long)m_setup.setup_id);
         m_setup.state = ST_ENTRY_VALIDATION;
      }

      if(m_setup.state == ST_ENTRY_VALIDATION)
      {
         if(ExpireActiveSetupIfNeeded())
            return;
         if(m_stats != NULL)
            m_stats.OnValidSetup();
         if(m_entry.TryEnter(m_setup, m_last_plan))
         {
            DumpChain("PASS",
                      (m_last_plan.valid ? ("PASS 1:" + DoubleToString(m_last_plan.rr_actual, 2)) : "PASS"),
                      "TRADE", "");
            m_setup.state = ST_ORDER_SENT;
            m_status = EA_TRADE_ACTIVE;
            RememberPlanRisk();
         }
         else
         {
            if(m_setup.ifvg.life == IFVG_LIFE_EXPIRED ||
               StringFind(m_setup.last_reject, "validity period elapsed") >= 0)
            {
               InvalidateExpiredIFVG();
               return;
            }
            if(CIFVGManager::IsWaitingForRetestReason(m_setup.last_reject))
            {
               ResumeWaitingForRetest();
               return;
            }
            if(m_stats != NULL)
               m_stats.OnRejected();
            const string rej = m_setup.last_reject;
            string rr_v = "-";
            if(StringFind(rej, "RR") >= 0)
               rr_v = "FAIL";
            DumpChain("FAIL", rr_v, "NO TRADE", rej);
            m_status = EA_SETUP_FOUND;
            if(StringFind(m_setup.last_reject, "cooldown") >= 0 ||
               StringFind(m_setup.last_reject, "positions") >= 0)
               return;
            if(StringFind(m_setup.last_reject, "retest") >= 0)
               m_setup.state = ST_WAITING_RETEST;
         }
      }
   }
};

#endif

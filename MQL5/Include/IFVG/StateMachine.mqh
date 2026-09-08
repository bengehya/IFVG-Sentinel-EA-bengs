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

public:
   CStateMachine()
   {
      m_status = EA_WAITING;
      m_last_bar = 0;
      m_last_diag_fp = "";
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

   void ForceCooldownStatus()
   {
      m_status = EA_COOLDOWN;
      m_setup.state = ST_COOLDOWN;
   }

   void Process(const bool cooldown_active)
   {
      if(cooldown_active)
      {
         m_status = EA_COOLDOWN;
         return;
      }

      const string symbol = m_sym.SymbolName();
      datetime t[];
      if(CopyTime(symbol, m_cfg.in.confirmation_tf, 0, 1, t) <= 0)
         return;

      const bool new_bar = (t[0] != m_last_bar);
      if(new_bar)
         m_last_bar = t[0];

      if(m_setup.state == ST_ORDER_SENT || m_setup.state == ST_POSITION_ACTIVE)
      {
         m_status = EA_TRADE_ACTIVE;
         return;
      }

      const bool tick_state = (m_setup.state == ST_WAITING_RETEST ||
                               m_setup.state == ST_RETEST_DETECTED ||
                               m_setup.state == ST_ENTRY_VALIDATION);
      if(!new_bar && !tick_state)
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
         DumpChain("FAIL", "-", "NO TRADE", "IFVG exists — waiting for valid retest");
         m_setup.state = ST_WAITING_RETEST;
         m_status = EA_SETUP_FOUND;
      }

      if(m_setup.state == ST_WAITING_RETEST)
      {
         m_status = EA_SETUP_FOUND;
         if(!m_ifvg.UpdateRetest(symbol, m_setup.ifvg))
         {
            if(m_setup.ifvg.life == IFVG_LIFE_INVALIDATED || m_setup.ifvg.life == IFVG_LIFE_EXPIRED)
            {
               DumpChain("FAIL", "-", "NO TRADE", "IFVG invalidated/expired before retest");
               Invalidate("IFVG invalidated before retest");
            }
            else
               Diag("RETEST", "FAIL", "IFVG exists but retest not found");
            return;
         }
         m_setup.state = ST_RETEST_DETECTED;
      }

      if(m_setup.state == ST_RETEST_DETECTED)
      {
         m_setup.state = ST_ENTRY_VALIDATION;
      }

      if(m_setup.state == ST_ENTRY_VALIDATION)
      {
         if(m_stats != NULL)
            m_stats.OnValidSetup();
         if(m_entry.TryEnter(m_setup, m_last_plan))
         {
            DumpChain("PASS",
                      (m_last_plan.valid ? ("PASS 1:" + DoubleToString(m_last_plan.rr_actual, 2)) : "PASS"),
                      "TRADE", "");
            m_setup.state = ST_ORDER_SENT;
            m_status = EA_TRADE_ACTIVE;
         }
         else
         {
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

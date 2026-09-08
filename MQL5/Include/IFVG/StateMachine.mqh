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

   void ResetSetup(const ENUM_SETUP_STATE st)
   {
      IFVG_ResetSetup(m_setup);
      m_setup.state = st;
      m_setup.created = TimeCurrent();
      IFVG_ResetPlan(m_last_plan);
   }

   void Invalidate(const string why)
   {
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
            m_status = EA_WAITING;
            m_setup.state = ST_IDLE;
            return;
         }
         const ENUM_LIQ_SIDE need = (dir == IFVG_DIR_BUY) ? LIQ_SELL_SIDE : LIQ_BUY_SIDE;
         if(!m_liq.BestResting(need, m_setup.liquidity))
         {
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
            m_status = EA_WAITING;
            m_setup.state = ST_LIQUIDITY_DETECTED;
            return;
         }
         m_setup.state = ST_SMT_VALIDATED;
      }

      if(m_setup.state == ST_SMT_VALIDATED)
      {
         m_setup.smt = m_smt.Evaluate(symbol, m_setup.direction);
         if(m_cfg.EffectiveSMTMode() == SMT_REQUIRED && !m_setup.smt.valid)
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
            m_status = EA_WAITING;
            return;
         }
         double pts = 0.0;
         m_setup.displacement = m_cisd.DetectDisplacement(symbol, m_setup.cisd, pts);
         m_setup.displacement_points = pts;
         if(!m_setup.displacement)
         {
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
            if(m_fvg.HasAnyActiveFVG())
            {
               m_status = EA_WAITING;
               return;
            }
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
      }

      if(m_setup.state == ST_WAITING_RETEST)
      {
         m_status = EA_SETUP_FOUND;
         if(!m_ifvg.UpdateRetest(symbol, m_setup.ifvg))
         {
            if(m_setup.ifvg.life == IFVG_LIFE_INVALIDATED || m_setup.ifvg.life == IFVG_LIFE_EXPIRED)
               Invalidate("IFVG invalidated before retest");
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
            m_setup.state = ST_ORDER_SENT;
            m_status = EA_TRADE_ACTIVE;
         }
         else
         {
            if(m_stats != NULL)
               m_stats.OnRejected();
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

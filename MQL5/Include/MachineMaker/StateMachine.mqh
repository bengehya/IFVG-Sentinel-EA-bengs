#ifndef MM_STATEMACHINE_MQH
#define MM_STATEMACHINE_MQH

#include "Safety.mqh"
#include "DirectionEngine.mqh"
#include "FibonacciEngine.mqh"
#include "FVGEngine.mqh"
#include "EntryModels.mqh"
#include "RiskEngine.mqh"
#include "TradeManager.mqh"
#include "PositionManager.mqh"
#include "CooldownManager.mqh"
#include "BacktestStats.mqh"
#include "SymbolProvider.mqh"

class CMMStateMachine
{
private:
   CMMConfig          *m_cfg;
   CMMLogger          *m_log;
   CMMDirectionEngine *m_dir;
   CMMFVGEngine       *m_fvg;
   CMMRiskEngine      *m_risk;
   CMMTradeManager    *m_trade;
   CMMPositionManager *m_pos;
   CMMCooldownManager *m_cd;
   CMMBacktestStats   *m_stats;
   CMMSymbolProvider  *m_sym;
   SMMSetup            m_setup;
   datetime            m_last_m15;
   datetime            m_last_h4;
   datetime            m_last_d1;
   string              m_fib_fp;
   bool                m_logged_wait;

   int FindFvgId(const ulong &ids[], const ulong id) const
   {
      const int n = ArraySize(ids);
      for(int i = 0; i < n; i++)
      {
         if(ids[i] == id)
            return i;
      }
      return -1;
   }

   void SnapshotFvgs(ulong &ids[], int &lives[]) const
   {
      const int n = m_fvg.Count();
      ArrayResize(ids, n);
      ArrayResize(lives, n);
      for(int i = 0; i < n; i++)
      {
         const SMMFVG f = m_fvg.At(i);
         ids[i] = f.id;
         lives[i] = (int)f.life;
      }
   }

   void AccountFvgScan(const ulong &ids[], const int &lives[])
   {
      if(m_stats == NULL)
         return;
      const int n = m_fvg.Count();
      for(int i = 0; i < n; i++)
      {
         const SMMFVG f = m_fvg.At(i);
         const int prev = FindFvgId(ids, f.id);
         if(prev < 0)
         {
            m_stats.OnFvgDetected();
            if(f.life == MM_FVG_INVALIDATED)
               m_stats.OnFvgInvalidated();
            else if(f.life == MM_FVG_EXPIRED)
               m_stats.OnFvgExpired();
         }
         else
         {
            const int old_life = lives[prev];
            if(old_life == (int)MM_FVG_VALID && f.life == MM_FVG_INVALIDATED)
               m_stats.OnFvgInvalidated();
            else if(old_life == (int)MM_FVG_VALID && f.life == MM_FVG_EXPIRED)
               m_stats.OnFvgExpired();
         }
      }
   }

   void RememberFill(const SMMEntryPlan &plan)
   {
      if(m_stats == NULL)
         return;
      SMMOpenTrade rec;
      ZeroMemory(rec);
      rec.position_id = m_trade.LastPositionId();
      rec.entry = m_trade.LastFillPrice();
      if(rec.entry <= 0.0)
         rec.entry = plan.entry;
      rec.sl = plan.sl;
      rec.volume = m_trade.LastVolume();
      if(rec.volume <= 0.0)
         rec.volume = plan.lot;
      rec.risk_distance = MathAbs(rec.entry - rec.sl);
      rec.risk_money = CMMSafety::RiskMoneyFromDistance(m_sym.Spec(), rec.risk_distance, rec.volume);
      rec.direction = plan.direction;
      rec.model = plan.model;
      rec.fvg_id = plan.fvg_id;
      m_stats.RememberOpen(rec);
   }

   void GoIdle(const string why)
   {
      const ulong old = m_setup.setup_id;
      MM_ResetSetup(m_setup);
      m_setup.state = MM_ST_IDLE;
      m_logged_wait = false;
      if(m_log != NULL)
         m_log.State("IDLE — " + why + (old > 0 ? " clearedSetup=" + IntegerToString((long)old) : ""));
   }

   void LogWaitOnce()
   {
      if(m_logged_wait || m_log == NULL)
         return;
      m_logged_wait = true;
      m_log.State("WAITING_FOR_RETEST FVG=" + IntegerToString((long)m_setup.fvg.id));
   }

   void InvalidateFVG(const string why)
   {
      SMMFVG live;
      const bool was_valid = (m_setup.fvg.id != 0 &&
                               m_fvg.GetById(m_setup.fvg.id, live) &&
                               live.life == MM_FVG_VALID);
      if(m_setup.fvg.id != 0)
         m_fvg.MarkLife(m_setup.fvg.id, MM_FVG_INVALIDATED);
      if(was_valid && m_stats != NULL)
         m_stats.OnFvgInvalidated();
      if(m_log != NULL)
         m_log.Fvg("Decision=INVALIDATED reason=" + why);
      GoIdle(why);
   }

   bool NewBar(const ENUM_TIMEFRAMES tf, datetime &last)
   {
      datetime t[];
      if(!MM_CopyTimeSafe(m_sym.SymbolName(), tf, t))
         return false;
      if(t[0] == last)
         return false;
      last = t[0];
      return true;
   }

   bool TryEnterOnClosedM15()
   {
      MqlRates rates[];
      if(!MM_CopyRatesSafe(m_sym.SymbolName(), MM_TF_M15, 5, rates) || ArraySize(rates) < 3)
         return false;
      const MqlRates closed = rates[1];
      if(closed.time <= m_setup.fvg.timestamp)
         return false;

      if(CMMFVGEngine::CompletelyBroken(m_setup.direction, m_setup.fvg.high, m_setup.fvg.low, closed.close))
      {
         InvalidateFVG("full break through FVG");
         return false;
      }

      bool wick_in = false, close_out = false, touch50 = false, close50 = false;
      const ENUM_MM_ENTRY_MODEL model = CMMEntryModels::Detect(m_setup.direction, closed,
                                                               m_setup.fvg.high, m_setup.fvg.low,
                                                               wick_in, close_out, touch50, close50);
      if(model == MM_MODEL_NONE)
      {
         m_setup.state = MM_ST_WAITING_FOR_RETEST;
         LogWaitOnce();
         return false;
      }

      m_setup.state = MM_ST_ENTRY_VALIDATION;
      if(m_log != NULL)
      {
         m_log.Entry("Model=" + IntegerToString((int)model));
         if(model == MM_MODEL_WICK)
         {
            m_log.Entry("WickIntoFVG=" + (wick_in ? "true" : "false"));
            m_log.Entry("CloseOutside=" + (close_out ? "true" : "false"));
         }
         else
         {
            m_log.Entry("Touch50=" + (touch50 ? "true" : "false"));
            m_log.Entry("CloseOutside50=" + (close50 ? "true" : "false"));
         }
         m_log.Entry("Decision=" + MM_DirToString(m_setup.direction));
      }

      string reason = "";
      if(!m_cd.AllowsEntry(TimeCurrent(), reason))
      {
         m_setup.last_reject = reason;
         if(m_log != NULL)
            m_log.NoTrade(reason);
         m_setup.state = MM_ST_WAITING_FOR_RETEST;
         return false;
      }
      if(!m_pos.CanOpenAnother(reason))
      {
         m_setup.last_reject = reason;
         if(m_log != NULL)
            m_log.NoTrade(reason);
         m_setup.state = MM_ST_WAITING_FOR_RETEST;
         return false;
      }

      const double entry = (m_setup.direction == MM_DIR_BUY) ? m_sym.Ask() : m_sym.Bid();
      SMMEntryPlan plan;
      if(!m_risk.BuildPlan(m_sym.Spec(), *m_sym, m_setup.direction, m_setup.fvg, m_setup.fib, entry, model, plan))
      {
         m_setup.plan = plan;
         m_setup.last_reject = plan.reject_reason;
         if(m_stats != NULL)
            m_stats.OnSetupRejected();
         if(m_log != NULL)
            m_log.NoTrade(plan.reject_reason);
         m_setup.state = MM_ST_WAITING_FOR_RETEST;
         return false;
      }
      m_setup.plan = plan;
      if(m_stats != NULL)
      {
         m_stats.OnValidSetup();
         m_stats.OnOrderAttempt();
      }
      if(!m_trade.Open(*m_sym, plan, reason))
      {
         m_setup.last_reject = reason;
         if(m_stats != NULL)
            m_stats.OnOrderRejected();
         m_setup.state = MM_ST_WAITING_FOR_RETEST;
         return false;
      }
      if(m_stats != NULL)
      {
         m_stats.OnTradeExecuted(model);
         m_stats.OnFvgTraded();
         RememberFill(plan);
      }
      m_fvg.MarkLife(m_setup.fvg.id, MM_FVG_TRADED);
      m_setup.state = MM_ST_ORDER_SENT;
      if(m_log != NULL)
         m_log.State("ORDER_SENT");
      return true;
   }

public:
   CMMStateMachine()
   {
      m_last_m15 = 0;
      m_last_h4 = 0;
      m_last_d1 = 0;
      m_fib_fp = "";
      m_logged_wait = false;
      MM_ResetSetup(m_setup);
   }

   void Bind(CMMConfig *cfg, CMMLogger *log, CMMDirectionEngine *dir, CMMFVGEngine *fvg,
             CMMRiskEngine *risk, CMMTradeManager *trade, CMMPositionManager *pos,
             CMMCooldownManager *cd, CMMBacktestStats *stats,
             CMMSymbolProvider *sym)
   {
      m_cfg = cfg;
      m_log = log;
      m_dir = dir;
      m_fvg = fvg;
      m_risk = risk;
      m_trade = trade;
      m_pos = pos;
      m_cd = cd;
      m_stats = stats;
      m_sym = sym;
   }

   SMMSetup Setup() const { return m_setup; }
   SMMEntryPlan LastPlan() const { return m_setup.plan; }

   void NotifyManagedPositionClosed()
   {
      if(m_setup.state == MM_ST_ORDER_SENT || m_setup.state == MM_ST_POSITION_ACTIVE)
         GoIdle("position closed");
   }

   void Process()
   {
      const datetime now = TimeCurrent();
      if(m_cd.Active(now))
      {
         m_setup.state = MM_ST_COOLDOWN;
         return;
      }
      if(m_setup.state == MM_ST_COOLDOWN)
         GoIdle("cooldown expired");

      const int open_n = m_pos.CountOpen();
      if(m_setup.state == MM_ST_ORDER_SENT || m_setup.state == MM_ST_POSITION_ACTIVE)
      {
         if(open_n > 0)
         {
            m_setup.state = MM_ST_POSITION_ACTIVE;
            return;
         }
      }

      const bool new_d1 = NewBar(MM_TF_DAILY, m_last_d1);
      const bool new_h4 = NewBar(MM_TF_H4, m_last_h4);
      const bool new_m15 = NewBar(MM_TF_M15, m_last_m15);
      if(!new_d1 && !new_h4 && !new_m15 && m_setup.fvg.id == 0)
      {
         if(m_setup.state == MM_ST_IDLE)
            return;
      }

      m_setup.state = (m_setup.state == MM_ST_IDLE) ? MM_ST_ANALYZING_DIRECTION : m_setup.state;
      SMMDirection dir;
      if(!m_dir.Update(m_sym.SymbolName(), dir))
      {
         if(m_setup.fvg.id != 0)
            GoIdle("direction lost");
         else
            m_setup.state = MM_ST_ANALYZING_DIRECTION;
         return;
      }
      m_setup.dir = dir;
      m_setup.direction = (dir.aligned == MM_BIAS_BULLISH) ? MM_DIR_BUY : MM_DIR_SELL;

      SMMFib fib;
      if(!CMMFibonacciEngine::BuildFromLastHighLastLow(m_sym.SymbolName(), m_setup.direction,
                                                        m_cfg.in.structure_lookback, fib))
      {
         GoIdle("fibonacci unavailable");
         return;
      }
      m_setup.fib = fib;
      CMMFibonacciEngine::LogOnce(m_log, fib, m_fib_fp);

      if(new_m15 || m_setup.fvg.id == 0)
      {
         ulong prev_ids[];
         int prev_lives[];
         SnapshotFvgs(prev_ids, prev_lives);
         m_fvg.Scan(m_sym.SymbolName(), fib, m_setup.direction);
         AccountFvgScan(prev_ids, prev_lives);
      }

      if(m_setup.fvg.id != 0)
      {
         SMMFVG live;
         if(!m_fvg.GetById(m_setup.fvg.id, live) || live.life == MM_FVG_INVALIDATED)
         {
            InvalidateFVG("FVG invalidated");
            return;
         }
         if(live.life == MM_FVG_EXPIRED)
         {
            if(m_log != NULL)
               m_log.Fvg("Decision=EXPIRED");
            GoIdle("FVG expired");
            return;
         }
         m_setup.fvg = live;
         if(new_m15)
            TryEnterOnClosedM15();
         return;
      }

      SMMFVG found;
      if(m_fvg.LatestValidInZone(m_setup.direction, found))
      {
         m_setup.fvg = found;
         m_setup.setup_id = found.id;
         m_setup.state = MM_ST_WAITING_FOR_RETEST;
         m_logged_wait = false;
         if(m_log != NULL)
         {
            m_log.Fvg("Direction=" + MM_DirToString(found.direction));
            m_log.Fvg("FVGHigh=" + DoubleToString(found.high, m_sym.Spec().digits));
            m_log.Fvg("FVGLow=" + DoubleToString(found.low, m_sym.Spec().digits));
            m_log.Fvg("FVG50=" + DoubleToString(found.mid, m_sym.Spec().digits));
            m_log.Fvg("Position=" + (found.direction == MM_DIR_BUY ? "DISCOUNT" : "PREMIUM"));
            m_log.Fvg("Decision=VALID");
         }
         LogWaitOnce();
         if(new_m15)
            TryEnterOnClosedM15();
         return;
      }
      m_setup.state = MM_ST_WAITING_FOR_FVG;
   }
};

#endif

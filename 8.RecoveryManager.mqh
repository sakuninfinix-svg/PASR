//+------------------------------------------------------------------+
//|                                              RecoveryManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+

#ifndef __RECOVERY_MANAGER_MQH__
#define __RECOVERY_MANAGER_MQH__

#property strict
#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "7.RiskCalculator.mqh"

//+------------------------------------------------------------------+
//| RecoveryManager - Event-Driven Position Lifecycle Manager       |
//| Subscribes: PriceUpdate, OrderExecution, SignalGenerated,       |
//|             EmergencyStop, Heartbeat, ConfigReload              |
//+------------------------------------------------------------------+
class RecoveryManager : public IManager 
{
//+------------------------------------------------------------------+
//| PRIVATE: State & Cache                                          |
//+------------------------------------------------------------------+
private:
   RiskCalculator  m_riskCalc;  // For BE/Partial calculations
   RecoveryEngine* engines[];
   CTrade          m_trade;
   
   // Event-Driven State
   datetime        m_lastTrailingUpdate;    // Throttle trailing modifications
   int             m_trailingThrottleMs;    // Min interval between trailing updates
   
   // Config Cache (avoid repeated CFG reads)
   struct RecoveryConfigCache {
      bool   useTrailing;
      bool   usePartialClose;
      double trailingStartATR;
      double trailingBufferATR;
      double trailActivationATR;
      double trailStepATR;
      double lockProfitATR;
      double lockOffsetATR;
      double partialCloseLotPct;
      double partialCloseATR;
      int    maxTradeDurationDays;
      bool   exitOnOpposite;
      ulong  magicNum;
      bool   debugMode;
   } m_cfgCache;

//+------------------------------------------------------------------+
//| PRIVATE: Core Logic (Extracted & Optimized)                     |
//+------------------------------------------------------------------+
private:
   virtual void RefreshConfigCache() override
   {
      m_cfgCache.useTrailing = CFG.UseTrailing;
      m_cfgCache.usePartialClose = CFG.UsePartialClose;
      m_cfgCache.trailingStartATR = CFG.TrailingStartATR;
      m_cfgCache.trailingBufferATR = CFG.TrailingBufferATR;
      m_cfgCache.trailActivationATR = CFG.TrailActivationATR;
      m_cfgCache.trailStepATR = CFG.TrailStepATR;
      m_cfgCache.lockProfitATR = CFG.LockProfitATR;
      m_cfgCache.lockOffsetATR = CFG.LockOffsetATR;
      m_cfgCache.partialCloseLotPct = CFG.PartialCloseLotPct;
      m_cfgCache.partialCloseATR = CFG.PartialCloseATR;
      m_cfgCache.maxTradeDurationDays = CFG.MaxTradeDurationDays;
      m_cfgCache.exitOnOpposite = CFG.ExitOnOpposite;
      m_cfgCache.magicNum = CFG.MagicNum;
      m_cfgCache.debugMode = CFG.DebugMode;
      
      // Refresh RiskCalculator config
      m_riskCalc.LoadConfig();
   }

   int FindEngineIndex(ulong ticket) 
   {
      for(int i = 0; i < ArraySize(engines); i++) {
         if(CheckPointer(engines[i]) != POINTER_INVALID && engines[i].active && engines[i].mainTicket == ticket)
            return i;
      }
      return -1;
   }

   void ClearEngineGVs(ulong ticket) 
   {
      string prefix = "PASR_" + (string)m_cfgCache.magicNum + "_" + (string)ticket + "_";
      GlobalVariablesDeleteAll(prefix);
   }

   void CloseActivePosition(RecoveryEngine *r, const string reason) 
   {
      if(CheckPointer(r) == POINTER_INVALID || r.state == TRADE_STATE_DONE) return;
      r.state = TRADE_STATE_DONE;

      bool closed = false;
      if(PositionSelectByTicket(r.mainTicket)) 
      {
         if(m_trade.PositionClose(r.mainTicket)) {
            closed = true;
            if(m_cfgCache.debugMode) 
               PrintFormat("[Recovery] Position %d closed: %s", r.mainTicket, reason);
         } else {
            if(m_cfgCache.debugMode) 
               PrintFormat("[Recovery] Failed to close %d: Error %d", r.mainTicket, GetLastError());
         }
      }

      ClearEngineGVs(r.mainTicket);
      r.Reset();
      r.active = false;
      
      // Notify other modules
      PositionUpdateEvent* notify = new PositionUpdateEvent(r.mainTicket, 0, 0, true);
      EventBus::Instance().Dispatch(notify);
   }

   void ProcessTrailingAndPartial(RecoveryEngine *r, const MqlTick &tick, double atrPoints) 
   {
      if(CheckPointer(r) == POINTER_INVALID || !r.active || !PositionSelectByTicket(r.mainTicket)) return;
      if(r.state != TRADE_STATE_NORMAL) return;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double slPrice = PositionGetDouble(POSITION_SL);
      double tpPrice = PositionGetDouble(POSITION_TP);
      double curLot = PositionGetDouble(POSITION_VOLUME);
      double atr = atrPoints * _Point;
      double curPrice = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      double profitATR = (type == POSITION_TYPE_BUY) ? (curPrice - openPrice) / atr : (openPrice - curPrice) / atr;

      // === PARTIAL CLOSE LOGIC ===
      if(m_cfgCache.usePartialClose && !r.partialClosed && curLot > 0) {
         bool touchPartial = (type == POSITION_TYPE_BUY) ? (curPrice >= r.partialTP) : (curPrice <= r.partialTP);
         if(touchPartial && !r.partialArmedNormal) {
            r.partialArmedNormal = true;
            r.SaveState(m_cfgCache.magicNum);
         }
         if(r.partialArmedNormal) {
            bool recross = (type == POSITION_TYPE_BUY) ? (curPrice <= r.partialTP + atr * 0.1) : (curPrice >= r.partialTP - atr * 0.1);
            if(recross) { // If price recrosses the partial TP level, execute partial close
               double closeLot = m_data.NormalizeVolume(_Symbol, curLot * m_cfgCache.partialCloseLotPct);
               double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               if(closeLot >= minVol) {
                  if(m_trade.PositionClosePartial(r.mainTicket, closeLot)) {
                     r.partialArmedNormal = false;
                     r.partialClosed = true;
                     r.lastActionTick = GetTickCount64();
                     r.SaveState(m_cfgCache.magicNum);
                     if(m_cfgCache.debugMode) Print("[Recovery] Partial closed for ticket: ", r.mainTicket);
                  }
               }
            }
         }
      }

      // === TRAILING STOP LOGIC (Throttled) ===
      if(!m_cfgCache.useTrailing) return;
      if(GetMicrosecondCount() - m_lastTrailingUpdate < m_trailingThrottleMs * 1000) return;

      double newSL = slPrice;
      double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double minModifyStep = atr * 0.12;

      if(type == POSITION_TYPE_BUY) {
         if(profitATR >= m_cfgCache.lockProfitATR)
            newSL = MathMax(newSL, openPrice + atr * m_cfgCache.lockOffsetATR);
         if(profitATR >= m_cfgCache.trailActivationATR)
            newSL = MathMax(newSL, curPrice - atr * m_cfgCache.trailStepATR); // Trailing SL

         if(newSL > slPrice + minModifyStep && (curPrice - newSL) > stopLevel) {
            if(m_trade.PositionModify(r.mainTicket, NormalizeDouble(newSL, _Digits), tpPrice)) {
               r.SaveState(m_cfgCache.magicNum);
               m_lastTrailingUpdate = GetMicrosecondCount();
               if(m_cfgCache.debugMode) PrintFormat("[Recovery] Trailing BUY %d to %.5f (TP: %.5f)", r.mainTicket, newSL, tpPrice);
            }
         }
      } else { // SELL
         if(profitATR >= m_cfgCache.lockProfitATR) {
            double trailBase = openPrice - atr * m_cfgCache.lockOffsetATR;
            if(newSL == 0 || trailBase < newSL) newSL = trailBase;
         }
         if(profitATR >= m_cfgCache.trailActivationATR) {
            double dynamicSL = curPrice + atr * m_cfgCache.trailStepATR;
            if(newSL == 0 || dynamicSL < newSL) newSL = dynamicSL;
         }
         if(newSL > 0 && (slPrice <= 0 || newSL < slPrice - minModifyStep) && (newSL - curPrice) > stopLevel) {
            if(m_trade.PositionModify(r.mainTicket, NormalizeDouble(newSL, _Digits), tpPrice)) {
               r.SaveState(m_cfgCache.magicNum);
               m_lastTrailingUpdate = GetMicrosecondCount();
               if(m_cfgCache.debugMode) PrintFormat("[Recovery] Trailing SELL %d to %.5f (TP: %.5f)", r.mainTicket, newSL, tpPrice);
            }
         }
      }
   }

   void VerifyAndCleanupEngines() 
   {
      for(int i = ArraySize(engines) - 1; i >= 0; i--) 
      {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) == POINTER_INVALID || !r.active) continue;
         
         // Check if position still exists
         if(!PositionSelectByTicket(r.mainTicket)) {
            if(m_cfgCache.debugMode) 
               PrintFormat("[Recovery] Position %d closed externally. Cleaning engine.", r.mainTicket);
            r.active = false;
            ClearEngineGVs(r.mainTicket);
            r.Reset();
            continue;
         }
         
         // Check max duration
         if(m_cfgCache.maxTradeDurationDays > 0 && r.entryTime > 0) {
            if(TimeCurrent() > r.entryTime + (m_cfgCache.maxTradeDurationDays * 86400)) {
               CloseActivePosition(r, "Max Duration Timeout");
               continue;
            }
         }
         
         // Update peak equity
         r.peakEquity = MathMax(r.peakEquity, AccountInfoDouble(ACCOUNT_EQUITY));
      }
   }

//+------------------------------------------------------------------+
//| PUBLIC: Event Handler Implementation                            |
//+------------------------------------------------------------------+
public:
   RecoveryManager() : IManager("RecoveryManager", 25)
   {
      m_lastTrailingUpdate = 0;
      m_trailingThrottleMs = 500; // Max 2 trailing updates/sec per engine
      ArrayResize(engines, 0);
   }

   virtual void DeclareEvents() override {
      AddEvent("PriceUpdate");
      AddEvent("OrderExecution");
      AddEvent("SignalGenerated");
   }

   ~RecoveryManager() 
   {
      for(int i = ArraySize(engines) - 1; i >= 0; i--) {
         if(CheckPointer(engines[i]) == POINTER_DYNAMIC) {
            delete engines[i];
            engines[i] = NULL;
         }
      }
      ArrayResize(engines, 0);
   }

//+------------------------------------------------------------------+
//| PUBLIC: Event Handler Methods                                   |
//+------------------------------------------------------------------+
public:
   virtual void OnPriceUpdate(PriceUpdateEvent* e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || ArraySize(engines) == 0 || !m_initialized) return;
      
      double atrPoints = 0;
      if(CheckPointer(m_data) != POINTER_INVALID) 
         atrPoints = m_data.GetATRPoints();
      if(atrPoints <= 0) return;

      for(int i = 0; i < ArraySize(engines); i++) {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active) {
            ProcessTrailingAndPartial(r, e.tick, atrPoints);
         }
      }
   }

   virtual void OnOrderExecution(OrderExecutionEvent* e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !e.success) return;
      
      // Only register if magic & symbol match
      if(e.orderType != ORDER_TYPE_BUY && e.orderType != ORDER_TYPE_SELL) return;
      if(e.ticket > 0) {
         Register(e.ticket, e.orderType, e.entryPrice, e.tp, e.sl, 
                  0.0, e.volume, 0.0); 
      }
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent* e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !m_cfgCache.exitOnOpposite) return;
      CloseOppositePositions(e.signal.orderType);
   }

   virtual void OnEmergencyStop(EmergencyStopEvent* e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      Log("EMERGENCY STOP triggered: " + e.reason);
      
      for(int i = ArraySize(engines) - 1; i >= 0; i--) {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active) {
            CloseActivePosition(r, "Emergency: " + e.reason);
         }
      }
   }

   virtual void OnHeartbeat(HeartbeatEvent* e) override
   {
      VerifyAndCleanupEngines();
   }

   virtual void OnConfigReload(ConfigReloadEvent* e) override
   {
      IManager::OnConfigReload(e);
      if(m_cfgCache.debugMode) Print("[Recovery] Config cache refreshed.");
   }

//+------------------------------------------------------------------+
//| PUBLIC: Integration Methods (Backward Compatible)               |
//+------------------------------------------------------------------+
public:
   virtual bool Init() override 
   {
      if(!IManager::Init()) return false;
      m_trade.SetExpertMagicNumber(m_cfgCache.magicNum);
      return true;
   }

   RecoveryEngine* GetEngine(ulong ticket) 
   {
      int idx = FindEngineIndex(ticket);
      return (idx != -1) ? engines[idx] : NULL;
   }

   void Register(ulong ticket, ENUM_ORDER_TYPE type, double entry, double tp, 
                 double brokerSL, double atr, double lot, double zonePrice) 
   {
      if(FindEngineIndex(ticket) >= 0) return;

      int targetIdx = -1;
      int total = ArraySize(engines);
      for(int i = 0; i < total; i++) {
         if(CheckPointer(engines[i]) == POINTER_INVALID || !engines[i].active) {
            targetIdx = i; break;
         }
      }

      if(targetIdx == -1) {
         targetIdx = total;
         ArrayResize(engines, total + 1);
         engines[targetIdx] = new RecoveryEngine();
         if(CheckPointer(engines[targetIdx]) == POINTER_INVALID) {
            if(m_cfgCache.debugMode) PrintFormat("[Recovery] CRITICAL: Failed to allocate engine for %d", ticket);
            ArrayResize(engines, total);
            return;
         }
      }

      RecoveryEngine *target = engines[targetIdx];
      target.Reset();
      target.active = true;
      target.mainTicket = ticket;
      target.direction = (type == ORDER_TYPE_BUY ? 1 : -1);
      target.state = TRADE_STATE_NORMAL;
      target.entryPrice = entry;
      target.initialTP = tp;
      target.brokerSL = brokerSL;
      target.lastKnownATR = (atr > 0) ? atr : m_data.GetATRPoints();
      target.zonePrice = zonePrice;
      target.lot = lot;
      target.peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      target.entryTime = TimeCurrent();
      
      // Partial TP setup
      double pcDist = target.lastKnownATR * CFG.PartialCloseATR * _Point;
      target.partialTP = NormalizeDouble(entry + ((type == ORDER_TYPE_BUY ? 1.0 : -1.0) * pcDist), _Digits);
      target.SaveState(m_cfgCache.magicNum);

      if(m_cfgCache.debugMode) 
         PrintFormat("[Recovery] Registered position %d | Type: %s | Lot: %.2f", ticket, (type==ORDER_TYPE_BUY?"BUY":"SELL"), lot);
   }

   void CloseOppositePositions(ENUM_ORDER_TYPE signalType) 
   {
      int oppositeDir = (signalType == ORDER_TYPE_BUY) ? -1 : 1;
      for(int i = ArraySize(engines) - 1; i >= 0; i--) {
         RecoveryEngine *r = engines[i];
         if(CheckPointer(r) != POINTER_INVALID && r.active && r.direction == oppositeDir)
            CloseActivePosition(r, "Opposite Signal Triggered");
      }
   }
};

#endif

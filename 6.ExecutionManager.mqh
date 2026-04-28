//+------------------------------------------------------------------+
//|                                             ExecutionManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
#ifndef __EXECUTION_MANAGER_MQH__
#define __EXECUTION_MANAGER_MQH__

#property strict
#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "7.RiskCalculator.mqh"

//+------------------------------------------------------------------+
//| Subscribes: SignalGenerated, ConfigReload, EmergencyStop,        |
//|             Heartbeat                                            |
//+------------------------------------------------------------------+
class ExecutionManager : public IManager 
{
//+------------------------------------------------------------------+
//| PRIVATE: State & Cache                                          |
//+------------------------------------------------------------------+
private:
   RiskCalculator  m_riskCalc;  // Independent risk module
   datetime        m_lastOrderTime;
   int             m_orderThrottleMs;
   
   // Config Cache
   struct ExecConfigCache {
      bool   useAutoLot;
      double riskPct;
      double lotSize;
      double qualityLotMult;
      double minTPDistanceATR;
      double atrBufferMult;
      double slBufferATR;
      double tpBufferATR;
      ulong  magicNum;
      bool   debugMode;
      ENUM_ENTRY_MODE entryMode;
   } m_cfgCache;

//+------------------------------------------------------------------+
//| PRIVATE: Core Logic                                             |
//+------------------------------------------------------------------+
private:
   virtual void RefreshConfigCache() override
   {
      m_cfgCache.useAutoLot = CFG.UseAutoLot;
      m_cfgCache.riskPct = CFG.RiskPct;
      m_cfgCache.lotSize = CFG.LotSize;
      m_cfgCache.qualityLotMult = CFG.QualityLotMult;
      m_cfgCache.minTPDistanceATR = CFG.MinTPDistanceATR;
      m_cfgCache.atrBufferMult = CFG.ATRBufferMult;
      m_cfgCache.slBufferATR = CFG.SLBufferATR;
      m_cfgCache.tpBufferATR = CFG.TPBufferATR;
      m_cfgCache.magicNum = CFG.MagicNum;
      m_cfgCache.debugMode = CFG.DebugMode;
      m_cfgCache.entryMode = CFG.EntryMode;
      
      // Refresh RiskCalculator config
      m_riskCalc.LoadConfig();
   }

   string MakePendingPrefix(const string symbol, ulong tsID) const
   {
      return "PASR_PEND_" + (string)m_cfgCache.magicNum + "_" + symbol + "_" + (string)tsID + "_";
   }

   void SavePendingState(const OrderPlan &plan, double zonePrice, const string symbol, ulong tsID) const
   {
      string p = MakePendingPrefix(symbol, tsID);
      GlobalVariableSet(p + "zprice", zonePrice);
      GlobalVariableSet(p + "atr",   plan.atrUsed); 
      GlobalVariableSet(p + "lot",   plan.lot);
      GlobalVariableSet(p + "type",  (double)plan.type);
      GlobalVariableSet(p + "entry", plan.entry);
      GlobalVariableSet(p + "tp",    plan.tp);
      GlobalVariableSet(p + "ts",    (double)TimeCurrent());
   }

   void DeletePendingStateById(const string symbol, ulong tsID) const
   {
      string prefix = MakePendingPrefix(symbol, tsID);
      GlobalVariablesDeleteAll(prefix);
   }

   void ScavengePendingGVs() 
   {
      string pattern = "PASR_PEND_" + (string)m_cfgCache.magicNum + "_" + _Symbol + "_";
      int total = GlobalVariablesTotal();
      
      for(int i = total - 1; i >= 0; i--) 
      {
         string gvName = GlobalVariableName(i);
         if(StringFind(gvName, pattern) != 0) continue;
         if(StringFind(gvName, "_ts") < 0) continue;
         
         datetime ts = (datetime)GlobalVariableGet(gvName + "_ts");
         if(TimeCurrent() - ts <= 120) continue; // Keep pending up to 2 minutes

         // Extract tsID
         int start = StringLen(pattern);
         int end = StringFind(gvName, "_ts");
         if(end <= start) continue;
         string tsID_str = StringSubstr(gvName, start, end - start);
         
         // Verify if still active in market
         bool stillActive = false;
         for(int j = 0; j < OrdersTotal(); j++) {
            ulong o = OrderGetTicket(j);
            if(o > 0 && StringFind(OrderGetString(ORDER_COMMENT), tsID_str) >= 0) {
               stillActive = true; break;
            }
         }
         for(int j = 0; j < PositionsTotal(); j++) {
            ulong p = PositionGetTicket(j);
            if(p > 0 && PositionSelectByTicket(p) && 
               StringFind(PositionGetString(POSITION_COMMENT), tsID_str) >= 0) {
               stillActive = true; break;
            }
         }

         if(!stillActive) {
            DeletePendingStateById(_Symbol, (ulong)StringToInteger(tsID_str));
            if(m_cfgCache.debugMode) PrintFormat("[Execution] Cleaned orphaned GV: %s", tsID_str);
         }
      }
   }

   bool ValidateOrderLevels(ENUM_ORDER_TYPE type, double price, double sl, double tp, 
                           string &reason, double atrPoints) const
   {
      double stopLevelPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double stopLevel = stopLevelPts * _Point;
      double minTPDist = atrPoints * m_cfgCache.minTPDistanceATR * _Point;
      double requiredTP = MathMax(stopLevel, minTPDist);

      if(type == ORDER_TYPE_BUY) {
         if(tp <= price + _Point) { reason = "BUY TP <= price"; return false; }
         if(sl > 0 && sl >= price - _Point) { reason = "BUY SL >= price"; return false; }
         if(tp - price < requiredTP) { reason = "BUY TP too close to price"; return false; }
         if(sl > 0 && price - sl < stopLevel) { reason = "BUY SL violates stop level"; return false; }
      } else {
         if(tp >= price - _Point) { reason = "SELL TP >= price"; return false; }
         if(sl > 0 && sl <= price + _Point) { reason = "SELL SL <= price"; return false; }
         if(price - tp < requiredTP) { reason = "SELL TP too close to price"; return false; }
         if(sl > 0 && sl - price < stopLevel) { reason = "SELL SL violates stop level"; return false; }
      }
      reason = "OK";
      return true;
   }

//+------------------------------------------------------------------+
//| PUBLIC: Event Handler Implementation                            |
//+------------------------------------------------------------------+
public:
   ExecutionManager() : IManager("ExecutionManager", 40)
   {
      m_lastOrderTime = 0;
      m_orderThrottleMs = 2000; // Min 2s between orders to prevent spam
   }

   virtual void DeclareEvents() override {
      AddEvent("SignalGenerated");
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent* e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !m_isInitialized) return;
      
      // Throttle: prevent rapid fire
      if(GetTickCount64() - m_lastOrderTime < m_orderThrottleMs) {
         if(m_cfgCache.debugMode) Print("[Execution] Order throttled. Skipping.");
         return;
      }

      // Throttle: max 1 per bar
      datetime currBar = iTime(_Symbol, _Period, 0);
      static datetime lastBarExecuted = 0;
      if(currBar == lastBarExecuted) {
         if(m_cfgCache.debugMode) Print("[Execution] Already executed this bar. Skipping.");
         return;
      }

      // Fetch required params (decoupled via event or direct getter)
      double atr = e.atrPoints;
      double sup = e.support;
      double res = e.resistance;
      
      if(atr <= 0 || sup <= 0 || res <= 0) {
         if(m_cfgCache.debugMode) Print("[Execution] Invalid market data. Skipping execution.");
         return;
      }

      OrderPlan plan;
      if(BuildOrderPlan(e.signal, plan, sup, res, atr)) 
      {
         ulong reqID = Open(plan, e.signal.zonePrice);
         if(reqID > 0) {
            lastBarExecuted = currBar;
            m_lastOrderTime = GetTickCount64();
            
            // Notify other modules
            OrderExecutionEvent* execEvent = new OrderExecutionEvent(
               true, reqID, plan.type, plan.entry, plan.brokerSL, plan.tp, plan.lot, "AsyncAccepted"
            );
            EventBus::Instance().Dispatch(execEvent);
         }
      }
   }

   virtual void OnEmergencyStop(EmergencyStopEvent* e) override
   {
      if(m_cfgCache.debugMode) Print("[Execution] EMERGENCY STOP: Halting new orders.");
      // Throttle will block new orders. Optionally clear pending GVs:
      GlobalVariablesDeleteAll("PASR_PEND_" + (string)m_cfgCache.magicNum + "_" + _Symbol + "_");
   }

   virtual void OnConfigReload(ConfigReloadEvent* e) override
   {
      RefreshConfigCache();
      if(m_cfgCache.debugMode) Print("[Execution] Config cache refreshed.");
   }

   virtual void OnHeartbeat(HeartbeatEvent* e) override
   {
      ScavengePendingGVs();
   }

//+------------------------------------------------------------------+
//| PUBLIC: Integration & Backward Compatible Methods               |
//+------------------------------------------------------------------+
public:

   bool BuildOrderPlan(const SignalDecision &decision, OrderPlan &plan, 
                      double support, double resistance, double atrPoints) 
   {
      ZeroMemory(plan);
      plan.type = decision.orderType;
      plan.atrUsed = atrPoints;

      if(support <= 0 || resistance <= 0) {
         if(m_cfgCache.debugMode) Print("[Exec Build] Error: Invalid SR levels.");
         return false;
      }

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(bid <= 0 || ask <= 0) {
         if(m_cfgCache.debugMode) Print("[Exec Build] Error: Invalid market prices.");
         return false;
      }

      plan.entry = (plan.type == ORDER_TYPE_BUY) ? ask : bid;
      double atrPrice = atrPoints * _Point;

      if(plan.type == ORDER_TYPE_BUY) {
         double sl = support - (atrPoints * m_cfgCache.slBufferATR * _Point); // SL below support
         double tp = resistance - (atrPoints * m_cfgCache.tpBufferATR * _Point); // TP below resistance
         plan.brokerSL = m_data ? m_data.NormalizePrice(_Symbol, sl) : NormalizeDouble(sl, _Digits);
         plan.tp       = m_data ? m_data.NormalizePrice(_Symbol, tp) : NormalizeDouble(tp, _Digits);
      } else {
         double sl = resistance + (atrPoints * m_cfgCache.slBufferATR * _Point); // SL above resistance
         double tp = support + (atrPoints * m_cfgCache.tpBufferATR * _Point); // TP above support
         plan.brokerSL = m_data ? m_data.NormalizePrice(_Symbol, sl) : NormalizeDouble(sl, _Digits);
         plan.tp       = m_data ? m_data.NormalizePrice(_Symbol, tp) : NormalizeDouble(tp, _Digits);
      }

      // Guard: price already far past zone
      if((plan.type == ORDER_TYPE_BUY && plan.entry < support - (atrPrice * 0.5)) || 
         (plan.type == ORDER_TYPE_SELL && plan.entry > resistance + (atrPrice * 0.5))) {
         if(m_cfgCache.debugMode) Print("[Exec Build] Abort: Price far past zone.");
         return false;
      }

      // Lot Calculation - Use RiskCalculator module
      double slDistancePoints = MathAbs(plan.entry - plan.brokerSL) / _Point;
      if(slDistancePoints < 10) slDistancePoints = 10;
      
      // Validate SL/TP distances using RiskCalculator
      string validationReason;
      double tpDistancePoints = (plan.tp > 0) ? MathAbs(plan.entry - plan.tp) / _Point : 0;
      if(!m_riskCalc.ValidateDistances(slDistancePoints, tpDistancePoints, atrPoints, validationReason)) {
         if(m_cfgCache.debugMode) Print("[Exec Build] Risk validation failed: ", validationReason);
         return false;
      }
      
      // Calculate lot size with quality multiplier
      int qualityScore = decision.orderType == ORDER_TYPE_BUY ? decision.bias : -decision.bias;
      double signalQuality = (qualityScore == 0) ? 1.5 : 1.0; // High quality if aligned
      
      double baseLot = m_riskCalc.CalculateLotSize(slDistancePoints, signalQuality);
      
      plan.lot = baseLot;
      plan.comment = m_data ? m_data.BuildComment(plan.type==ORDER_TYPE_BUY?"BUY":"SELL", decision.bias, m_cfgCache.entryMode) : 
                               "P_EXEC";

      string reason;
      if(!ValidateOrderLevels(plan.type, plan.entry, plan.brokerSL, plan.tp, reason, atrPoints)) {
         if(m_cfgCache.debugMode) Print("[Exec Build] Validation failed: ", reason);
         return false;
      }

      return true;
   }

   ulong Open(const OrderPlan &plan, double zonePrice) 
   {
      if(plan.lot <= 0 || plan.entry <= 0 || plan.atrUsed <= 0) {
         if(m_cfgCache.debugMode) Print("[Exec Open] Abort: Invalid parameters.");
         return 0;
      }

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action       = TRADE_ACTION_DEAL;
      request.symbol       = _Symbol;
      request.magic        = m_cfgCache.magicNum;
      request.volume       = plan.lot;
      request.type         = plan.type;
      request.price        = plan.entry;
      request.sl           = plan.brokerSL;
      request.tp           = plan.tp;
      request.deviation    = 30;
      request.type_time    = ORDER_TIME_GTC;

      long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_IOC) != 0) request.type_filling = ORDER_FILLING_IOC;
      else if((filling & SYMBOL_FILLING_FOK) != 0) request.type_filling = ORDER_FILLING_FOK;
      else request.type_filling = ORDER_FILLING_RETURN;

      ulong tsID = GetTickCount64() % 10000000000; 
      request.comment = plan.comment + "#" + (string)tsID;
      
      // Save pending state BEFORE sending (for async tracking)
      SavePendingState(plan, zonePrice, _Symbol, tsID);

      if(!OrderSendAsync(request, result)) {
         DeletePendingStateById(_Symbol, tsID);
         if(m_cfgCache.debugMode) PrintFormat("[Exec Async] OrderSend failed: %d", GetLastError());
         return 0;
      }

      if(m_cfgCache.debugMode) 
         PrintFormat("[Exec Async] Request sent: %s %.2f @ %.5f | ID: %d", 
                    EnumToString(plan.type), plan.lot, plan.entry, tsID);

      return tsID;
   }
};

#endif

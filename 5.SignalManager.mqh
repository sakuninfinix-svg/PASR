//+------------------------------------------------------------------+
//|                                                SignalManager.mqh |
//|                              Event-Driven Version for PASR EA    |
//|                                     Copyright 2026, Agsicentre   |
//+------------------------------------------------------------------+
#ifndef __SIGNAL_MANAGER_MQH__
#define __SIGNAL_MANAGER_MQH__

#property strict
#include "IManager.mqh"
#include "9.PatternManager.mqh"

//+------------------------------------------------------------------+
//| SignalManager - Event-Driven Implementation                    |
//| Handles: PriceUpdate, NewBar, ConfigReload, EmergencyStop      |
//+------------------------------------------------------------------+
class SignalManager : public IManager 
{
//+------------------------------------------------------------------+
//| PRIVATE: Internal State & Cache                                 |
//+------------------------------------------------------------------+
private:
   // --- Pattern Detection ---
   PatternManager m_patterns;
   
   // --- Zone Tracking ---
   double         m_lastBuyZonePrice;
   double         m_lastSellZonePrice;
   datetime       m_lastBuyZoneBar;
   datetime       m_lastSellZoneBar;
   
   // --- Signal Cooldown ---
   struct SignalCooldown {
      double   price;
      datetime expiry;
   };
   SignalCooldown m_signalCooldowns[];

   // --- Failure Cooldown ---
   struct FailedZone {
      double   price;
      datetime expiry;
   };
   FailedZone     m_failedZones[];
   
   // --- Event-Driven State Flags ---
   bool           m_hasNewTick;      
   bool           m_hasNewBar; 
   MqlTick        m_cachedTick;  
   datetime       m_lastProcessedBar;
   SignalDecision m_pendingSignal; 
   bool           m_signalPending; 
   
   // --- Cached Market Data from Events ---
   struct CachedMarketData {
      double atrPoints;
      double support, resistance;
      double htfSupport, htfResistance;
      bool   isSupBroken, isResBroken;
      double supBufferMult, resBufferMult;
      int    supHtfAlign, resHtfAlign;
      
      void Reset() { ZeroMemory(this); }
   } m_marketData;

   // --- Config Cache (hindari repeated CFG access) ---
   struct CachedConfig {
      int      signalLookback;
      bool     useMTF;
      bool     exitOnOpposite;
      double   zoneReuseATR;
      int      patternFailureCooldownBars;
      ENUM_ENTRY_MODE entryMode;
      double   maxSignalATR;
      double   antiBreakoutPct;
      double   momentumThresholdATR;
      double   minTPDistanceATR;
      int      signalCooldownBars;
      double   atrBufferMult;
      bool     debugMode;
   } m_cfgCache;
   
//+------------------------------------------------------------------+
//| PRIVATE: Helper Methods                                         |
//+------------------------------------------------------------------+
private:
   // --- Config Cache Management ---
   virtual void RefreshConfigCache() override
   {
      m_cfgCache.signalLookback = CFG.SignalLookback;
      m_cfgCache.useMTF = CFG.UseMTF;
      m_cfgCache.exitOnOpposite = CFG.ExitOnOpposite;
      m_cfgCache.zoneReuseATR = CFG.ZoneReuseATR;
      m_cfgCache.patternFailureCooldownBars = CFG.PatternFailureCooldownBars;
      m_cfgCache.entryMode = CFG.EntryMode;
      m_cfgCache.maxSignalATR = CFG.MaxSignalATR;
      m_cfgCache.antiBreakoutPct = CFG.AntiBreakoutPct;
      m_cfgCache.momentumThresholdATR = CFG.MomentumThresholdATR;
      m_cfgCache.minTPDistanceATR = CFG.MinTPDistanceATR;
      m_cfgCache.signalCooldownBars = CFG.SignalCooldownBars;
      m_cfgCache.atrBufferMult = CFG.ATRBufferMult;
      m_cfgCache.debugMode = CFG.DebugMode;
   }
   
   // --- Candle Data Batch Fetch (Optimization) ---
   bool FetchCandleBatch(int shiftStart, int count, MqlRates &outRates[]) 
   {
      ArraySetAsSeries(outRates, true);
      int copied = CopyRates(_Symbol, _Period, shiftStart, count, outRates);
      return (copied > 0);
   }
   
   // --- Zone Reuse Check ---
   bool IsZoneReuseBlocked(bool isBuy, double zonePrice, double atrPoints) 
   {
      datetime currBar = iTime(_Symbol, _Period, 0);
      double tol = atrPoints * m_cfgCache.zoneReuseATR * _Point;

      if(isBuy)
         return (m_lastBuyZoneBar == currBar && MathAbs(zonePrice - m_lastBuyZonePrice) <= tol);
      return (m_lastSellZoneBar == currBar && MathAbs(zonePrice - m_lastSellZonePrice) <= tol);
   }
   
   void RegisterZoneUse(bool isBuy, double zonePrice) 
   {
      datetime currBar = iTime(_Symbol, _Period, 0);
      if(isBuy) {
         m_lastBuyZonePrice = zonePrice;
         m_lastBuyZoneBar = currBar;
      } else {
         m_lastSellZonePrice = zonePrice;
         m_lastSellZoneBar = currBar;
      }
   }
   
   // --- Pattern Failure Cooldown ---
   bool IsPatternFailureBlocked(bool isBuy, double zonePrice, double atrPoints) 
   {
      datetime now = TimeCurrent();
      double tol = atrPoints * m_cfgCache.zoneReuseATR * _Point;
      
      for(int i = ArraySize(m_failedZones) - 1; i >= 0; i--) 
      {
         if(MathAbs(zonePrice - m_failedZones[i].price) <= tol) 
            return true;
      }
      return false;
   }

   void CleanupFailedZones()
   {
      datetime now = TimeCurrent();
      int count = ArraySize(m_failedZones);
      if(count <= 0) return;

      for(int i = ArraySize(m_failedZones) - 1; i >= 0; i--) {
         if(now > m_failedZones[i].expiry) {
            for(int j = i; j < ArraySize(m_failedZones) - 1; j++)
               m_failedZones[j] = m_failedZones[j + 1];
            ArrayResize(m_failedZones, ArraySize(m_failedZones) - 1);
         }
      }
   }
   
   void RegisterFailure(bool isBuy, double zonePrice) 
   {
      int sz = ArraySize(m_failedZones);
      ArrayResize(m_failedZones, sz + 1);
      m_failedZones[sz].price = zonePrice;
      m_failedZones[sz].expiry = TimeCurrent() + (m_cfgCache.patternFailureCooldownBars * PeriodSeconds());
      
      if(m_cfgCache.debugMode) 
         PrintFormat("[PASR Signal] Level %.5f registered as FAILED. Cooldown %d candles.", 
                    zonePrice, m_cfgCache.patternFailureCooldownBars);
   }

   // --- Signal Cooldown Management ---
   bool IsSignalCooldownActive(double price, ENUM_ORDER_TYPE orderType)
   {
      datetime now = TimeCurrent();
      for(int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--)
      {
         if(now > m_signalCooldowns[i].expiry) continue;
         
         // Check if price is within tolerance
         double tol = m_data.GetATRPoints() * m_cfgCache.zoneReuseATR * _Point;
         if(MathAbs(price - m_signalCooldowns[i].price) <= tol)
         {
            // Check if same direction
            if((orderType == ORDER_TYPE_BUY && m_signalCooldowns[i].price < price) ||
               (orderType == ORDER_TYPE_SELL && m_signalCooldowns[i].price > price))
               return true;
         }
      }
      return false;
   }

   void RegisterSignalCooldown(double price, ENUM_ORDER_TYPE orderType)
   {
      int sz = ArraySize(m_signalCooldowns);
      ArrayResize(m_signalCooldowns, sz + 1);
      m_signalCooldowns[sz].price = price;
      m_signalCooldowns[sz].expiry = TimeCurrent() + (m_cfgCache.signalCooldownBars * PeriodSeconds());

      if(m_cfgCache.debugMode)
         PrintFormat("[PASR Signal] Signal cooldown registered @ %.5f for %d bars.",
                    price, m_cfgCache.signalCooldownBars);
   }

   void CleanupSignalCooldowns()
   {
      datetime now = TimeCurrent();
      for(int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--) {
         if(now > m_signalCooldowns[i].expiry) {
            for(int j = i; j < ArraySize(m_signalCooldowns) - 1; j++)
               m_signalCooldowns[j] = m_signalCooldowns[j + 1];
            ArrayResize(m_signalCooldowns, ArraySize(m_signalCooldowns) - 1);
         }
      }
   }
   
   // --- MTF Bias Helper ---
   int GetMTFBias(double price, double htfSupport, double htfResistance, double atrPoints) 
   {
      if(!m_cfgCache.useMTF) return 0;

      double zone = (atrPoints * m_cfgCache.atrBufferMult) * _Point;
      bool nearHtfSupport = (price <= htfSupport + zone);
      bool nearHtfResistance = (price >= htfResistance - zone);

      if(nearHtfSupport && !nearHtfResistance) return 1;
      if(nearHtfResistance && !nearHtfSupport) return -1;
      return 0;
   }
   
//+------------------------------------------------------------------+
//| PRIVATE: Signal Detection Logic (Core Business)                 |
//+------------------------------------------------------------------+
private:
   // === FILTER METHODS (dipisah agar mudah di-test) ===
   
   bool PassZoneTouchFilter(int shift, int dir, double zonePrice, 
                           double atrPoints, double dynamicMult, string &reason,
                           const MqlRates &rates) 
   {
      double extreme = (dir == 1) ? rates[shift].low : rates[shift].high;
      double zoneWidth = (atrPoints * dynamicMult) * _Point;
      double multiplier = (m_cfgCache.entryMode == MODE_SAFE) ? 0.5 : 1.0;

      bool ok = (dir == 1) ? 
                (extreme <= zonePrice + (zoneWidth * multiplier)) : 
                (extreme >= zonePrice - (zoneWidth * multiplier));
      
      if(!ok) reason = "Not touching zone";
      return ok;
   }

   bool PassContextFilter(int shift, double atrPoints, string &reason, 
                         const MqlRates &rates, int dir) 
   {
      double o = rates[shift].open, h = rates[shift].high;
      double l = rates[shift].low, c = rates[shift].close;
      double range = h - l;
      double body = MathAbs(o - c);
      
      if(range > m_cfgCache.maxSignalATR * atrPoints * _Point) // FIX: Use m_cfgCache
         { reason = "Signal too large"; return false; }
      if((body / range) > m_cfgCache.antiBreakoutPct) // FIX: Use m_cfgCache
         { reason = "Body too long"; return false; }

      // Filter Momentum: Cek 1-3 candle sebelumnya
      double threshold = atrPoints * m_cfgCache.momentumThresholdATR * _Point; // FIX: Use m_cfgCache
      int pushCount = 0;
      
      for(int i = 1; i <= 3 && (shift + i) < ArraySize(rates); i++)
      {
         double curO = rates[shift + i].open, curC = rates[shift + i].close;
         double curH = rates[shift + i].high, curL = rates[shift + i].low;
         double prevH = rates[shift + i + 1].high, prevL = rates[shift + i + 1].low;
         double curBody = MathAbs(curO - curC);
         
         bool isPush = (dir == 1) ? 
                      (curH < prevH || (curC < curO && curBody > threshold)) : 
                      (curL > prevL || (curC > curO && curBody > threshold));
         
         if(isPush) pushCount++;
         else break;
      }

      if(pushCount < 1) { reason = "No momentum push to zone"; return false; }
      return true;
   }

   bool PassMTFFilter(int dir, double referencePrice, 
                     double htfSupport, double htfResistance, 
                     double atrPoints, int &bias, string &reason) 
   {
      bias = GetMTFBias(referencePrice, htfSupport, htfResistance, atrPoints);

      if(!m_cfgCache.useMTF) return true;

      int qualityScore = dir * bias; 

      if(qualityScore == 1) {
         reason = "High Quality Signal (MTF Aligned)";
         return true;
      }
      if(qualityScore == 0) {
         reason = "Standard Quality Signal (MTF Neutral)";
         return true;
      }

      reason = "Low Quality (Blocked by MTF Contra-Bias)";
      return false;
   }

   bool PassOpportunityFilter(int dir, int shift, double atrPoints, 
                             double support, double resistance, 
                             double signalPrice, string &reason,
                             const MqlRates &rates) 
   {
      double target = (dir == 1) ? resistance : support;
      double profitDist = (dir == 1) ? (target - signalPrice) : (signalPrice - target);
      
      double minTPDist = (atrPoints * m_cfgCache.minTPDistanceATR) * _Point; // FIX: Use m_cfgCache
      if(profitDist < minTPDist) { reason = "TP distance < Min ATR"; return false; }
      
      return true;
   }
   
   // === MAIN DETECTION ENGINE ===
   
   bool DetectSignalCore(SignalDecision &decision, 
                        double atrPoints,
                        double support, double resistance, 
                        double htfSupport, double htfResistance,
                        bool isSupBroken, bool isResBroken,
                        double supBufferMult, double resBufferMult,
                        int supHtfAlign, int resHtfAlign) 
   {
      ZeroMemory(decision);
      string reason = "No pattern detected";

      // Validate data availability
      if(iBars(_Symbol, _Period) < m_cfgCache.signalLookback + 5) {
         decision.reason = "Insufficient history data";
         return false;
      }

      // === OPTIMIZATION: Batch fetch candles once ===
      MqlRates rates[];
      if(!FetchCandleBatch(1, m_cfgCache.signalLookback + 3, rates)) {
         decision.reason = "Failed to fetch candle data";
         return false;
      }

      // Scan patterns in lookback window
      for(int shift = 1; shift <= m_cfgCache.signalLookback; shift++) 
      {
         string currentFilterReason = ""; 
         int dir = 0;
         double signalPrice = 0;
         ENUM_PATTERN_TYPE pType = PATTERN_NONE;
         string patternReason = "";
         
         // Pattern detection via PatternManager
         if(!m_patterns.Detect(rates, shift, atrPoints, pType, dir, signalPrice, patternReason))
            continue;

         double zonePrice = (dir == 1) ? support : resistance;
         double currentBufferMult = (dir == 1) ? supBufferMult : resBufferMult;
         int currentHtfAlign = (dir == 1) ? supHtfAlign : resHtfAlign;

         // === FILTER PIPELINE ===
         // 1. HTF Alignment Filter
         if(m_cfgCache.useMTF && currentHtfAlign < 0) {
            reason = (dir == 1) ? "HTF Contra-Support" : "HTF Contra-Resistance";
            continue;
         }
         
         // 2. Zone Broken Filter
         if((dir == 1 && isSupBroken) || (dir == -1 && isResBroken)) {
            reason = "Zone broken (Price closed outside)";
            continue;
         }

         // 3. Zone Touch Filter
         if(!PassZoneTouchFilter(shift, dir, zonePrice, atrPoints, currentBufferMult, currentFilterReason, rates)) {
            reason = currentFilterReason; continue; 
         }

         // 4. Context/Momentum Filter
         if(!PassContextFilter(shift, atrPoints, currentFilterReason, rates, dir)) {
            reason = currentFilterReason; continue;
         }

         // 5. MTF Quality Filter
         int bias = 0;
         if(!PassMTFFilter(dir, rates[shift].close, htfSupport, htfResistance, 
                          atrPoints, bias, currentFilterReason)) {
            reason = currentFilterReason; continue;
         }

         // 6. Opportunity/R:R Filter
         if(!PassOpportunityFilter(dir, shift, atrPoints, support, resistance, 
                                  signalPrice, currentFilterReason, rates)) {
            reason = currentFilterReason; continue;
         }

         // 7. Zone Reuse Filter
         if(IsZoneReuseBlocked(dir == 1, zonePrice, atrPoints)) { 
            reason = "Zone reuse blocked"; continue; 
         }
         
         // 8. Pattern Failure Cooldown
         if(IsPatternFailureBlocked(dir == 1, zonePrice, atrPoints)) {
            reason = "Level failure cooldown"; continue;
         }

         // 9. Signal Cooldown Filter
         if(IsSignalCooldownActive(signalPrice, decision.orderType)) {
             reason = "Signal cooldown active"; continue;
         }

         // === SIGNAL FOUND: Populate decision struct ===
         decision.valid = true;
         decision.orderType = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         decision.signalPrice = signalPrice;
         decision.patternType = pType;
         decision.zonePrice = zonePrice;
         decision.signalShift = shift;
         decision.bias = bias;
         decision.reason = patternReason + (currentFilterReason != "" ? " | " + currentFilterReason : "");
         
         // Register zone usage to prevent duplicate signals
         RegisterZoneUse(dir == 1, zonePrice);
         
         if(m_cfgCache.debugMode) // FIX: Use m_cfgCache
            PrintFormat("[PASR Signal] ✓ %s @ %.5f | Pattern: %s | %s", 
                       (dir==1?"BUY":"SELL"), signalPrice, EnumToString(pType), decision.reason);
         
         return true; // Early return on first valid signal
      }
      
      // No signal found
      decision.reason = (reason == "") ? "No signal" : reason;
      return false;
   }
   
//+------------------------------------------------------------------+
//| PUBLIC: Event Handler Implementation (IEventHandler)           |
//+------------------------------------------------------------------+
public:
   // Constructor: Auto-subscribe to relevant events
   SignalManager() : IManager("SignalManager", 30)
   {
      m_lastBuyZonePrice = 0.0;
      m_lastSellZonePrice = 0.0;
      m_lastBuyZoneBar = 0;
      m_lastSellZoneBar = 0;
      m_hasNewTick = false;
      m_hasNewBar = false;
      m_signalPending = false;
   }

   virtual void Deinit() override {
      ArrayFree(m_failedZones);
      ArrayFree(m_signalCooldowns); // FIX: Free signal cooldowns
      m_signalPending = false;
      IManager::Deinit();
   }

   virtual void DeclareEvents() override {
      AddEvent("PriceUpdate");
      AddEvent("NewBar");
      AddEvent("ZoneUpdate");
   }
   
//+------------------------------------------------------------------+
//| PUBLIC: Event Handler Methods                                   |
//+------------------------------------------------------------------+
public:
   // --- PriceUpdate Event: Cache tick, don't process yet ---
   virtual void OnPriceUpdate(PriceUpdateEvent* e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      // Cache the tick for later processing on NewBar
      m_cachedTick = e.tick;
      m_hasNewTick = true;
   }
   
   // --- NewBar Event: MAIN SIGNAL DETECTION TRIGGER ---
   virtual void OnNewBar(NewBarEvent* e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !m_initialized) return;
      // Skip if already processed this bar (safety)
      if(e.barOpenTime == m_lastProcessedBar) return;
      // Skip if no tick data received (data gap)
      if(!m_hasNewTick) return;

      // === SIGNAL DETECTION EXECUTION ===
      ProcessSignalOnNewBar(e);
      m_lastProcessedBar = e.barOpenTime;
      m_hasNewTick = false;  // Reset for next cycle
   }

   // --- ConfigReload Event ---
   virtual void OnConfigReload(ConfigReloadEvent* e) override
   {
      RefreshConfigCache();
   }

   // --- EmergencyStop Event ---
   virtual void OnEmergencyStop(EmergencyStopEvent* e) override
   {
      m_signalPending = false;
      if(m_cfgCache.debugMode) Log("Emergency Stop: Clearing pending signals.");
   }

   // --- Heartbeat Event ---
   virtual void OnHeartbeat(HeartbeatEvent* e) override
   {
      CleanupFailedZones();
      CleanupSignalCooldowns(); // FIX: Call cleanup for signal cooldowns
   }

   virtual void OnCustomEvent(Event* e) override {
      if(e.Type() == "ZoneUpdate") {
         ZoneUpdateEvent* ze = (ZoneUpdateEvent*)e;
         m_marketData.atrPoints      = ze.atrPoints;
         m_marketData.support        = ze.support;
         m_marketData.resistance     = ze.resistance;
         m_marketData.htfSupport     = ze.htfSupport;
         m_marketData.htfResistance  = ze.htfResistance;
         m_marketData.isSupBroken    = ze.isSupBroken;
         m_marketData.isResBroken    = ze.isResBroken;
         m_marketData.supBufferMult  = ze.supBufferMult;
         m_marketData.resBufferMult  = ze.resBufferMult;
         m_marketData.supHtfAlign    = ze.supHtfAlign;
         m_marketData.resHtfAlign    = ze.resHtfAlign;
      }
   }
//+------------------------------------------------------------------+
//| PUBLIC: Integration Methods (for other modules)                 |
//+------------------------------------------------------------------+
public:
   // Called by SRManager or similar to trigger signal check
   // This is the "pull" interface for backward compatibility
   bool TryGenerateSignal(SignalDecision &outDecision,
                         double atrPoints,
                         double support, double resistance, 
                         double htfSupport, double htfResistance,
                         bool isSupBroken, bool isResBroken,
                         double supBufferMult, double resBufferMult,
                         int supHtfAlign, int resHtfAlign) 
   {
      // Direct call to core detection logic
      bool found = DetectSignalCore(outDecision, atrPoints, support, resistance,
                                   htfSupport, htfResistance, isSupBroken, isResBroken,
                                   supBufferMult, resBufferMult, supHtfAlign, resHtfAlign);
      
      // If signal found, also dispatch event for other modules
      if(found && outDecision.valid) 
      {
         SignalGeneratedEvent* sigEvent = new SignalGeneratedEvent(
            outDecision, atrPoints, support, resistance
         );
         EventBus::Instance().Dispatch(sigEvent);  // Auto-cleanup after dispatch
      }
      
      return found;
   }
   
   // Register a failed zone externally (e.g., from TradeManager on loss)
   void NotifyPatternFailure(bool isBuy, double zonePrice) 
   {
      RegisterFailure(isBuy, zonePrice);
   }
   
   // Get pending signal (if any) - for polling-style integration
   bool HasPendingSignal(SignalDecision &outSignal) 
   {
      if(m_signalPending) {
         outSignal = m_pendingSignal;
         m_signalPending = false;  // Consume the signal
         return true;
      }
      return false;
   }
   
//+------------------------------------------------------------------+
//| PRIVATE: Core Processing Logic                                  |
//+------------------------------------------------------------------+
private:
   // Main processing method called on NewBar event
   void ProcessSignalOnNewBar(NewBarEvent* e) 
   {
      // Use cached data from ZoneUpdateEvent
      double atrPoints      = m_marketData.atrPoints;
      double support        = m_marketData.support;
      double resistance     = m_marketData.resistance;
      double htfSupport     = m_marketData.htfSupport;
      double htfResistance  = m_marketData.htfResistance;
      bool   isSupBroken    = m_marketData.isSupBroken;
      bool   isResBroken    = m_marketData.isResBroken;
      double supBufferMult  = m_marketData.supBufferMult;
      double resBufferMult  = m_marketData.resBufferMult;
      int    supHtfAlign    = m_marketData.supHtfAlign;
      int    resHtfAlign    = m_marketData.resHtfAlign;

      if(atrPoints <= 0 || support <= 0 || resistance <= 0) {
         if(m_cfgCache.debugMode) Print("[SignalManager] Missing data for signal detection");
         return;
      }
      
      // Run core detection
      SignalDecision decision;
      if(DetectSignalCore(decision, atrPoints, support, resistance,
                         htfSupport, htfResistance, isSupBroken, isResBroken,
                         supBufferMult, resBufferMult, supHtfAlign, resHtfAlign)) 
      {
         // Signal found! Dispatch to ExecutionManager via event
         SignalGeneratedEvent* sigEvent = new SignalGeneratedEvent(
            decision, atrPoints, support, resistance
         );
         EventBus::Instance().Dispatch(sigEvent);  // Memory auto-managed
         
         RegisterSignalCooldown(decision.signalPrice, decision.orderType); // FIX: Register cooldown
         // Also buffer for polling-style access (backward compat)
         m_pendingSignal = decision;
         m_signalPending = true;
      }
   }
};

#endif
//+------------------------------------------------------------------+
//|                                                 DataManager.mqh   |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
#ifndef __DATA_MANAGER_MQH__
#define __DATA_MANAGER_MQH__

#property strict
#include "IManager.mqh"

DataManager* IManager::s_dataCache = NULL;

class DataManager : public IManager {
private:
   int    m_atrHandle;
   int    m_fractalHandle;
   
   struct CachedData {
      datetime barTime;
      double atr;
      double fractalsUp[];
      double fractalsDown[];
      bool dirty;
   } m_cache;

   PositionScanResult m_scanCache;
   PerformanceStats   m_perfStats;
   double m_realizedDailyProfit;
   double m_dayStartBalance;
   datetime m_lastProfitUpdateDay;
   datetime m_lastScanTime;

public:
   DataManager() : IManager("DataManager", 10),
                   m_atrHandle(INVALID_HANDLE), m_fractalHandle(INVALID_HANDLE),
                   m_realizedDailyProfit(0), 
                   m_dayStartBalance(0), m_lastProfitUpdateDay(0), m_lastScanTime(0) 
   {
      m_cache.barTime = 0;
      m_cache.atr = 0;
      m_cache.dirty = true;
      ArraySetAsSeries(m_cache.fractalsUp, true);
      ArraySetAsSeries(m_cache.fractalsDown, true);
      ZeroMemory(m_scanCache);
   }

   ~DataManager() {
      if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
      if(m_fractalHandle != INVALID_HANDLE) IndicatorRelease(m_fractalHandle);
   }

   virtual bool Init() override {
      if(!IManager::Init()) return false;
      return ResetIndicators();
   }

   virtual void DeclareEvents() override {
      AddEvent("PriceUpdate");
      AddEvent("Heartbeat");
   }

   bool ResetIndicators() {
      m_atrHandle = iATR(_Symbol, _Period, CFG.ATRPeriod);
      m_fractalHandle = iFractals(_Symbol, _Period);
      if(m_atrHandle == INVALID_HANDLE || m_fractalHandle == INVALID_HANDLE) return false;
      UpdateIndicators(); 
      return true;
   }

   void UpdateIndicators() {
      // MQL5 Best Practice: Gunakan CopyTime untuk async safety
      datetime times[];
      if(CopyTime(_Symbol, _Period, 0, 1, times) <= 0) return;
      datetime currentBar = times[0];
      
      if(m_cache.barTime == currentBar && !m_cache.dirty) return;

      double atrBuf[1];
      if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuf) > 0) {
         m_cache.atr = atrBuf[0] / _Point;
         CopyBuffer(m_fractalHandle, 0, 0, 100, m_cache.fractalsUp);
         CopyBuffer(m_fractalHandle, 1, 0, 100, m_cache.fractalsDown);

         m_cache.barTime = currentBar;
         m_cache.dirty = false;
      }
   }

   virtual void OnPriceUpdate(PriceUpdateEvent *e) override {
      UpdateIndicators();
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override {
      UpdateAccountState(CFG.MagicNum);
      ScavengePendingGVs();
   }

   // --- Getters & Business Logic ---
   double GetATRPoints() const { return m_cache.atr; }
   void MarkDirty() { m_cache.dirty = true; }
   PositionScanResult GetScanResult() const { return m_scanCache; }
   PerformanceStats GetPerformanceStats() const { return m_perfStats; }
   double GetDayStartBalance() const { return m_dayStartBalance; }

   void RefreshDailyProfit() {
      string gvName = "PASR_PROFIT_" + _Symbol + "_" + (string)CFG.MagicNum;
      
      // MQL5 Best Practice: Gunakan CopyTime untuk daily timeframe
      datetime times[];
      if(CopyTime(_Symbol, PERIOD_D1, 0, 1, times) <= 0) return;
      datetime today = times[0];

      if(HistorySelect(today, INT_MAX)) {
         double dailySum = 0;
         for(int i = 0; i < HistoryDealsTotal(); i++) {
            ulong t = HistoryDealGetTicket(i);
            if(t > 0 && HistoryDealGetInteger(t, DEAL_MAGIC) == CFG.MagicNum && HistoryDealGetString(t, DEAL_SYMBOL) == _Symbol) {
               dailySum += HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION);
            }
         }
         m_realizedDailyProfit = dailySum;
      }
      GlobalVariableSet(gvName, m_realizedDailyProfit);
   }

   void ResetDailyAnchor() {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      // MQL5 Best Practice: Gunakan CopyTime untuk daily timeframe
      datetime times[];
      if(CopyTime(_Symbol, PERIOD_D1, 0, 1, times) <= 0) return;
      datetime today = times[0];

      RefreshDailyProfit(); 
      m_dayStartBalance = currentBalance - m_realizedDailyProfit;
      m_lastProfitUpdateDay = today;
   }

   void UpdateAccountState(ulong magic) {
      if(TimeCurrent() - m_lastScanTime < 1 && m_lastScanTime > 0) return;
      
      // MQL5 Best Practice: Gunakan CopyTime untuk daily timeframe
      datetime times[];
      if(CopyTime(_Symbol, PERIOD_D1, 0, 1, times) <= 0) return;
      datetime today = times[0];
      
      if(today != m_lastProfitUpdateDay) ResetDailyAnchor();
      else RefreshDailyProfit();
      
      UpdatePerformanceStats();

      PositionScanResult temp;
      ZeroMemory(temp);
      temp.dailyRealized = m_realizedDailyProfit;
      double floatingTotal = 0;

      for(int i = 0; i < PositionsTotal(); i++) {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0 || PositionGetInteger(POSITION_MAGIC) != magic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         floatingTotal += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
         temp.normalCount++;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) temp.buyCount++; else temp.sellCount++;
      }

      for(int i = 0; i < OrdersTotal(); i++) {
         ulong oTicket = OrderGetTicket(i);
         if(oTicket > 0 && OrderGetInteger(ORDER_MAGIC) == magic && OrderGetString(ORDER_SYMBOL) == _Symbol) {
            ENUM_ORDER_STATE oState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
            if(oState == ORDER_STATE_STARTED || oState == ORDER_STATE_PLACED) temp.pendingCount++;
         }
      }

      temp.floatingPnL = floatingTotal;
      temp.totalProfit = temp.dailyRealized + temp.floatingPnL;
      
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(MathAbs(m_dayStartBalance) > _Point) // FIX: Avoid division by zero on small balance
         temp.dailyDrawdown = ((m_dayStartBalance - equity) / m_dayStartBalance) * 100.0;

      m_scanCache = temp;
      m_lastScanTime = TimeCurrent();
   }

   void ScavengePendingGVs() {
      string prefix = "PASR_PEND_" + (string)CFG.MagicNum + "_" + _Symbol;
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--) {
         string name = GlobalVariableName(i);
         if(StringFind(name, prefix) == 0) {
            datetime ts = (datetime)GlobalVariableGet(name);
            if(TimeCurrent() - ts > 3600) GlobalVariableDel(name);
         }
      }
   }

   double NormalizePrice(string symbol, double price) const {
      return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   }

   double NormalizeVolume(string symbol, double vol) const {
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      vol = MathFloor((vol + 1e-12) / (step > 0 ? step : 0.01)) * (step > 0 ? step : 0.01);
      vol = MathMax(vol, minv);
      if(maxv > 0.0) vol = MathMin(vol, maxv);
      return vol;
   }

   void UpdatePerformanceStats() {
      ZeroMemory(m_perfStats);
      if(!HistorySelect(0, TimeCurrent())) return;
      
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++) {
         ulong t = HistoryDealGetTicket(i);
         if(t <= 0 || HistoryDealGetInteger(t, DEAL_MAGIC) != CFG.MagicNum) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         
         string comment = HistoryDealGetString(t, DEAL_COMMENT);
         if(StringFind(comment, "P_") == 0 && StringLen(comment) >= 5) {
            double net = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_COMMISSION) + HistoryDealGetDouble(t, DEAL_SWAP);
            ushort modeChar = StringGetCharacter(comment, 4);
            if(modeChar == 'S') { m_perfStats.safeTotal++; if(net > 0) m_perfStats.safeWins++; }
            else if(modeChar == 'A') { m_perfStats.aggTotal++; if(net > 0) m_perfStats.aggWins++; }
         }
      }
   }

   int ParseHM(string hhmm) const
   {
      string parts[];
      if(StringSplit(hhmm, ':', parts) != 2) return -1;
      int h = (int)StringToInteger(parts[0]);
      int m = (int)StringToInteger(parts[1]);
      return (h >= 0 && h <= 23 && m >= 0 && m <= 59) ? (h * 60 + m) : -1;
   }

   double CalculateAutoLot(string symbol, double riskPct, double slDistancePoints)
   {
      if(slDistancePoints <= 0) return 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0 || tickSize <= 0 || equity <= 0) return 0.0;
      double riskMoney = equity * (riskPct / 100.0);
      double lossPerLot = (slDistancePoints * _Point / tickSize) * tickValue;
      return (lossPerLot > 0) ? NormalizeVolume(symbol, riskMoney / lossPerLot) : 0.0;
   }

   string BuildComment(string type, int bias, ENUM_ENTRY_MODE mode) const
   {
      string b = (bias > 0) ? "+" : (bias < 0 ? "-" : "0");
      string t = (type == "BUY") ? "B" : (type == "SELL" ? "S" : type);
      string m = (mode == MODE_SAFE) ? "S" : "A";
      return "P_" + t + b + m;
   }

   string StripTags(string html) const {
      string res = "";
      bool inside = false;
      for(int i = 0; i < StringLen(html); i++) {
         ushort c = StringGetCharacter(html, i);
         if(c == '<') inside = true;
         else if(c == '>') inside = false;
         else if(!inside) StringAdd(res, CharToString((char)c));
      }
      return res;
   }

   void DebugLog(bool enabled, string msg) const { if(enabled) Print("[PASR] ", msg); }
};

#endif
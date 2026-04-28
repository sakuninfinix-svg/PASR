//+------------------------------------------------------------------+
//|               Price Action & Support Ressistance V1              |
//|         Optimized by Agsicentre (agsicentre.wordpress.com)       |
//+------------------------------------------------------------------+

#include <PASR/0.EventBus.mqh>
#include <PASR/1.Events.mqh>
#include <PASR/2.Config.mqh>
#include <PASR/3.MarketManager.mqh>
#include <PASR/4.SRManager.mqh>
#include <PASR/5.SignalManager.mqh>
#include <PASR/6.ExecutionManager.mqh>
#include <PASR/8.RecoveryManager.mqh>
#include <PASR/10.DataManager.mqh>
#include <PASR/11.DashboardManager.mqh>

EventBus* g_eventBus;
MarketManager market;
SRManager sr;
SignalManager signal;
ExecutionManager exec;
RecoveryManager recovery;
DashboardManager dashboard;
DashboardController* dashCtrl = NULL;
DataManager data;

int OnInit()
{
   // 1. Initialize Event Bus first
   g_eventBus = EventBus::Instance();
   if(CheckPointer(g_eventBus) == POINTER_INVALID) {
      Print("[ERROR] Failed to initialize EventBus");
      return INIT_FAILED;
   }

   if(CFG.DebugMode) {
      g_recorder = new EventRecorder();
      g_recorder.Start();
   }

   // 2. Initialize config & managers
   SetCommonDefaults();
   PrintConfigSummary();

   if(!data.Init()) return(INIT_FAILED);
   
   // Set global cache for all IManager children
   IManager::SetGlobalDataManager(GetPointer(data)); // Corrected static method call

   // All these now pull m_data from s_dataCache automatically during Init()
   if(!signal.Init())   return(INIT_FAILED);
   if(!market.Init())   return(INIT_FAILED);
   if(!sr.Init())       return(INIT_FAILED);
   if(!exec.Init())     return(INIT_FAILED);
   if(!recovery.Init()) return(INIT_FAILED);
   
   dashCtrl = DashboardControllerFactory::Create(GetPointer(dashboard), GetPointer(data));
   if(CheckPointer(dashCtrl) == POINTER_INVALID) return(INIT_FAILED);
   dashboard.SetController(dashCtrl);
   // 3. Initialize Dashboard UI
   if(!dashboard.CreateDashboard(0, "PASR_Dashboard", 0, 20, 20, 320, 420)) {
      Print("[ERROR] Failed to create dashboard");
   }
   dashboard.Run();

   // 4. Start periodic timer (2 seconds) for system heartbeats
   EventSetTimer(2);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) 
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && 
         PositionGetInteger(POSITION_MAGIC) == CFG.MagicNum && 
         PositionGetString(POSITION_SYMBOL) == _Symbol) 
      {
         double currentATR = data.GetATRPoints();
         RecoveryEngine *eng = recovery.GetEngine(t);
         
         if(eng == NULL) {
            recovery.Register(t, (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE), 
                             PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_TP), 
                             PositionGetDouble(POSITION_SL), currentATR, PositionGetDouble(POSITION_VOLUME), 0);
            eng = recovery.GetEngine(t);
         }
         
         if(CheckPointer(eng) != POINTER_INVALID) {
            eng.LoadState(t, CFG.MagicNum);
            
            // Dispatch event to notify listeners about current position state
            g_eventBus.Dispatch(new PositionUpdateEvent( // Dispatch only if engine is valid
               t, PositionGetDouble(POSITION_PRICE_CURRENT),
               PositionGetDouble(POSITION_PROFIT)
            ));
         }
      }
   }

   // 7. Dispatch initial system ready event
   g_eventBus.Dispatch(new HeartbeatEvent(0));

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   // Stop timer
   EventKillTimer();

   // Clear EventBus subscriptions before destroying objects
   EventBus* bus = EventBus::Instance();
   if(CheckPointer(bus) != POINTER_INVALID) {
      bus.Clear();  // Unsubscribe all handlers
   }
   DashboardControllerFactory::Destroy(dashCtrl);
   if(CheckPointer(g_recorder) != POINTER_INVALID) {
      delete g_recorder;
      g_recorder = NULL;
   }

   dashboard.Destroy(reason);
   Comment("");
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   dashboard.ChartEvent(id, lparam, dparam, sparam);
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Handle new position creation and deal closing
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal)) {
      if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == CFG.MagicNum && 
         HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol) {
            
            long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
            ulong positionID = trans.position;

            if(entryType == DEAL_ENTRY_IN) { // New position opened
               string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
               int hashPos = StringFind(comment, "#");
               ulong tsID = 0;
               if(hashPos >= 0) tsID = (ulong)StringToInteger(StringSubstr(comment, hashPos + 1));

               // Extract data directly from the deal
               ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
               double entry  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
               double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
               double sl     = HistoryDealGetDouble(trans.deal, DEAL_SL);
               double tp     = HistoryDealGetDouble(trans.deal, DEAL_TP);

               // Robust SL/TP lookup: HistoryDeal might have 0 if orders were modified async
               if(PositionSelectByTicket(positionID)) {
                  if(sl <= 0) sl = PositionGetDouble(POSITION_SL);
                  if(tp <= 0) tp = PositionGetDouble(POSITION_TP);
               }

               // Context from Global Variables (sent from ExecutionManager)
               if(tsID > 0) {
                  string p = "PASR_PEND_" + (string)CFG.MagicNum + "_" + _Symbol + "_" + (string)tsID + "_";
                  if(GlobalVariableCheck(p + "ts")) {
                     if(tp <= 0) tp = GlobalVariableGet(p + "tp");
                     // Clean up the pending GV after successful confirmation
                     GlobalVariablesDeleteAll("PASR_PEND_" + (string)CFG.MagicNum + "_" + _Symbol + "_" + (string)tsID);
                  }
               }

               // Dispatch final confirmation event for RecoveryManager to register the position
               OrderExecutionEvent* confirm = new OrderExecutionEvent(
                  true, positionID, type, entry, sl, tp, volume, "Confirmed", comment
               );
               EventBus::Instance().Dispatch(confirm);
            } else if (entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_INOUT) {
               data.RefreshDailyProfit();
            }
      }
   }
   // Other transaction handling (e.g., for pending orders, modifications) can go here
}

void OnTimer()
{
   // Dispatch heartbeat for periodic tasks (UI update, health checks, etc)
   g_eventBus.Dispatch(new HeartbeatEvent(2));
}

void OnTick() 
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;

   // Dispatch price update event (lightweight)
   g_eventBus.Dispatch(new PriceUpdateEvent(tick));

   // Check for new bar -> dispatch NewBarEvent dengan CopyTime (MQL5 Best Practice)
   static datetime lastBarTime = 0;
   
   datetime times[];
   if(CopyTime(_Symbol, _Period, 0, 1, times) <= 0) return;
   datetime currentBar = times[0];
   
   if(currentBar != lastBarTime) {
      lastBarTime = currentBar;
      market.SetLastBarTime(currentBar);
      
      // Fetch OHLC dengan CopyRates untuk konsistensi data
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, _Period, 0, 1, rates) > 0) {
         g_eventBus.Dispatch(new NewBarEvent(
            currentBar,
            rates[0].open,
            rates[0].high, 
            rates[0].low,
            rates[0].close,
            _Period
         ));
      }
   } 
 }
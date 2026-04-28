//+------------------------------------------------------------------+
//|                                                   IManager.mqh   |
//|              Base Class for Event-Driven PASR EA Modules         |
//|                                     Copyright 2026, Agsicentre   |
//+------------------------------------------------------------------+
#ifndef __I_MANAGER_MQH__
#define __I_MANAGER_MQH__

#property strict

#include "0.EventBus.mqh"
#include "1.Events.mqh"
#include "2.Config.mqh"

class DataManager;

//+------------------------------------------------------------------+
//| IManager - Template Base Class                                  |
//| Provides: Lifecycle, Auto-Subscription, Config Cache, Logging   |
//+------------------------------------------------------------------+
class IManager : public IEventHandler
{
protected:
   string        m_name;
   bool          m_initialized;
   int           m_priority;
   EventBus*     m_bus;
   DataManager*  m_data;
   bool          m_debugMode;
   string        m_subscribedEvents[];
   
   static DataManager* s_dataCache;

public:
   IManager(const string name, int priority = 50) 
   {
      m_name = name;
      m_initialized = false;
      m_priority = priority;
      m_debugMode = CFG.DebugMode;
      m_bus = EventBus::Instance();
      m_data = NULL;
   }
   
   static void SetGlobalDataManager(DataManager* d) { s_dataCache = d; }
   static DataManager* GetGlobalDataManager() { return s_dataCache; }
   virtual ~IManager() 
   {
      if(m_initialized) Deinit();
      ArrayFree(m_subscribedEvents);
   }
   
   virtual bool Init() 
   {
      if(m_initialized) return true;
      if(m_data == NULL && m_name != "DataManager") {
         if(CheckPointer(s_dataCache) == POINTER_INVALID) {
            PrintFormat("[%s] CRITICAL: Global Data Cache is NULL during Init.", m_name);
            return false;
         }
         m_data = s_dataCache;
      }

      if(CheckPointer(m_bus) == POINTER_INVALID) {
         Log("CRITICAL: EventBus not available.");
         return false;
      }
      
      DeclareBaseEvents();
      SubscribeToEvents();
      RefreshConfigCache();
      m_initialized = true;
      Log("✅ Initialized.");
      return true;
   }
   
   virtual void Deinit() 
   {
      if(!m_initialized) return;
      UnsubscribeFromEvents();
      m_initialized = false;
      Log("🛑 Deinitialized.");
   }
   
   void SetDataManager(DataManager* dta) { m_data = dta; }
   DataManager* GetDataManager() const   { return m_data; }
   
   virtual void RefreshConfigCache() {
      Log("⚠️ RefreshConfigCache() not overridden. Using default empty implementation.");
   }
   
   virtual void HandleEvent(Event* e)
   {
      if(CheckPointer(e) == POINTER_INVALID || !m_initialized) return;
      
      string type = e.Type();
      if(type == "Heartbeat")       OnHeartbeat((HeartbeatEvent*)e);
      else if(type == "ConfigReload") OnConfigReload((ConfigReloadEvent*)e);
      else if(type == "EmergencyStop") OnEmergencyStop((EmergencyStopEvent*)e);
      else if(type == "PriceUpdate") OnPriceUpdate((PriceUpdateEvent*)e);
      else if(type == "NewBar")     OnNewBar((NewBarEvent*)e);
      else if(type == "SignalGenerated") OnSignalGenerated((SignalGeneratedEvent*)e);
      else if(type == "OrderExecution") OnOrderExecution((OrderExecutionEvent*)e);
      else if(type == "PositionUpdate") OnPositionUpdate((PositionUpdateEvent*)e);
      else                          OnCustomEvent(e);
   }
   
   // --- VIRTUAL HOOKS (OVERRIDE AS NEEDED) ---
   virtual void OnHeartbeat(HeartbeatEvent* e) {}
   virtual void OnConfigReload(ConfigReloadEvent* e) { RefreshConfigCache(); }
   virtual void OnEmergencyStop(EmergencyStopEvent* e) {}
   virtual void OnPriceUpdate(PriceUpdateEvent* e) {}
   virtual void OnNewBar(NewBarEvent* e) {}
   virtual void OnSignalGenerated(SignalGeneratedEvent* e) {}
   virtual void OnOrderExecution(OrderExecutionEvent* e) {}
   virtual void OnPositionUpdate(PositionUpdateEvent* e) {}
   virtual void OnCustomEvent(Event* e) {} // Fallback for module-specific events
   
   // --- UTILITIES ---
   bool   IsInitialized() const { return m_initialized; }
   string GetName()       const { return m_name; }
   int    GetPriority()   const { return m_priority; }
   
protected:
   // Auto-subscription logic
   void SubscribeToEvents() 
   {
      if(CheckPointer(m_bus) == POINTER_INVALID) return;
      for(int i = 0; i < ArraySize(m_subscribedEvents); i++) {
         m_bus.Subscribe(m_subscribedEvents[i], this, m_priority);
      }
   }
   
   void UnsubscribeFromEvents() 
   {
      if(CheckPointer(m_bus) == POINTER_INVALID) return;
      for(int i = 0; i < ArraySize(m_subscribedEvents); i++) {
         m_bus.Unsubscribe(m_subscribedEvents[i], this);
      }
   }
   
   // Child classes override this to add custom event types
   virtual void DeclareEvents() {}
   
   void AddEvent(const string eventType) 
   {
      int sz = ArraySize(m_subscribedEvents);
      ArrayResize(m_subscribedEvents, sz + 1);
      m_subscribedEvents[sz] = eventType;
   }
   
   void DeclareBaseEvents() 
   {
      AddEvent("Heartbeat");
      AddEvent("ConfigReload");
      AddEvent("EmergencyStop");
      DeclareEvents(); // Hook for child-specific events
   }
   
   void Log(const string msg) const 
   {
      if(m_debugMode) 
         Print("[", m_name, "] ", TimeToString(TimeCurrent(), TIME_SECONDS), " | ", msg);
   }
};

// ✅ FIX: Inisialisasi static dipindah ke DataManager.mqh agar tidak circular
#endif
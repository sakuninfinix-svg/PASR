//+------------------------------------------------------------------+
//|                                                   Events.mqh     |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
#ifndef __EVENTS_MQH__
#define __EVENTS_MQH__

#include "0.EventBus.mqh"
#include "2.Config.mqh"

//+------------------------------------------------------------------+
//| PRICE EVENTS                                                     |
//+------------------------------------------------------------------+
class PriceUpdateEvent : public Event {
public:
   MqlTick tick;
   
   PriceUpdateEvent(const MqlTick &t) : Event("PriceFeed") { tick = t; }
   virtual string Type() const override { return "PriceUpdate"; }
   
   virtual string Serialize() const override {
      return StringFormat("%I64d;%f;%f;%f;%f", 
             tick.time_msc, tick.bid, tick.ask, tick.last, tick.volume);
   }
};

class NewBarEvent : public Event {
public:
   datetime barOpenTime;
   double   open, high, low, close;
   int      period;
   
   NewBarEvent(datetime time, double o, double h, double l, double c, int tf) 
      : Event("BarMonitor"), barOpenTime(time), open(o), high(h), low(l), close(c), period(tf) {}
   
   virtual string Type() const override { return "NewBar"; }
   
   virtual string Serialize() const override {
      return StringFormat("%d;%f;%f;%f;%f;%d", 
             barOpenTime, open, high, low, close, period);
   }
};

//+------------------------------------------------------------------+
//| MARKET STATE EVENTS                                              |
//+------------------------------------------------------------------+
class SessionChangeEvent : public Event {
public:
   bool sessionActive;
   string sessionName;
   
   SessionChangeEvent(bool active, const string name) 
      : Event("MarketManager"), sessionActive(active), sessionName(name) {}
   
   virtual string Type() const override { return "SessionChange"; }
};

class NewsAlertEvent : public Event {
public:
   string newsTitle;
   datetime eventTime;
   int      impact; // 1=High, 2=Medium, 3=Low
   
   NewsAlertEvent(const string title, datetime time, int lvl)
      : Event("NewsFilter"), newsTitle(title), eventTime(time), impact(lvl) {}
   
   virtual string Type() const override { return "NewsAlert"; }
};

class ZoneUpdateEvent : public Event {
public:
   double support, resistance;
   double htfSupport, htfResistance;
   bool   isSupBroken, isResBroken;
   double supBufferMult, resBufferMult;
   int    supHtfAlign, resHtfAlign;
   double atrPoints;
   
   ZoneUpdateEvent(double sup, double res, double htfSup, double htfRes,
                  bool supBroken, bool resBroken, double supMult, double resMult,
                  int supAlign, int resAlign, double atr)
      : Event("SRManager"), support(sup), resistance(res), htfSupport(htfSup), htfResistance(htfRes),
        isSupBroken(supBroken), isResBroken(resBroken), supBufferMult(supMult), resBufferMult(resMult),
        supHtfAlign(supAlign), resHtfAlign(resAlign), atrPoints(atr) {}
   
   virtual string Type() const override { return "ZoneUpdate"; }
};

//+------------------------------------------------------------------+
//| TRADING EVENTS                                                   |
//+------------------------------------------------------------------+
class SignalGeneratedEvent : public Event {
public:
   SignalDecision signal;
   double         atrPoints;
   double         support, resistance;
   
   SignalGeneratedEvent(const SignalDecision &sig, double atr, double sup, double res)
      : Event("SignalManager"), signal(sig), atrPoints(atr), support(sup), resistance(res) {}
   
   virtual string Type() const override { return "SignalGenerated"; }
};

class ConfigReloadEvent : public Event {
public:
   ConfigReloadEvent() : Event("System") {}
   virtual string Type() const override { return "ConfigReload"; }
};

class OrderExecutionEvent : public Event {
public:
   bool       success;
   ulong      ticket;
   ENUM_ORDER_TYPE orderType;
   double     entryPrice, sl, tp, volume;
   string     rejectionReason;
   string     orderComment;
   
   OrderExecutionEvent(bool ok, ulong t, ENUM_ORDER_TYPE type, 
                      double entry, double stopLoss, double takeProfit, double vol,
                      const string reason = "", const string comment = "")
      : Event("ExecutionManager"), success(ok), ticket(t), orderType(type),
        entryPrice(entry), sl(stopLoss), tp(takeProfit), volume(vol),
        rejectionReason(reason), orderComment(comment) {}
   
   virtual string Type() const override { return "OrderExecution"; }
};

class PositionUpdateEvent : public Event {
public:
   ulong      ticket;
   double     currentPrice;
   double     unrealizedPnL;
   bool       isClosing;
   
   PositionUpdateEvent(ulong t, double price, double pnl, bool closing = false)
      : Event("RecoveryManager"), ticket(t), currentPrice(price), 
        unrealizedPnL(pnl), isClosing(closing) {}
   
   virtual string Type() const override { return "PositionUpdate"; }
};

class PauseToggleEvent : public Event {
public:
    bool isBuy;
    bool newState;
    PauseToggleEvent(bool buy, bool state) : Event("Dashboard"), isBuy(buy), newState(state) {}
    virtual string Type() const override { return "PauseToggle"; }
};

//+------------------------------------------------------------------+
//| SYSTEM EVENTS                                                    |
//+------------------------------------------------------------------+
class HeartbeatEvent : public Event {
public:
   int intervalSeconds;
   
   HeartbeatEvent(int secs = 5) : Event("System"), intervalSeconds(secs) {}
   virtual string Type() const override { return "Heartbeat"; }
   
   virtual string Serialize() const override {
      return (string)intervalSeconds;
   }
};

class EmergencyStopEvent : public Event { // NEW EVENT
public:
   string reason;
   
   EmergencyStopEvent(const string r = "Manual Trigger") : Event("System"), reason(r) {}
   virtual string Type() const override { return "EmergencyStop"; }
   
   virtual string Serialize() const override { return reason; }
};

//+------------------------------------------------------------------+
//| EVENT UTILITIES                                                  |
//+------------------------------------------------------------------+
template<typename T>
void DispatchEvent(T* event) {
   EventBus::Instance().Dispatch(event);
}

//+------------------------------------------------------------------+
//| Replay Helper - Converts strings back to objects                 |
//+------------------------------------------------------------------+
void ReplayRecordedEvents() {
   if(g_recorder == NULL) return;
   
   Print("Replaying ", g_recorder.HistorySize(), " events...");
   for(int i = 0; i < g_recorder.HistorySize(); i++) {
      string type = g_recorder.GetHistoryType(i);
      string data = g_recorder.GetHistoryData(i);
      Event* e = NULL;
      
      if(type == "PriceUpdate") {
         string parts[];
         if(StringSplit(data, ';', parts) >= 5) {
            MqlTick t;
            t.time_msc = (long)parts[0];
            t.bid = (double)parts[1];
            t.ask = (double)parts[2];
            t.last = (double)parts[3];
            t.volume = (double)parts[4];
            e = new PriceUpdateEvent(t);
         }
      }
      else if(type == "NewBar") {
         string parts[];
         if(StringSplit(data, ';', parts) >= 6) {
            e = new NewBarEvent((datetime)parts[0], (double)parts[1], (double)parts[2], 
                                (double)parts[3], (double)parts[4], (int)parts[5]);
         }
      }
      else if(type == "Heartbeat") {
         e = new HeartbeatEvent((int)data);
      }
      else if(type == "EmergencyStop") { // NEW: Deserialize EmergencyStopEvent
         e = new EmergencyStopEvent(data);
      }
      
      if(CheckPointer(e) != POINTER_INVALID) {
         // Dispatch without re-recording
         bool wasRecording = g_recorder.IsRecording();
         if(wasRecording) g_recorder.Stop();
         
         EventBus::Instance().Dispatch(e);
         
         if(wasRecording) g_recorder.Start();
         Sleep(10); 
      }
   }
}

#define HANDLE_EVENT(className, eventType) \
   virtual void HandleEvent(Event* e) override { \
      if(e.Type() == eventType) { \
         className* typed = (className*)e; \
         On##eventType(typed); \
      } \
   } \
   virtual void On##eventType(className* e) = 0;

#endif
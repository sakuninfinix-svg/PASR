//+------------------------------------------------------------------+
//|               Price Action & Support Ressistance V1              |
//|         Optimized by Agsicentre (agsicentre.wordpress.com)       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#ifndef __MARKET_MANAGER_MQH__
#define __MARKET_MANAGER_MQH__

#property link      "agsicentre.wordpress.com"
#property version   "2.00"
#property strict

#include "IManager.mqh"
#include "10.DataManager.mqh"

class MarketManager : public IManager {
private:
   string m_baseCurr;
   string m_profitCurr;

   // --- Internal State Variables ---
   string m_newsStatus;
   datetime m_nextNewsTime;
   datetime m_lastBarTime;
   datetime m_dayAnchor;
   datetime m_lastNewsCheck;
   bool     m_lastNewsResult;
   datetime m_lastWebFetch;
   datetime m_webNewsTimes[];
   int      m_sessionStarts[7];
   int      m_sessionEnds[7];
   datetime m_lastEntryBarTime;
   datetime m_lastLossBarTime;
   int    m_consecutiveLosses;

   // Config Cache
   struct MarketConfigCache {
      string tradingSessions[7];
      double maxSpread;
      double atrMin;
      double atrMax;
      bool useNews;
      int newsFreeze;
      ENUM_NEWS_LEVEL newsLevel;
      string newsWebURL;
      int entryCooldownBars;
      int maxConsecutiveLoss;
      int lossCooldownBars;
      bool debugMode;
   } m_cfgCache;


   void     FetchWebNews();

public:
   MarketManager() : IManager("MarketManager", 100) {
      m_baseCurr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
      m_profitCurr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
      ZeroMemory(m_sessionStarts);
      ZeroMemory(m_sessionEnds);
   }
   ~MarketManager(); 

   virtual void RefreshConfigCache() override
   {
      for(int i=0; i<7; i++) m_cfgCache.tradingSessions[i] = CFG.TradingSessions[i];
      m_cfgCache.maxSpread = CFG.MaxSpread;
      m_cfgCache.atrMin = CFG.ATRMin;
      m_cfgCache.atrMax = CFG.ATRMax;
      m_cfgCache.useNews = CFG.UseNews;
      m_cfgCache.newsFreeze = CFG.NewsFreeze;
      m_cfgCache.newsLevel = CFG.NewsLevel;
      m_cfgCache.newsWebURL = CFG.NewsWebURL;
      m_cfgCache.entryCooldownBars = CFG.EntryCooldownBars;
      m_cfgCache.maxConsecutiveLoss = CFG.MaxConsecutiveLoss;
      m_cfgCache.lossCooldownBars = CFG.LossCooldownBars;
      m_cfgCache.debugMode = CFG.DebugMode;
   }

   virtual void OnConfigReload(ConfigReloadEvent* e) override {
      RefreshConfigCache();
   }

   virtual bool Init() override;
   bool IsNewBar();
   bool PassesGate(const MqlTick &tick, double &currentSpread, double currentATR);
   bool IsTradingSession();
   bool IsNewsTime();
   bool IsEntryCooldownActive();
   string GetNewsStatus() const { return m_newsStatus; }
   datetime GetNextNewsTime() const { return m_nextNewsTime; }
   int GetConsecutiveLosses() const { return m_consecutiveLosses; }

   // --- Methods to update internal state ---
   void UpdateLastEntryBarTime(datetime time) { m_lastEntryBarTime = time; }
   void UpdateLossStreak(double netProfit); 
   void SetLastBarTime(datetime time) { m_lastBarTime = time; }
};
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
MarketManager::~MarketManager()
{
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
bool MarketManager::Init()
{
   if(!IManager::Init()) return false;

   for(int i=0; i<7; i++) {
      string session = m_cfgCache.tradingSessions[i];
      if(session == "0" || session == "") { m_sessionStarts[i] = -1; m_sessionEnds[i] = -1; }
      else if(session == "00:00-24:00") { m_sessionStarts[i] = 0; m_sessionEnds[i] = 1440; }
      else {
         string parts[];
         if(StringSplit(session, '-', parts) == 2) {
            m_sessionStarts[i] = m_data.ParseHM(parts[0]);
            m_sessionEnds[i] = m_data.ParseHM(parts[1]);
         } else { m_sessionStarts[i] = 0; m_sessionEnds[i] = 1440; }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| IsNewBar                                                         |
//+------------------------------------------------------------------+
bool MarketManager::IsNewBar()
{
   datetime currTime = iTime(_Symbol, _Period, 0);
   if(currTime == m_lastBarTime)
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| PassesGate - Combines all market filters                         |
//+------------------------------------------------------------------+
bool MarketManager::PassesGate(const MqlTick &tick, double &currentSpread, double currentATR)
{
   if(!IsTradingSession())
   {
      m_data.DebugLog(m_cfgCache.debugMode, "Trading session is closed.");
      return false;
   }

   double bid = tick.bid;
   double ask = tick.ask;
   currentSpread = (ask - bid) / _Point;
   if(currentSpread > m_cfgCache.maxSpread)
   {
      m_data.DebugLog(m_cfgCache.debugMode, "Spread too high: " + DoubleToString(currentSpread, 1));
      return false;
   }

   if(currentATR < m_cfgCache.atrMin || currentATR > m_cfgCache.atrMax)
   {
      m_data.DebugLog(m_cfgCache.debugMode, "ATR out of range: " + DoubleToString(currentATR, 1));
      return false;
   }
   
   if(IsNewsTime()) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| IsTradingSession                                                 |
//+------------------------------------------------------------------+
bool MarketManager::IsTradingSession()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   
   int startMin = m_sessionStarts[now.day_of_week];
   int endMin = m_sessionEnds[now.day_of_week];
   
   if(startMin < 0) return false;
   if(startMin == 0 && endMin == 1440) return true;

   int currMin = now.hour * 60 + now.min;
   if(startMin <= endMin)
      return (currMin >= startMin && currMin <= endMin);
   return (currMin >= startMin || currMin <= endMin);
}

//+------------------------------------------------------------------+
//| FetchWebNews - Mendapatkan data berita via WebRequest            |
//+------------------------------------------------------------------+
void MarketManager::FetchWebNews()
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(TimeCurrent() < m_lastWebFetch + 3600) return; // Throttle web requests to once per hour
   char dta[], result[];
   string headers;
   int res = WebRequest("GET", m_cfgCache.newsWebURL, NULL, NULL, 5000, dta, 0, result, headers);

   if(res != 200) {
      m_data.DebugLog(m_cfgCache.debugMode, "WebNews Fetch Failed. HTTP Status: " + (string)res + ", MQL Error: " + (string)GetLastError());
      return;
   }

   string content = CharArrayToString(result);
   ArrayFree(m_webNewsTimes);
   string tagOpen = "<event>", tagClose = "</event>";
   int pos = 0;
   while((pos = StringFind(content, tagOpen, pos)) >= 0)
   {
      int endPos = StringFind(content, tagClose, pos);
      if(endPos < 0) break;
      
      string eventData = StringSubstr(content, pos, endPos - pos);
      bool isHighImpact = (StringFind(eventData, "High") >= 0 || 
                           (m_cfgCache.newsLevel >= NEWS_HIGH_MEDIUM && StringFind(eventData, "Medium") >= 0));
      
      bool isRelevant = (StringFind(eventData, m_baseCurr) >= 0 || 
                         StringFind(eventData, m_profitCurr) >= 0 ||
                         StringFind(eventData, "USD") >= 0);

      if(isHighImpact && isRelevant)
      {
         int datePos = StringFind(eventData, "<date>");
         int timePos = StringFind(eventData, "<time>");
         if(datePos >= 0 && timePos >= 0)
         {
            int dateEnd = StringFind(eventData, "</date>", datePos);
            int timeEnd = StringFind(eventData, "</time>", timePos);
            string dateRaw = StringSubstr(eventData, datePos, dateEnd - datePos);
            string timeRaw = StringSubstr(eventData, timePos, timeEnd - timePos);
            string dStr = m_data.StripTags(dateRaw); 
            string tStr = m_data.StripTags(timeRaw); 
            string dParts[];
            if(StringSplit(dStr, '-', dParts) == 3 && dParts[0] != "" && dParts[1] != "" && dParts[2] != "") {
               dStr = dParts[2] + "." + dParts[0] + "." + dParts[1];
               if(dStr == "..") continue; // Skip malformed dates
            }

            string timeOnly = tStr;
            StringReplace(timeOnly, " AM", "");
            StringReplace(timeOnly, " PM", "");
            int sep = StringFind(timeOnly, ":");
            if(sep < 0)
               continue;

            int hr = (int)StringToInteger(StringSubstr(timeOnly, 0, sep));
            int mn = (int)StringToInteger(StringSubstr(timeOnly, sep + 1));

            if(StringFind(tStr, "PM") >= 0 && hr != 12) hr += 12;
            else if(StringFind(tStr, "AM") >= 0 && hr == 12) hr = 0;
            
            string finalTime = StringFormat("%02d:%02d", hr, mn);

            datetime eventTime = StringToTime(dStr + " " + finalTime);
            if(eventTime > 0) {
               int sz = ArraySize(m_webNewsTimes);
               ArrayResize(m_webNewsTimes, sz + 1);
               m_webNewsTimes[sz] = eventTime;
            }
         }
      }
      pos = endPos + StringLen(tagClose);
   }
   m_lastWebFetch = TimeCurrent();
}

//+------------------------------------------------------------------+
//| IsNewsTime                                                       |
//+------------------------------------------------------------------+
bool MarketManager::IsNewsTime()
{
   if(!m_cfgCache.useNews)
   {
      m_newsStatus = "News filter OFF";
      return (m_lastNewsResult = false);
   }

   if(TimeCurrent() < m_lastNewsCheck + 60 && m_lastNewsCheck > 0)
      return m_lastNewsResult;

   m_lastNewsCheck = TimeCurrent();
   m_lastNewsResult = false;
   m_newsStatus = "Market Clear";

   // 1. Cek Web Fallback terlebih dahulu (karena kita simpan cache-nya)
   FetchWebNews();
   datetime now = TimeGMT(); // Web feeds usually use GMT
   for(int i = 0; i < ArraySize(m_webNewsTimes); i++)
   {
      if(now >= m_webNewsTimes[i] - (CFG.NewsFreeze * 60) && 
         now <= m_webNewsTimes[i] + (CFG.NewsFreeze * 60))
      {
         m_nextNewsTime = m_webNewsTimes[i];
         m_newsStatus = "WEB NEWS ACTIVE";
         m_lastNewsResult = true;
         return true;
      }
   }

   // 2. Jika Web tidak mendeteksi, gunakan Kalender Native sebagai lapis kedua
   m_nextNewsTime = 0;
   datetime gmtNow = TimeGMT(); // Native calendar also uses GMT
   datetime timeFrom = gmtNow - (m_cfgCache.newsFreeze * 60);
   datetime timeTo = gmtNow + (m_cfgCache.newsFreeze * 60);

   MqlCalendarValue values[];
   string currencies[2] = {m_baseCurr, m_profitCurr};

   for(int c = 0; c < 2; c++)
   {
      if(currencies[c] == "") continue;
      if(CalendarValueHistory(values, timeFrom, timeTo, NULL, currencies[c]) > 0)
      {
         for(int i = 0; i < ArraySize(values); i++)
         {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
               bool shouldBlock = false;
               if((int)m_cfgCache.newsLevel >= 1 && event.importance == CALENDAR_IMPORTANCE_HIGH) shouldBlock = true;
               else if((int)m_cfgCache.newsLevel >= 2 && event.importance == CALENDAR_IMPORTANCE_MODERATE) shouldBlock = true;
               else if((int)m_cfgCache.newsLevel >= 3 && event.importance == CALENDAR_IMPORTANCE_LOW) shouldBlock = true;

               if(shouldBlock)
               {
                  m_nextNewsTime = values[i].time;
                  m_newsStatus = "NEWS ACTIVE: " + event.name;
                  m_data.DebugLog(CFG.DebugMode, "News blocked: " + m_newsStatus);
                  m_lastNewsResult = true;
                  return m_lastNewsResult;
               }
            }
         }
      }
   }

   return m_lastNewsResult;
}

//+------------------------------------------------------------------+
//| GetATRPoints                                                     |
//+------------------------------------------------------------------+
//| IsEntryCooldownActive                                            |
//+------------------------------------------------------------------+
bool MarketManager::IsEntryCooldownActive()
{
   datetime currBar = iTime(_Symbol, _Period, 0);

   if(m_lastEntryBarTime > 0)
   {
      int barsSinceEntry = (int)((currBar - m_lastEntryBarTime) / PeriodSeconds(_Period));
      if(barsSinceEntry < m_cfgCache.entryCooldownBars)
      {
         m_data.DebugLog(m_cfgCache.debugMode, "Entry cooldown active (bars: " + (string)barsSinceEntry + ")");
         return true;
      }
   }

   if(m_consecutiveLosses >= m_cfgCache.maxConsecutiveLoss && m_lastLossBarTime > 0)
   {
      int barsSinceLoss = (int)((currBar - m_lastLossBarTime) / PeriodSeconds(_Period));
      if(barsSinceLoss < m_cfgCache.lossCooldownBars)
      {
         m_data.DebugLog(m_cfgCache.debugMode, "Loss cooldown active (bars: " + (string)barsSinceLoss + ")");
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| UpdateLossStreak                                                 |
//+------------------------------------------------------------------+
void MarketManager::UpdateLossStreak(double netProfit)
{
   if(netProfit < 0)
   {
      m_consecutiveLosses++;
      m_lastLossBarTime = iTime(_Symbol, _Period, 0); // Record the bar time of the loss
      m_data.DebugLog(m_cfgCache.debugMode, "Loss Detected! Net Profit: " + DoubleToString(netProfit, 2) + 
               " | Consecutive Losses: " + (string)m_consecutiveLosses + 
               " | Cooldown Active.");
   }
   else if(netProfit > 0)
   {
      m_consecutiveLosses = 0;
      m_data.DebugLog(m_cfgCache.debugMode, "Profit Detected! Resetting loss counter.");
   }
}

#endif

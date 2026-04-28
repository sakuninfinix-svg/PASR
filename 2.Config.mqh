//+------------------------------------------------------------------+
//|                            Price Action & Support Ressistance V1 |
//|                                                       Config.mqh |
//+------------------------------------------------------------------+

#ifndef __CONFIG_MQH__
#define __CONFIG_MQH__

#include <Trade/Trade.mqh>

enum ENUM_PATTERN_TYPE {
   PATTERN_NONE,
   PATTERN_PINBAR,
   PATTERN_ENGULFING,
   PATTERN_BOTTOM,
   PATTERN_FAKEY,
   PATTERN_INSIDE_BAR_BREAKOUT
};

struct SignalDecision {
   bool valid;
   ENUM_ORDER_TYPE orderType;
   double signalPrice;
   double zonePrice;
   ENUM_PATTERN_TYPE patternType;
   int bias;
   int signalShift;
   string reason;
};

struct OrderPlan {
   ENUM_ORDER_TYPE type;
   double entry;
   double brokerSL;
   double tp;
   double lot;
   double atrUsed;
   string comment;
};

enum ENUM_ENTRY_MODE { MODE_SAFE, MODE_AGGRESSIVE };
enum ENUM_SR_MODE { SR_EXTREME, SR_SWING, SR_AUTO };
enum ENUM_NEWS_LEVEL { NEWS_HIGH=1, NEWS_HIGH_MEDIUM=2, NEWS_ALL=3 };

enum ENUM_TRADE_STATE {
   TRADE_STATE_NONE = 0,
   TRADE_STATE_NORMAL,
   TRADE_STATE_DONE
};

struct PositionScanResult {
   int normalCount;
   int buyCount;
   int sellCount;
   int pendingCount;
   double totalProfit;
   double floatingPnL;
   double dailyRealized;
   double dailyDrawdown;
};

struct PerformanceStats {
   int safeTotal;
   int safeWins;
   int aggTotal;
   int aggWins;
};

// ------------------------------------------------------------
// ------------------------------------------------------------
input double InpMaxSpread          = 300.0;          // Batas Maksimal Spread (Points)  
input string InpSessionSun         = "00:00-24:00"; // Sesi Minggu (0=Off JJ:MM-JJ:MM=on)
input string InpSessionMon         = "00:00-24:00"; // Sesi Senin
input string InpSessionTue         = "00:00-24:00"; // Sesi Selasa
input string InpSessionWed         = "00:00-24:00"; // Sesi Rabu
input string InpSessionThu         = "00:00-24:00"; // Sesi Kamis
input string InpSessionFri         = "00:00-24:00"; // Sesi Jumat
input string InpSessionSat         = "0";           // Sesi Sabtu
input bool   InpUseAutoLot         = true;          // Gunakan AutoLot (Risk %)
input double InpRiskPct            = 1.0;           // Risiko % per Trade (dari Equity)
input double InpLotSize            = 0.01;          // Lot Statis (jika AutoLot OFF)
input double InpMaxDailyLossPct    = 5.0;           // Batas Maksimal Loss Harian (%)
input ulong  InpMagicNum           = 20260403;      // ID Transaksi

input ENUM_ENTRY_MODE       InpEntryMode = MODE_SAFE;       // Mode Entry (Safe/Aggressive)
input bool                  InpUseMTF = false;              // Gunakan Filter Multi-Timeframe
input bool                  InpUseTrailing = true;           // Aktifkan Trailing & Lock Profit
input bool                  InpExitOnOpposite = true;       // Close Posisi jika muncul Sinyal Lawan
input bool                  InpDebugMode = true;            // Aktifkan Mode Debug (Log)

input group ">>> CUSTOM OVERRIDE (aktif hanya jika PROFILE_CUSTOM) <<<"
input int               InpATRPeriod          = 14;              // ATR Period
input double            InpATRMin             = 150.0;           // Batas Minimum ATR (Points)
input double            InpATRMax             = 4000.0;          // Batas Maximum ATR (Points)
input bool              InpUseNewsFilter      = true;            // Aktifkan News Filter
input int               InpNewsFreezeMinutes  = 60;              // News Freeze (Menit sebelum/sesudah)
input ENUM_NEWS_LEVEL   InpNewsLevel          = NEWS_HIGH_MEDIUM;// Level News yang Diblokir
input string            InpNewsWebURL         = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml"; // URL Web News Feed

input ENUM_SR_MODE      InpSRMode             = SR_AUTO;         // Mode Deteksi SR
input int               InpSRLookback         = 20;              // SR Lookback (Candles)
input int               InpSignalLookback     = 5;               // Signal Lookback (Candles)
input double            InpMomentumThresholdATR = 0.15;          // Ambang Momentum (ATR x)
input double            InpMaxSignalSizeATR   = 1.8;             // Max Ukuran Sinyal (ATR x)

input double            InpMinTPDistanceATR   = 0.3;             // Min Jarak ke TP (ATR x)
input double            InpMinSRRangeATR      = 0.5;             // Min Range Zona SR (ATR x)
input double            InpMinWickRatio       = 45.0;            // Min Rasio Ekor/Wick (%)
input double            InpAntiBreakoutPct    = 0.85;            // Ambang Anti-Breakout (%)
input double            InpATRBufferMult      = 0.5;             // Global ATR Buffer Mult
input double            InpBufferMultStrong   = 0.3;             // Strong Zone Buffer Mult
input double            InpBufferMultWeak     = 0.8;             // Weak Zone Buffer Mult
input double            InpAggressiveWickRel  = 0.8;             // Aggressive Wick Relation

input ENUM_TIMEFRAMES   InpHTF                = PERIOD_H1;       // Higher Timeframe (HTF)
input int               InpHTFLookback        = 50;              // HTF Lookback (Candles)
input double            InpQualityLotMult     = 0.5;             // Multiplier Lot Sinyal Lemah

input int               InpMaxOpenPositions   = 3;               // Max Posisi Berjalan
input int               InpEntryCooldownBars  = 1;               // Jeda Antar Entry (Bars)
input bool              InpOneEntryPerZone    = true;            // Batasi Satu Entry Per Zona
input int               InpLossCooldownBars   = 3;               // Jeda Setelah Loss (Bars)
input int               InpSignalCooldownBars = 5;               // Cooldown Sinyal (Bars)
input int               InpPatternFailureCooldownBars = 10;      // Cooldown Level Gagal (Bars)
input int               InpMaxConsecutiveLoss = 2;               // Batas Loss Beruntun
input double            InpTPBufferATR        = 0.2;             // TP Buffer di Dalam Zona (ATR x)
input double            InpSLBufferATR        = 0.2;             // SL Buffer di Luar Zona (ATR x)
input double            InpZoneReuseATR       = 0.20;            // Jarak Reuse Zona (ATR x)

input double            InpTrailingStartATR   = 0.5;             // Pemicu Trailing Start (ATR x)
input double            InpTrailingBufferATR  = 0.05;            // Jarak Aman Buffer (ATR x)
input double            InpTrailActivationATR = 1.8;             // Aktivasi Trailing (ATR x)
input double            InpTrailStepATR       = 0.7;             // Langkah Trailing (ATR x)
input double            InpLockProfitATR      = 1.2;             // Ambang Lock Profit (ATR x)
input double            InpLockOffsetATR      = 0.15;            // Level Profit yang Dikunci (ATR x)

input int               InpMaxTradeDurationDays = 5;            // Durasi Maksimal Trade (Hari)

input bool              InpUsePartialClose    = true;            // Aktifkan Virtual Partial TP
input bool              InpSafeMode           = true;            // Aktifkan Safe Mode (Error Handling)
input double            InpPartialCloseLotPct = 0.5;             // Persentase Lot Partial Close
input double            InpPartialCloseATR    = 0.25;            // Target Partial Close (ATR x)

// ------------------------------------------------------------
// ACTIVE CONFIG OBJECT
// ------------------------------------------------------------
struct StrategyConfig
{
   // market
   int ATRPeriod;
   double ATRMin;
   double ATRMax;
   string TradingSessions[7];
   double MaxSpread;
   double MaxDailyLossPct;
   bool   UseAutoLot;
   double RiskPct;
   double LotSize;
   bool UseNews;
   int NewsFreeze;
   ENUM_NEWS_LEVEL NewsLevel;
   string NewsWebURL;

   // strategy
   ENUM_ENTRY_MODE EntryMode;
   ENUM_SR_MODE SRMode;
   int SRLookback;
   int SignalLookback;
   double MomentumThresholdATR;
   double MaxSignalATR;

   // price action
   double MinTPDistanceATR;
   double MinSRRangeATR;
   double MinWickRatio;
   double AntiBreakoutPct;
   double ATRBufferMult;
   double BufferMultStrong;
   double BufferMultWeak;
   double AggressiveWickRel;

   // mtf
   bool UseMTF;
   ENUM_TIMEFRAMES HTF;
   int HTFLookback;
   double QualityLotMult;

   // risk / anti overtrade
   int MaxPositions;
   int EntryCooldownBars;
   bool OneEntryPerZone;
   int LossCooldownBars;
   int SignalCooldownBars;
   int PatternFailureCooldownBars;
   int MaxConsecutiveLoss;
   double SLBufferATR;
   double TPBufferATR;
   double ZoneReuseATR;
   bool   ExitOnOpposite;

   // exit / trailing
   bool UseTrailing;
   double TrailingStartATR;
   double TrailingBufferATR;
   double TrailActivationATR;
   double TrailStepATR;
   double LockProfitATR;
   double LockOffsetATR;

   // trade protection
   int MaxTradeDurationDays;

   // partial close
   bool UsePartialClose;
   double PartialCloseLotPct;
   double PartialCloseATR;

   // misc
   bool DebugMode;
   bool SafeMode; // New: For error handling in EventBus
   ulong  MagicNum;
};

StrategyConfig CFG;

// ------------------------------------------------------------
// DEFAULT BUILDER
// ------------------------------------------------------------
void SetCommonDefaults()
{
   CFG.MagicNum = InpMagicNum;
   CFG.EntryMode = InpEntryMode;
   CFG.UseMTF = InpUseMTF;
   CFG.TradingSessions[0] = InpSessionSun;
   CFG.TradingSessions[1] = InpSessionMon;
   CFG.TradingSessions[2] = InpSessionTue;
   CFG.TradingSessions[3] = InpSessionWed;
   CFG.TradingSessions[4] = InpSessionThu;
   CFG.TradingSessions[5] = InpSessionFri;
   CFG.TradingSessions[6] = InpSessionSat;
   CFG.UseAutoLot = InpUseAutoLot;
   CFG.RiskPct = InpRiskPct;
   CFG.LotSize = InpLotSize;
   CFG.NewsWebURL = InpNewsWebURL;
   CFG.UseTrailing = InpUseTrailing;
   CFG.DebugMode = InpDebugMode;
   CFG.MaxSpread = InpMaxSpread;
   CFG.MaxDailyLossPct = InpMaxDailyLossPct;

   CFG.NewsLevel = InpNewsLevel;
   CFG.HTF = InpHTF;
   CFG.HTFLookback = InpHTFLookback;

   CFG.ATRPeriod = InpATRPeriod;
   CFG.ATRMin = InpATRMin;
   CFG.ATRMax = InpATRMax;
   CFG.UseNews = InpUseNewsFilter;
   CFG.NewsFreeze = InpNewsFreezeMinutes;
   CFG.SRMode = InpSRMode;
   CFG.SRLookback = InpSRLookback;
   CFG.SignalLookback = InpSignalLookback;
   CFG.MomentumThresholdATR = InpMomentumThresholdATR;
   CFG.MaxSignalATR = InpMaxSignalSizeATR;
   CFG.MinTPDistanceATR = InpMinTPDistanceATR;
   CFG.MinSRRangeATR = InpMinSRRangeATR;
   CFG.MinWickRatio = InpMinWickRatio;
   CFG.AntiBreakoutPct = InpAntiBreakoutPct;
   CFG.ATRBufferMult = InpATRBufferMult;
   CFG.BufferMultStrong = InpBufferMultStrong;
   CFG.BufferMultWeak = InpBufferMultWeak;
   CFG.AggressiveWickRel = InpAggressiveWickRel;
   CFG.MaxPositions = InpMaxOpenPositions;
   CFG.EntryCooldownBars = InpEntryCooldownBars;
   CFG.OneEntryPerZone = InpOneEntryPerZone;
   CFG.LossCooldownBars = InpLossCooldownBars;
   CFG.SignalCooldownBars = InpSignalCooldownBars;
   CFG.PatternFailureCooldownBars = InpPatternFailureCooldownBars;
   CFG.MaxConsecutiveLoss = InpMaxConsecutiveLoss;
   CFG.SLBufferATR = InpSLBufferATR;
   CFG.TPBufferATR = InpTPBufferATR;
   CFG.ZoneReuseATR = InpZoneReuseATR;
   CFG.QualityLotMult = InpQualityLotMult;
   CFG.ExitOnOpposite = InpExitOnOpposite;
   CFG.TrailingStartATR = InpTrailingStartATR;
   CFG.TrailingBufferATR = InpTrailingBufferATR;
   CFG.TrailActivationATR = InpTrailActivationATR;
   CFG.TrailStepATR = InpTrailStepATR;
   CFG.LockProfitATR = InpLockProfitATR;
   CFG.LockOffsetATR = InpLockOffsetATR;
   CFG.MaxTradeDurationDays = InpMaxTradeDurationDays;
   CFG.UsePartialClose = InpUsePartialClose;
   CFG.PartialCloseLotPct = InpPartialCloseLotPct;
   CFG.PartialCloseATR = InpPartialCloseATR;
   CFG.SafeMode = InpSafeMode; // Assign new input
}

void PrintConfigSummary()
{
   if(!CFG.DebugMode)
      return;

   Print("=== PASR CONFIG ACTIVE ===");
   Print("ATR Period       : ", CFG.ATRPeriod);
   Print("ATR Range        : ", DoubleToString(CFG.ATRMin,1), " - ", DoubleToString(CFG.ATRMax,1));
   Print("SR Mode          : ", (string)CFG.SRMode);
   Print("Signal Lookback  : ", CFG.SignalLookback);
   Print("Use MTF          : ", (CFG.UseMTF ? "true" : "false"));
   Print("Use Trailing     : ", (CFG.UseTrailing ? "true" : "false"));
}

//+------------------------------------------------------------------+
//| RecoveryEngine - Mengelola state persistensi untuk satu posisi  |
//+------------------------------------------------------------------+
class RecoveryEngine {
public:
   bool active;
   ulong mainTicket;
   int direction;
   ENUM_TRADE_STATE state;
   datetime entryTime;
   double entryPrice;
   double initialTP;
   double brokerSL;
   double zonePrice;
   double partialTP;
   double lastKnownATR;
   double lot;
   double peakEquity;
   bool partialClosed;
   bool partialArmedNormal;
   ulong lastActionTick;
   
   void SaveState(const ulong magic) const {
      if(mainTicket <= 0) return;
      string p = "PASR_" + (string)magic + "_" + (string)mainTicket + "_";
      GlobalVariablesDeleteAll(p);
      GlobalVariableSet(p + "v2", 2.0); 
      GlobalVariableSet(p + "st", (double)state);
      GlobalVariableSet(p + "ep", entryPrice);
      GlobalVariableSet(p + "it", initialTP);
      GlobalVariableSet(p + "bs", brokerSL);
      GlobalVariableSet(p + "zp", zonePrice);
      GlobalVariableSet(p + "dr", (double)direction);
      GlobalVariableSet(p + "at", lastKnownATR);
      GlobalVariableSet(p + "pk", peakEquity);
      GlobalVariableSet(p + "tm", (double)entryTime);
      GlobalVariableSet(p + "pc", (double)partialClosed);
      GlobalVariableSet(p + "an", (double)partialArmedNormal);
      GlobalVariableSet(p + "lo", lot);
      GlobalVariableSet(p + "ak", (double)lastActionTick);
   }

   void LoadState(ulong ticket, ulong magic) {
      string p = "PASR_" + (string)magic + "_" + (string)ticket + "_";
      if(GlobalVariableCheck(p + "v2")) {
         mainTicket = ticket;
         state      = (ENUM_TRADE_STATE)((int)GlobalVariableGet(p + "st"));
         entryPrice = GlobalVariableGet(p + "ep");
         initialTP  = GlobalVariableGet(p + "it");
         brokerSL   = GlobalVariableGet(p + "bs");
         zonePrice  = GlobalVariableGet(p + "zp");
         direction  = (int)GlobalVariableGet(p + "dr");
         lastKnownATR = GlobalVariableGet(p + "at");
         peakEquity = GlobalVariableGet(p + "pk");
         entryTime  = (datetime)GlobalVariableGet(p + "tm");
         partialClosed = (GlobalVariableGet(p + "pc") > 0.5);
         partialArmedNormal = (GlobalVariableGet(p + "an") > 0.5);
         lot        = GlobalVariableGet(p + "lo");
         lastActionTick = (ulong)GlobalVariableGet(p + "ak");

         double pcDist = lastKnownATR * CFG.PartialCloseATR * _Point;
         partialTP = NormalizeDouble(entryPrice + ((direction == 1 ? 1.0 : -1.0) * pcDist), _Digits);
         active = true;
      }
   }
   
   void Reset() { 
      active = false; mainTicket = 0; direction = 0; 
      state = TRADE_STATE_NONE; entryTime = 0; 
      entryPrice = 0.0; zonePrice = 0.0; initialTP = 0.0; 
      brokerSL = 0.0; partialTP = 0.0; lastKnownATR = 0.0; 
      lot = 0.0; peakEquity = 0.0; 
      partialClosed = false; partialArmedNormal = false; 
      lastActionTick = 0; 
   }

   RecoveryEngine() { Reset(); }
};

#endif
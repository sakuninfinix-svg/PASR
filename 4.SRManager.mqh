//+------------------------------------------------------------------+
//|                                                    SRManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
#ifndef __SR_MANAGER_MQH__
#define __SR_MANAGER_MQH__

#property copyright "Copyright 2026, Agsicentre"
#property strict

#include "IManager.mqh"
#include "10.DataManager.mqh"

class SRManager : public IManager {
private:
   double m_targetSupport;
   double m_targetResistance;
   double m_htfSupport;
   double m_htfResistance;
   bool   m_isSupportBroken;
   bool   m_isResistanceBroken;
   double m_supBufferMult;
   double m_resBufferMult;
   int    m_supHtfAlignment; // 1: Aligned, 0: Neutral, -1: Contra
   int    m_resHtfAlignment;

   // Config Cache
   struct SRConfigCache {
      ENUM_SR_MODE srMode;
      int srLookback;
      ENUM_ENTRY_MODE entryMode;
      double bufferMultWeak;
      double bufferMultStrong;
      double atrBufferMult;
      bool useMTF;
      ENUM_TIMEFRAMES htf;
      int htfLookback;
      double minSRRangeATR;
      bool debugMode;
   } m_cfgCache;


   // Helper: Cek apakah zona ditembus 2x Close dalam X bar
   bool IsBroken(double price, bool isSupport, int barsCount)
   {
      if(price <= 0) return true;
      double closePrices[];
      if(CopyClose(_Symbol, _Period, 1, barsCount, closePrices) <= 0) return false;
      
      int breach = 0;
      for(int i = 0; i < barsCount; i++)
      {
         if(isSupport && closePrices[i] < price) breach++;
         if(!isSupport && closePrices[i] > price) breach++;
      }
      return (breach >= 2);
   }

   // Helper: Mencari Swing Fractal terdekat
   double FindNearestSwing(bool isSupport, int maxBars, int &foundShift)
   {
      foundShift = -1;
      for(int i = 2; i <= maxBars; i++)
      {
         if(isSupport) {
            if(iLow(_Symbol, _Period, i) < iLow(_Symbol, _Period, i+1) && iLow(_Symbol, _Period, i) < iLow(_Symbol, _Period, i-1))
               { foundShift = i; return iLow(_Symbol, _Period, i); }
         } else {
            if(iHigh(_Symbol, _Period, i) > iHigh(_Symbol, _Period, i+1) && iHigh(_Symbol, _Period, i) > iHigh(_Symbol, _Period, i-1))
               { foundShift = i; return iHigh(_Symbol, _Period, i); }
         }
      }
      return 0;
   }

   // Helper untuk menggambar garis
   void DrawOrMoveHLine(string name, double price, color clr)
   {
      // Performa: Cek apakah harga berubah sebelum update objek
      if(ObjectFind(0, name) >= 0) {
         if(MathAbs(ObjectGetDouble(0, name, OBJPROP_PRICE) - price) < _Point) return;
      }

      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }

public:
   SRManager() : IManager("SRManager", 20),
                 m_targetSupport(0), 
                 m_targetResistance(0), 
                 m_htfSupport(0), 
                 m_htfResistance(0),
                 m_isSupportBroken(false),
                 m_isResistanceBroken(false),
                 m_supBufferMult(0.5),
                 m_resBufferMult(0.5),
                 m_supHtfAlignment(0),
                 m_resHtfAlignment(0) {}

   virtual void RefreshConfigCache() override
   {
      m_cfgCache.srMode = CFG.SRMode;
      m_cfgCache.srLookback = CFG.SRLookback;
      m_cfgCache.entryMode = CFG.EntryMode;
      m_cfgCache.bufferMultWeak = CFG.BufferMultWeak;
      m_cfgCache.bufferMultStrong = CFG.BufferMultStrong;
      m_cfgCache.atrBufferMult = CFG.ATRBufferMult;
      m_cfgCache.useMTF = CFG.UseMTF;
      m_cfgCache.htf = CFG.HTF;
      m_cfgCache.htfLookback = CFG.HTFLookback;
      m_cfgCache.minSRRangeATR = CFG.MinSRRangeATR;
      m_cfgCache.debugMode = CFG.DebugMode;
   }

   virtual void OnConfigReload(ConfigReloadEvent* e) override {
      RefreshConfigCache();
   }

   virtual void DeclareEvents() override 
   {
      AddEvent("NewBar");
   }

   virtual void OnNewBar(NewBarEvent *e) override {
      UpdateHTFZones();
      UpdateMainZones(m_data.GetATRPoints());
   }

   void UpdateMainZones(double atrPoints)
   {
      double extRes = 0, extSup = 0;
      double swRes = 0, swSup = 0;
      int swResShift = -1, swSupShift = -1;      

      // 1. Ambil Data Extreme (HH/LL)
      int highestIdx = iHighest(_Symbol, _Period, MODE_HIGH, CFG.SRLookback, 1);
      int lowestIdx  = iLowest(_Symbol, _Period, MODE_LOW, CFG.SRLookback, 1);
      if(highestIdx >= 0) extRes = iHigh(_Symbol, _Period, highestIdx);
      if(lowestIdx >= 0)  extSup = iLow(_Symbol, _Period, lowestIdx);

      // 2. Ambil Data Swing (Fractal terdekat < 50 bar)
      swRes = FindNearestSwing(false, 50, swResShift);
      swSup = FindNearestSwing(true, 50, swSupShift);

      // Logic Pemilihan berdasarkan Mode
      if(CFG.SRMode == SR_EXTREME)
      {
         m_targetResistance = extRes;
         m_targetSupport    = extSup;
      }
      else if(CFG.SRMode == SR_SWING)
      {
         m_targetResistance = (swRes > 0) ? swRes : extRes;
         m_targetSupport    = (swSup > 0) ? swSup : extSup;
      }
      else // SR_AUTO (EA urus sendiri)
      {
         // Evaluasi Resistance
         if(swRes > 0 && !IsBroken(swRes, false, 5) && (IsBroken(extRes, false, 10) || swResShift < 15)) 
            m_targetResistance = swRes;
         else 
            m_targetResistance = extRes;

         // Evaluasi Support
         if(swSup > 0 && !IsBroken(swSup, true, 5) && (IsBroken(extSup, true, 10) || swSupShift < 15))
            m_targetSupport = swSup;
         else
            m_targetSupport = extSup;
      }

      DrawOrMoveHLine("ResLine", m_targetResistance, clrRed);
      DrawOrMoveHLine("SupLine", m_targetSupport, clrAqua);
      
      CheckZoneStatus(atrPoints);

      // Setelah zone dihitung, kirim event:
      ZoneUpdateEvent* zoneEvent = new ZoneUpdateEvent(
         m_targetSupport, m_targetResistance,
         m_htfSupport, m_htfResistance,
         m_isSupportBroken, m_isResistanceBroken,
         m_supBufferMult, m_resBufferMult,
         m_supHtfAlignment, m_resHtfAlignment,
         atrPoints
      );
      if(CheckPointer(EventBus::Instance()) != POINTER_INVALID)
         EventBus::Instance().Dispatch(zoneEvent);
   }
   void CheckZoneStatus(double atrPoints)
   {
      m_isSupportBroken = false;
      m_isResistanceBroken = false;
      if(m_targetSupport <= 0 || m_targetResistance <= 0) return;
      
      // Filter "rusak" dinamis berdasarkan mode
      int barsToCheck = (CFG.SRMode == SR_EXTREME) ? 10 : 5;
      m_isSupportBroken = IsBroken(m_targetSupport, true, barsToCheck);
      m_isResistanceBroken = IsBroken(m_targetResistance, false, barsToCheck);

      // Jika mode EXTREME, gunakan buffer statis agar lebih "Safe" sesuai filosofi Extreme SR
      if(CFG.SRMode == SR_EXTREME) {
         m_resBufferMult = m_supBufferMult = (CFG.EntryMode == MODE_SAFE) ? 0.5 : 0.8;
         return; 
      }

      // Hitung Touch Count untuk menentukan Buffer Mult
      int supTouches = 0, resTouches = 0;
      double touchZone = (atrPoints * 0.5) * _Point; // Gunakan standar 0.5 ATR untuk deteksi sentuhan

      for(int i = 1; i <= CFG.SRLookback; i++)
      {
         if(MathAbs(iLow(_Symbol, _Period, i) - m_targetSupport) < touchZone) supTouches++;
         if(MathAbs(iHigh(_Symbol, _Period, i) - m_targetResistance) < touchZone) resTouches++;
      }

      // Tentukan Multiplier Dinamis untuk Support
      if(m_isSupportBroken) m_supBufferMult = CFG.BufferMultWeak; 
      else if(supTouches >= 3) m_supBufferMult = CFG.BufferMultStrong;
      else if(supTouches <= 1) m_supBufferMult = CFG.ATRBufferMult; 
      else m_supBufferMult = 0.65; // Normal/Intermediate

      // Tentukan Multiplier Dinamis untuk Resistance
      if(m_isResistanceBroken) m_resBufferMult = CFG.BufferMultWeak;
      else if(resTouches >= 3) m_resBufferMult = CFG.BufferMultStrong;
      else if(resTouches <= 1) m_resBufferMult = CFG.ATRBufferMult;
      else m_resBufferMult = 0.65; // Normal/Intermediate

      // --- HTF Alignment Integration ---
      m_supHtfAlignment = 0;
      m_resHtfAlignment = 0;
      
      if(CFG.UseMTF && m_htfSupport > 0 && m_htfResistance > 0)
      {
         double htfZoneBuffer = (atrPoints * CFG.ATRBufferMult) * _Point;
         
         // Primary Support vs HTF Zones
         if(m_targetSupport <= m_htfSupport + htfZoneBuffer) m_supHtfAlignment = 1; // Aligned with HTF Support
         else if(m_targetSupport >= m_htfResistance - htfZoneBuffer) m_supHtfAlignment = -1; // Contra: At HTF Resistance

         // Primary Resistance vs HTF Zones
         if(m_targetResistance >= m_htfResistance - htfZoneBuffer) m_resHtfAlignment = 1; // Aligned with HTF Resistance
         else if(m_targetResistance <= m_htfSupport + htfZoneBuffer) m_resHtfAlignment = -1; // Contra: At HTF Support
      }
   }

   void UpdateHTFZones()
   {
      if(!CFG.UseMTF) return;
      
      int highestIdx = iHighest(_Symbol, CFG.HTF, MODE_HIGH, CFG.HTFLookback, 1);
      int lowestIdx  = iLowest(_Symbol, CFG.HTF, MODE_LOW, CFG.HTFLookback, 1);
      
      if(highestIdx >= 0 && lowestIdx >= 0)
      {
         m_htfResistance = iHigh(_Symbol, CFG.HTF, highestIdx);
         m_htfSupport    = iLow(_Symbol, CFG.HTF, lowestIdx);
      }
   }

   bool IsTradableRange(double atrPoints)
   {
      if(m_targetResistance <= 0 || m_targetSupport <= 0) return false;

      double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      double minRange = MathMax(atrPoints * CFG.MinSRRangeATR, spread * 5.0); 
      double rangePts = (m_targetResistance - m_targetSupport) / _Point;

      return (rangePts >= minRange);
   }

   // Getters
   double Support()        const { return m_targetSupport; }
   double Resistance()     const { return m_targetResistance; }
   double HTFSupport()     const { return m_htfSupport; }
   double HTFResistance()  const { return m_htfResistance; }
   bool IsSupportBroken()    const { return m_isSupportBroken; }
   bool IsResistanceBroken() const { return m_isResistanceBroken; }
   double SupBufferMult()    const { return m_supBufferMult; }
   double ResBufferMult()    const { return m_resBufferMult; }
   int SupHtfAlignment()     const { return m_supHtfAlignment; }
   int ResHtfAlignment()     const { return m_resHtfAlignment; }
};

#endif
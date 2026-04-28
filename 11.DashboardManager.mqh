//+------------------------------------------------------------------+
//|                                             DashboardManager.mqh |
//|                             Price Action & Support Resistance V1 |
//|                                     Copyright 2026, Agsicentre   |
//+------------------------------------------------------------------+
#ifndef __DASHBOARD_MANAGER_MQH__
#define __DASHBOARD_MANAGER_MQH__

#property strict

#include "0.EventBus.mqh"
#include "1.Events.mqh"
#include "2.Config.mqh"
#include "IManager.mqh"
#include "10.DataManager.mqh"
#include <Controls/Dialog.mqh>
#include <Controls/Button.mqh>
#include <Controls/Label.mqh>

#define DASHBOARD_EVENT_REFRESH    (CHARTEVENT_CUSTOM + 100)
#define DASHBOARD_EVENT_EMERGENCY  (CHARTEVENT_CUSTOM + 101)
#define DASHBOARD_EVENT_PAUSE      (CHARTEVENT_CUSTOM + 102)
#define DASHBOARD_EVENT_STATS      (CHARTEVENT_CUSTOM + 103)

// ✅ DashboardController: Bertindak sebagai Event Proxy & Data Provider
class DashboardController : public IManager
{
private:
    CAppDialog*     m_uiParent;
    long            m_chartId;
    datetime        m_lastHeartbeat;
    int             m_heartbeatIntervalSec;
    
    struct DataCache {
        double atrPoints;
        PositionScanResult scanResult;
        PerformanceStats perfStats;
        datetime lastUpdate;
    } m_dataCache;

    void RefreshDataCache() {
        if(CheckPointer(m_data) == POINTER_INVALID) return;
        m_dataCache.atrPoints = m_data.GetATRPoints();
        m_dataCache.scanResult = m_data.GetScanResult();
        m_dataCache.perfStats = m_data.GetPerformanceStats();
        m_dataCache.lastUpdate = TimeCurrent();
    }

public:
    DashboardController() : IManager("DashboardController", 90) 
    {
        m_uiParent = NULL; m_chartId = ChartID();
        m_lastHeartbeat = 0; m_heartbeatIntervalSec = 2;
        ZeroMemory(m_dataCache);
    }
    void SetUI(CAppDialog* ui_ptr) { m_uiParent = ui_ptr; }

    virtual void DeclareEvents() override {
        AddEvent("Heartbeat"); AddEvent("EmergencyStop"); AddEvent("PauseToggle");
        AddEvent("ConfigReload"); AddEvent("PositionUpdate");
        AddEvent("OrderExecution"); AddEvent("SignalGenerated");
    }

    // ✅ Route event kustom yang tidak ada di IManager
    virtual void OnCustomEvent(Event* e) override {
        if(e.Type() == "PauseToggle") {
            PauseToggleEvent* pt = dynamic_cast<PauseToggleEvent*>(e); // Use dynamic_cast for safety
            if(CheckPointer(m_uiParent) != POINTER_INVALID)
                m_uiParent.EventChartCustom(m_chartId, DASHBOARD_EVENT_PAUSE, pt.isBuy ? 1 : 0, pt.newState ? 1 : 0, "");
        }
    }

    // ✅ Override OnConfigReload untuk memastikan cache internal diperbarui
    virtual void OnConfigReload(ConfigReloadEvent* e) override {
        RefreshDataCache();
        if(CheckPointer(m_uiParent) != POINTER_INVALID)
            m_uiParent.EventChartCustom(m_chartId, DASHBOARD_EVENT_REFRESH, 0, 0, "");
    }

    virtual void OnHeartbeat(HeartbeatEvent* e) override {
        if(TimeCurrent() - m_lastHeartbeat < m_heartbeatIntervalSec) return;
        m_lastHeartbeat = TimeCurrent();
        RefreshDataCache();
        if(CheckPointer(m_uiParent) != POINTER_INVALID)
            m_uiParent.EventChartCustom(m_chartId, DASHBOARD_EVENT_REFRESH, 0, 0, "");
    }

    virtual void OnEmergencyStop(EmergencyStopEvent* e) override {
        Log("🚨 EMERGENCY: " + e.reason);
        if(CheckPointer(m_uiParent) != POINTER_INVALID)
            m_uiParent.EventChartCustom(m_chartId, DASHBOARD_EVENT_EMERGENCY, 0, 0, e.reason);
    }

    virtual void OnSignalGenerated(SignalGeneratedEvent* e) override {
        if(CheckPointer(m_uiParent) != POINTER_INVALID)
            m_uiParent.EventChartCustom(m_chartId, DASHBOARD_EVENT_STATS, e.signal.orderType, (long)e.signal.patternType, e.signal.reason);
    }

    const DataCache& GetCachedData() const { return m_dataCache; }
};

class DashboardControllerFactory {
public:
    static DashboardController* Create(CAppDialog* parent, DataManager* data) {
        DashboardController* ctrl = new DashboardController();
        if(CheckPointer(ctrl) != POINTER_INVALID) {
            ctrl.SetUI(parent);
            ctrl.SetDataManager(data);
            if(!ctrl.Init()) { delete ctrl; return NULL; }
        }
        return ctrl;
    }
    static void Destroy(DashboardController* &ctrl) {
        if(CheckPointer(ctrl) != POINTER_INVALID) { ctrl.Deinit(); delete ctrl; ctrl = NULL; }
    }
};

class DashboardManager : public CAppDialog
{
private:
    DashboardController* m_controller;
    CLabel      m_lblHeader;
    CLabel      m_lblSystemState;
    CLabel      m_lblGlobalPnL;
    CLabel      m_lblSymbolStats;
    CLabel      m_lblWinRate;
    CButton     m_btnEmergencyClose;
    CButton     m_btnPauseBuy;
    CButton     m_btnPauseSell;
    ulong       m_magic;
    bool        m_isInitialized;

    struct UICache {
        double   globalPnL;
        int      activePositions;
        double   floatingPnL;
        double   dailyDrawdown;
        double   dailyRealized;
        string   systemState;
        bool     pauseBuy, pauseSell;
        int      safeTotal, safeWins;
        int      aggTotal, aggWins;
    } m_cache;

    void SafeUpdateLabel(CLabel &ctrl, string text) {
        if(ctrl.Name() != "") ctrl.Text(text);
    }

    void UpdateButtonColors(CButton &btn, bool active) {
        btn.ColorBackground(active ? clrOrange : clrSilver);
        btn.Refresh();
    }

    void RefreshCache() {
        if(CheckPointer(m_controller) == POINTER_INVALID) return;
        const DashboardController::DataCache data = m_controller.GetCachedData();
        m_cache.globalPnL = data.scanResult.totalProfit;
        m_cache.activePositions = data.scanResult.normalCount;
        m_cache.floatingPnL = data.scanResult.floatingPnL;
        m_cache.dailyDrawdown = data.scanResult.dailyDrawdown;
        m_cache.dailyRealized = data.scanResult.dailyRealized; // FIX: Add dailyRealized
        m_cache.pauseBuy = GlobalVariableCheck("PASR_PAUSE_BUY_"+(string)m_magic) && GlobalVariableGet("PASR_PAUSE_BUY_"+(string)m_magic) > 0;
        m_cache.pauseSell = GlobalVariableCheck("PASR_PAUSE_SELL_"+(string)m_magic) && GlobalVariableGet("PASR_PAUSE_SELL_"+(string)m_magic) > 0;
        
        if(m_cache.pauseBuy && m_cache.pauseSell) m_cache.systemState = "PAUSED";
        else if(GlobalVariableCheck("PASR_EMERGENCY_"+(string)m_magic) && GlobalVariableGet("PASR_EMERGENCY_"+(string)m_magic) > 0) m_cache.systemState = "EMERGENCY";
        else m_cache.systemState = "ACTIVE";
        
        m_cache.safeTotal = data.perfStats.safeTotal; m_cache.safeWins = data.perfStats.safeWins;
        m_cache.aggTotal = data.perfStats.aggTotal; m_cache.aggWins = data.perfStats.aggWins;
    }

    void ApplyUI() {
        SafeUpdateLabel(m_lblSystemState, StringFormat("SYSTEM: %s | EQUITY: %.2f", m_cache.systemState, AccountInfoDouble(ACCOUNT_EQUITY)));
        SafeUpdateLabel(m_lblGlobalPnL, StringFormat("FLOAT PnL: %.2f | POS: %d", m_cache.floatingPnL, m_cache.activePositions)); // FIX: Use floatingPnL
        SafeUpdateLabel(m_lblSymbolStats, StringFormat("[%s] DD: %.2f%% | Realized: %.2f", _Symbol, m_cache.dailyDrawdown, m_cache.dailyRealized)); // FIX: Use dailyRealized
        double safeWR = (m_cache.safeTotal > 0) ? (m_cache.safeWins * 100.0 / m_cache.safeTotal) : 0;
        double aggWR = (m_cache.aggTotal > 0) ? (m_cache.aggWins * 100.0 / m_cache.aggTotal) : 0;
        SafeUpdateLabel(m_lblWinRate, StringFormat("WR - Safe: %.1f%%(%d) | Agg: %.1f%%(%d)", safeWR, m_cache.safeTotal, aggWR, m_cache.aggTotal));
        
        m_btnPauseBuy.Text(m_cache.pauseBuy ? "PAUSE BUY: ON" : "PAUSE BUY: OFF");
        UpdateButtonColors(m_btnPauseBuy, m_cache.pauseBuy);
        m_btnPauseSell.Text(m_cache.pauseSell ? "PAUSE SELL: ON" : "PAUSE SELL: OFF");
        UpdateButtonColors(m_btnPauseSell, m_cache.pauseSell);
        m_btnEmergencyClose.Refresh();
        
        Redraw();
    }

public:
    DashboardManager() : m_controller(NULL) {
        m_isInitialized = false;
        m_magic = 0; // Will be set in CreateDashboard after CFG is ready
        ZeroMemory(m_cache); // Initialize m_cache
    }

    void SetController(DashboardController* ctrl) { m_controller = ctrl; }

    ~DashboardManager() {
        if(m_isInitialized) Destroy(0);
    }

    bool CreateDashboard(const long chart, const string name, const int subwin,
                         const int x1, const int y1, const int x2, const int y2) {
        m_magic = CFG.MagicNum; // Set magic after CFG is initialized
        if(!CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2)) return false;
        
        int x = 15, y = 10;
        m_lblHeader.Create(m_chart_id, m_name+"_hdr", m_subwin, x, y, x2-x, y+15); // ✅ FIX: Beri tinggi
        m_lblHeader.Text("PASR NEURAL TERMINAL v2.0");
        m_lblHeader.FontSize(10); m_lblHeader.Color(clrWhiteSmoke);
        Add(m_lblHeader);
        
        y += 25; // Space for header
        m_lblSystemState.Create(m_chart_id, m_name+"_sys", m_subwin, x, y, x2-x, y+15); // Height 15
        Add(m_lblSystemState);
        
        y += 20; // Space between labels
        m_lblGlobalPnL.Create(m_chart_id, m_name+"_pnl", m_subwin, x, y, x2-x, y+15); // Height 15
        Add(m_lblGlobalPnL);
        
        y += 20; // Space between labels
        m_lblSymbolStats.Create(m_chart_id, m_name+"_sym", m_subwin, x, y, x2-x, y+15); // Height 15
        Add(m_lblSymbolStats);
        
        y += 20; // Space between labels
        m_lblWinRate.Create(m_chart_id, m_name+"_wr", m_subwin, x, y, x2-x, y+15); // Height 15
        Add(m_lblWinRate);
        
        y += 30; // Space before buttons
        m_btnEmergencyClose.Create(m_chart_id, m_name+"_btn_ec", m_subwin, x, y, x+120, y+25); // Height 25
        m_btnEmergencyClose.Text("EMERGENCY CLOSE");
        m_btnEmergencyClose.ColorBackground(clrFireBrick);
        Add(m_btnEmergencyClose);
        
        y += 30; // Space between button rows
        m_btnPauseBuy.Create(m_chart_id, m_name+"_btn_pb", m_subwin, x, y, x+120, y+25); // Height 25
        m_btnPauseBuy.Text("PAUSE BUY: OFF");
        Add(m_btnPauseBuy);
        
        m_btnPauseSell.Create(m_chart_id, m_name+"_btn_ps", m_subwin, x+130, y, x+250, y+25); // Height 25
        m_btnPauseSell.Text("PAUSE SELL: OFF");
        Add(m_btnPauseSell);
        
        m_isInitialized = true;
        Run();
        return true;
    }

    virtual bool OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam) override {
        if(id == CHARTEVENT_OBJECT_CLICK) {
            if(sparam == m_btnEmergencyClose.Name()) { OnEmergencyClick(); return true; }
            if(sparam == m_btnPauseBuy.Name()) { OnPauseBuyClick(); return true; }
            if(sparam == m_btnPauseSell.Name()) { OnPauseSellClick(); return true; }
        }
        if(id >= CHARTEVENT_CUSTOM) {
            if(id == DASHBOARD_EVENT_REFRESH) { RefreshCache(); ApplyUI(); return true; }
            if(id == DASHBOARD_EVENT_PAUSE) {
                if(lparam == 1) m_cache.pauseBuy = (bool)dparam;
                else m_cache.pauseSell = (bool)dparam;
                ApplyUI(); return true;
            }
            if(id == DASHBOARD_EVENT_EMERGENCY) { m_cache.systemState = "EMERGENCY TRIGGERED"; ApplyUI(); return true; }
        }
        return CAppDialog::OnEvent(id, lparam, dparam, sparam);
    }

    void OnEmergencyClick() {
        if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
        GlobalVariableSet("PASR_EMERGENCY_"+(string)m_magic, 1);
        EmergencyStopEvent* ev = new EmergencyStopEvent("Manual Emergency via Dashboard");
        EventBus::Instance().Dispatch(ev);
        if(CFG.DebugMode) Print("[Dashboard] EMERGENCY CLOSE dispatched.");
    }

    void OnPauseBuyClick() {
        string gv = "PASR_PAUSE_BUY_"+(string)m_magic;
        bool state = GlobalVariableCheck(gv) && GlobalVariableGet(gv) > 0;
        state = !state;
        GlobalVariableSet(gv, state ? 1 : 0);
        EventBus::Instance().Dispatch(new PauseToggleEvent(true, state));
    }

    void OnPauseSellClick() {
        string gv = "PASR_PAUSE_SELL_"+(string)m_magic;
        bool state = GlobalVariableCheck(gv) && GlobalVariableGet(gv) > 0;
        state = !state;
        GlobalVariableSet(gv, state ? 1 : 0);
        EventBus::Instance().Dispatch(new PauseToggleEvent(false, state));
    }
};
#endif
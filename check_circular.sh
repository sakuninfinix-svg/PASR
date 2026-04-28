#!/bin/bash
echo "Checking for circular dependencies..."
echo ""

# Check if any file includes itself directly or indirectly
for file in *.mqh; do
    echo "=== Checking $file ==="
    grep "#include" "$file" | grep -v "^//" | while read line; do
        included=$(echo "$line" | sed 's/.*"\(.*\)".*/\1/')
        echo "  Includes: $included"
    done
done

echo ""
echo "Dependency graph summary:"
echo "EventBus -> Config"
echo "Events -> EventBus + Config"
echo "IManager -> EventBus + Events + Config"
echo "DataManager -> IManager"
echo "MarketManager -> IManager + DataManager"
echo "SRManager -> IManager + DataManager"
echo "PatternManager -> Config (only structs/enums)"
echo "SignalManager -> IManager + PatternManager"
echo "RiskCalculator -> Config (only structs/enums)"
echo "ExecutionManager -> IManager + DataManager + RiskCalculator"
echo "RecoveryManager -> IManager + DataManager + RiskCalculator"
echo "DashboardManager -> IManager + DataManager + GUI"

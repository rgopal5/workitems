#!/bin/bash
# System Check Script for AI Engine Prerequisites
# Run this to verify what's already installed

echo "=========================================="
echo "AI Engine System Prerequisites Check"
echo "Host: $(hostname)"
echo "IP: $(hostname -I | awk '{print $1}')"
echo "Date: $(date)"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed: $(command -v $1)"
        if [ ! -z "$2" ]; then
            echo "  Version: $($1 $2 2>&1 | head -1)"
        fi
        return 0
    else
        echo -e "${RED}✗${NC} $1 is NOT installed"
        return 1
    fi
}

check_service() {
    if systemctl is-active --quiet $1 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $1 service is running"
        systemctl status $1 --no-pager -l | grep "Active:" | sed 's/^/  /'
        return 0
    elif systemctl list-unit-files | grep -q "^$1.service"; then
        echo -e "${YELLOW}⚠${NC} $1 service exists but not running"
        return 1
    else
        echo -e "${RED}✗${NC} $1 service not found"
        return 1
    fi
}

check_port() {
    if netstat -tuln 2>/dev/null | grep -q ":$1 " || ss -tuln 2>/dev/null | grep -q ":$1 "; then
        echo -e "${GREEN}✓${NC} Port $1 is in use ($2)"
        return 0
    else
        echo -e "${RED}✗${NC} Port $1 is not in use ($2)"
        return 1
    fi
}

echo "=== Operating System ==="
cat /etc/os-release | grep -E "^(NAME|VERSION)="
echo "Kernel: $(uname -r)"
echo ""

echo "=== System Resources ==="
echo "CPU Cores: $(nproc)"
echo "RAM Total: $(free -h | grep Mem | awk '{print $2}')"
echo "RAM Available: $(free -h | grep Mem | awk '{print $7}')"
echo "Disk Space:"
df -h / | tail -1 | awk '{print "  Root: "$2" total, "$4" available ("$5" used)"}'
echo ""

echo "=== Python ==="
check_command python3 --version
check_command python3.10 --version
check_command python3.11 --version
check_command python3.12 --version
check_command pip3 --version
echo ""

echo "=== Database - PostgreSQL ==="
check_command psql --version
check_service postgresql
check_port 5432 "PostgreSQL"
if command -v psql &> /dev/null; then
    echo "  Databases:"
    sudo -u postgres psql -c "\l" 2>/dev/null | grep -E "universal_ai|aiengine" || echo "    No AI Engine databases found"
fi
echo ""

echo "=== Cache - Redis ==="
check_command redis-server --version
check_command redis-cli --version
check_service redis
check_port 6379 "Redis"
if command -v redis-cli &> /dev/null; then
    echo "  Redis Status:"
    redis-cli ping 2>/dev/null | sed 's/^/    /' || echo "    Cannot connect to Redis"
fi
echo ""

echo "=== Message Queue - Kafka ==="
check_command java --version
check_service zookeeper
check_service kafka
check_port 2181 "Zookeeper"
check_port 9092 "Kafka"
if [ -d "/kafka" ] || [ -d "/opt/kafka" ] || [ -d "/usr/local/kafka" ]; then
    echo -e "${GREEN}✓${NC} Kafka directory found"
else
    echo -e "${RED}✗${NC} Kafka directory not found"
fi
echo ""

echo "=== Monitoring - Prometheus ==="
check_command prometheus --version
check_service prometheus
check_port 9090 "Prometheus"
echo ""

echo "=== Monitoring - Grafana ==="
check_service grafana-server
check_port 3000 "Grafana"
echo ""

echo "=== Monitoring - Alertmanager ==="
check_service alertmanager
check_port 9093 "Alertmanager"
echo ""

echo "=== Node Exporter ==="
check_service node_exporter
check_port 9100 "Node Exporter"
echo ""

echo "=== Build Tools ==="
check_command gcc --version
check_command g++ --version
check_command make --version
check_command cmake --version
echo ""

echo "=== Network Tools ==="
check_command curl --version
check_command wget --version
check_command git --version
echo ""

echo "=== AI Engine Specific ==="
if [ -d "/aiengine" ]; then
    echo -e "${GREEN}✓${NC} /aiengine directory exists"
    echo "  Size: $(du -sh /aiengine 2>/dev/null | awk '{print $1}')"
    if [ -d "/aiengine/src/aiengine/venv" ]; then
        echo -e "${GREEN}✓${NC} Python virtual environment exists"
    else
        echo -e "${RED}✗${NC} Python virtual environment not found"
    fi
else
    echo -e "${RED}✗${NC} /aiengine directory not found"
fi

check_service ai-engine
check_port 8000 "AI Engine API"
echo ""

echo "=== Python Packages (if venv exists) ==="
if [ -d "/aiengine/src/aiengine/venv" ]; then
    source /aiengine/src/aiengine/venv/bin/activate 2>/dev/null
    echo "Checking key packages:"
    for pkg in torch transformers flask pandas numpy sklearn redis psycopg2; do
        if python3 -c "import $pkg" 2>/dev/null; then
            version=$(python3 -c "import $pkg; print($pkg.__version__)" 2>/dev/null)
            echo -e "${GREEN}✓${NC} $pkg: $version"
        else
            echo -e "${RED}✗${NC} $pkg not installed"
        fi
    done
    deactivate 2>/dev/null
else
    echo -e "${YELLOW}⚠${NC} Virtual environment not found - skipping package check"
fi
echo ""

echo "=== Port Usage Summary ==="
echo "Checking all AI Engine related ports:"
netstat -tuln 2>/dev/null | grep -E ":(8000|5432|6379|9092|2181|9090|3000|9093|9100|32287) " || \
ss -tuln 2>/dev/null | grep -E ":(8000|5432|6379|9092|2181|9090|3000|9093|9100|32287) " || \
echo "No netstat/ss available"
echo ""

echo "=========================================="
echo "System Check Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "--------"
MISSING=""

command -v python3 &> /dev/null || MISSING="${MISSING}- Python 3\n"
command -v psql &> /dev/null || MISSING="${MISSING}- PostgreSQL\n"
command -v redis-server &> /dev/null || MISSING="${MISSING}- Redis\n"
command -v java &> /dev/null || MISSING="${MISSING}- Java (for Kafka)\n"
systemctl is-active --quiet prometheus 2>/dev/null || MISSING="${MISSING}- Prometheus\n"

if [ -z "$MISSING" ]; then
    echo -e "${GREEN}All major components appear to be installed!${NC}"
else
    echo -e "${YELLOW}Missing components:${NC}"
    echo -e "$MISSING"
fi

echo ""
echo "Next steps:"
echo "1. Review the output above"
echo "2. Install missing components"
echo "3. Run the AI Engine deployment script"

#!/bin/bash
# System Check Script for AI Engine Prerequisites
# Run this on your Linux server: 10.67.156.182

echo "=========================================="
echo "AI Engine System Prerequisites Check"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
        $1 --version 2>&1 | head -n 1
        return 0
    else
        echo -e "${RED}✗${NC} $1 is NOT installed"
        return 1
    fi
}

check_service() {
    if systemctl is-active --quiet $1 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $1 service is running"
        return 0
    elif systemctl status $1 &>/dev/null; then
        echo -e "${YELLOW}⚠${NC} $1 service exists but not running"
        return 1
    else
        echo -e "${RED}✗${NC} $1 service not found"
        return 1
    fi
}

check_port() {
    if netstat -tuln 2>/dev/null | grep -q ":$2 " || ss -tuln 2>/dev/null | grep -q ":$2 "; then
        echo -e "${GREEN}✓${NC} Port $2 ($1) is in use"
        return 0
    else
        echo -e "${RED}✗${NC} Port $2 ($1) is not in use"
        return 1
    fi
}

echo "=== Operating System ==="
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo ""

echo "=== Python ==="
check_command python3
check_command python3.10
check_command python3.11
check_command python3.12
check_command pip3
echo ""

echo "=== Databases ==="
check_command psql
if command -v psql &> /dev/null; then
    echo "  PostgreSQL version: $(psql --version)"
    check_service postgresql
fi
echo ""

check_command redis-cli
if command -v redis-cli &> /dev/null; then
    check_service redis
    check_service redis-server
fi
echo ""

echo "=== Message Queue ==="
check_command java
if [ -d "/opt/kafka" ] || [ -d "/usr/local/kafka" ] || [ -d "$HOME/kafka" ]; then
    echo -e "${GREEN}✓${NC} Kafka directory found"
    ls -ld /opt/kafka /usr/local/kafka $HOME/kafka 2>/dev/null | head -1
else
    echo -e "${RED}✗${NC} Kafka directory not found"
fi
check_service kafka
check_service zookeeper
echo ""

echo "=== Monitoring ==="
check_command prometheus
check_service prometheus
check_port "Prometheus" 9090

check_command grafana-server
check_service grafana-server
check_port "Grafana" 3000
echo ""

echo "=== Network Ports ==="
check_port "AI Engine" 8000
check_port "PostgreSQL" 5432
check_port "Redis" 6379
check_port "Kafka" 9092
check_port "Zookeeper" 2181
echo ""

echo "=== System Resources ==="
echo "CPU Cores: $(nproc)"
echo "Total Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "Available Memory: $(free -h | awk '/^Mem:/ {print $7}')"
echo "Disk Space:"
df -h / | tail -1
echo ""

echo "=== Python Packages (if virtual env exists) ==="
if [ -f "$HOME/venv/bin/pip" ]; then
    echo "Virtual environment found at $HOME/venv"
    $HOME/venv/bin/pip list | grep -E "(torch|flask|transformers|pandas|numpy)" 2>/dev/null || echo "No key packages found"
elif [ -f "/aiengine/src/aiengine/venv/bin/pip" ]; then
    echo "Virtual environment found at /aiengine/src/aiengine/venv"
    /aiengine/src/aiengine/venv/bin/pip list | grep -E "(torch|flask|transformers|pandas|numpy)" 2>/dev/null || echo "No key packages found"
else
    echo "No virtual environment found"
    echo "Checking system Python packages:"
    pip3 list 2>/dev/null | grep -E "(torch|flask|transformers|pandas|numpy)" || echo "No key packages found in system Python"
fi
echo ""

echo "=== Network Configuration ==="
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo ""

echo "=========================================="
echo "Check Complete!"
echo "=========================================="

#!/bin/bash
# Install Missing Components for AI Engine
# Run this on your Linux server after checking what's missing

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AI Engine - Install Missing Components${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    echo -e "${GREEN}Detected OS: $PRETTY_NAME${NC}"
else
    echo -e "${RED}Cannot detect OS${NC}"
    exit 1
fi

# Function to install packages based on OS
install_package() {
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        sudo apt-get install -y $@
    elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "fedora" ]; then
        sudo yum install -y $@
    else
        echo -e "${RED}Unsupported OS: $OS${NC}"
        return 1
    fi
}

# Update package manager
echo -e "\n${YELLOW}Updating package manager...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    sudo apt-get update
elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "fedora" ]; then
    sudo yum update -y
fi

# Install Python 3.10+ if not present
echo -e "\n${YELLOW}Checking Python installation...${NC}"
if ! command -v python3.10 &> /dev/null && ! command -v python3.11 &> /dev/null && ! command -v python3.12 &> /dev/null; then
    echo -e "${YELLOW}Installing Python 3.10+...${NC}"
    if [ "$OS" = "ubuntu" ]; then
        sudo add-apt-repository ppa:deadsnakes/ppa -y
        sudo apt-get update
        install_package python3.11 python3.11-venv python3.11-dev python3-pip
    elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ]; then
        install_package python3.11 python3.11-devel python3-pip
    fi
else
    echo -e "${GREEN}✓ Python 3.10+ already installed${NC}"
fi

# Install build essentials
echo -e "\n${YELLOW}Installing build tools...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    install_package build-essential gcc g++ make cmake
elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "fedora" ]; then
    sudo yum groupinstall -y "Development Tools"
fi

# Install system libraries
echo -e "\n${YELLOW}Installing system libraries...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    install_package libssl-dev libffi-dev libxml2-dev libxslt1-dev zlib1g-dev \
        libjpeg-dev libpng-dev libmagic1 git curl wget
elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "fedora" ]; then
    install_package openssl-devel libffi-devel libxml2-devel libxslt-devel \
        zlib-devel libjpeg-devel libpng-devel file-libs git curl wget
fi

# Install PostgreSQL if not present
echo -e "\n${YELLOW}Checking PostgreSQL...${NC}"
if ! command -v psql &> /dev/null; then
    echo -e "${YELLOW}Installing PostgreSQL...${NC}"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        install_package postgresql postgresql-contrib
    elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "fedora" ]; then
        install_package postgresql-server postgresql-contrib
        sudo postgresql-setup --initdb
    fi
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    echo -e "${GREEN}✓ PostgreSQL installed${NC}"
else
    echo -e "${GREEN}✓ PostgreSQL already installed${NC}"
fi

# Install Redis if not present
echo -e "\n${YELLOW}Checking Redis...${NC}"
if ! command -v redis-cli &> /dev/null; then
    echo -e "${YELLOW}Installing Redis...${NC}"
    install_package redis
    sudo systemctl start redis
    sudo systemctl enable redis
    echo -e "${GREEN}✓ Redis installed${NC}"
else
    echo -e "${GREEN}✓ Redis already installed${NC}"
fi

# Install Java if not present (needed for Kafka)
echo -e "\n${YELLOW}Checking Java...${NC}"
if ! command -v java &> /dev/null; then
    echo -e "${YELLOW}Installing Java...${NC}"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        install_package openjdk-11-jdk openjdk-11-jre
    elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "fedora" ]; then
        install_package java-11-openjdk java-11-openjdk-devel
    fi
    echo -e "${GREEN}✓ Java installed${NC}"
else
    echo -e "${GREEN}✓ Java already installed${NC}"
fi

# Install Kafka if not present
echo -e "\n${YELLOW}Checking Kafka...${NC}"
if [ ! -d "/opt/kafka" ] && [ ! -d "/usr/local/kafka" ]; then
    echo -e "${YELLOW}Do you want to install Kafka? (Y/N):${NC} "
    read -r response
    if [ "$response" = "Y" ] || [ "$response" = "y" ]; then
        echo -e "${YELLOW}Installing Kafka...${NC}"
        cd /tmp
        wget https://downloads.apache.org/kafka/3.6.0/kafka_2.13-3.6.0.tgz
        tar -xzf kafka_2.13-3.6.0.tgz
        sudo mkdir -p /opt/kafka
        sudo mv kafka_2.13-3.6.0/* /opt/kafka/
        sudo useradd -r -s /bin/false kafka || true
        sudo chown -R kafka:kafka /opt/kafka
        sudo mkdir -p /var/lib/zookeeper /var/lib/kafka
        sudo chown -R kafka:kafka /var/lib/zookeeper /var/lib/kafka
        echo -e "${GREEN}✓ Kafka installed at /opt/kafka${NC}"
    fi
else
    echo -e "${GREEN}✓ Kafka already installed${NC}"
fi

# Install Prometheus if not present
echo -e "\n${YELLOW}Checking Prometheus...${NC}"
if ! command -v prometheus &> /dev/null; then
    echo -e "${YELLOW}Do you want to install Prometheus? (Y/N):${NC} "
    read -r response
    if [ "$response" = "Y" ] || [ "$response" = "y" ]; then
        echo -e "${YELLOW}Installing Prometheus...${NC}"
        cd /tmp
        wget https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz
        tar -xzf prometheus-2.48.0.linux-amd64.tar.gz
        sudo useradd -r -s /bin/false prometheus || true
        sudo mkdir -p /opt/prometheus /etc/prometheus /var/lib/prometheus
        sudo cp prometheus-2.48.0.linux-amd64/prometheus /usr/local/bin/
        sudo cp prometheus-2.48.0.linux-amd64/promtool /usr/local/bin/
        sudo chown -R prometheus:prometheus /opt/prometheus /etc/prometheus /var/lib/prometheus
        echo -e "${GREEN}✓ Prometheus installed${NC}"
    fi
else
    echo -e "${GREEN}✓ Prometheus already installed${NC}"
fi

# Setup Python virtual environment
echo -e "\n${YELLOW}Setting up Python virtual environment...${NC}"
cd /aiengine/src/aiengine || { echo -e "${RED}Error: /aiengine/src/aiengine directory not found${NC}"; exit 1; }

# Find available Python
PYTHON_CMD=""
for py in python3.12 python3.11 python3.10 python3; do
    if command -v $py &> /dev/null; then
        PYTHON_CMD=$py
        break
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    echo -e "${RED}Error: No suitable Python version found${NC}"
    exit 1
fi

echo -e "${GREEN}Using: $PYTHON_CMD${NC}"
$PYTHON_CMD -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools wheel

# Install PyTorch (CPU version)
echo -e "\n${YELLOW}Installing PyTorch...${NC}"
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# Install requirements
echo -e "\n${YELLOW}Installing Python dependencies...${NC}"
if [ -f requirements.txt ]; then
    # Filter out PHP packages
    grep -v "^php" requirements.txt > /tmp/requirements_filtered.txt || true
    pip install -r /tmp/requirements_filtered.txt
    echo -e "${GREEN}✓ Python dependencies installed${NC}"
else
    echo -e "${RED}Error: requirements.txt not found${NC}"
fi

# Create database
echo -e "\n${YELLOW}Setting up database...${NC}"
sudo -u postgres psql << EOF || echo "Database might already exist"
CREATE DATABASE universal_ai_prod;
CREATE USER aiengine WITH PASSWORD 'changeme123';
GRANT ALL PRIVILEGES ON DATABASE universal_ai_prod TO aiengine;
ALTER USER aiengine CREATEDB;
EOF

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. Update .env file with your credentials"
echo -e "2. Activate virtual environment: ${BLUE}source /aiengine/src/aiengine/venv/bin/activate${NC}"
echo -e "3. Initialize database: ${BLUE}python -c 'from main import UniversalDatabase; UniversalDatabase()'${NC}"
echo -e "4. Start AI Engine: ${BLUE}python main.py${NC}"
echo ""
echo -e "${YELLOW}Default PostgreSQL password: changeme123${NC}"
echo -e "${RED}⚠ IMPORTANT: Change all default passwords in .env file!${NC}"
echo ""

#!/bin/bash
# Install Missing Components for AI Engine
# This script installs only what's not already present

set -e

echo "=========================================="
echo "AI Engine - Install Missing Components"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo -e "${RED}Cannot detect OS version${NC}"
    exit 1
fi

echo -e "${BLUE}Detected OS: $OS $VER${NC}"
echo ""

# Update package manager
echo -e "${YELLOW}Updating package manager...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt update -y
elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "rocky" ]; then
    yum update -y
else
    echo -e "${YELLOW}Unknown package manager, continuing...${NC}"
fi

# Install Python 3.12 if not present
if ! command -v python3.12 &> /dev/null; then
    echo -e "${YELLOW}Installing Python 3.12...${NC}"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt install -y software-properties-common
        add-apt-repository ppa:deadsnakes/ppa -y
        apt update
        apt install -y python3.12 python3.12-venv python3.12-dev
    else
        yum install -y python3.12 python3.12-devel
    fi
    echo -e "${GREEN}✓ Python 3.12 installed${NC}"
else
    echo -e "${GREEN}✓ Python 3.12 already installed${NC}"
fi

# Install PostgreSQL if not present
if ! command -v psql &> /dev/null; then
    echo -e "${YELLOW}Installing PostgreSQL...${NC}"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt install -y postgresql postgresql-contrib
    else
        yum install -y postgresql-server postgresql-contrib
        postgresql-setup --initdb
    fi
    systemctl start postgresql
    systemctl enable postgresql
    echo -e "${GREEN}✓ PostgreSQL installed${NC}"
else
    echo -e "${GREEN}✓ PostgreSQL already installed${NC}"
fi

# Install Redis if not present
if ! command -v redis-server &> /dev/null; then
    echo -e "${YELLOW}Installing Redis...${NC}"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt install -y redis-server
    else
        yum install -y redis
    fi
    systemctl start redis
    systemctl enable redis
    echo -e "${GREEN}✓ Redis installed${NC}"
else
    echo -e "${GREEN}✓ Redis already installed${NC}"
fi

# Install Java for Kafka if not present
if ! command -v java &> /dev/null; then
    echo -e "${YELLOW}Installing Java...${NC}"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt install -y openjdk-11-jdk
    else
        yum install -y java-11-openjdk java-11-openjdk-devel
    fi
    echo -e "${GREEN}✓ Java installed${NC}"
else
    echo -e "${GREEN}✓ Java already installed${NC}"
fi

# Install Kafka if not present
if [ ! -d "/kafka" ] && [ ! -d "/opt/kafka" ]; then
    echo -e "${YELLOW}Installing Kafka...${NC}"
    
    # Create kafka user
    if ! id kafka &>/dev/null; then
        useradd -r -s /bin/false kafka
    fi
    
    cd /tmp
    wget -q https://downloads.apache.org/kafka/3.6.0/kafka_2.13-3.6.0.tgz
    tar -xzf kafka_2.13-3.6.0.tgz
    mkdir -p /aiengine/src/aiengine
    mv kafka_2.13-3.6.0 /aiengine/src/aiengine/kafka
    chown -R kafka:kafka /aiengine/src/aiengine/kafka
    
    # Create data directories
    mkdir -p /var/lib/zookeeper /var/lib/kafka
    chown -R kafka:kafka /var/lib/zookeeper /var/lib/kafka
    
    # Configure Zookeeper
    mkdir -p /etc/kafka
    cat > /etc/kafka/zookeeper.properties << 'EOF'
dataDir=/var/lib/zookeeper
clientPort=2181
maxClientCnxns=0
admin.enableServer=false
EOF

    # Configure Kafka
    cat > /etc/kafka/server.properties << 'EOF'
broker.id=0
listeners=PLAINTEXT://0.0.0.0:9092
advertised.listeners=PLAINTEXT://$(hostname -I | awk '{print $1}'):9092
log.dirs=/var/lib/kafka
num.partitions=3
log.retention.hours=168
zookeeper.connect=localhost:2181
EOF

    echo -e "${GREEN}✓ Kafka installed${NC}"
else
    echo -e "${GREEN}✓ Kafka already installed${NC}"
fi

# Install build tools
echo -e "${YELLOW}Installing build tools...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y build-essential gcc g++ make cmake libssl-dev libffi-dev \
        libxml2-dev libxslt1-dev zlib1g-dev libjpeg-dev libpng-dev libmagic1
else
    yum groupinstall -y "Development Tools"
    yum install -y openssl-devel libffi-devel libxml2-devel libxslt-devel \
        zlib-devel libjpeg-devel libpng-devel file-libs
fi
echo -e "${GREEN}✓ Build tools installed${NC}"

# Setup AI Engine directory structure
echo -e "${YELLOW}Setting up AI Engine directories...${NC}"
mkdir -p /aiengine/{src/aiengine,data,logs,models,exports,backups,temp}

# Create aiengine user if doesn't exist
if ! id aiengine &>/dev/null; then
    useradd -r -s /bin/bash -d /aiengine aiengine
fi
chown -R aiengine:aiengine /aiengine
echo -e "${GREEN}✓ Directories created${NC}"

# Setup Python virtual environment
echo -e "${YELLOW}Setting up Python virtual environment...${NC}"
cd /aiengine/src/aiengine

if [ ! -d "venv" ]; then
    sudo -u aiengine python3.12 -m venv venv
    echo -e "${GREEN}✓ Virtual environment created${NC}"
else
    echo -e "${GREEN}✓ Virtual environment already exists${NC}"
fi

# Install Python packages
if [ -f "requirements.txt" ]; then
    echo -e "${YELLOW}Installing Python packages (this may take several minutes)...${NC}"
    sudo -u aiengine bash -c "source venv/bin/activate && pip install --upgrade pip setuptools wheel"
    sudo -u aiengine bash -c "source venv/bin/activate && pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"
    sudo -u aiengine bash -c "source venv/bin/activate && pip install -r requirements.txt || true"
    echo -e "${GREEN}✓ Python packages installed${NC}"
else
    echo -e "${YELLOW}⚠ requirements.txt not found, skipping Python packages${NC}"
fi

# Configure PostgreSQL
echo -e "${YELLOW}Configuring PostgreSQL...${NC}"
sudo -u postgres psql << 'EOF' 2>/dev/null || echo "Database might already exist"
CREATE DATABASE universal_ai_prod;
CREATE USER aiengine WITH PASSWORD 'changeme';
GRANT ALL PRIVILEGES ON DATABASE universal_ai_prod TO aiengine;
ALTER USER aiengine CREATEDB;
EOF
echo -e "${GREEN}✓ PostgreSQL configured${NC}"

# Install systemd services
echo -e "${YELLOW}Installing systemd services...${NC}"

# Copy systemd files if they exist in /tmp/aiengine-config
if [ -d "/tmp/aiengine-config/systemd/system" ]; then
    cp /tmp/aiengine-config/systemd/system/*.service /etc/systemd/system/ 2>/dev/null || true
    systemctl daemon-reload
    echo -e "${GREEN}✓ Systemd services installed${NC}"
else
    echo -e "${YELLOW}⚠ Systemd service files not found, skipping${NC}"
fi

# Create .env template
if [ ! -f "/aiengine/src/aiengine/.env" ]; then
    echo -e "${YELLOW}Creating .env template...${NC}"
    cat > /aiengine/src/aiengine/.env << 'EOF'
# Environment
ENVIRONMENT=production
DEPLOYMENT_ID=aiengine-prod-001

# PostgreSQL Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=universal_ai_prod
POSTGRES_USER=aiengine
POSTGRES_PASSWORD=changeme
DB_SSL_MODE=prefer
DB_SCHEMA=universal_ai

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

# Kafka Configuration
KAFKA_BOOTSTRAP_SERVERS=localhost:9092
KAFKA_TOPIC_INGREDIENTS=ingredient-events
KAFKA_TOPIC_PRECHECKS=precheck-results

# Azure OpenAI (for Wiki Q&A)
AZURE_OPENAI_BASE_URL=https://your-instance.openai.azure.com/
AZURE_OPENAI_API_KEY=your_api_key_here
AZURE_OPENAI_DEPLOYMENT=gpt-4
AZURE_OPENAI_API_VERSION=2024-05-01-preview

# AI Engine Settings
AI_ENGINE_HOST=0.0.0.0
AI_ENGINE_PORT=8000

# Monitoring
PROMETHEUS_HOST=10.223.162.95
PROMETHEUS_PORT=9090
METRICS_EXPORTER_PORT=32287

# Logging
LOG_LEVEL=INFO
LOG_FILE_PATH=logs/enterprise_ai_secure.log
EOF
    chown aiengine:aiengine /aiengine/src/aiengine/.env
    chmod 600 /aiengine/src/aiengine/.env
    echo -e "${GREEN}✓ .env template created${NC}"
    echo -e "${YELLOW}⚠ Please edit /aiengine/src/aiengine/.env with your actual credentials${NC}"
else
    echo -e "${GREEN}✓ .env file already exists${NC}"
fi

# Create log directory
mkdir -p /var/log/ai-engine
chown -R aiengine:aiengine /var/log/ai-engine

echo ""
echo "=========================================="
echo -e "${GREEN}Installation Complete!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Edit configuration:"
echo "   vim /aiengine/src/aiengine/.env"
echo ""
echo "2. Start services (if installed):"
echo "   systemctl start zookeeper"
echo "   systemctl start kafka"
echo "   systemctl start ai-engine"
echo ""
echo "3. Enable services on boot:"
echo "   systemctl enable zookeeper kafka ai-engine"
echo ""
echo "4. Check status:"
echo "   systemctl status ai-engine"
echo "   tail -f /var/log/ai-engine/main.log"
echo ""
echo "5. Test AI Engine:"
echo "   curl http://localhost:8000/api/health"
echo ""

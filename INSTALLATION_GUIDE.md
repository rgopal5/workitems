# AI Engine Installation Guide for Linux

This guide provides comprehensive instructions to set up and run the Intel AI Engine Precheck System on a Linux box.

## System Requirements

### Hardware Requirements
- **CPU**: 4+ cores recommended (8+ for production)
- **RAM**: Minimum 8GB (16GB+ recommended for ML models)
- **Storage**: 50GB+ free space
- **Network**: Stable internet connection for downloading dependencies

### Operating System
- **Linux Distribution**: Ubuntu 20.04/22.04, RHEL 8+, CentOS 8+, or similar
- **Kernel**: 4.15+ 
- **Architecture**: x86_64

---

## Installation Steps

### 1. System Packages & Core Dependencies

#### Ubuntu/Debian
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Python 3.12 (or 3.10+)
sudo apt install -y software-properties-common
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3.12-dev

# Install build essentials
sudo apt install -y build-essential gcc g++ make cmake

# Install system libraries
sudo apt install -y \
    libssl-dev \
    libffi-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    libjpeg-dev \
    libpng-dev \
    libmagic1 \
    git \
    curl \
    wget \
    vim \
    net-tools

# Install Java (required for Kafka/Zookeeper)
sudo apt install -y openjdk-11-jdk openjdk-11-jre

# Verify Java installation
java -version
```

#### RHEL/CentOS
```bash
# Update system
sudo yum update -y

# Install Python 3.12
sudo yum install -y python3.12 python3.12-devel

# Install build tools
sudo yum groupinstall -y "Development Tools"

# Install system libraries
sudo yum install -y \
    openssl-devel \
    libffi-devel \
    libxml2-devel \
    libxslt-devel \
    zlib-devel \
    libjpeg-devel \
    libpng-devel \
    file-libs \
    git \
    curl \
    wget

# Install Java
sudo yum install -y java-11-openjdk java-11-openjdk-devel
```

---

### 2. PostgreSQL Database (Primary Database)

```bash
# Ubuntu/Debian
sudo apt install -y postgresql postgresql-contrib postgresql-client

# RHEL/CentOS
sudo yum install -y postgresql-server postgresql-contrib

# Initialize PostgreSQL (RHEL/CentOS only)
sudo postgresql-setup --initdb

# Start and enable PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Create database and user
sudo -u postgres psql << EOF
CREATE DATABASE universal_ai_prod;
CREATE USER aiengine WITH PASSWORD 'your_secure_password_here';
GRANT ALL PRIVILEGES ON DATABASE universal_ai_prod TO aiengine;
ALTER USER aiengine CREATEDB;
\q
EOF

# Verify connection
psql -h localhost -U aiengine -d universal_ai_prod -c "SELECT version();"
```

**Configure PostgreSQL for remote access (if needed):**
```bash
# Edit postgresql.conf
sudo vim /etc/postgresql/*/main/postgresql.conf
# Change: listen_addresses = 'localhost' to listen_addresses = '*'

# Edit pg_hba.conf
sudo vim /etc/postgresql/*/main/pg_hba.conf
# Add: host    all    all    0.0.0.0/0    md5

# Restart PostgreSQL
sudo systemctl restart postgresql
```

---

### 3. Redis (Caching & Message Queue)

```bash
# Ubuntu/Debian
sudo apt install -y redis-server

# RHEL/CentOS
sudo yum install -y redis

# Configure Redis
sudo vim /etc/redis/redis.conf
# Set: bind 0.0.0.0
# Set: requirepass your_redis_password

# Start and enable Redis
sudo systemctl start redis
sudo systemctl enable redis

# Test Redis
redis-cli ping
# Should return: PONG
```

---

### 4. Apache Kafka & Zookeeper (Message Streaming)

```bash
# Create kafka user
sudo useradd -r -s /bin/false kafka

# Download Kafka
cd /tmp
wget https://downloads.apache.org/kafka/3.6.0/kafka_2.13-3.6.0.tgz
tar -xzf kafka_2.13-3.6.0.tgz
sudo mv kafka_2.13-3.6.0 /aiengine/src/aiengine/kafka

# Set ownership
sudo chown -R kafka:kafka /aiengine/src/aiengine/kafka

# Create data directories
sudo mkdir -p /var/lib/zookeeper /var/lib/kafka
sudo chown -R kafka:kafka /var/lib/zookeeper /var/lib/kafka

# Configure Zookeeper
sudo mkdir -p /etc/kafka
sudo cat > /etc/kafka/zookeeper.properties << 'EOF'
dataDir=/var/lib/zookeeper
clientPort=2181
maxClientCnxns=0
admin.enableServer=false
EOF

# Configure Kafka
sudo cat > /etc/kafka/server.properties << 'EOF'
broker.id=0
listeners=PLAINTEXT://localhost:9092
advertised.listeners=PLAINTEXT://localhost:9092
log.dirs=/var/lib/kafka
num.partitions=3
log.retention.hours=168
zookeeper.connect=localhost:2181
EOF

# Copy systemd service files from etc/systemd/system/
sudo cp etc/systemd/system/zookeeper.service /etc/systemd/system/
sudo cp etc/systemd/system/kafka.service /etc/systemd/system/

# Reload systemd and start services
sudo systemctl daemon-reload
sudo systemctl start zookeeper
sudo systemctl enable zookeeper
sudo systemctl start kafka
sudo systemctl enable kafka

# Verify Kafka
/aiengine/src/aiengine/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
```

---

### 5. Prometheus (Monitoring)

```bash
# Create prometheus user
sudo useradd -r -s /bin/false prometheus

# Download Prometheus
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz
tar -xzf prometheus-2.48.0.linux-amd64.tar.gz
sudo mkdir -p /aiengine/src/aiengine/prometheus
sudo cp -r prometheus-2.48.0.linux-amd64/* /aiengine/src/aiengine/prometheus/

# Create directories
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus /aiengine/src/aiengine/prometheus

# Create basic prometheus.yml
sudo cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'ai-engine'
    static_configs:
      - targets: ['localhost:32287']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF

# Install node_exporter (system metrics)
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xzf node_exporter-1.7.0.linux-amd64.tar.gz
sudo cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/

# Copy systemd service files
sudo cp etc/systemd/system/prometheus.service /etc/systemd/system/
sudo cp etc/systemd/system/node_exporter.service /etc/systemd/system/

# Start services
sudo systemctl daemon-reload
sudo systemctl start prometheus
sudo systemctl enable prometheus
sudo systemctl start node_exporter
sudo systemctl enable node_exporter

# Access Prometheus: http://your-server:9090
```

---

### 6. Python Virtual Environment & Dependencies

```bash
# Navigate to project directory
cd /aiengine/src/aiengine

# Create virtual environment
python3.12 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

# Install PyTorch (CPU version for standard servers)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# For GPU support (if you have NVIDIA GPU with CUDA 11.8)
# pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Install all Python dependencies
pip install -r requirements.txt

# Note: Skip PHP packages in requirements.txt - they're system packages
# Install PHP separately if needed:
# sudo apt install php8.1-cli php8.1-fpm php8.1-curl php8.1-mbstring

# Verify critical installations
python -c "import torch; print(f'PyTorch: {torch.__version__}')"
python -c "import transformers; print(f'Transformers: {transformers.__version__}')"
python -c "import flask; print(f'Flask: {flask.__version__}')"
```

---

### 7. Project Configuration

```bash
# Create .env file
cat > /aiengine/src/aiengine/.env << 'EOF'
# Environment
ENVIRONMENT=production
DEPLOYMENT_ID=aiengine-001

# PostgreSQL Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=universal_ai_prod
POSTGRES_USER=aiengine
POSTGRES_PASSWORD=your_secure_password_here
DB_SSL_MODE=prefer
DB_SCHEMA=universal_ai

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password

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
DEFAULT_HOST=0.0.0.0
DEFAULT_PORT=8000

# Monitoring
PROMETHEUS_PORT=9090
METRICS_EXPORTER_PORT=32287

# Logging
LOG_LEVEL=INFO
LOG_FORMAT=detailed
LOG_FILE_PATH=logs/enterprise_ai_secure.log

# Security
SECRET_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)

# Performance
MAX_WORKERS=4
REQUEST_TIMEOUT=300

# Storage
DB_STORAGE_PATH=/aiengine/data
JSON_STORAGE_PATH=/aiengine/data
SQLITE_DB_PATH=/aiengine/data/universal_ai.db
EOF

# Secure the .env file
chmod 600 /aiengine/src/aiengine/.env

# Create necessary directories
mkdir -p /aiengine/data
mkdir -p /aiengine/logs
mkdir -p /aiengine/models
mkdir -p /aiengine/exports
mkdir -p /aiengine/backups
mkdir -p /aiengine/temp
```

---

### 8. Initialize Database Schema

```bash
# Activate virtual environment
source /aiengine/src/aiengine/venv/bin/activate

# Run database initialization
python -c "
from main import UniversalDatabase
db = UniversalDatabase(db_type='postgresql')
print('✅ Database initialized successfully')
print(f'Database info: {db.get_database_info()}')
"
```

---

### 9. Set Up Systemd Services

```bash
# Create AI Engine systemd service
sudo cat > /etc/systemd/system/ai-engine.service << 'EOF'
[Unit]
Description=AI Engine Main Service
After=network.target postgresql.service redis.service kafka.service
Requires=postgresql.service redis.service

[Service]
Type=simple
User=aiengine
Group=aiengine
WorkingDirectory=/aiengine/src/aiengine
Environment="PATH=/aiengine/src/aiengine/venv/bin"
ExecStart=/aiengine/src/aiengine/venv/bin/python main.py
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/ai-engine/main.log
StandardError=append:/var/log/ai-engine/error.log

[Install]
WantedBy=multi-user.target
EOF

# Create user for AI Engine
sudo useradd -r -s /bin/bash -d /aiengine aiengine
sudo chown -R aiengine:aiengine /aiengine

# Create log directory
sudo mkdir -p /var/log/ai-engine
sudo chown -R aiengine:aiengine /var/log/ai-engine

# Enable and start AI Engine
sudo systemctl daemon-reload
sudo systemctl enable ai-engine
sudo systemctl start ai-engine

# Check status
sudo systemctl status ai-engine
```

---

### 10. Configure Firewall

```bash
# Using UFW (Ubuntu)
sudo ufw allow 8000/tcp   # AI Engine API
sudo ufw allow 9090/tcp   # Prometheus
sudo ufw allow 5432/tcp   # PostgreSQL (if remote access needed)
sudo ufw allow 6379/tcp   # Redis (if remote access needed)
sudo ufw allow 9092/tcp   # Kafka (if remote access needed)
sudo ufw enable

# Using firewalld (RHEL/CentOS)
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --permanent --add-port=9090/tcp
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --permanent --add-port=6379/tcp
sudo firewall-cmd --permanent --add-port=9092/tcp
sudo firewall-cmd --reload
```

---

## Verification & Testing

### 1. Check All Services
```bash
# Check service status
sudo systemctl status postgresql
sudo systemctl status redis
sudo systemctl status zookeeper
sudo systemctl status kafka
sudo systemctl status prometheus
sudo systemctl status ai-engine

# Check ports
sudo netstat -tlnp | grep -E '8000|5432|6379|9092|2181|9090'
```

### 2. Test AI Engine API
```bash
# Health check
curl http://localhost:8000/api/health

# System status
curl http://localhost:8000/api/system_status

# Test precheck
curl -X POST http://localhost:8000/api/precheck \
  -H "Content-Type: application/json" \
  -d '{
    "ingredient_id": "test-001",
    "ingredient_type": "driver",
    "vendor": "Intel",
    "version": "1.0.0"
  }'
```

### 3. Test Database Connection
```bash
source /aiengine/src/aiengine/venv/bin/activate
python << 'EOF'
from main import UniversalDatabase
db = UniversalDatabase(db_type='postgresql')
print(f"Database Type: {db.db_type}")
print(f"Database Available: {db.db_available}")
print(f"Task Count: {db.get_task_count()}")
EOF
```

### 4. Monitor Logs
```bash
# AI Engine logs
tail -f /var/log/ai-engine/main.log

# PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-*.log

# Kafka logs
sudo journalctl -u kafka -f

# System logs
sudo journalctl -u ai-engine -f
```

---

## Optional Components

### Grafana (Visualization Dashboard)
```bash
# Install Grafana
sudo apt-get install -y apt-transport-https software-properties-common
sudo wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana

# Start Grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# Access: http://your-server:3000
# Default credentials: admin/admin
```

### Alertmanager (Alert Management)
```bash
# Download Alertmanager
cd /tmp
wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz
tar -xzf alertmanager-0.26.0.linux-amd64.tar.gz
sudo mkdir -p /aiengine/src/aiengine/alertmanager
sudo cp -r alertmanager-0.26.0.linux-amd64/* /aiengine/src/aiengine/alertmanager/

# Copy and enable service
sudo cp etc/systemd/system/alertmanager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start alertmanager
sudo systemctl enable alertmanager
```

---

## Troubleshooting

### Common Issues

#### 1. PostgreSQL Connection Failed
```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Check pg_hba.conf for authentication
sudo cat /etc/postgresql/*/main/pg_hba.conf

# Test connection
psql -h localhost -U aiengine -d universal_ai_prod
```

#### 2. PyTorch Import Error
```bash
# Reinstall PyTorch
pip uninstall torch torchvision torchaudio
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
```

#### 3. Kafka Not Starting
```bash
# Check Zookeeper first
sudo systemctl status zookeeper
sudo journalctl -u zookeeper -n 50

# Check Kafka logs
sudo journalctl -u kafka -n 50

# Verify Java installation
java -version
```

#### 4. Out of Memory Errors
```bash
# Increase Java heap for Kafka
sudo vim /etc/systemd/system/kafka.service
# Add: Environment=KAFKA_HEAP_OPTS="-Xmx2G -Xms2G"

# Restart service
sudo systemctl daemon-reload
sudo systemctl restart kafka
```

#### 5. Permission Issues
```bash
# Fix ownership
sudo chown -R aiengine:aiengine /aiengine
sudo chown -R kafka:kafka /aiengine/src/aiengine/kafka
sudo chown -R prometheus:prometheus /aiengine/src/aiengine/prometheus
sudo chown -R redis:redis /etc/redis
```

---

## Performance Tuning

### PostgreSQL
```sql
-- Edit postgresql.conf
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4MB
min_wal_size = 1GB
max_wal_size = 4GB
```

### Redis
```bash
# Edit /etc/redis/redis.conf
maxmemory 2gb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
```

### Linux System
```bash
# Increase file descriptors
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf

# Increase max connections
echo "net.core.somaxconn = 1024" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## Backup & Maintenance

### Database Backup
```bash
# PostgreSQL backup
pg_dump -h localhost -U aiengine universal_ai_prod > backup_$(date +%Y%m%d).sql

# Automated backup script
cat > /usr/local/bin/backup-aiengine.sh << 'EOF'
#!/bin/bash
BACKUP_DIR=/aiengine/backups
DATE=$(date +%Y%m%d_%H%M%S)
pg_dump -h localhost -U aiengine universal_ai_prod | gzip > $BACKUP_DIR/db_$DATE.sql.gz
find $BACKUP_DIR -name "db_*.sql.gz" -mtime +7 -delete
EOF

chmod +x /usr/local/bin/backup-aiengine.sh

# Add to crontab
echo "0 2 * * * /usr/local/bin/backup-aiengine.sh" | sudo crontab -
```

### Log Rotation
```bash
sudo cat > /etc/logrotate.d/ai-engine << 'EOF'
/var/log/ai-engine/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 aiengine aiengine
}
EOF
```

---

## Security Hardening

```bash
# Disable password authentication for PostgreSQL
sudo vim /etc/postgresql/*/main/pg_hba.conf
# Change all 'md5' to 'scram-sha-256'

# Enable SSL for PostgreSQL
sudo vim /etc/postgresql/*/main/postgresql.conf
# ssl = on
# ssl_cert_file = '/etc/ssl/certs/server.crt'
# ssl_key_file = '/etc/ssl/private/server.key'

# Set strong Redis password
sudo vim /etc/redis/redis.conf
# requirepass YourVeryStrongPasswordHere

# Enable firewall
sudo ufw enable

# Regular updates
sudo apt update && sudo apt upgrade -y
```

---

## Quick Start Script

Save this as `install-aiengine.sh`:

```bash
#!/bin/bash
set -e

echo "🚀 AI Engine Installation Script"
echo "================================"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "❌ This script should not be run as root"
   exit 1
fi

# Install system packages
echo "📦 Installing system packages..."
sudo apt update
sudo apt install -y python3.12 python3.12-venv postgresql redis-server openjdk-11-jdk

# Set up directories
echo "📁 Creating directories..."
sudo mkdir -p /aiengine/{data,logs,models,exports,backups}
sudo chown -R $USER:$USER /aiengine

# Set up Python environment
echo "🐍 Setting up Python environment..."
cd /aiengine/src/aiengine
python3.12 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Configure database
echo "🗄️ Configuring PostgreSQL..."
sudo -u postgres psql << EOF
CREATE DATABASE universal_ai_prod;
CREATE USER aiengine WITH PASSWORD 'changeme';
GRANT ALL PRIVILEGES ON DATABASE universal_ai_prod TO aiengine;
EOF

# Create .env file
echo "⚙️ Creating configuration..."
cp .env.example .env
echo "✅ Please edit /aiengine/src/aiengine/.env with your credentials"

echo "✅ Installation complete!"
echo "Next steps:"
echo "1. Edit .env file with your configuration"
echo "2. Run: source /aiengine/src/aiengine/venv/bin/activate"
echo "3. Run: python main.py"
```

---

## Success!

Your AI Engine should now be running. Access the following:

- **AI Engine API**: http://your-server:8000/api/system_status
- **Prometheus**: http://your-server:9090
- **Grafana** (if installed): http://your-server:3000

For support or issues, check the logs at `/var/log/ai-engine/` and `/aiengine/logs/`.

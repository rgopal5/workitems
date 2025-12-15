# Quick Deployment Guide - AI Engine

## Server Setup

### **Server 1: Main AI Engine** (10.67.156.182)
- AI Engine application
- PostgreSQL database
- Redis cache
- Kafka message queue

### **Server 2: Monitoring** (10.223.162.95)
- Prometheus
- Grafana  
- Alertmanager

---

## Prerequisites Check

Before deploying, ensure you have:

1. **SSH access** to both servers:
   ```bash
   ssh root@10.67.156.182
   ssh root@10.223.162.95
   ```

2. **SSH key-based authentication** (recommended) or password access

3. **Windows tools** (if deploying from Windows):
   - OpenSSH client (included in Windows 10/11)
   - Or use PuTTY/WinSCP for file transfers

---

## Deployment Steps

### Step 1: Check What's Already Installed

On your **local Windows machine**, run:

```powershell
# Check main server
ssh root@10.67.156.182 "command -v python3 && command -v psql && command -v redis-server && command -v java"

# Check monitoring server  
ssh root@10.223.162.95 "command -v prometheus && command -v grafana-server"
```

Or manually check by SSHing to each server:

```bash
# On main server (10.67.156.182)
python3 --version
psql --version
redis-server --version
java --version
systemctl status postgresql
systemctl status redis
```

---

### Step 2: Transfer Files to Main Server

From your **Windows machine**:

```powershell
cd C:\repo\DCA\workitems

# Method 1: Using SCP (if OpenSSH installed)
scp -r aiengine root@10.67.156.182:/tmp/aiengine
scp deployment/install_missing.sh root@10.67.156.182:/tmp/
scp deployment/check_system.sh root@10.67.156.182:/tmp/
scp -r etc root@10.67.156.182:/tmp/aiengine-config

# Method 2: Using WinSCP (GUI tool)
# 1. Open WinSCP
# 2. Connect to 10.67.156.182
# 3. Drag and drop folders to /tmp/
```

---

### Step 3: Install Missing Components on Main Server

SSH to the main server:

```bash
ssh root@10.67.156.182
```

Then run:

```bash
# Make scripts executable
chmod +x /tmp/install_missing.sh
chmod +x /tmp/check_system.sh

# Check what's installed
/tmp/check_system.sh

# Install missing components
/tmp/install_missing.sh

# This will install:
# - Python 3.12 + packages
# - PostgreSQL (if missing)
# - Redis (if missing)
# - Kafka + Zookeeper (if missing)
# - All Python dependencies
```

---

### Step 4: Configure AI Engine

Still on the main server:

```bash
# Edit configuration file
vim /aiengine/src/aiengine/.env

# Update these critical settings:
POSTGRES_PASSWORD=your_secure_password
AZURE_OPENAI_API_KEY=your_api_key
PROMETHEUS_HOST=10.223.162.95
```

**Important settings to update:**
- `POSTGRES_PASSWORD` - Set a strong password
- `AZURE_OPENAI_*` - Add your Azure OpenAI credentials if using Wiki Q&A
- `PROMETHEUS_HOST=10.223.162.95` - Point to your monitoring server
- `REDIS_PASSWORD` - Set if you want Redis authentication

---

### Step 5: Initialize Database

```bash
cd /aiengine/src/aiengine
source venv/bin/activate

# Initialize database
python -c "
from main import UniversalDatabase
db = UniversalDatabase(db_type='postgresql')
print('Database initialized:', db.db_available)
"

# If you get errors, manually create the database:
sudo -u postgres psql << EOF
CREATE DATABASE universal_ai_prod;
CREATE USER aiengine WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE universal_ai_prod TO aiengine;
ALTER USER aiengine CREATEDB;
EOF
```

---

### Step 6: Set Up Systemd Services

```bash
# Copy service files
cp /tmp/aiengine-config/systemd/system/*.service /etc/systemd/system/

# Reload systemd
systemctl daemon-reload

# Start services
systemctl start zookeeper
systemctl start kafka
systemctl start ai-engine

# Enable on boot
systemctl enable zookeeper kafka ai-engine

# Check status
systemctl status ai-engine
```

---

### Step 7: Configure Monitoring Server

SSH to monitoring server:

```bash
ssh root@10.223.162.95
```

If Prometheus/Grafana already installed, just update config:

```bash
# Edit Prometheus config
vim /etc/prometheus/prometheus.yml
```

Add these scrape configs:

```yaml
scrape_configs:
  - job_name: 'ai-engine-api'
    static_configs:
      - targets: ['10.67.156.182:8000']
  
  - job_name: 'ai-engine-metrics'
    static_configs:
      - targets: ['10.67.156.182:32287']
  
  - job_name: 'postgresql'
    static_configs:
      - targets: ['10.67.156.182:5432']
  
  - job_name: 'redis'
    static_configs:
      - targets: ['10.67.156.182:6379']
```

Restart Prometheus:

```bash
systemctl restart prometheus
```

---

### Step 8: Verify Installation

On **main server** (10.67.156.182):

```bash
# Check services
systemctl status postgresql redis zookeeper kafka ai-engine

# Check ports
netstat -tlnp | grep -E '8000|5432|6379|9092'

# Test AI Engine
curl http://localhost:8000/api/health
curl http://localhost:8000/api/system_status

# View logs
tail -f /var/log/ai-engine/main.log
```

From **anywhere**:

```bash
# Test API from your Windows machine or monitoring server
curl http://10.67.156.182:8000/api/health
curl http://10.67.156.182:8000/api/system_status
```

On **monitoring server** (10.223.162.95):

```bash
# Check Prometheus
curl http://localhost:9090/-/healthy

# Access dashboards:
# Prometheus: http://10.223.162.95:9090
# Grafana: http://10.223.162.95:3000
```

---

## Troubleshooting

### Cannot connect via SSH

If you get "Connection refused":

1. **Check if SSH service is running on the server:**
   - You may need console/physical access
   - Or contact your network admin

2. **Firewall blocking SSH:**
   ```bash
   # On the target server (requires console access):
   systemctl status sshd
   systemctl start sshd
   firewall-cmd --add-service=ssh --permanent
   firewall-cmd --reload
   ```

3. **Wrong IP or credentials:**
   - Verify IP: `ping 10.67.156.182`
   - Try different user: `ssh intel@10.67.156.182`

### Alternative: Manual File Transfer

If SCP doesn't work, use these alternatives:

1. **Using Git:**
   ```bash
   # On Linux server
   cd /tmp
   git clone https://github.com/rgopal5/workitems.git
   cd workitems
   ```

2. **Using HTTP/FTP:**
   - Set up a simple HTTP server on Windows
   - Download from Linux

3. **Using USB/Shared Folder:**
   - If servers are VMs, use shared folders
   - Or physically copy to USB drive

---

## Quick Start (if everything is already installed)

If PostgreSQL, Redis, Kafka are already running:

```bash
# 1. Copy files
cp -r /tmp/aiengine /aiengine/src/

# 2. Setup Python
cd /aiengine/src/aiengine
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 3. Configure
cp .env.example .env
vim .env  # Update credentials

# 4. Start
python main.py
```

---

## Contact Points

**Main Server (10.67.156.182):**
- AI Engine API: http://10.67.156.182:8000
- Health Check: http://10.67.156.182:8000/api/health
- Metrics: http://10.67.156.182:32287/metrics

**Monitoring Server (10.223.162.95):**
- Prometheus: http://10.223.162.95:9090
- Grafana: http://10.223.162.95:3000
- Alertmanager: http://10.223.162.95:9093

---

## Next Steps After Deployment

1. **Add monitoring dashboards** in Grafana
2. **Configure alerts** in Alertmanager
3. **Set up ingredient directories** for monitoring
4. **Test precheck workflow** with sample ingredients
5. **Configure backup scripts**
6. **Set up log rotation**

---

## Need Help?

If you encounter issues:

1. Check the full logs: `tail -f /var/log/ai-engine/main.log`
2. Review systemd logs: `journalctl -u ai-engine -n 100`
3. Verify all services: `systemctl status postgresql redis kafka ai-engine`
4. Check network connectivity: `telnet 10.223.162.95 9090`

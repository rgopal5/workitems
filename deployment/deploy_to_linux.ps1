# PowerShell Deployment Script for AI Engine
# Deploy from Windows to Linux servers

param(
    [string]$MainServer = "10.67.156.182",
    [string]$MonitoringServer = "10.223.162.95",
    [string]$User = "root",
    [switch]$CheckOnly,
    [switch]$DeployMain,
    [switch]$DeployMonitoring,
    [switch]$DeployAll
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AI Engine Deployment Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Main Server (AI Engine): $MainServer" -ForegroundColor Yellow
Write-Host "Monitoring Server (Prometheus/Grafana): $MonitoringServer" -ForegroundColor Yellow
Write-Host ""

# Check if deployment scripts directory exists
$DeploymentDir = Join-Path $PSScriptRoot ".."
$ProjectRoot = (Get-Item $DeploymentDir).Parent.FullName

if (-not (Test-Path $DeploymentDir)) {
    Write-Host "Error: Deployment directory not found" -ForegroundColor Red
    exit 1
}

# Function to run SSH command
function Invoke-SSHCommand {
    param(
        [string]$Server,
        [string]$User,
        [string]$Command
    )
    
    Write-Host "Running on ${User}@${Server}: $Command" -ForegroundColor Gray
    ssh "${User}@${Server}" $Command
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Command failed with exit code $LASTEXITCODE" -ForegroundColor Yellow
    }
}

# Function to copy file via SCP
function Copy-FileToServer {
    param(
        [string]$Server,
        [string]$User,
        [string]$LocalPath,
        [string]$RemotePath
    )
    
    Write-Host "Copying $LocalPath to ${User}@${Server}:${RemotePath}" -ForegroundColor Gray
    scp $LocalPath "${User}@${Server}:${RemotePath}"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: File copy failed" -ForegroundColor Red
        return $false
    }
    return $true
}

# Check System
if ($CheckOnly -or $DeployAll) {
    Write-Host "`n=== Checking Main Server ($MainServer) ===" -ForegroundColor Cyan
    
    # Copy and run check script
    $checkScript = Join-Path $DeploymentDir "deployment\check_system.sh"
    if (Test-Path $checkScript) {
        Copy-FileToServer -Server $MainServer -User $User -LocalPath $checkScript -RemotePath "/tmp/check_system.sh"
        Invoke-SSHCommand -Server $MainServer -User $User -Command "chmod +x /tmp/check_system.sh && /tmp/check_system.sh"
    } else {
        Write-Host "Error: check_system.sh not found at $checkScript" -ForegroundColor Red
    }
    
    Write-Host "`n=== Checking Monitoring Server ($MonitoringServer) ===" -ForegroundColor Cyan
    Copy-FileToServer -Server $MonitoringServer -User $User -LocalPath $checkScript -RemotePath "/tmp/check_system.sh"
    Invoke-SSHCommand -Server $MonitoringServer -User $User -Command "chmod +x /tmp/check_system.sh && /tmp/check_system.sh"
}

# Deploy to Main Server
if ($DeployMain -or $DeployAll) {
    Write-Host "`n=== Deploying to Main Server ($MainServer) ===" -ForegroundColor Cyan
    
    # Create directory structure
    Write-Host "Creating directory structure..." -ForegroundColor Yellow
    Invoke-SSHCommand -Server $MainServer -User $User -Command "mkdir -p /aiengine/{src,data,logs,models,exports,backups,temp}"
    
    # Copy project files
    Write-Host "Copying project files..." -ForegroundColor Yellow
    $aiengineSource = Join-Path $ProjectRoot "aiengine"
    if (Test-Path $aiengineSource) {
        # Use rsync if available, otherwise scp
        Write-Host "Syncing aiengine directory..." -ForegroundColor Gray
        rsync -avz --exclude 'venv' --exclude '__pycache__' --exclude '*.pyc' `
            "${aiengineSource}/" "${User}@${MainServer}:/aiengine/src/"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "rsync not available, using scp..." -ForegroundColor Yellow
            scp -r $aiengineSource "${User}@${MainServer}:/aiengine/src/"
        }
    }
    
    # Copy configuration files
    Write-Host "Copying configuration files..." -ForegroundColor Yellow
    $etcDir = Join-Path $ProjectRoot "etc"
    if (Test-Path $etcDir) {
        Invoke-SSHCommand -Server $MainServer -User $User -Command "mkdir -p /tmp/aiengine-config"
        scp -r "${etcDir}/*" "${User}@${MainServer}:/tmp/aiengine-config/"
    }
    
    # Deploy installation script
    $installScript = Join-Path $DeploymentDir "deployment\install_missing.sh"
    if (Test-Path $installScript) {
        Copy-FileToServer -Server $MainServer -User $User -LocalPath $installScript -RemotePath "/tmp/install_missing.sh"
        
        Write-Host "`nReady to install missing components. Run this on the server:" -ForegroundColor Yellow
        Write-Host "  ssh ${User}@${MainServer}" -ForegroundColor White
        Write-Host "  chmod +x /tmp/install_missing.sh" -ForegroundColor White
        Write-Host "  /tmp/install_missing.sh" -ForegroundColor White
    }
    
    Write-Host "`nMain server deployment prepared!" -ForegroundColor Green
}

# Deploy to Monitoring Server
if ($DeployMonitoring -or $DeployAll) {
    Write-Host "`n=== Deploying to Monitoring Server ($MonitoringServer) ===" -ForegroundColor Cyan
    
    # Copy Prometheus configuration
    Write-Host "Preparing Prometheus configuration..." -ForegroundColor Yellow
    
    $prometheusConfig = @"
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'aiengine-prod'
    environment: 'production'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'ai-engine-main'
    static_configs:
      - targets: ['${MainServer}:8000']
        labels:
          service: 'ai-engine-api'

  - job_name: 'ai-engine-metrics'
    static_configs:
      - targets: ['${MainServer}:32287']
        labels:
          service: 'ai-engine-metrics'

  - job_name: 'node-exporter-main'
    static_configs:
      - targets: ['${MainServer}:9100']
        labels:
          instance: 'main-server'

  - job_name: 'node-exporter-monitoring'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          instance: 'monitoring-server'

  - job_name: 'postgresql'
    static_configs:
      - targets: ['${MainServer}:5432']
        labels:
          service: 'postgresql'

  - job_name: 'redis'
    static_configs:
      - targets: ['${MainServer}:6379']
        labels:
          service: 'redis'

  - job_name: 'kafka'
    static_configs:
      - targets: ['${MainServer}:9092']
        labels:
          service: 'kafka'
"@

    $tempPrometheusConfig = Join-Path $env:TEMP "prometheus.yml"
    $prometheusConfig | Out-File -FilePath $tempPrometheusConfig -Encoding UTF8
    
    Copy-FileToServer -Server $MonitoringServer -User $User -LocalPath $tempPrometheusConfig -RemotePath "/tmp/prometheus.yml"
    Invoke-SSHCommand -Server $MonitoringServer -User $User -Command "mkdir -p /etc/prometheus && mv /tmp/prometheus.yml /etc/prometheus/prometheus.yml"
    
    Remove-Item $tempPrometheusConfig -Force
    
    Write-Host "`nMonitoring server configuration deployed!" -ForegroundColor Green
    Write-Host "Restart Prometheus: ssh ${User}@${MonitoringServer} 'systemctl restart prometheus'" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. SSH to main server: ssh ${User}@${MainServer}" -ForegroundColor White
Write-Host "2. Run installation: /tmp/install_missing.sh" -ForegroundColor White
Write-Host "3. Configure .env file: vim /aiengine/src/aiengine/.env" -ForegroundColor White
Write-Host "4. Start AI Engine: systemctl start ai-engine" -ForegroundColor White
Write-Host ""
Write-Host "Monitoring:" -ForegroundColor Yellow
Write-Host "- Prometheus: http://${MonitoringServer}:9090" -ForegroundColor White
Write-Host "- Grafana: http://${MonitoringServer}:3000" -ForegroundColor White
Write-Host "- AI Engine: http://${MainServer}:8000/api/system_status" -ForegroundColor White

# PowerShell Script to Deploy AI Engine to Linux Server
# Usage: .\deploy_to_linux.ps1

param(
    [string]$ServerIP = "10.67.156.182",
    [string]$Username = "root",  # Change to your username
    [string]$RemotePath = "/aiengine/src/aiengine"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AI Engine Deployment Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$SSHTarget = "${Username}@${ServerIP}"
$LocalPath = "C:\repo\DCA\workitems\aiengine"

Write-Host "Target Server: $ServerIP" -ForegroundColor Yellow
Write-Host "Username: $Username" -ForegroundColor Yellow
Write-Host "Remote Path: $RemotePath" -ForegroundColor Yellow
Write-Host ""

# Step 1: Check SSH connection
Write-Host "Step 1: Testing SSH connection..." -ForegroundColor Green
$sshTest = ssh -o ConnectTimeout=5 $SSHTarget "echo 'SSH OK'" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ SSH connection successful" -ForegroundColor Green
} else {
    Write-Host "✗ SSH connection failed!" -ForegroundColor Red
    Write-Host "Please ensure you can SSH to ${SSHTarget}" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 2: Run system check
Write-Host "Step 2: Checking installed software on remote server..." -ForegroundColor Green
scp check_system.sh "${SSHTarget}:/tmp/check_system.sh"
ssh $SSHTarget "chmod +x /tmp/check_system.sh && /tmp/check_system.sh"
Write-Host ""

# Step 3: Ask user if they want to continue
Write-Host "Do you want to continue with deployment? (Y/N): " -ForegroundColor Yellow -NoNewline
$response = Read-Host
if ($response -ne "Y" -and $response -ne "y") {
    Write-Host "Deployment cancelled by user." -ForegroundColor Yellow
    exit 0
}
Write-Host ""

# Step 4: Create remote directory structure
Write-Host "Step 3: Creating remote directory structure..." -ForegroundColor Green
ssh $SSHTarget "mkdir -p $RemotePath/{logs,data,models,exports,backups,temp}"
Write-Host "✓ Directories created" -ForegroundColor Green
Write-Host ""

# Step 5: Copy files to remote server
Write-Host "Step 4: Copying files to remote server..." -ForegroundColor Green
Write-Host "This may take a few minutes..." -ForegroundColor Yellow

# Copy main aiengine directory
scp -r "$LocalPath" "${SSHTarget}:$(Split-Path $RemotePath -Parent)/"

# Copy systemd service files
ssh $SSHTarget "mkdir -p /tmp/aiengine-services"
scp -r "C:\repo\DCA\workitems\etc\systemd\system\*" "${SSHTarget}:/tmp/aiengine-services/"

Write-Host "✓ Files copied successfully" -ForegroundColor Green
Write-Host ""

# Step 6: Create .env file template
Write-Host "Step 5: Creating .env configuration file..." -ForegroundColor Green
$envContent = @"
# Environment Configuration for AI Engine
# Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

# Environment
ENVIRONMENT=production
DEPLOYMENT_ID=aiengine-$(Get-Random -Minimum 1000 -Maximum 9999)

# PostgreSQL Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=universal_ai_prod
POSTGRES_USER=aiengine
POSTGRES_PASSWORD=CHANGE_ME_$(Get-Random -Minimum 100000 -Maximum 999999)
DB_SSL_MODE=prefer
DB_SCHEMA=universal_ai

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=CHANGE_ME_$(Get-Random -Minimum 100000 -Maximum 999999)

# Kafka Configuration
KAFKA_BOOTSTRAP_SERVERS=localhost:9092
KAFKA_TOPIC_INGREDIENTS=ingredient-events
KAFKA_TOPIC_PRECHECKS=precheck-results

# Azure OpenAI (for Wiki Q&A)
AZURE_OPENAI_BASE_URL=https://your-instance.openai.azure.com/
AZURE_OPENAI_API_KEY=YOUR_API_KEY_HERE
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

# Performance
MAX_WORKERS=4
REQUEST_TIMEOUT=300

# Storage
DB_STORAGE_PATH=/aiengine/data
JSON_STORAGE_PATH=/aiengine/data
SQLITE_DB_PATH=/aiengine/data/universal_ai.db
"@

$envContent | Out-File -FilePath "C:\repo\DCA\workitems\.env.template" -Encoding UTF8
scp "C:\repo\DCA\workitems\.env.template" "${SSHTarget}:${RemotePath}/.env"
Write-Host "✓ .env file created (PLEASE UPDATE WITH YOUR CREDENTIALS)" -ForegroundColor Yellow
Write-Host ""

# Step 7: Display next steps
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. SSH to your server: ssh $SSHTarget" -ForegroundColor White
Write-Host "2. Edit configuration: nano $RemotePath/.env" -ForegroundColor White
Write-Host "3. Install missing dependencies (if any shown in system check)" -ForegroundColor White
Write-Host "4. Set up Python virtual environment:" -ForegroundColor White
Write-Host "   cd $RemotePath" -ForegroundColor Gray
Write-Host "   python3 -m venv venv" -ForegroundColor Gray
Write-Host "   source venv/bin/activate" -ForegroundColor Gray
Write-Host "   pip install -r requirements.txt" -ForegroundColor Gray
Write-Host "5. Initialize database:" -ForegroundColor White
Write-Host "   python -c 'from main import UniversalDatabase; UniversalDatabase()'" -ForegroundColor Gray
Write-Host "6. Start the AI Engine:" -ForegroundColor White
Write-Host "   python main.py" -ForegroundColor Gray
Write-Host ""
Write-Host "For systemd service setup, run on Linux server:" -ForegroundColor Yellow
Write-Host "   sudo cp /tmp/aiengine-services/*.service /etc/systemd/system/" -ForegroundColor Gray
Write-Host "   sudo systemctl daemon-reload" -ForegroundColor Gray
Write-Host "   sudo systemctl enable ai-engine" -ForegroundColor Gray
Write-Host "   sudo systemctl start ai-engine" -ForegroundColor Gray
Write-Host ""

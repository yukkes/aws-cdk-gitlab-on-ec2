# PowerShell deployment script for AWS CDK GitLab on EC2
param(
    [switch]$Force = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=== AWS CDK GitLab on EC2 Deployment ===" -ForegroundColor Cyan

# Check if .env file exists
if (-not (Test-Path ".env")) {
    Write-Host "❌ Error: .env file not found!" -ForegroundColor Red
    Write-Host "Please create a .env file with the required configuration."
    Write-Host "See README.md for details."
    exit 1
}

# Check if AWS CLI is configured
try {
    aws sts get-caller-identity | Out-Null
    Write-Host "✅ AWS CLI configured" -ForegroundColor Green
} catch {
    Write-Host "❌ Error: AWS CLI is not configured or credentials are invalid." -ForegroundColor Red
    Write-Host "Please run 'aws configure' to set up your credentials."
    exit 1
}

# Load environment variables from .env file
Get-Content ".env" | ForEach-Object {
    if ($_ -match "^([^=]+)=(.*)$") {
        $name = $matches[1]
        $value = $matches[2]
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

# Validate required environment variables
$requiredVars = @("VPC_ID", "GITLAB_AMI_ID", "HOSTED_ZONE_ID", "SMTP_ADDRESS", "SMTP_PORT", "SMTP_USER_NAME", "SMTP_PASSWORD", "SMTP_DOMAIN", "EMAIL_FROM", "LETSENCRYPT_EMAIL")
foreach ($var in $requiredVars) {
    if (-not [Environment]::GetEnvironmentVariable($var)) {
        Write-Host "❌ Error: Required environment variable $var is not set in .env file." -ForegroundColor Red
        exit 1
    }
}

# Validate architecture if specified
$architecture = [Environment]::GetEnvironmentVariable("ARCHITECTURE")
if ($architecture -and $architecture -ne "x86_64" -and $architecture -ne "arm64") {
    Write-Host "❌ Error: ARCHITECTURE must be either 'x86_64' or 'arm64'." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Environment variables validated" -ForegroundColor Green

# Build the project
Write-Host "🔨 Building the project..." -ForegroundColor Yellow
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed" -ForegroundColor Red
    exit 1
}

# Check if CDK is bootstrapped
Write-Host "🚀 Checking CDK bootstrap status..." -ForegroundColor Yellow
$region = [Environment]::GetEnvironmentVariable("AWS_REGION")
if (-not $region) { $region = "ap-northeast-1" }

try {
    aws cloudformation describe-stacks --stack-name CDKToolkit --region $region | Out-Null
    Write-Host "✅ CDK already bootstrapped" -ForegroundColor Green
} catch {
    Write-Host "📦 Bootstrapping CDK..." -ForegroundColor Yellow
    npx cdk bootstrap --region $region
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ CDK bootstrap failed" -ForegroundColor Red
        exit 1
    }
}

# Display deployment info
Write-Host ""
Write-Host "=== Deployment Configuration ===" -ForegroundColor Cyan
Write-Host "Domain: $([Environment]::GetEnvironmentVariable('DOMAIN_NAME') ?? 'gitlab.example.com')"
Write-Host "Region: $region"
Write-Host "Instance Type: $([Environment]::GetEnvironmentVariable('INSTANCE_TYPE') ?? 't3.medium')"
Write-Host "Architecture: $([Environment]::GetEnvironmentVariable('ARCHITECTURE') ?? 'x86_64')"
Write-Host "Disk Size: $([Environment]::GetEnvironmentVariable('DISK_SIZE_GB') ?? '50') GB"
Write-Host "VPC ID: $([Environment]::GetEnvironmentVariable('VPC_ID'))"
Write-Host ""

# Ask for confirmation unless -Force is specified
if (-not $Force) {
    $response = Read-Host "Do you want to proceed with the deployment? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Deploy the stack
Write-Host "🚀 Deploying GitLab stack..." -ForegroundColor Yellow
npx cdk deploy --require-approval never
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Deployment failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Deployment Complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "🎉 GitLab has been deployed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📍 Next steps:" -ForegroundColor Cyan
Write-Host "1. Wait 10-15 minutes for GitLab to fully initialize (includes SSL certificate setup)"
Write-Host "2. Access GitLab at: https://$([Environment]::GetEnvironmentVariable('DOMAIN_NAME') ?? 'gitlab.example.com')"
Write-Host "3. Login with root user and password from AWS Secrets Manager:"
Write-Host "   aws secretsmanager get-secret-value --secret-id <SECRET_ARN> --query SecretString --output text | jq -r .password"
Write-Host ""
Write-Host "🔐 Initial Password Setup:" -ForegroundColor Green
Write-Host "   • Root password is automatically configured from Secrets Manager"
Write-Host "   • Password is securely removed from config files after setup"
Write-Host ""
Write-Host "⏰ Instance Schedule:" -ForegroundColor Yellow
Write-Host "   • Automatic Start: 8:00 AM JST (Monday-Friday)"
Write-Host "   • Automatic Stop:  10:00 PM JST (Monday-Friday)"
Write-Host "   • Weekend: Instance remains stopped"
Write-Host ""
Write-Host "🛠️ Manual Control:" -ForegroundColor Cyan
Write-Host "   Use .\gitlab-utils.ps1 -Action start-instance or stop-instance for manual control"
Write-Host ""
Write-Host "📊 Check the CloudFormation outputs for detailed information." -ForegroundColor Cyan

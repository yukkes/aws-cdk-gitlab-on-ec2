# PowerShell script to get GitLab root password from AWS Secrets Manager
param(
    [Parameter(Mandatory=$true)]
    [string]$SecretArn,
    
    [string]$Region = "ap-northeast-1"
)

$ErrorActionPreference = "Stop"

Write-Host "🔐 Retrieving GitLab root password from AWS Secrets Manager..." -ForegroundColor Cyan

try {
    # Get the secret value
    $secretValue = aws secretsmanager get-secret-value --secret-id $SecretArn --region $Region --query "SecretString" --output text
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to retrieve secret from AWS Secrets Manager" -ForegroundColor Red
        exit 1
    }
    
    # Parse JSON and extract password
    $secretObject = $secretValue | ConvertFrom-Json
    $password = $secretObject.password
    
    Write-Host ""
    Write-Host "✅ GitLab Root Credentials:" -ForegroundColor Green
    Write-Host "Username: root" -ForegroundColor White
    Write-Host "Password: $password" -ForegroundColor White
    Write-Host ""
    Write-Host "🌐 GitLab URL: https://gitlab.example.com" -ForegroundColor Cyan
    Write-Host "📦 Container Registry: https://gitlab.example.com:5050" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "💡 Tip: Change the root password after first login for security." -ForegroundColor Yellow
    
} catch {
    Write-Host "❌ Error retrieving password: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "💡 Make sure:" -ForegroundColor Yellow
    Write-Host "1. AWS CLI is configured with proper credentials"
    Write-Host "2. You have permission to access the secret"
    Write-Host "3. The secret ARN is correct"
    exit 1
}

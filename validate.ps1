# Validation script to check if CDK stack can be synthesized
Write-Host "🔍 Validating CDK stack configuration..." -ForegroundColor Cyan

# Set required environment variables for validation
$env:VPC_ID = "vpc-12345678"
$env:GITLAB_AMI_ID = "ami-12345678"
$env:HOSTED_ZONE_ID = "Z1234567890"
$env:DOMAIN_NAME = "gitlab.example.com"
$env:SMTP_ADDRESS = "email-smtp.us-west-2.amazonaws.com"
$env:SMTP_PORT = "587"
$env:SMTP_USER_NAME = "test-smtp-user"
$env:SMTP_PASSWORD = "test-smtp-password"
$env:SMTP_DOMAIN = "example.com"
$env:EMAIL_FROM = "noreply@example.com"
$env:EMAIL_DISPLAY_NAME = "GitLab Test"
$env:EMAIL_REPLY_TO = "noreply@example.com"
$env:LETSENCRYPT_EMAIL = "admin@example.com"

try {
    Write-Host "📦 Building project..." -ForegroundColor Yellow
    npm run build
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Build failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "🎯 Synthesizing CDK stack..." -ForegroundColor Yellow
    npx cdk synth --quiet
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ CDK stack validation successful!" -ForegroundColor Green
        Write-Host "🎉 Your GitLab CDK project is ready for deployment!" -ForegroundColor Green
        Write-Host ""
        Write-Host "📍 Next steps:" -ForegroundColor Cyan
        Write-Host "1. Update the .env file with your actual AWS resource IDs"
        Write-Host "2. Run: .\deploy.ps1 to deploy GitLab"
        Write-Host "3. Wait 10-15 minutes for GitLab to initialize"
        Write-Host "4. Access GitLab at: https://gitlab.example.com"
    } else {
        Write-Host "❌ CDK synthesis failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Validation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Pre-deployment validation script
# Checks if all prerequisites are met before deployment

param(
    [switch]$Fix = $false
)

$ErrorActionPreference = "Continue"
$validationErrors = @()
$warnings = @()

Write-Host "🔍 GitLab CDK Pre-deployment Validation" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

# Check if .env file exists
Write-Host "1. Checking .env file..." -ForegroundColor Yellow
if (-not (Test-Path ".env")) {
    $validationErrors += "❌ .env file not found"
    Write-Host "   ❌ .env file not found" -ForegroundColor Red
} else {
    Write-Host "   ✅ .env file exists" -ForegroundColor Green
    
    # Load and validate environment variables
    $envVars = @{}
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^([^=]+)=(.*)$" -and -not $_.StartsWith("#")) {
            $envVars[$matches[1]] = $matches[2]
        }
    }
      $requiredVars = @("VPC_ID", "GITLAB_AMI_ID", "HOSTED_ZONE_ID", "DOMAIN_NAME", "SMTP_ADDRESS", "SMTP_PORT", "SMTP_USER_NAME", "SMTP_PASSWORD", "SMTP_DOMAIN", "EMAIL_FROM", "LETSENCRYPT_EMAIL")
    $placeholderValues = @("vpc-xxxxxxxxx", "ami-xxxxxxxxx", "ZXXXXXXXXXXXXX", "your-smtp-username", "your-smtp-password", "example.com", "noreply@example.com", "admin@example.com")
    
    foreach ($var in $requiredVars) {
        if (-not $envVars.ContainsKey($var) -or [string]::IsNullOrWhiteSpace($envVars[$var])) {
            $validationErrors += "❌ $var is not set in .env file"
            Write-Host "   ❌ $var is not set" -ForegroundColor Red
        } elseif ($envVars[$var] -in $placeholderValues) {
            $validationErrors += "❌ $var still has placeholder value: $($envVars[$var])"
            Write-Host "   ❌ $var has placeholder value: $($envVars[$var])" -ForegroundColor Red
        } else {
            Write-Host "   ✅ $var is set" -ForegroundColor Green
        }
    }
}

# Check AWS CLI
Write-Host ""
Write-Host "2. Checking AWS CLI..." -ForegroundColor Yellow
try {
    $awsId = aws sts get-caller-identity 2>$null | ConvertFrom-Json
    Write-Host "   ✅ AWS CLI configured (Account: $($awsId.Account))" -ForegroundColor Green
} catch {
    $validationErrors += "❌ AWS CLI not configured or invalid credentials"
    Write-Host "   ❌ AWS CLI not configured or invalid credentials" -ForegroundColor Red
    Write-Host "   💡 Run: aws configure" -ForegroundColor Yellow
}

# Check Node.js and npm
Write-Host ""
Write-Host "3. Checking Node.js and npm..." -ForegroundColor Yellow
try {
    $nodeVersion = node --version 2>$null
    if ($nodeVersion) {
        Write-Host "   ✅ Node.js installed ($nodeVersion)" -ForegroundColor Green
    } else {
        $validationErrors += "❌ Node.js not found"
        Write-Host "   ❌ Node.js not installed" -ForegroundColor Red
    }
} catch {
    $validationErrors += "❌ Node.js not found"
    Write-Host "   ❌ Node.js not installed" -ForegroundColor Red
}

try {
    $npmVersion = npm --version 2>$null
    if ($npmVersion) {
        Write-Host "   ✅ npm installed ($npmVersion)" -ForegroundColor Green
    } else {
        $validationErrors += "❌ npm not found"
        Write-Host "   ❌ npm not installed" -ForegroundColor Red
    }
} catch {
    $validationErrors += "❌ npm not found"
    Write-Host "   ❌ npm not installed" -ForegroundColor Red
}

# Check if dependencies are installed
Write-Host ""
Write-Host "4. Checking project dependencies..." -ForegroundColor Yellow
if (-not (Test-Path "node_modules")) {
    $warnings += "⚠️ Dependencies not installed"
    Write-Host "   ⚠️ Dependencies not installed" -ForegroundColor Yellow
    Write-Host "   💡 Run: npm install" -ForegroundColor Yellow
} else {
    Write-Host "   ✅ Dependencies installed" -ForegroundColor Green
}

# Check if project builds
Write-Host ""
Write-Host "5. Checking TypeScript compilation..." -ForegroundColor Yellow
try {
    $buildResult = npm run build 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ TypeScript compilation successful" -ForegroundColor Green
    } else {
        $validationErrors += "❌ TypeScript compilation failed"
        Write-Host "   ❌ TypeScript compilation failed" -ForegroundColor Red
    }
} catch {
    $validationErrors += "❌ Unable to run build"
    Write-Host "   ❌ Unable to run build" -ForegroundColor Red
}

# Validate AWS resources (if AWS CLI is working and env vars are set)
if ($envVars -and $awsId) {
    Write-Host ""
    Write-Host "6. Validating AWS resources..." -ForegroundColor Yellow
    
    $region = if ($envVars["AWS_REGION"]) { $envVars["AWS_REGION"] } else { "ap-northeast-1" }
    
    # Check VPC
    if ($envVars["VPC_ID"] -and $envVars["VPC_ID"] -ne "vpc-xxxxxxxxx") {
        try {
            $vpc = aws ec2 describe-vpcs --vpc-ids $envVars["VPC_ID"] --region $region 2>$null | ConvertFrom-Json
            if ($vpc.Vpcs) {
                Write-Host "   ✅ VPC exists: $($envVars["VPC_ID"])" -ForegroundColor Green
            } else {
                $validationErrors += "❌ VPC not found: $($envVars["VPC_ID"])"
                Write-Host "   ❌ VPC not found: $($envVars["VPC_ID"])" -ForegroundColor Red
            }
        } catch {
            $warnings += "⚠️ Unable to validate VPC (permission issue?)"
            Write-Host "   ⚠️ Unable to validate VPC" -ForegroundColor Yellow
        }
    }
    
    # Check Key Pair
    if ($envVars["KEY_PAIR_NAME"] -and $envVars["KEY_PAIR_NAME"] -ne "your-key-pair") {
        try {
            $keyPair = aws ec2 describe-key-pairs --key-names $envVars["KEY_PAIR_NAME"] --region $region 2>$null | ConvertFrom-Json
            if ($keyPair.KeyPairs) {
                Write-Host "   ✅ Key Pair exists: $($envVars["KEY_PAIR_NAME"])" -ForegroundColor Green
            } else {
                $validationErrors += "❌ Key Pair not found: $($envVars["KEY_PAIR_NAME"])"
                Write-Host "   ❌ Key Pair not found: $($envVars["KEY_PAIR_NAME"])" -ForegroundColor Red
            }
        } catch {
            $warnings += "⚠️ Unable to validate Key Pair"
            Write-Host "   ⚠️ Unable to validate Key Pair" -ForegroundColor Yellow
        }
    }
    
    # Check Hosted Zone
    if ($envVars["HOSTED_ZONE_ID"] -and $envVars["HOSTED_ZONE_ID"] -ne "ZXXXXXXXXXXXXX") {
        try {
            $hostedZone = aws route53 get-hosted-zone --id $envVars["HOSTED_ZONE_ID"] 2>$null | ConvertFrom-Json
            if ($hostedZone.HostedZone) {
                Write-Host "   ✅ Hosted Zone exists: $($envVars["HOSTED_ZONE_ID"])" -ForegroundColor Green
            } else {
                $validationErrors += "❌ Hosted Zone not found: $($envVars["HOSTED_ZONE_ID"])"
                Write-Host "   ❌ Hosted Zone not found: $($envVars["HOSTED_ZONE_ID"])" -ForegroundColor Red
            }
        } catch {
            $warnings += "⚠️ Unable to validate Hosted Zone"
            Write-Host "   ⚠️ Unable to validate Hosted Zone" -ForegroundColor Yellow
        }
    }
}

# Summary
Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "📋 Validation Summary" -ForegroundColor Cyan
Write-Host ""

if ($validationErrors.Count -eq 0) {
    Write-Host "🎉 All validations passed! You're ready to deploy." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Run: .\deploy.ps1" -ForegroundColor White
    Write-Host "2. Wait 10-15 minutes for GitLab to initialize" -ForegroundColor White
    Write-Host "3. Access: https://$($envVars["DOMAIN_NAME"] ?? 'gitlab.example.com')" -ForegroundColor White
} else {
    Write-Host "❌ Validation failed. Please fix the following issues:" -ForegroundColor Red
    Write-Host ""
    foreach ($error in $validationErrors) {
        Write-Host "   $error" -ForegroundColor Red
    }
}

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠️ Warnings:" -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "   $warning" -ForegroundColor Yellow
    }
}

Write-Host ""

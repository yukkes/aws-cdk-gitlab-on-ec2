# GitLab Management Utilities
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("get-password", "get-logs", "restart-gitlab", "backup", "status", "start-instance", "stop-instance")]
    [string]$Action,
    
    [string]$InstanceId,
    [string]$SecretArn,
    [string]$Region = "ap-northeast-1"
)

$ErrorActionPreference = "Stop"

function Get-GitLabPassword {
    param([string]$SecretArn, [string]$Region)
    
    Write-Host "🔐 Retrieving GitLab root password..." -ForegroundColor Cyan
    
    try {
        $secretValue = aws secretsmanager get-secret-value --secret-id $SecretArn --region $Region --query "SecretString" --output text
        $secretObject = $secretValue | ConvertFrom-Json
        
        Write-Host "Username: root" -ForegroundColor Green
        Write-Host "Password: $($secretObject.password)" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to retrieve password: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-GitLabLogs {
    param([string]$InstanceId, [string]$Region)
    
    Write-Host "📋 Retrieving GitLab instance logs..." -ForegroundColor Cyan
    
    try {
        aws ec2 get-console-output --instance-id $InstanceId --region $Region --output text
    } catch {
        Write-Host "❌ Failed to retrieve logs: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Restart-GitLab {
    param([string]$InstanceId, [string]$Region)
    
    Write-Host "🔄 Restarting GitLab instance..." -ForegroundColor Yellow
    
    $response = Read-Host "Are you sure you want to restart the GitLab instance? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return
    }
    
    try {
        aws ec2 reboot-instances --instance-ids $InstanceId --region $Region
        Write-Host "✅ Restart initiated. GitLab will be unavailable for a few minutes." -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to restart instance: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-GitLabStatus {
    param([string]$InstanceId, [string]$Region)
    
    Write-Host "📊 Checking GitLab instance status..." -ForegroundColor Cyan
    
    try {
        $instance = aws ec2 describe-instances --instance-ids $InstanceId --region $Region --query "Reservations[0].Instances[0]" | ConvertFrom-Json
        
        Write-Host "Instance State: $($instance.State.Name)" -ForegroundColor $(if($instance.State.Name -eq "running") {"Green"} else {"Yellow"})
        Write-Host "Instance Type: $($instance.InstanceType)" -ForegroundColor White
        Write-Host "Public IP: $($instance.PublicIpAddress)" -ForegroundColor White
        Write-Host "Private IP: $($instance.PrivateIpAddress)" -ForegroundColor White
        Write-Host "Launch Time: $($instance.LaunchTime)" -ForegroundColor White
        
        # Check GitLab service status via HTTP
        try {
            $response = Invoke-WebRequest -Uri "https://gitlab.example.com/-/health" -TimeoutSec 10 -UseBasicParsing
            Write-Host "GitLab Health: ✅ Healthy (HTTP $($response.StatusCode))" -ForegroundColor Green
        } catch {
            Write-Host "GitLab Health: ❌ Not responding or unhealthy" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "❌ Failed to get instance status: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Backup-GitLab {
    param([string]$InstanceId, [string]$Region)
    
    Write-Host "💾 Creating GitLab backup..." -ForegroundColor Cyan
    
    $response = Read-Host "This will create an AMI snapshot of the GitLab instance. Continue? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "Backup cancelled." -ForegroundColor Yellow
        return
    }
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
        $amiName = "gitlab-backup-$timestamp"
        
        $result = aws ec2 create-image --instance-id $InstanceId --name $amiName --description "GitLab backup created on $timestamp" --region $Region | ConvertFrom-Json
        
        Write-Host "✅ Backup initiated. AMI ID: $($result.ImageId)" -ForegroundColor Green
        Write-Host "📝 Note: The backup process may take several minutes to complete." -ForegroundColor Yellow
    } catch {
        Write-Host "❌ Failed to create backup: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Start-GitLabInstance {
    param([string]$InstanceId, [string]$Region)
    
    Write-Host "▶️ Starting GitLab instance..." -ForegroundColor Green
    
    try {
        # Check current state
        $instance = aws ec2 describe-instances --instance-ids $InstanceId --region $Region --query "Reservations[0].Instances[0].State.Name" --output text
        
        if ($instance -eq "running") {
            Write-Host "ℹ️ Instance is already running." -ForegroundColor Yellow
            return
        }
        
        aws ec2 start-instances --instance-ids $InstanceId --region $Region
        Write-Host "✅ Instance start initiated. GitLab will be available in a few minutes." -ForegroundColor Green
        Write-Host "📝 Note: GitLab services may take additional time to fully start." -ForegroundColor Yellow
    } catch {
        Write-Host "❌ Failed to start instance: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Stop-GitLabInstance {
    param([string]$InstanceId, [string]$Region)
    
    Write-Host "⏹️ Stopping GitLab instance..." -ForegroundColor Yellow
    
    $response = Read-Host "Are you sure you want to stop the GitLab instance? This will make GitLab inaccessible. (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return
    }
    
    try {
        # Check current state
        $instance = aws ec2 describe-instances --instance-ids $InstanceId --region $Region --query "Reservations[0].Instances[0].State.Name" --output text
        
        if ($instance -eq "stopped") {
            Write-Host "ℹ️ Instance is already stopped." -ForegroundColor Yellow
            return
        }
        
        aws ec2 stop-instances --instance-ids $InstanceId --region $Region
        Write-Host "✅ Instance stop initiated. GitLab will be unavailable shortly." -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to stop instance: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main execution
switch ($Action) {
    "get-password" {
        if (-not $SecretArn) {
            Write-Host "❌ SecretArn parameter is required for get-password action" -ForegroundColor Red
            exit 1
        }
        Get-GitLabPassword -SecretArn $SecretArn -Region $Region
    }
    "get-logs" {
        if (-not $InstanceId) {
            Write-Host "❌ InstanceId parameter is required for get-logs action" -ForegroundColor Red
            exit 1
        }
        Get-GitLabLogs -InstanceId $InstanceId -Region $Region
    }
    "restart-gitlab" {
        if (-not $InstanceId) {
            Write-Host "❌ InstanceId parameter is required for restart-gitlab action" -ForegroundColor Red
            exit 1
        }
        Restart-GitLab -InstanceId $InstanceId -Region $Region
    }
    "backup" {
        if (-not $InstanceId) {
            Write-Host "❌ InstanceId parameter is required for backup action" -ForegroundColor Red
            exit 1
        }
        Backup-GitLab -InstanceId $InstanceId -Region $Region
    }
    "status" {
        if (-not $InstanceId) {
            Write-Host "❌ InstanceId parameter is required for status action" -ForegroundColor Red
            exit 1
        }
        Get-GitLabStatus -InstanceId $InstanceId -Region $Region
    }
    "start-instance" {
        if (-not $InstanceId) {
            Write-Host "❌ InstanceId parameter is required for start-instance action" -ForegroundColor Red
            exit 1
        }
        Start-GitLabInstance -InstanceId $InstanceId -Region $Region
    }
    "stop-instance" {
        if (-not $InstanceId) {
            Write-Host "❌ InstanceId parameter is required for stop-instance action" -ForegroundColor Red
            exit 1
        }
        Stop-GitLabInstance -InstanceId $InstanceId -Region $Region
    }
}

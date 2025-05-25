#!/bin/bash

# Deployment script for AWS CDK GitLab on EC2
set -e

echo "=== AWS CDK GitLab on EC2 Deployment ==="

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create a .env file with the required configuration."
    echo "See README.md for details."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "❌ Error: AWS CLI is not configured or credentials are invalid."
    echo "Please run 'aws configure' to set up your credentials."
    exit 1
fi

# Load environment variables
source .env

# Validate required environment variables
required_vars=("VPC_ID" "GITLAB_AMI_ID" "HOSTED_ZONE_ID" "SMTP_ADDRESS" "SMTP_PORT" "SMTP_USER_NAME" "SMTP_PASSWORD" "SMTP_DOMAIN" "EMAIL_FROM" "LETSENCRYPT_EMAIL")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Error: Required environment variable $var is not set in .env file."
        exit 1
    fi
done

echo "✅ Environment variables validated"

# Build the project
echo "🔨 Building the project..."
npm run build

# Check if CDK is bootstrapped
echo "🚀 Checking CDK bootstrap status..."
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region ${AWS_REGION:-ap-northeast-1} > /dev/null 2>&1; then
    echo "📦 Bootstrapping CDK..."
    npx cdk bootstrap --region ${AWS_REGION:-ap-northeast-1}
else
    echo "✅ CDK already bootstrapped"
fi

# Display deployment info
echo ""
echo "=== Deployment Configuration ==="
echo "Domain: ${DOMAIN_NAME:-gitlab.example.com}"
echo "Region: ${AWS_REGION:-ap-northeast-1}"
echo "Instance Type: ${INSTANCE_TYPE:-t3.medium}"
echo "VPC ID: ${VPC_ID}"
echo ""

# Ask for confirmation
read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Deploy the stack
echo "🚀 Deploying GitLab stack..."
npx cdk deploy --require-approval never

echo ""
echo "=== Deployment Complete! ==="
echo ""
echo "🎉 GitLab has been deployed successfully!"
echo ""
echo "📍 Next steps:"
echo "1. Wait 10-15 minutes for GitLab to fully initialize"
echo "2. Access GitLab at: https://${DOMAIN_NAME:-gitlab.example.com}"
echo "3. Get the root password from AWS Secrets Manager:"
echo "   aws secretsmanager get-secret-value --secret-id <SECRET_ARN> --query SecretString --output text | jq -r .password"
echo ""
echo "📊 Check the CloudFormation outputs for detailed information."

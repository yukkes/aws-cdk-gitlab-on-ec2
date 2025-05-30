import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as scheduler from 'aws-cdk-lib/aws-scheduler';
import { Construct } from 'constructs';

export class GitLabStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);    // Environment variables
    const vpcId = process.env.VPC_ID;
    const allowedHttpsCidr = process.env.ALLOWED_HTTPS_CIDR || '0.0.0.0/0';
    const allowedRegistryCidr = process.env.ALLOWED_REGISTRY_CIDR || '0.0.0.0/0';
    const gitlabAmiId = process.env.GITLAB_AMI_ID;
    const instanceType = process.env.INSTANCE_TYPE || 't3.medium';
    const architecture = process.env.ARCHITECTURE || 'x86_64';
    const diskSizeGb = parseInt(process.env.DISK_SIZE_GB || '50');
    const hostedZoneId = process.env.HOSTED_ZONE_ID;
    const domainName = process.env.DOMAIN_NAME || 'gitlab.example.com';

    // SMTP configuration
    const smtpAddress = process.env.SMTP_ADDRESS;
    const smtpPort = process.env.SMTP_PORT;
    const smtpUserName = process.env.SMTP_USER_NAME;
    const smtpPassword = process.env.SMTP_PASSWORD;
    const smtpDomain = process.env.SMTP_DOMAIN;
    const emailFrom = process.env.EMAIL_FROM;
    const emailDisplayName = process.env.EMAIL_DISPLAY_NAME;
    const emailReplyTo = process.env.EMAIL_REPLY_TO;
    const letsencryptEmail = process.env.LETSENCRYPT_EMAIL;

    if (!vpcId || !gitlabAmiId || !hostedZoneId || !smtpAddress || !smtpPort || !smtpUserName || !smtpPassword || !smtpDomain || !emailFrom || !letsencryptEmail) {
      throw new Error('Required environment variables are missing. Please check your .env file.');
    }

    // Validate architecture
    if (architecture !== 'x86_64' && architecture !== 'arm64') {
      throw new Error('ARCHITECTURE must be either "x86_64" or "arm64". Please check your .env file.');
    }

    // Validate disk size
    if (isNaN(diskSizeGb) || diskSizeGb < 20) {
      throw new Error('DISK_SIZE_GB must be a number and at least 20 GB. Please check your .env file.');
    }

    // Parse CIDR blocks (support comma-separated values)
    const httpsCidrBlocks = allowedHttpsCidr.split(',').map(cidr => cidr.trim());
    const registryCidrBlocks = allowedRegistryCidr.split(',').map(cidr => cidr.trim());

    // Import existing VPC
    const vpc = ec2.Vpc.fromLookup(this, 'GitLabVPC', {
      vpcId: vpcId,
    });

    // Generate a random password for GitLab root user
    const gitlabRootPassword = new secretsmanager.Secret(this, 'GitLabRootPassword', {
      description: 'GitLab root user password',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'root' }),
        generateStringKey: 'password',
        excludeCharacters: ' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
        passwordLength: 32,
      },
    });

    // Create security group for GitLab
    const gitlabSecurityGroup = new ec2.SecurityGroup(this, 'GitLabSecurityGroup', {
      vpc,
      description: 'Security group for GitLab EC2 instance',
      allowAllOutbound: true,
    });

    // Allow HTTPS (443) access from multiple CIDR blocks
    httpsCidrBlocks.forEach((cidr, index) => {
      gitlabSecurityGroup.addIngressRule(
        ec2.Peer.ipv4(cidr),
        ec2.Port.tcp(443),
        `Allow HTTPS access from ${cidr}`
      );
    });

    // Allow Container Registry (5050) access from multiple CIDR blocks
    registryCidrBlocks.forEach((cidr, index) => {
      gitlabSecurityGroup.addIngressRule(
        ec2.Peer.ipv4(cidr),
        ec2.Port.tcp(5050),
        `Allow GitLab Container Registry access from ${cidr}`
      );
    });

    // Allow HTTP (80) for Let's Encrypt challenges
    gitlabSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP access for Lets Encrypt challenges'
    );

    // Create IAM role for EC2 instance
    const gitlabRole = new iam.Role(this, 'GitLabRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Add permission to read the password from Secrets Manager
    gitlabRootPassword.grantRead(gitlabRole);

    // User data script for GitLab configuration
    const userData = ec2.UserData.forLinux();

    // Determine AWS CLI download URL based on architecture
    const awsCliUrl = architecture === 'arm64'
      ? 'https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip'
      : 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip';

    userData.addCommands(
      '#!/bin/bash',
      'set -e',
      '',
      '# Update system',
      'apt-get update -y',
      'apt-get install -y jq unzip curl',
      '',
      '# Install AWS CLI v2',
      `curl "${awsCliUrl}" -o "awscliv2.zip"`,
      'unzip -q awscliv2.zip',
      './aws/install',
      'rm -rf awscliv2.zip aws/',
      '',
      '# Get the root password from Secrets Manager before GitLab configuration',
      `SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id ${gitlabRootPassword.secretArn} --region ${this.region} --query SecretString --output text)`,
      'ROOT_PASSWORD=$(echo $SECRET_VALUE | jq -r .password)',
      '',
      '# Configure GitLab',
      '# Backup existing gitlab.rb if it exists',
      'if [ -f /etc/gitlab/gitlab.rb ]; then',
      '  mv /etc/gitlab/gitlab.rb /etc/gitlab/gitlab.rb.backup.$(date +%Y%m%d_%H%M%S)',
      'fi',
      '',
      '# Create new gitlab.rb configuration with initial root password',
      'cat > /etc/gitlab/gitlab.rb << EOF',
      '# External URLs',
      `external_url "https://${domainName}"`,
      `registry_external_url "https://${domainName}:5050"`,
      '',
      '# Basic configuration',
      'gitlab_rails[\'time_zone\'] = "Asia/Tokyo"',
      '',
      '# SMTP configuration',
      'gitlab_rails[\'smtp_enable\'] = true',
      `gitlab_rails[\'smtp_address\'] = "${smtpAddress}"`,
      `gitlab_rails[\'smtp_port\'] = ${smtpPort}`,
      `gitlab_rails[\'smtp_user_name\'] = "${smtpUserName}"`,
      `gitlab_rails[\'smtp_password\'] = "${smtpPassword}"`,
      `gitlab_rails[\'smtp_domain\'] = "${smtpDomain}"`,
      'gitlab_rails[\'smtp_authentication\'] = "login"',
      'gitlab_rails[\'smtp_enable_starttls_auto\'] = true',
      `gitlab_rails[\'gitlab_email_from\'] = "${emailFrom}"`,
      `gitlab_rails[\'gitlab_email_display_name\'] = "${emailDisplayName || 'GitLab'}"`,
      `gitlab_rails[\'gitlab_email_reply_to\'] = "${emailReplyTo || emailFrom}"`,
      '',
      '# Lets Encrypt configuration',
      'letsencrypt[\'enable\'] = true',
      `letsencrypt[\'contact_emails\'] = ["${letsencryptEmail}"]`,
      'letsencrypt[\'auto_renew\'] = true',
      '',
      '# Disable SSH',
      'gitlab_sshd[\'enable\'] = false',
      '',
      '# Container Registry configuration',
      'registry[\'enable\'] = true',
      'EOF',
      '',
      '# Reconfigure GitLab with initial password',
      'echo "Starting GitLab reconfiguration with initial password..."',
      'gitlab-ctl reconfigure',
      '',
      '# Reset root password using gitlab-rake with heredoc',
      'echo "Resetting root password using gitlab-rake..."',
      'gitlab-rake "gitlab:password:reset[root]" << EOF',
      '$ROOT_PASSWORD',
      '$ROOT_PASSWORD',
      'EOF',
      '',
      '# Wait for GitLab to be fully ready and accessible',
      'echo "Waiting for GitLab to be ready..."',
      'if curl -f --retry 10 --retry-delay 30 --retry-connrefused --retry-all-errors http://localhost/-/health > /dev/null 2>&1; then',
      '  echo "GitLab is ready!"',
      'else',
      '  echo "⚠️ GitLab may still be starting up after maximum retries"',
      'fi',
    );

    // Create Elastic IP
    const elasticIp = new ec2.CfnEIP(this, 'GitLabElasticIP', {
      domain: 'vpc',
      tags: [
        {
          key: 'Name',
          value: 'GitLab-EIP',
        },
      ],
    });

    // Create EC2 instance
    const gitlabInstance = new ec2.Instance(this, 'GitLabInstance', {
      vpc,
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: ec2.MachineImage.genericLinux({
        [this.region]: gitlabAmiId,
      }),
      securityGroup: gitlabSecurityGroup,
      role: gitlabRole,
      userData,
      blockDevices: [
        {
          deviceName: '/dev/sda1',
          volume: ec2.BlockDeviceVolume.ebs(diskSizeGb, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
          }),
        },
      ],
    });

    // Associate Elastic IP with the instance
    new ec2.CfnEIPAssociation(this, 'GitLabEIPAssociation', {
      allocationId: elasticIp.attrAllocationId,
      instanceId: gitlabInstance.instanceId,
    });

    // Import existing hosted zone
    const hostedZone = route53.HostedZone.fromHostedZoneAttributes(this, 'GitLabHostedZone', {
      hostedZoneId: hostedZoneId,
      zoneName: domainName.split('.').slice(1).join('.'), // Extract zone name from domain
    });

    // Create Route53 A record
    new route53.ARecord(this, 'GitLabARecord', {
      zone: hostedZone,
      recordName: domainName.split('.')[0], // Extract subdomain from domain
      target: route53.RecordTarget.fromIpAddresses(elasticIp.ref),
      ttl: cdk.Duration.minutes(5),
    });

    // Output important information
    new cdk.CfnOutput(this, 'GitLabURL', {
      value: `https://${domainName}`,
      description: 'GitLab URL',
    });

    new cdk.CfnOutput(this, 'GitLabRegistryURL', {
      value: `https://${domainName}:5050`,
      description: 'GitLab Container Registry URL',
    });

    new cdk.CfnOutput(this, 'ElasticIP', {
      value: elasticIp.ref,
      description: 'Elastic IP address',
    });

    new cdk.CfnOutput(this, 'RootPasswordSecretArn', {
      value: gitlabRootPassword.secretArn,
      description: 'ARN of the secret containing GitLab root password',
    });

    new cdk.CfnOutput(this, 'InstanceId', {
      value: gitlabInstance.instanceId,
      description: 'GitLab EC2 Instance ID',
    });

    // Create IAM role for EventBridge Scheduler to manage EC2 instances
    const schedulerRole = new iam.Role(this, 'SchedulerEC2Role', { // Renamed and updated principal
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
      inlinePolicies: {
        EC2StartStopPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ec2:StartInstances',
                'ec2:StopInstances'
              ],
              resources: [`arn:aws:ec2:${this.region}:${this.account}:instance/${gitlabInstance.instanceId}`]
            })
          ]
        })
      }
    });

    // EventBridge Scheduler rule to start instance at 8:00 AM JST (Monday to Friday)
    new scheduler.CfnSchedule(this, 'GitLabStartSchedule', {
      name: 'GitLabStartInstanceSchedule',
      description: 'Start GitLab instance at 8:00 AM JST on weekdays (23:00 UTC previous day, SUN-THU)',
      scheduleExpression: 'cron(0 23 ? * SUN-THU *)',
      scheduleExpressionTimezone: 'UTC', // Explicitly UTC as cron is set for UTC
      flexibleTimeWindow: { mode: 'OFF' },
      state: 'ENABLED',
      target: {
        arn: 'arn:aws:scheduler:::aws-sdk:ec2:startInstances',
        roleArn: schedulerRole.roleArn,
        input: JSON.stringify({ InstanceIds: [gitlabInstance.instanceId] }),
        retryPolicy: {
          maximumEventAgeInSeconds: 300, // Optional: 5 minutes
          maximumRetryAttempts: 3,      // Optional: 3 retries
        },
      },
    });

    // EventBridge Scheduler rule to stop instance at 10:00 PM JST (Monday to Friday)
    new scheduler.CfnSchedule(this, 'GitLabStopSchedule', {
      name: 'GitLabStopInstanceSchedule',
      description: 'Stop GitLab instance at 10:00 PM JST on weekdays (13:00 UTC, MON-FRI)',
      scheduleExpression: 'cron(0 13 ? * MON-FRI *)',
      scheduleExpressionTimezone: 'UTC', // Explicitly UTC as cron is set for UTC
      flexibleTimeWindow: { mode: 'OFF' },
      state: 'ENABLED',
      target: {
        arn: 'arn:aws:scheduler:::aws-sdk:ec2:stopInstances',
        roleArn: schedulerRole.roleArn,
        input: JSON.stringify({ InstanceIds: [gitlabInstance.instanceId] }),
        retryPolicy: {
          maximumEventAgeInSeconds: 300, // Optional: 5 minutes
          maximumRetryAttempts: 3,      // Optional: 3 retries
        },
      },
    });

    // Output schedule information
    new cdk.CfnOutput(this, 'InstanceSchedule', {
      value: 'Instance will automatically start at 8:00 AM and stop at 10:00 PM JST (Monday-Friday)',
      description: 'EC2 Instance Schedule Information',
    });
  }
}

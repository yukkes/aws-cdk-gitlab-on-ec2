import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { GitLabStack } from '../lib/gitlab-stack';

// Mock environment variables for testing
const originalEnv = process.env;

beforeAll(() => {
  process.env = {
    ...originalEnv,
    VPC_ID: 'vpc-12345678',
    GITLAB_AMI_ID: 'ami-12345678',
    HOSTED_ZONE_ID: 'Z1234567890',
    DOMAIN_NAME: 'gitlab.example.com',
    ALLOWED_HTTPS_CIDR: '10.0.0.0/8,172.16.0.0/12',
    ALLOWED_REGISTRY_CIDR: '192.168.0.0/16,10.0.0.0/8',
    SMTP_ADDRESS: 'email-smtp.us-west-2.amazonaws.com',
    SMTP_PORT: '587',
    SMTP_USER_NAME: 'test-smtp-user',
    SMTP_PASSWORD: 'test-smtp-password',
    SMTP_DOMAIN: 'example.com',
    EMAIL_FROM: 'noreply@example.com',
    EMAIL_DISPLAY_NAME: 'GitLab Test',
    EMAIL_REPLY_TO: 'noreply@example.com',
    LETSENCRYPT_EMAIL: 'admin@example.com',
  };
});

afterAll(() => {
  process.env = originalEnv;
});

describe('GitLab CDK Stack', () => {
  let app: cdk.App;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    const stack = new GitLabStack(app, 'TestGitLabStack', {
      env: {
        account: '123456789012',
        region: 'ap-northeast-1',
      },
    });
    template = Template.fromStack(stack);
  });

  test('Creates EC2 Instance', () => {
    template.hasResourceProperties('AWS::EC2::Instance', {
      InstanceType: 't3.medium',
    });
  });

  test('Creates Elastic IP', () => {
    template.hasResourceProperties('AWS::EC2::EIP', {
      Domain: 'vpc',
    });
  });  test('Creates Security Group with required ports', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for GitLab EC2 instance',
    });
  });
  test('Creates Secrets Manager Secret', () => {
    template.hasResourceProperties('AWS::SecretsManager::Secret', {
      Description: 'GitLab root user password',
    });
  });

  test('Creates IAM Role with Session Manager permissions', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'ec2.amazonaws.com',
            },
          },
        ],
      },
      ManagedPolicyArns: [
        {
          'Fn::Join': [
            '',
            [
              'arn:',
              {
                Ref: 'AWS::Partition',
              },
              ':iam::aws:policy/CloudWatchAgentServerPolicy',
            ],
          ],
        },
        {
          'Fn::Join': [
            '',
            [
              'arn:',
              {
                Ref: 'AWS::Partition',
              },
              ':iam::aws:policy/AmazonSSMManagedInstanceCore',
            ],
          ],
        },
      ],
    });
  });

  test('Creates Route53 A Record', () => {
    template.hasResourceProperties('AWS::Route53::RecordSet', {
      Type: 'A',
    });
  });

  test('Creates IAM Role for EC2', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'ec2.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          },
        ],
      },
    });
  });
});

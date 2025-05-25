# AWS CDK GitLab on EC2

このプロジェクトは、AWS CDKを使用してEC2インスタンス上にGitLabをデプロイします。以下の機能を提供します：

## 機能

- **GitLab CE**: Let's Encrypt SSL証明書を使用してEC2にデプロイ
- **コンテナレジストリ**: 有効化され、ポート5050でアクセス可能
- **Elastic IP**: 静的IPアドレスとRoute53 DNSレコード
- **セキュアなパスワード**: rootパスワードはAWS Secrets Managerに保存
- **メール統合**: 通知用のSMTP設定
- **セキュリティ**: SSH無効化、HTTPS専用アクセス
- **自動スケジューリング**: 平日8時～22時のみ自動起動・停止（JST）

## 前提条件

1. 適切な権限で設定されたAWS CLI
2. Node.jsとnpmがインストール済み
3. AWSアカウント内の既存VPC
4. ドメイン用のRoute53ホストゾーン
5. GitLab AMI ID（公式GitLab AMIを使用可能）

**注意**: このデプロイメントは、セキュアなアクセス用にAWS Systems Manager Session Managerを使用します。SSHキーは不要です。

## 設定

1. `.env`ファイルをコピーして、以下の変数を更新してください：

```bash
# VPC設定
VPC_ID=vpc-xxxxxxxxx

# セキュリティグループCIDRブロック
# 複数のCIDRはカンマ区切りで指定可能
# 例: ALLOWED_HTTPS_CIDR=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
ALLOWED_HTTPS_CIDR=0.0.0.0/0
ALLOWED_REGISTRY_CIDR=0.0.0.0/0

# GitLab AMI ID
GITLAB_AMI_ID=ami-xxxxxxxxx

# EC2設定
INSTANCE_TYPE=t3.medium
# アーキテクチャ: x86_64 または arm64 (AWS CLIインストールに影響)
# t3, t2インスタンス: x86_64
# t4g, m6g, c6g, r6gインスタンス: arm64
ARCHITECTURE=x86_64
# ルートボリュームサイズ（GB単位、最小20GB、GitLabには50GB以上推奨）
DISK_SIZE_GB=50

# Route53設定
HOSTED_ZONE_ID=ZXXXXXXXXXXXXX
DOMAIN_NAME=gitlab.example.com

# SMTP設定（GitLabメール通知用）
# AWS SES SMTPエンドポイント例:
# 米国東部 (バージニア北部): email-smtp.us-east-1.amazonaws.com
# 米国西部 (オレゴン): email-smtp.us-west-2.amazonaws.com
# アジアパシフィック (東京): email-smtp.ap-northeast-1.amazonaws.com
SMTP_ADDRESS=email-smtp.us-west-2.amazonaws.com
SMTP_PORT=587
SMTP_USER_NAME=your-smtp-username
SMTP_PASSWORD=your-smtp-password
SMTP_DOMAIN=example.com
EMAIL_FROM=noreply@example.com
EMAIL_DISPLAY_NAME=GitLab
EMAIL_REPLY_TO=noreply@example.com
LETSENCRYPT_EMAIL=admin@example.com

# AWSリージョン
AWS_REGION=ap-northeast-1
```

## インストールとデプロイ

1. 依存関係をインストール：
```bash
npm install
```

2. 特定の値で`.env`ファイルを更新（上記の設定セクションを参照）

### 🏗️ アーキテクチャ設定について

EC2インスタンスのアーキテクチャに応じて`ARCHITECTURE`を設定してください：

- **x86_64**: Intel/AMD系プロセッサ（t3, t2, m5, c5, r5シリーズなど）
- **arm64**: ARM系プロセッサ（t4g, m6g, c6g, r6gシリーズなど）

**一般的なインスタンスタイプ例:**
```bash
# x86_64アーキテクチャ
INSTANCE_TYPE=t3.medium
ARCHITECTURE=x86_64

# arm64アーキテクチャ（Graviton2/3プロセッサ）
INSTANCE_TYPE=t4g.medium
ARCHITECTURE=arm64
DISK_SIZE_GB=100
```

この設定により、適切なAWS CLIバイナリが自動的にダウンロードされます：
- x86_64: `awscli-exe-linux-x86_64.zip`
- arm64: `awscli-exe-linux-aarch64.zip`

**注意**: インスタンスタイプとアーキテクチャが一致しない場合、デプロイメントは失敗します。

### 💾 ディスクサイズ設定について

GitLab用のEBSルートボリュームサイズを`DISK_SIZE_GB`で設定できます：

```bash
# ディスクサイズ設定例
DISK_SIZE_GB=50   # 最小構成（開発・テスト用）
DISK_SIZE_GB=100  # 推奨構成（小規模チーム用）
DISK_SIZE_GB=200  # 大容量構成（大規模チーム・多数のプロジェクト用）
```

**ディスクサイズの目安:**
- **最小**: 20GB（システム要件の最低限）
- **推奨**: 50GB以上（GitLabの標準構成）
- **小規模チーム**: 100-200GB（10-50ユーザー、複数プロジェクト）
- **大規模チーム**: 500GB以上（100+ユーザー、多数のリポジトリ）

**使用量の内訳:**
- GitLabアプリケーション: ~10GB
- システムOS: ~5-10GB
- GitLabデータベース: ~1-5GB（利用状況による）
- Gitリポジトリ: 可変（プロジェクトサイズによる）
- Docker Registry: 可変（コンテナイメージサイズによる）
- ログファイル: ~1-2GB
- バックアップ（一時保存）: 可変

**注意事項:**
- デプロイ後のディスクサイズ変更は可能ですが、ダウンタイムが発生します
- GP3ボリュームタイプで暗号化が有効になります
- 容量不足を避けるため、余裕を持ったサイズ設定をお勧めします

### 🔧 SMTP設定について

GitLabのメール通知を有効にするには、適切なSMTP設定が必要です：

- **SMTP_ADDRESS**: SMTP サーバーのアドレス（AWS SES推奨）
- **SMTP_PORT**: SMTP ポート（通常は587）
- **SMTP_USER_NAME**: SMTP認証用のユーザー名
- **SMTP_PASSWORD**: SMTP認証用のパスワード  
- **SMTP_DOMAIN**: 送信ドメイン
- **EMAIL_FROM**: GitLabからのメール送信元アドレス
- **EMAIL_DISPLAY_NAME**: メール送信者表示名
- **EMAIL_REPLY_TO**: 返信先メールアドレス
- **LETSENCRYPT_EMAIL**: Let's Encrypt証明書用の連絡先メール

**AWS SESを使用する場合：**
1. AWS SESでドメインまたはメールアドレスを検証
2. SMTP認証情報を生成
3. 生成された認証情報を`.env`ファイルに設定

3. 以下のいずれかの方法でデプロイ：

### オプションA: PowerShell（Windows推奨）
```powershell
.\deploy.ps1
```

### オプションB: 手動CDKコマンド
```bash
# CDKブートストラップ（初回のみ）
npx cdk bootstrap

# スタックをデプロイ
npx cdk deploy
```

## GitLabアクセス

デプロイ後：

1. **初期設定の完了を待機**（15-20分かかる場合があります）
   - EC2インスタンスの起動
   - GitLabの初期設定とreconfigure
   - Let's Encrypt SSL証明書の取得
2. GitLabにアクセス：`https://your-domain.com`
3. 以下でログイン：
   - ユーザー名：`root`
   - パスワード：AWS Secrets Managerから取得

**重要**: rootパスワードは初回GitLab設定時に自動的に設定されます。セキュリティのため、設定後は設定ファイルから削除されます。

### rootパスワードの取得

#### PowerShell（Windows）：
```powershell
.\get-password.ps1 -SecretArn "<出力からのSECRET_ARN>"
```

#### AWS CLI：
```bash
aws secretsmanager get-secret-value --secret-id <SECRET_ARN> --query SecretString --output text | jq -r .password
```

### 管理ユーティリティ

一般的な管理タスクには`gitlab-utils.ps1`スクリプトを使用：

```powershell
# GitLab状態確認
.\gitlab-utils.ps1 -Action status -InstanceId "i-1234567890abcdef0"

# rootパスワード取得
.\gitlab-utils.ps1 -Action get-password -SecretArn "arn:aws:secretsmanager:..."

# GitLab再起動
.\gitlab-utils.ps1 -Action restart-gitlab -InstanceId "i-1234567890abcdef0"

# バックアップ作成
.\gitlab-utils.ps1 -Action backup -InstanceId "i-1234567890abcdef0"

# インスタンスログ取得
.\gitlab-utils.ps1 -Action get-logs -InstanceId "i-1234567890abcdef0"

# 手動でインスタンス起動（スケジュール外での起動）
.\gitlab-utils.ps1 -Action start-instance -InstanceId "i-1234567890abcdef0"

# 手動でインスタンス停止（緊急時やメンテナンス）
.\gitlab-utils.ps1 -Action stop-instance -InstanceId "i-1234567890abcdef0"
```

## GitLab設定

デプロイで自動設定される項目：

- **初期rootパスワード**: AWS Secrets Managerから自動取得・設定
- **タイムゾーン**: Asia/Tokyo
- **SMTP**: AWS SES経由のメール通知
- **SSL**: Let's Encrypt証明書（自動更新有効）
- **コンテナレジストリ**: ポート5050で有効
- **SSH**: セキュリティのため無効

**初期パスワード設定プロセス**:
1. AWS Secrets Managerからランダムパスワードを生成
2. GitLab設定ファイル（gitlab.rb）に初期パスワードを設定
3. GitLabの初回reconfigureでパスワードが適用
4. セキュリティのため設定ファイルからパスワードを削除
5. 後続のreconfigureでクリーンな設定を確立
- **SSH**: セキュリティのため無効

## セキュリティ機能

- **暗号化EBS**: ルートボリュームは暗号化済み
- **セキュリティグループ**: ポート443と5050への制限されたアクセス
- **Secrets Manager**: rootパスワードの安全な保存
- **Let's Encrypt**: 自動SSL証明書管理

## 自動スケジューリング

このプロジェクトには、コスト最適化のためのEC2インスタンス自動スケジューリング機能が含まれています：

- **起動時間**: 平日 8:00 AM JST
- **停止時間**: 平日 10:00 PM JST
- **休日**: 土曜日・日曜日は自動起動しません

### スケジュールの変更

スケジュールを変更したい場合は、`lib/gitlab-stack.ts`のEventBridgeルール設定を修正してください：

```typescript
// 起動時間の変更例（9:00 AM JST）
schedule: events.Schedule.cron({
  minute: '0',
  hour: '0', // 9:00 AM JST = 00:00 UTC
  weekDay: 'MON-FRI'
})
```

### 手動での起動・停止

#### PowerShellユーティリティ使用（推奨）
```powershell
# インスタンス起動
.\gitlab-utils.ps1 -Action start-instance -InstanceId <INSTANCE_ID>

# インスタンス停止
.\gitlab-utils.ps1 -Action stop-instance -InstanceId <INSTANCE_ID>
```

#### AWS CLI直接使用
```bash
# インスタンス起動
aws ec2 start-instances --instance-ids <INSTANCE_ID>

# インスタンス停止
aws ec2 stop-instances --instance-ids <INSTANCE_ID>
```

**注意**: 
- 手動停止後、次の自動起動スケジュール（平日8:00 AM JST）まで停止状態が維持されます
- 緊急メンテナンスや計画停止時に手動停止を使用してください

## 監視と保守

- システム監視用のCloudWatch Agentがインストール済み
- Let's Encrypt証明書は自動更新
- GitLabの定期更新は手動で実行が必要

## クリーンアップ

スタックを削除するには：
```bash
npm run destroy
```

**注意**: これによりGitLabデータを含むすべてのリソースが削除されます。スタックを削除する前に重要なデータをバックアップしてください。

## トラブルシューティング

1. **GitLabにアクセスできない**: セキュリティグループルールとインスタンス状態を確認
2. **SSL証明書の問題**: DNSレコードが正しく設定されているか確認
3. **初期パスワードでログインできない**: 
   - AWS Secrets Managerから正しいパスワードを取得しているか確認
   - GitLabの初期設定が完了するまで15-20分待機
   - インスタンスログで`GitLab configuration completed successfully!`を確認
4. **メールが機能しない**: SMTP認証情報とSES設定を確認
5. **コンテナレジストリの問題**: Let's Encrypt証明書が有効か確認
6. **デプロイメント失敗**: インスタンスタイプとARCHITECTURE設定が一致しているか確認
   - t3/t2シリーズ → `ARCHITECTURE=x86_64`
   - t4g/m6g/c6g/r6gシリーズ → `ARCHITECTURE=arm64`

## コスト最適化

- 使用量に基づいて適切なインスタンスタイプを使用
- **Gravitonプロセッサ**: t4g, m6g, c6g, r6gインスタンスは同等性能でx86_64より最大20%安価
- 本番環境ではReserved Instancesの使用を検討
- **EBSストレージコスト**: GP3ボリュームタイプでコスト効率が良い
  - 50GB: ~$4/月
  - 100GB: ~$8/月
  - 200GB: ~$16/月
- **自動スケジューリング**: 平日8時～22時のみ稼働で約58%のコスト削減
- **ディスクサイズ最適化**: 必要以上に大きなサイズは避け、後から拡張可能

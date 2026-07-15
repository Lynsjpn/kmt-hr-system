# KMT 人事管理システム（クラウド版）

登録支援機関（人材紹介・特定技能）向けの人事管理システム。
人事情報・労務書類チェックリスト（入社前〜退職後）・評価（MBO）・KPI・社内資産を一元管理します。

- **フロントエンド**: 単一の `index.html`（依存なし・GitHub Pages でホスト可能）
- **バックエンド**: Supabase（東京リージョン / プロジェクト `kmt-hr-system`）
  - PostgreSQL + Row Level Security（`allowed_users` に登録されたメールのみアクセス可）
  - Supabase Auth（メール＋パスワード）

## 使い方

1. ブラウザで `index.html`（または GitHub Pages の URL）を開く
2. 初回のみ「新規登録」でアカウント作成（メールは `allowed_users` に登録済みであること）→ 確認メールのリンクをクリック
3. ログインして利用開始

## データを Supabase 側から直接入力する

Supabase ダッシュボード → Table Editor で以下のテーブルを直接編集できます:

| テーブル | 内容 |
|---|---|
| `employees` | 従業員マスタ（在留資格・パスポート等を含む） |
| `employee_docs` | 従業員×書類のステータス |
| `doc_templates` | 書類マスタ（入社前/入社時/在職中/退職時/退職後） |
| `evaluations` | 評価シート（goals は JSON） |
| `kpis` | KPI（records は JSON） |
| `assets` | 社内資産・貸与管理 |
| `departments` | 部署マスタ |
| `allowed_users` | ログイン許可メールリスト |

## セキュリティ

- `index.html` 内のキーは **publishable key**（公開前提のキー）。データ保護は RLS が担います。
- マイナンバー（個人番号）そのものは入力しない運用としてください。
- 利用者の追加/削除はアプリの「データ管理 > 利用ユーザー」タブから行えます。

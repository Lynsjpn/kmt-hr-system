# KMT HR System - GitHub公開スクリプト
# 使い方: このフォルダで右クリック > "PowerShellで実行" するか、PowerShellで .\publish-to-github.ps1
# 初回はブラウザでGitHubログインを求められます（画面の指示に従ってください）

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# 0. GitHub CLI が無ければインストール（UACの確認が出たら「はい」を選択）
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "GitHub CLI をインストールします..." -ForegroundColor Cyan
    winget install --id GitHub.cli --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
}

# 1. GitHub CLI ログイン確認
gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "GitHubにログインします。ブラウザが開いたら指示に従ってください..." -ForegroundColor Cyan
    gh auth login --hostname github.com --git-protocol https --web
}

# 2. リポジトリ作成 & push（既にあればpushのみ）
$remote = git remote get-url origin 2>$null
if (-not $remote) {
    Write-Host "リポジトリ kmt-hr-system を作成してpushします..." -ForegroundColor Cyan
    gh repo create kmt-hr-system --public --source . --push
} else {
    git push -u origin main
}

# 3. GitHub Pages 有効化（main ブランチ / ルート）
$owner = gh api user --jq '.login'
Write-Host "GitHub Pages を有効化します..." -ForegroundColor Cyan
try {
    gh api -X POST "repos/$owner/kmt-hr-system/pages" -f "source[branch]=main" -f "source[path]=/" | Out-Null
} catch {
    Write-Host "(Pagesは既に有効化されている可能性があります)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "完了！ 数分後に以下のURLでアクセスできます:" -ForegroundColor Green
Write-Host "  https://$owner.github.io/kmt-hr-system/" -ForegroundColor Green

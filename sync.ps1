# KMT HR System - 変更をGitHubに反映するスクリプト
# 使い方: PowerShellで  .\sync.ps1        （コミットメッセージは自動）
#         .\sync.ps1 "評価タブを修正"     （メッセージを指定）

param([string]$Message)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# 変更が無ければ何もしない
$changes = git status --porcelain
if (-not $changes) {
    Write-Host "変更はありません。" -ForegroundColor DarkGray
} else {
    Write-Host "以下の変更をコミットします:" -ForegroundColor Cyan
    git status --short
    if (-not $Message) {
        $Message = "Update KMT HR system ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
    }
    git add -A
    git commit -m $Message
    if ($LASTEXITCODE -ne 0) { Write-Host "コミットに失敗しました。" -ForegroundColor Red; exit 1 }
}

$remote = git remote get-url origin 2>$null
if (-not $remote) {
    Write-Host "GitHubに接続されていません。まず .\publish-to-github.ps1 を実行してください。" -ForegroundColor Yellow
    exit 1
}

Write-Host "GitHubにpushします..." -ForegroundColor Cyan
git push origin main
if ($LASTEXITCODE -ne 0) { Write-Host "push に失敗しました。" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "完了！ 1〜2分後に公開サイトに反映されます。" -ForegroundColor Green
if ($remote -match 'github\.com[:/]([^/]+)/([^/.]+)') {
    Write-Host "  https://$($Matches[1]).github.io/$($Matches[2])/" -ForegroundColor Green
}

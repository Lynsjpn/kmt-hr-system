# KMT HR System - GitHub公開スクリプト
# 使い方: PowerShellで  .\publish-to-github.ps1
# 初回はブラウザでGitHubログインを求められます（画面の指示に従ってください）
# 2回目以降も同じスクリプトを実行すればOK（push＋Pages確認のみ）

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$RepoName = 'kmt-hr-system'

# ---- gh コマンドを探す（PATHに無い既定のインストール先も見る）----
function Resolve-Gh {
    $c = Get-Command gh -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $cands = @(
        "$env:LOCALAPPDATA\GitHubCLI\bin\gh.exe",
        "$env:ProgramFiles\GitHub CLI\gh.exe",
        "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe"
    )
    foreach ($p in $cands) { if (Test-Path $p) { return $p } }
    return $null
}

# 0. GitHub CLI が無ければインストール（UACの確認が出たら「はい」を選択）
$gh = Resolve-Gh
if (-not $gh) {
    Write-Host "GitHub CLI をインストールします（UACの確認が出たら「はい」を選んでください）..." -ForegroundColor Cyan
    winget install --id GitHub.cli --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
    $gh = Resolve-Gh
    if (-not $gh) {
        Write-Host "gh が見つかりません。PowerShellを一度閉じて開き直し、もう一度実行してください。" -ForegroundColor Red
        exit 1
    }
}
Write-Host "gh: $gh" -ForegroundColor DarkGray

# 1. GitHub CLI ログイン確認
& $gh auth status
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "GitHubにログインします。表示される8桁のコードをコピーし、開いたブラウザに貼り付けてください。" -ForegroundColor Cyan
    & $gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Write-Host "ログインできませんでした。" -ForegroundColor Red; exit 1 }
}

# gh を git の認証ヘルパーにする（以後 git push でパスワードを聞かれない）
& $gh auth setup-git

$owner = (& $gh api user --jq '.login').Trim()
Write-Host "GitHubユーザー: $owner" -ForegroundColor DarkGray

# 2. リポジトリ作成 & push（既にあればpushのみ）
$remote = git remote get-url origin 2>$null
if (-not $remote) {
    # 同名リポジトリが既にある場合はそれを origin に設定
    & $gh repo view "$owner/$RepoName" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "既存のリポジトリ $owner/$RepoName に接続します..." -ForegroundColor Cyan
        git remote add origin "https://github.com/$owner/$RepoName.git"
        git push -u origin main
    } else {
        Write-Host "リポジトリ $RepoName を作成してpushします..." -ForegroundColor Cyan
        # GitHub Pages（無料プラン）は public リポジトリが必要です
        & $gh repo create $RepoName --public --source . --push
    }
} else {
    Write-Host "push します（$remote）..." -ForegroundColor Cyan
    git push -u origin main
}
if ($LASTEXITCODE -ne 0) { Write-Host "push に失敗しました。" -ForegroundColor Red; exit 1 }

# 3. GitHub Pages 有効化（main ブランチ / ルート）
Write-Host "GitHub Pages を確認・有効化します..." -ForegroundColor Cyan
& $gh api "repos/$owner/$RepoName/pages" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    & $gh api -X POST "repos/$owner/$RepoName/pages" -f "source[branch]=main" -f "source[path]=/" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Pagesの自動有効化に失敗しました。ブラウザで手動設定してください:" -ForegroundColor Yellow
        Write-Host "  https://github.com/$owner/$RepoName/settings/pages" -ForegroundColor Yellow
        Write-Host "  （Source: Deploy from a branch / Branch: main / Folder: / (root)）" -ForegroundColor Yellow
    }
} else {
    Write-Host "(Pagesは既に有効です)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "完了！ 数分後に以下のURLでアクセスできます:" -ForegroundColor Green
Write-Host "  https://$owner.github.io/$RepoName/" -ForegroundColor Green
Write-Host ""
Write-Host "次回以降、変更をネットに反映するには:  .\sync.ps1" -ForegroundColor Cyan

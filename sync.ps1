# KMT HR System - 変更をGitHubに反映するスクリプト
# 使い方: PowerShellで  .\sync.ps1        （コミットメッセージは自動）
#         .\sync.ps1 "評価タブを修正"     （メッセージを指定）

param([string]$Message)

# 注意: $ErrorActionPreference = 'Stop' は使わない。
# Windows PowerShell 5.1 では、git が stderr に出す「ただの警告」まで
# 致命的エラー扱いになり、途中で止まってしまうため。
# 代わりに $LASTEXITCODE を毎回確認する。
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

function Invoke-Git {
    # git の警告(stderr)で止まらないように実行し、終了コードだけで成否を判断する
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    & git @GitArgs 2>&1 | ForEach-Object { Write-Host $_ }
    return $LASTEXITCODE
}

# バージョン番号を自動で上げる。
# これを忘れると、利用者の画面に「新しいバージョンがあります」が一切出ない
# （手動更新にしていた間、6回のデプロイで一度も通知が出ていなかった）。
function Bump-Version {
    $file = Join-Path $PSScriptRoot 'index.html'
    if (-not (Test-Path $file)) { return $null }
    $txt = [System.IO.File]::ReadAllText($file, [System.Text.UTF8Encoding]::new($false))
    # コミット数＋1 を使う。必ず増えるので重複しない
    $n   = [int](& git rev-list --count HEAD) + 1
    $ver = "ver.$(Get-Date -Format 'yyyyMMdd').$n"
    $new = [regex]::Replace($txt, "const APP_VER = '[^']*';", "const APP_VER = '$ver';")
    if ($new -ne $txt) {
        [System.IO.File]::WriteAllText($file, $new, [System.Text.UTF8Encoding]::new($false))
        Write-Host "バージョンを $ver に更新しました" -ForegroundColor DarkGray
        return $ver
    }
    return $null
}

# 変更が無ければコミットしない
$changes = & git status --porcelain
if (-not $changes) {
    Write-Host "変更はありません。" -ForegroundColor DarkGray
} else {
    Write-Host "以下の変更をコミットします:" -ForegroundColor Cyan
    & git status --short
    $newVer = Bump-Version
    if (-not $Message) {
        $Message = "Update KMT HR system ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
    }
    if ((Invoke-Git add -A) -ne 0) { Write-Host "git add に失敗しました。" -ForegroundColor Red; exit 1 }
    if ((Invoke-Git commit -m $Message) -ne 0) { Write-Host "コミットに失敗しました。" -ForegroundColor Red; exit 1 }
}

$remote = & git remote get-url origin 2>$null
if (-not $remote) {
    Write-Host "GitHubに接続されていません。まず .\publish-to-github.ps1 を実行してください。" -ForegroundColor Yellow
    exit 1
}

# push するものが無ければ終了
$ahead = & git rev-list --count "origin/main..main" 2>$null
if ($ahead -eq '0') {
    Write-Host "GitHubは既に最新です。" -ForegroundColor Green
    exit 0
}

Write-Host "GitHubにpushします（$ahead 件）..." -ForegroundColor Cyan
if ((Invoke-Git push origin main) -ne 0) {
    Write-Host ""
    Write-Host "push に失敗しました。GitHubへのログインが必要かもしれません:" -ForegroundColor Red
    Write-Host "  winget install --id GitHub.cli --scope user" -ForegroundColor Yellow
    Write-Host "  gh auth login --web" -ForegroundColor Yellow
    Write-Host "  gh auth setup-git" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "完了！ 1〜2分後に公開サイトに反映されます。" -ForegroundColor Green
if ($remote -match 'github\.com[:/]([^/]+)/([^/.]+)') {
    $url = "https://" + $Matches[1].ToLower() + ".github.io/" + $Matches[2] + "/"
    Write-Host "  $url" -ForegroundColor Green
}

param(
    [switch]$NoBrowser
)

$ErrorActionPreference = "Continue"
$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location $root
$cfgDir = Join-Path $env:LOCALAPPDATA "OmniApexStudio"
$cfgFile = Join-Path $cfgDir "settings.json"
$chatsFile = Join-Path $cfgDir "chats.json"
$hubFile = Join-Path $cfgDir "hub_data.json"
$agentsFile = Join-Path $cfgDir "custom_agents.json"

# Multi-Root Authorized Workspaces (omni-apex-studio + tum scratch projeleri + OtonomAsistan)
$allowedRoots = @($root)
foreach ($extra in @(
    "C:\Users\dhm16596\.gemini\antigravity\scratch",
    "C:\OtonomAsistan"
)) {
    if (Test-Path $extra -PathType Container) {
        $fullExtra = [System.IO.Path]::GetFullPath($extra)
        if ($allowedRoots -notcontains $fullExtra) { $allowedRoots += $fullExtra }
    }
}

$blockedNames = @(".env", ".env.local", ".env.production", "api_keys.env", "settings.json", "comms_profiles.json", "storage_accounts.json")

function Test-AllowedPath([string]$rawPath, [string]$baseDir = $root) {
    try {
        $p = if ([System.IO.Path]::IsPathRooted($rawPath)) { $rawPath } else { Join-Path $baseDir ($rawPath.TrimStart('/', '\') -replace '/', '\') }
        $full = [System.IO.Path]::GetFullPath($p)
        $leaf = [System.IO.Path]::GetFileName($full).ToLower()
        if ($blockedNames -contains $leaf) { return $null }
        foreach ($r in $allowedRoots) {
            if ($full.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) { return $full }
        }
    } catch {}
    return $null
}

$port = 8080
$listener = $null

foreach ($p in @(8080, 8081, 8082, 8888, 9090)) {
    try {
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://localhost:$p/")
        $l.Prefixes.Add("http://127.0.0.1:$p/")
        $l.Start()
        $listener = $l
        $port = $p
        break
    } catch {
        if ($l) { try { $l.Close() } catch {} }
    }
}

if (-not $listener) {
    Write-Host "[HATA] Uygun port bulunamadi (8080-9090)." -ForegroundColor Red
    if (-not $NoBrowser) { Read-Host "Cikmak icin Enter'a basin" }
    exit 1
}

$url = "http://localhost:$port/"
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  OMNI-NEXUS APEX STUDIO OS v5.0 BRIDGE + TELEMETRI" -ForegroundColor Green
Write-Host "  Adres: $url" -ForegroundColor Yellow
Write-Host "  Kok Dizinler: $($allowedRoots -join ' | ')" -ForegroundColor Gray
Write-Host "==================================================" -ForegroundColor Cyan

if (-not $NoBrowser) {
    Start-Process $url
}

function Send-Json($res, $obj, $code = 200) {
    $res.StatusCode = $code
    $res.ContentType = "application/json; charset=utf-8"
    $json = $obj | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Get-Telemetry {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMb = [math]::Round($os.TotalVisibleMemorySize / 1024)
        $freeMb = [math]::Round($os.FreePhysicalMemory / 1024)
        $usedMb = $totalMb - $freeMb
        $ramPct = if ($totalMb -gt 0) { [math]::Round(($usedMb / $totalMb) * 100, 1) } else { 0 }
        $drv = Get-PSDrive -Name ($root.Substring(0,1)) -ErrorAction SilentlyContinue
        $freeGb = if ($drv) { [math]::Round($drv.Free / 1GB, 1) } else { 0 }
        return @{
            os = "Windows"
            cpu_cores = [Environment]::ProcessorCount
            ram_used_mb = $usedMb
            ram_total_mb = $totalMb
            ram_pct = $ramPct
            disk_free_gb = $freeGb
            cwd = $root
            roots = $allowedRoots
            port = $port
        }
    } catch {
        return @{ os = "Windows"; cwd = $root; roots = $allowedRoots; port = $port }
    }
}

$interactiveTraps = @{
    "cmd" = "cmd /c ver && dir /b"
    "cmd.exe" = "cmd /c ver"
    "powershell" = "`$PSVersionTable.PSVersion"
    "pwsh" = "`$PSVersionTable.PSVersion"
    "python" = "python --version"
    "node" = "node --version"
    "adb shell" = "adb shell getprop ro.product.model"
}

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        $res.Headers.Add("Access-Control-Allow-Origin", "*")
        $res.Headers.Add("Access-Control-Allow-Headers", "*")
        $res.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $res.Headers.Add("Access-Control-Allow-Private-Network", "true")

        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 204
            $res.Close()
            continue
        }

        $path = $req.Url.LocalPath

        if ($path -eq "/api/ping") {
            Send-Json $res @{ ok = $true; os = "Windows"; cwd = $root; roots = $allowedRoots; port = $port }
            $res.Close()
            continue
        }

        if ($path -eq "/api/firewall-rule" -and $req.HttpMethod -eq "POST") {
            try {
                $cmd = 'netsh advfirewall firewall add rule name="OmniApexStudio Bridge" dir=in action=allow protocol=TCP localport=8080-8085,8765-8766,8888,9090'
                $ruleOut = Invoke-Expression $cmd 2>&1 | Out-String
                Send-Json $res @{ ok = $true; message = "Windows Güvenlik Duvarı kuralı eklendi: " + $ruleOut.Trim() }
            } catch {
                Send-Json $res @{ ok = $false; error = $_.Exception.Message }
            }
            $res.Close()
            continue
        }

        if ($path -eq "/api/telemetry") {
            Send-Json $res @{ ok = $true; telemetry = (Get-Telemetry) }
            $res.Close()
            continue
        }

        if ($path -eq "/api/load-settings") {
            if (Test-Path $cfgFile -PathType Leaf) {
                $raw = [System.IO.File]::ReadAllText($cfgFile, [System.Text.Encoding]::UTF8)
                $res.StatusCode = 200; $res.ContentType = "application/json; charset=utf-8"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw); $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else { Send-Json $res @{ ok = $false } }
            $res.Close(); continue
        }

        if ($path -eq "/api/save-settings" -and $req.HttpMethod -eq "POST") {
            $rawBody = (New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)).ReadToEnd()
            if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
            [System.IO.File]::WriteAllText($cfgFile, $rawBody, [System.Text.Encoding]::UTF8)
            Send-Json $res @{ ok = $true }; $res.Close(); continue
        }

        if ($path -eq "/api/load-chats") {
            if (Test-Path $chatsFile -PathType Leaf) {
                $raw = [System.IO.File]::ReadAllText($chatsFile, [System.Text.Encoding]::UTF8)
                $res.StatusCode = 200; $res.ContentType = "application/json; charset=utf-8"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw); $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else { Send-Json $res @{ ok = $false; sessions = @{} } }
            $res.Close(); continue
        }

        if ($path -eq "/api/save-chats" -and $req.HttpMethod -eq "POST") {
            $rawBody = (New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)).ReadToEnd()
            if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
            [System.IO.File]::WriteAllText($chatsFile, $rawBody, [System.Text.Encoding]::UTF8)
            Send-Json $res @{ ok = $true }; $res.Close(); continue
        }

        if ($path -eq "/api/load-hub") {
            if (Test-Path $hubFile -PathType Leaf) {
                $raw = [System.IO.File]::ReadAllText($hubFile, [System.Text.Encoding]::UTF8)
                $res.StatusCode = 200; $res.ContentType = "application/json; charset=utf-8"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw); $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else { Send-Json $res @{ ok = $false } }
            $res.Close(); continue
        }

        if ($path -eq "/api/save-hub" -and $req.HttpMethod -eq "POST") {
            $rawBody = (New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)).ReadToEnd()
            if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
            [System.IO.File]::WriteAllText($hubFile, $rawBody, [System.Text.Encoding]::UTF8)
            Send-Json $res @{ ok = $true }; $res.Close(); continue
        }

        if ($path -eq "/api/load-agents") {
            if (Test-Path $agentsFile -PathType Leaf) {
                $raw = [System.IO.File]::ReadAllText($agentsFile, [System.Text.Encoding]::UTF8)
                $res.StatusCode = 200; $res.ContentType = "application/json; charset=utf-8"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw); $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else { Send-Json $res @{ ok = $true; agents = @() } }
            $res.Close(); continue
        }

        if ($path -eq "/api/save-agents" -and $req.HttpMethod -eq "POST") {
            $rawBody = (New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)).ReadToEnd()
            if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
            [System.IO.File]::WriteAllText($agentsFile, $rawBody, [System.Text.Encoding]::UTF8)
            Send-Json $res @{ ok = $true }; $res.Close(); continue
        }

        if ($path -eq "/api/capture-screen") {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing
                $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
                $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
                $ms = New-Object System.IO.MemoryStream
                $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                $base64 = [Convert]::ToBase64String($ms.ToArray())
                $gfx.Dispose(); $bmp.Dispose(); $ms.Dispose()
                Send-Json $res @{ ok = $true; dataUrl = "data:image/png;base64," + $base64 }
            } catch {
                Send-Json $res @{ ok = $false; error = $_.Exception.Message } 500
            }
            $res.Close(); continue
        }

        if ($path -eq "/api/list-files") {
            $reqDir = $req.QueryString["dir"]
            $baseToScan = if ($reqDir) { Test-AllowedPath $reqDir } else { $root }
            if (-not $baseToScan -or -not (Test-Path $baseToScan -PathType Container)) { $baseToScan = $root }
            $items = Get-ChildItem -Path $baseToScan -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                $_.FullName -notmatch '\\(node_modules|\.git|release|_backup|__pycache__|\.venv)\\' -and ($blockedNames -notcontains $_.Name.ToLower())
            } | Select-Object -First 250 | ForEach-Object {
                $_.FullName.Substring($baseToScan.Length).TrimStart('\') -replace '\\', '/'
            }
            $scratchProjects = @()
            if (Test-Path "C:\Users\dhm16596\.gemini\antigravity\scratch" -PathType Container) {
                $scratchProjects = @(Get-ChildItem "C:\Users\dhm16596\.gemini\antigravity\scratch" -Directory | ForEach-Object { $_.FullName })
            }
            if (Test-Path "C:\OtonomAsistan\Antigravity_V4_Ultra" -PathType Container) {
                $scratchProjects += "C:\OtonomAsistan\Antigravity_V4_Ultra"
            }
            Send-Json $res @{ ok = $true; root = $baseToScan; roots = $allowedRoots; projects = $scratchProjects; files = @($items) }
            $res.Close(); continue
        }

        if ($path -eq "/api/read-file" -and $req.HttpMethod -eq "POST") {
            $body = (New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)).ReadToEnd() | ConvertFrom-Json
            $rawP = [string]$body.path
            $baseDir = if ($body.root) { [string]$body.root } else { $root }
            $target = Test-AllowedPath $rawP $baseDir
            if (-not $target -or -not (Test-Path $target -PathType Leaf)) {
                Send-Json $res @{ ok = $false; error = "Dosya bulunamadi veya erisim korumasinda." } 404
            } else {
                $content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
                Send-Json $res @{ ok = $true; path = $target; content = $content }
            }
            $res.Close(); continue
        }

        if ($path -eq "/api/exec" -and $req.HttpMethod -eq "POST") {
            $body = (New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)).ReadToEnd() | ConvertFrom-Json
            $cmd = ([string]$body.command).Trim()
            $shell = if ($body.shell) { [string]$body.shell.ToLower() } else { "powershell" }
            $notice = ""
            $lower = $cmd.ToLower()
            if ($interactiveTraps.ContainsKey($lower)) {
                $notice = "[KORUMA] '$cmd' interaktif kabuk oldugu icin kilitlenmeyi onlemek adina bilgi modunda calistirildi:`n"
                $cmd = $interactiveTraps[$lower]
            }
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            if ($shell -eq "cmd") {
                $psi.FileName = "cmd.exe"
                $psi.Arguments = "/c " + $cmd
            } elseif ($shell -eq "bash") {
                $bashExe = if (Test-Path "C:\Program Files\Git\bin\bash.exe") { "C:\Program Files\Git\bin\bash.exe" } elseif (Get-Command bash.exe -ErrorAction SilentlyContinue) { "bash.exe" } else { $null }
                if ($bashExe) {
                    $psi.FileName = $bashExe
                    $psi.Arguments = "-c `"$cmd`""
                } else {
                    $notice += "[BILGI] Bash bulunamadi, PowerShell uzerinden calistirildi:`n"
                    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
                    $psi.FileName = "powershell.exe"
                    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $b64"
                }
            } else {
                $b64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
                $psi.FileName = "powershell.exe"
                $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $b64"
            }
            $workDir = if ($body.cwd -and (Test-AllowedPath ([string]$body.cwd))) { [string]$body.cwd } else { $root }
            $psi.WorkingDirectory = $workDir
            $psi.RedirectStandardInput = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

            $proc = [System.Diagnostics.Process]::Start($psi)
            $proc.StandardInput.Close()
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()

            if (-not $proc.WaitForExit(30000)) {
                try { $proc.Kill() } catch {}
                Send-Json $res @{ ok = $false; exitCode = -1; stdout = $notice; stderr = "[ZAMAN ASIMI] Komut 30 saniyede tamamlanamadi." }
            } else {
                Send-Json $res @{ ok = ($proc.ExitCode -eq 0); exitCode = $proc.ExitCode; stdout = ($notice + $outTask.Result); stderr = $errTask.Result }
            }
            $res.Close(); continue
        }

        if ($path -eq "/api/write-file" -and $req.HttpMethod -eq "POST") {
            $body = (New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)).ReadToEnd() | ConvertFrom-Json
            $rawP = [string]$body.path
            $baseDir = if ($body.root) { [string]$body.root } else { $root }
            $target = Test-AllowedPath $rawP $baseDir
            if (-not $target) {
                Send-Json $res @{ ok = $false; error = "Calisma alani disina veya korumali dosyaya yazma engellendi." } 403
            } else {
                $backupPath = $null
                if (Test-Path $target -PathType Leaf) {
                    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $backupPath = Join-Path $root ("_backup\$stamp\" + [System.IO.Path]::GetFileName($target))
                    $bakDir = Split-Path -Parent $backupPath
                    if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir -Force | Out-Null }
                    Copy-Item -Path $target -Destination $backupPath -Force
                }
                $dir = Split-Path -Parent $target
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                [System.IO.File]::WriteAllText($target, [string]$body.content, [System.Text.Encoding]::UTF8)
                Send-Json $res @{ ok = $true; path = $target; backup = $backupPath }
            }
            $res.Close(); continue
        }

        # Guvenli statik dosya sunucusu (.env ve root disi engelli)
        $rel = $path.TrimStart('/')
        if ([string]::IsNullOrEmpty($rel)) { $rel = "index.html" }
        $safeStatic = Test-AllowedPath $rel $root
        if ($safeStatic -and $safeStatic.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $safeStatic -PathType Leaf)) {
            $bytes = [System.IO.File]::ReadAllBytes($safeStatic)
            if ($safeStatic.EndsWith(".html")) { $res.ContentType = "text/html; charset=utf-8" }
            elseif ($safeStatic.EndsWith(".json")) { $res.ContentType = "application/json; charset=utf-8" }
            elseif ($safeStatic.EndsWith(".js")) { $res.ContentType = "application/javascript; charset=utf-8" }
            elseif ($safeStatic.EndsWith(".css")) { $res.ContentType = "text/css; charset=utf-8" }
            elseif ($safeStatic.EndsWith(".xml")) { $res.ContentType = "application/xml; charset=utf-8" }
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $res.StatusCode = 404
        }
        $res.Close()
    } catch {
        try { $ctx.Response.Close() } catch {}
    }
}

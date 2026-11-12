$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
$cfgDir = Join-Path $env:LOCALAPPDATA "OmniApexStudio"
$cfgFile = Join-Path $cfgDir "settings.json"

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
    Read-Host "Cikmak icin Enter'a basin"
    exit 1
}

$url = "http://localhost:$port/"
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  OMNI-APEX STUDIO OS v3.0 + CANLI TELEMETRI" -ForegroundColor Green
Write-Host "  Adres: $url" -ForegroundColor Yellow
Write-Host "  Kapatmak icin bu pencereyi kapatin veya Ctrl+C" -ForegroundColor Gray
Write-Host "==================================================" -ForegroundColor Cyan

Start-Process $url

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
            port = $port
        }
    } catch {
        return @{ os = "Windows"; cwd = $root; port = $port }
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
        $res.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
        $res.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 204
            $res.Close()
            continue
        }

        $path = $req.Url.LocalPath

        if ($path -eq "/api/ping") {
            Send-Json $res @{ ok = $true; os = "Windows"; cwd = $root; port = $port }
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
                $res.StatusCode = 200
                $res.ContentType = "application/json; charset=utf-8"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                Send-Json $res @{ ok = $false }
            }
            $res.Close()
            continue
        }

        if ($path -eq "/api/save-settings" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $rawBody = $reader.ReadToEnd()
            if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
            [System.IO.File]::WriteAllText($cfgFile, $rawBody, [System.Text.Encoding]::UTF8)
            Send-Json $res @{ ok = $true }
            $res.Close()
            continue
        }

        if ($path -eq "/api/list-files") {
            $items = Get-ChildItem -Path $root -Recurse -File | Where-Object {
                $_.FullName -notmatch '\\(node_modules|\.git|release|_backup)\\'
            } | ForEach-Object {
                $_.FullName.Substring($root.Length).TrimStart('\') -replace '\\', '/'
            }
            Send-Json $res @{ ok = $true; root = $root; files = @($items) }
            $res.Close()
            continue
        }

        if ($path -eq "/api/read-file" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd() | ConvertFrom-Json
            $relPath = ([string]$body.path).TrimStart('/', '\')
            $target = [System.IO.Path]::GetFullPath((Join-Path $root ($relPath -replace '/', '\')))
            if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $target -PathType Leaf)) {
                Send-Json $res @{ ok = $false; error = "Dosya bulunamadi." } 404
            } else {
                $content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
                Send-Json $res @{ ok = $true; content = $content }
            }
            $res.Close()
            continue
        }

        if ($path -eq "/api/exec" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd() | ConvertFrom-Json
            $cmd = ([string]$body.command).Trim()
            $notice = ""
            $lower = $cmd.ToLower()
            if ($interactiveTraps.ContainsKey($lower)) {
                $notice = "[KORUMA] '$cmd' interaktif kabuk oldugu icin kilitlenmeyi onlemek adina bilgi modunda calistirildi:`n"
                $cmd = $interactiveTraps[$lower]
            }
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command " + ($cmd | ConvertTo-Json)
            $psi.WorkingDirectory = $root
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
                Send-Json $res @{ ok = $false; exitCode = -1; stdout = $notice; stderr = "[ZAMAN ASIMI] Komut 30 saniyede tamamlanamadigi icin sonlandirildi (interaktif giris bekliyor olabilir)." }
            } else {
                $stdout = $notice + $outTask.Result
                $stderr = $errTask.Result
                Send-Json $res @{ ok = ($proc.ExitCode -eq 0); exitCode = $proc.ExitCode; stdout = $stdout; stderr = $stderr }
            }
            $res.Close()
            continue
        }

        if ($path -eq "/api/write-file" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd() | ConvertFrom-Json
            $relPath = ([string]$body.path).TrimStart('/', '\')
            $target = [System.IO.Path]::GetFullPath((Join-Path $root ($relPath -replace '/', '\')))
            if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                Send-Json $res @{ ok = $false; error = "Calisma alani disina yazma engellendi." } 403
            } else {
                $backupPath = $null
                if (Test-Path $target -PathType Leaf) {
                    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $backupPath = Join-Path $root ("_backup\$stamp\" + ($relPath -replace '/', '\'))
                    $bakDir = Split-Path -Parent $backupPath
                    if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir -Force | Out-Null }
                    Copy-Item -Path $target -Destination $backupPath -Force
                }
                $dir = Split-Path -Parent $target
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                [System.IO.File]::WriteAllText($target, [string]$body.content, [System.Text.Encoding]::UTF8)
                Send-Json $res @{ ok = $true; path = $target; backup = $backupPath }
            }
            $res.Close()
            continue
        }

        $rel = $path.TrimStart('/')
        if ([string]::IsNullOrEmpty($rel)) { $rel = "index.html" }
        $file = Join-Path $root ($rel -replace '/', '\')
        if (Test-Path $file -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($file)
            if ($file.EndsWith(".html")) { $res.ContentType = "text/html; charset=utf-8" }
            elseif ($file.EndsWith(".json")) { $res.ContentType = "application/json; charset=utf-8" }
            elseif ($file.EndsWith(".js")) { $res.ContentType = "application/javascript; charset=utf-8" }
            elseif ($file.EndsWith(".css")) { $res.ContentType = "text/css; charset=utf-8" }
            elseif ($file.EndsWith(".xml")) { $res.ContentType = "application/xml; charset=utf-8" }
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $res.StatusCode = 404
        }
        $res.Close()
    } catch {
        try { $ctx.Response.Close() } catch {}
    }
}

param(
    [switch]$Clean,
    [switch]$SkipInstall,
    [switch]$SkipBackendBuild,
    [switch]$SkipFrontendBuild,
    [switch]$Start
)

# 修改这里：部署目标目录和启动端口
$DeployDir = "C:\GreenSoft\NovelForgeDeploy"
$ExistingInstallDir = "C:\GreenSoft\NovelForge"
$Python = "python"
$BackendHost = "0.0.0.0"
$BackendPort = 18970
$WebHost = "0.0.0.0"
$WebPort = 18960

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    Write-Step $Name
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

function Assert-CommandExists {
    param([string]$Command)
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Command not found: $Command"
    }
}

function Copy-DirectoryContents {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source directory does not exist: $Source"
    }

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
}

function Copy-BackendBuildOutput {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source directory does not exist: $Source"
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Destination $_.Name) -Force
    }
}

function Stop-ProcessTreeById {
    param([int]$ProcessId)
    try {
        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            Stop-ProcessTreeById -ProcessId ([int]$child.ProcessId)
        }
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    } catch { }
}

function Stop-DeployedProcesses {
    param(
        [string]$TargetRoot,
        [string]$TargetBackendExe,
        [string]$TargetWebScript,
        [int]$TargetBackendPort,
        [int]$TargetWebPort
    )

    Write-Step "Stop deployed services if running"

    $normalizedBackend = [System.IO.Path]::GetFullPath($TargetBackendExe).ToLowerInvariant()
    $backendProcesses = Get-CimInstance Win32_Process -Filter "Name = 'NovelForgeBackend.exe'" -ErrorAction SilentlyContinue
    foreach ($process in $backendProcesses) {
        $path = if ($process.ExecutablePath) { [System.IO.Path]::GetFullPath($process.ExecutablePath).ToLowerInvariant() } else { '' }
        $commandLine = if ($process.CommandLine) { $process.CommandLine.ToLowerInvariant() } else { '' }
        if ($path -eq $normalizedBackend -or $commandLine.Contains($TargetBackendPort.ToString())) {
            Stop-ProcessTreeById -ProcessId ([int]$process.ProcessId)
        }
    }

    $normalizedWebScript = [System.IO.Path]::GetFullPath($TargetWebScript).ToLowerInvariant()
    $powershellProcesses = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue
    foreach ($process in $powershellProcesses) {
        $commandLine = if ($process.CommandLine) { $process.CommandLine.ToLowerInvariant() } else { '' }
        if ($commandLine.Contains($normalizedWebScript) -or $commandLine.Contains($TargetWebPort.ToString())) {
            Stop-ProcessTreeById -ProcessId ([int]$process.ProcessId)
        }
    }

    $trayProcesses = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue
    foreach ($process in $trayProcesses) {
        $commandLine = if ($process.CommandLine) { $process.CommandLine.ToLowerInvariant() } else { '' }
        if ($commandLine.Contains((Join-Path $TargetRoot "NovelForgeTray.ps1").ToLowerInvariant())) {
            Stop-ProcessTreeById -ProcessId ([int]$process.ProcessId)
        }
    }
}

function Copy-ExistingRuntimeData {
    param(
        [string]$ExistingRoot,
        [string]$TargetBackend
    )

    if (-not (Test-Path -LiteralPath $ExistingRoot)) {
        Write-Host "Existing install directory not found, skip data sync: $ExistingRoot" -ForegroundColor Yellow
        return
    }

    $existingBackend = Join-Path $ExistingRoot "backend"
    if (-not (Test-Path -LiteralPath $existingBackend)) {
        Write-Host "Existing backend directory not found, skip data sync: $existingBackend" -ForegroundColor Yellow
        return
    }

    New-Item -ItemType Directory -Path $TargetBackend -Force | Out-Null

    $runtimeFiles = @("novelforge.db", ".env")
    foreach ($name in $runtimeFiles) {
        $source = Join-Path $existingBackend $name
        $target = Join-Path $TargetBackend $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $target -Force
            Write-Host "Synced runtime data: $name" -ForegroundColor Green
        }
    }
}

function Write-LauncherScripts {
    param(
        [string]$TargetRoot,
        [string]$BackendExeName,
        [string]$BackendHostValue,
        [int]$BackendPortValue,
        [string]$WebHostValue,
        [int]$WebPortValue
    )

    $startBackend = @"
`$ErrorActionPreference = "Stop"
`$root = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$backend = Join-Path `$root "backend\$BackendExeName"
if (-not (Test-Path -LiteralPath `$backend)) {
    throw "Backend executable not found: `$backend"
}
`$env:NOVELFORGE_BACKEND_HOST = "$BackendHostValue"
`$env:NOVELFORGE_BACKEND_PORT = "$BackendPortValue"
& `$backend
"@

    $startWeb = @"
param(
    [string]`$HostName = "$WebHostValue",
    [int]`$Port = $WebPortValue
)

`$ErrorActionPreference = "Stop"
`$root = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$webRoot = Join-Path `$root "frontend"
if (-not (Test-Path -LiteralPath `$webRoot)) {
    throw "Frontend directory not found: `$webRoot"
}

`$bindAddress = if (`$HostName -eq "0.0.0.0") {
    [System.Net.IPAddress]::Any
} else {
    [System.Net.IPAddress]::Parse(`$HostName)
}

`$listener = [System.Net.Sockets.TcpListener]::new(`$bindAddress, `$Port)
`$listener.Start()
Write-Host "Web service listening on http://`${HostName}:`$Port" -ForegroundColor Green
Write-Host "Open from another machine: http://<machine-a-ip>:`$Port" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop."

function Get-ContentType {
    param([string]`$File)
    `$ext = [System.IO.Path]::GetExtension(`$File).ToLowerInvariant()
    switch (`$ext) {
        ".html" { "text/html; charset=utf-8" }
        ".js" { "text/javascript; charset=utf-8" }
        ".css" { "text/css; charset=utf-8" }
        ".json" { "application/json; charset=utf-8" }
        ".svg" { "image/svg+xml" }
        ".png" { "image/png" }
        ".jpg" { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".ico" { "image/x-icon" }
        default { "application/octet-stream" }
    }
}

function Write-Response {
    param(
        [System.Net.Sockets.NetworkStream]`$Stream,
        [int]`$StatusCode,
        [string]`$StatusText,
        [string]`$ContentType,
        [byte[]]`$Body
    )

    `$crlf = [string][char]13 + [string][char]10
    `$header = "HTTP/1.1 `$StatusCode `$StatusText" + `$crlf +
        "Content-Type: `$ContentType" + `$crlf +
        "Content-Length: `$(`$Body.Length)" + `$crlf +
        "Connection: close" + `$crlf + `$crlf
    `$headerBytes = [System.Text.Encoding]::ASCII.GetBytes(`$header)
    `$Stream.Write(`$headerBytes, 0, `$headerBytes.Length)
    if (`$Body.Length -gt 0) {
        `$Stream.Write(`$Body, 0, `$Body.Length)
    }
}

try {
    while (`$true) {
        `$client = `$listener.AcceptTcpClient()
        try {
            `$stream = `$client.GetStream()
            `$buffer = New-Object byte[] 8192
            `$read = `$stream.Read(`$buffer, 0, `$buffer.Length)
            if (`$read -le 0) { continue }

            `$request = [System.Text.Encoding]::ASCII.GetString(`$buffer, 0, `$read)
            `$requestLine = (`$request -split '\r?\n', 2)[0]
            `$parts = `$requestLine -split ' '
            if (`$parts.Length -lt 2) {
                `$body = [System.Text.Encoding]::UTF8.GetBytes("Bad Request")
                Write-Response `$stream 400 "Bad Request" "text/plain; charset=utf-8" `$body
                continue
            }

            `$path = [Uri]::UnescapeDataString(`$parts[1].Split('?')[0].TrimStart('/'))
            if ([string]::IsNullOrWhiteSpace(`$path)) { `$path = "index.html" }
            `$file = Join-Path `$webRoot `$path

            if (-not (Test-Path -LiteralPath `$file -PathType Leaf)) {
                `$file = Join-Path `$webRoot "index.html"
            }

            `$bytes = [System.IO.File]::ReadAllBytes(`$file)
            Write-Response `$stream 200 "OK" (Get-ContentType `$file) `$bytes
        }
        catch {
            `$message = [System.Text.Encoding]::UTF8.GetBytes(`$_.Exception.Message)
            if (`$stream) {
                Write-Response `$stream 500 "Internal Server Error" "text/plain; charset=utf-8" `$message
            }
        }
        finally {
            if (`$stream) { `$stream.Dispose() }
            `$client.Close()
        }
    }
}
finally {
    `$listener.Stop()
}
"@

    $startAll = @"
`$ErrorActionPreference = "Stop"
`$root = Split-Path -Parent `$MyInvocation.MyCommand.Path
& (Join-Path `$root 'NovelForgeTray.ps1')
"@

    $trayScript = @"
`$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

`$root = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$backendExe = Join-Path `$root "backend\$BackendExeName"
`$webScript = Join-Path `$root "start-web.ps1"
`$backendUrl = "http://127.0.0.1:$BackendPortValue/"
`$webUrl = "http://127.0.0.1:$WebPortValue/"

if (-not (Test-Path -LiteralPath `$backendExe)) {
    [System.Windows.Forms.MessageBox]::Show("Backend executable not found: `$backendExe", "NovelForge", "OK", "Error") | Out-Null
    exit 1
}
if (-not (Test-Path -LiteralPath `$webScript)) {
    [System.Windows.Forms.MessageBox]::Show("Web script not found: `$webScript", "NovelForge", "OK", "Error") | Out-Null
    exit 1
}

`$backendProcess = `$null
`$webProcess = `$null
`$pidFile = Join-Path `$root "novelforge-processes.json"

function Stop-ProcessTreeById {
    param([int]`$ProcessId)
    try {
        `$children = Get-CimInstance Win32_Process -Filter "ParentProcessId = `$ProcessId" -ErrorAction SilentlyContinue
        foreach (`$child in `$children) {
            Stop-ProcessTreeById -ProcessId ([int]`$child.ProcessId)
        }
        Stop-Process -Id `$ProcessId -Force -ErrorAction SilentlyContinue
    } catch { }
}

function Stop-DeployedBackendProcesses {
    `$normalizedBackend = [System.IO.Path]::GetFullPath(`$backendExe).ToLowerInvariant()
    `$processes = Get-CimInstance Win32_Process -Filter "Name = 'NovelForgeBackend.exe'" -ErrorAction SilentlyContinue
    foreach (`$process in `$processes) {
        `$path = if (`$process.ExecutablePath) { [System.IO.Path]::GetFullPath(`$process.ExecutablePath).ToLowerInvariant() } else { '' }
        if (`$path -eq `$normalizedBackend) {
            Stop-ProcessTreeById -ProcessId ([int]`$process.ProcessId)
        }
    }
}

function Stop-DeployedWebProcesses {
    `$normalizedWebScript = [System.IO.Path]::GetFullPath(`$webScript).ToLowerInvariant()
    `$processes = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue
    foreach (`$process in `$processes) {
        `$commandLine = ''
        if (`$process.CommandLine) { `$commandLine = `$process.CommandLine.ToLowerInvariant() }
        if (`$commandLine.Contains(`$normalizedWebScript)) {
            Stop-ProcessTreeById -ProcessId ([int]`$process.ProcessId)
        }
    }
}

function Stop-StaleManagedProcesses {
    Stop-DeployedWebProcesses
    Stop-DeployedBackendProcesses
}

function Start-ManagedProcesses {
    Stop-StaleManagedProcesses

    `$env:NOVELFORGE_BACKEND_HOST = "$BackendHostValue"
    `$env:NOVELFORGE_BACKEND_PORT = "$BackendPortValue"

    `$backendStart = [System.Diagnostics.ProcessStartInfo]::new()
    `$backendStart.FileName = `$backendExe
    `$backendStart.WorkingDirectory = Split-Path -Parent `$backendExe
    `$backendStart.UseShellExecute = `$true
    `$backendStart.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    `$script:backendProcess = [System.Diagnostics.Process]::Start(`$backendStart)

    `$webStart = [System.Diagnostics.ProcessStartInfo]::new()
    `$webStart.FileName = "powershell.exe"
    `$webStart.Arguments = '-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + `$webScript + '"'
    `$webStart.WorkingDirectory = `$root
    `$webStart.UseShellExecute = `$true
    `$webStart.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    `$script:webProcess = [System.Diagnostics.Process]::Start(`$webStart)

    @{
        backendPid = `$script:backendProcess.Id
        webPid = `$script:webProcess.Id
    } | ConvertTo-Json | Set-Content -LiteralPath `$pidFile -Encoding ASCII
}

function Stop-ManagedProcess {
    param([System.Diagnostics.Process]`$Process)
    if (`$null -eq `$Process) { return }
    try {
        if (`$Process.HasExited) { return }
        `$Process.CloseMainWindow() | Out-Null
        if (-not `$Process.WaitForExit(3000)) {
            `$Process.Kill(`$true)
            `$Process.WaitForExit(3000)
        }
    }
    catch {
        try { `$Process.Kill(`$true) } catch { }
    }
}

function Stop-All {
    Stop-ManagedProcess `$script:webProcess
    Stop-ManagedProcess `$script:backendProcess
    Stop-StaleManagedProcesses
    if (Test-Path -LiteralPath `$pidFile) {
        try { Remove-Item -LiteralPath `$pidFile -Force } catch { }
    }
}

`$notifyIcon = [System.Windows.Forms.NotifyIcon]::new()
`$notifyIcon.Text = "NovelForge Web"
try {
    `$notifyIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon(`$backendExe)
} catch {
    `$notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
}
`$notifyIcon.Visible = `$true

`$menu = [System.Windows.Forms.ContextMenuStrip]::new()
`$openItem = [System.Windows.Forms.ToolStripMenuItem]::new("Open Web")
`$openItem.Add_Click({ Start-Process `$webUrl })
`$backendItem = [System.Windows.Forms.ToolStripMenuItem]::new("Open Backend Status")
`$backendItem.Add_Click({ Start-Process `$backendUrl })
`$exitItem = [System.Windows.Forms.ToolStripMenuItem]::new("Exit NovelForge")
`$exitItem.Add_Click({
    `$notifyIcon.Visible = `$false
    Stop-All
    [System.Windows.Forms.Application]::Exit()
})

`$menu.Items.Add(`$openItem) | Out-Null
`$menu.Items.Add(`$backendItem) | Out-Null
`$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null
`$menu.Items.Add(`$exitItem) | Out-Null
`$notifyIcon.ContextMenuStrip = `$menu
`$notifyIcon.Add_DoubleClick({ Start-Process `$webUrl })

try {
    Start-ManagedProcesses
    `$notifyIcon.ShowBalloonTip(3000, "NovelForge", "Backend and Web services started.", [System.Windows.Forms.ToolTipIcon]::Info)
    [System.Windows.Forms.Application]::Run()
}
finally {
    `$notifyIcon.Visible = `$false
    `$notifyIcon.Dispose()
    Stop-All
}
"@

    $startBackendBat = @"
@echo off
setlocal
cd /d "%~dp0"
set NOVELFORGE_BACKEND_HOST=$BackendHostValue
set NOVELFORGE_BACKEND_PORT=$BackendPortValue
if not exist "backend\$BackendExeName" (
    echo Backend executable not found: "%~dp0backend\$BackendExeName"
    pause
    exit /b 1
)
"backend\$BackendExeName"
pause
"@

    $startAllBat = @"
@echo off
setlocal
cd /d "%~dp0"
wscript.exe "%~dp0start-all.vbs"
exit /b 0
"@

    $startAllVbs = @"
Set shell = CreateObject("WScript.Shell")
root = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
quote = Chr(34)
cmd = "powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & quote & root & "\NovelForgeTray.ps1" & quote
shell.Run cmd, 0, False
"@

    $startTrayDebugBat = @"
@echo off
setlocal
cd /d "%~dp0"
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0NovelForgeTray.ps1"
pause
"@

    $startWebBat = @"
@echo off
setlocal
cd /d "%~dp0"
powershell -NoExit -ExecutionPolicy Bypass -File "%~dp0start-web.ps1"
"@

    Set-Content -LiteralPath (Join-Path $TargetRoot "start-backend.ps1") -Value $startBackend -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $TargetRoot "start-web.ps1") -Value $startWeb -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $TargetRoot "start-frontend.ps1") -Value $startWeb -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $TargetRoot "start-all.ps1") -Value $startAll -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $TargetRoot "NovelForgeTray.ps1") -Value $trayScript -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $TargetRoot "start-backend.bat") -Value $startBackendBat -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $TargetRoot "start-web.bat") -Value $startWebBat -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $TargetRoot "start-all.bat") -Value $startAllBat -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $TargetRoot "start-all.vbs") -Value $startAllVbs -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $TargetRoot "start-tray-debug.bat") -Value $startTrayDebugBat -Encoding ASCII
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$backendRoot = Join-Path $repoRoot "backend"
$frontendRoot = Join-Path $repoRoot "frontend"
$deployRoot = [System.IO.Path]::GetFullPath($DeployDir)
$existingRoot = [System.IO.Path]::GetFullPath($ExistingInstallDir)
$backendDist = Join-Path $backendRoot "dist"
$backendBuild = Join-Path $backendRoot "build"
$frontendDist = Join-Path $frontendRoot "dist-web"
$deployBackend = Join-Path $deployRoot "backend"
$deployFrontend = Join-Path $deployRoot "frontend"
$backendExe = "NovelForgeBackend.exe"

Assert-CommandExists $Python
Assert-CommandExists "npm"

if ($Clean) {
    Write-Step "Clean build and deploy directories"
    foreach ($path in @($backendDist, $backendBuild, $frontendDist, $deployRoot)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

if (-not $SkipBackendBuild) {
    if (-not $SkipInstall) {
        Invoke-Checked "Install backend Python dependencies" {
            Push-Location $backendRoot
            try {
                & $Python -m pip install -r requirements.txt
                & $Python -m pip install pyinstaller
            }
            finally {
                Pop-Location
            }
        }
    }

    Invoke-Checked "Build backend executable with PyInstaller" {
        Push-Location $backendRoot
        try {
            & $Python -m PyInstaller `
                --noconfirm `
                --clean `
                --onefile `
                --name NovelForgeBackend `
                --distpath dist `
                --workpath build `
                --specpath build `
                --hidden-import langchain_openai `
                --hidden-import langchain_google_genai `
                --hidden-import langchain_anthropic `
                run_backend.py
        }
        finally {
            Pop-Location
        }
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $backendDist $backendExe))) {
    throw "Backend executable was not found: $(Join-Path $backendDist $backendExe)"
}

if (-not $SkipFrontendBuild) {
    if (-not $SkipInstall -and -not (Test-Path -LiteralPath (Join-Path $frontendRoot "node_modules"))) {
        Invoke-Checked "Install frontend npm dependencies" {
            Push-Location $frontendRoot
            try { npm install }
            finally { Pop-Location }
        }
    }

    Invoke-Checked "Build web frontend" {
        Push-Location $frontendRoot
        $oldPlatform = $env:VITE_APP_PLATFORM
        try {
            $env:VITE_APP_PLATFORM = "web"
            npm run clean:web
            npm exec -- vite build -c vite.config.web.ts
        }
        finally {
            $env:VITE_APP_PLATFORM = $oldPlatform
            Pop-Location
        }
    }
}

if (-not (Test-Path -LiteralPath $frontendDist)) {
    throw "Frontend build directory was not found: $frontendDist"
}

Write-Step "Deploy files to $deployRoot"
New-Item -ItemType Directory -Path $deployRoot -Force | Out-Null
Stop-DeployedProcesses `
    -TargetRoot $deployRoot `
    -TargetBackendExe (Join-Path $deployBackend $backendExe) `
    -TargetWebScript (Join-Path $deployRoot "start-web.ps1") `
    -TargetBackendPort $BackendPort `
    -TargetWebPort $WebPort
Copy-BackendBuildOutput -Source $backendDist -Destination $deployBackend
Copy-DirectoryContents -Source $frontendDist -Destination $deployFrontend
Copy-ExistingRuntimeData -ExistingRoot $existingRoot -TargetBackend $deployBackend

$frontendConfig = "window.__NOVELFORGE_CONFIG__ = { backendBaseUrl: window.location.origin };"
Set-Content -LiteralPath (Join-Path $deployFrontend "novelforge-config.js") -Value $frontendConfig -Encoding ASCII

$sourceEnv = Join-Path $backendRoot ".env.example"
$targetEnv = Join-Path $deployBackend ".env"
if ((Test-Path -LiteralPath $sourceEnv) -and -not (Test-Path -LiteralPath $targetEnv)) {
    Copy-Item -LiteralPath $sourceEnv -Destination $targetEnv -Force
}

Write-LauncherScripts `
    -TargetRoot $deployRoot `
    -BackendExeName $backendExe `
    -BackendHostValue $BackendHost `
    -BackendPortValue $BackendPort `
    -WebHostValue $WebHost `
    -WebPortValue $WebPort

Write-Host "`nDeployment complete." -ForegroundColor Green
Write-Host "Deploy directory: $deployRoot"
Write-Host "Start all services: powershell -ExecutionPolicy Bypass -File `"$(Join-Path $deployRoot 'start-all.ps1')`""
Write-Host "Browser URL from machine B: http://<machine-a-ip>:$WebPort"
Write-Host "Backend health URL: http://<machine-a-ip>:$BackendPort/"

if ($Start) {
    Write-Step "Start deployed services"
    & (Join-Path $deployRoot "start-all.ps1")
}

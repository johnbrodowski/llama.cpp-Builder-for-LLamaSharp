# Build-LlamaCpp.ps1
# Interactive llama.cpp builder - run from any folder, builds go into subfolders here.

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

function Write-Header {
    param($Text)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Info  { param($Text) Write-Host "  $Text" -ForegroundColor White }
function Write-Good  { param($Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn  { param($Text) Write-Host "  [!!] $Text" -ForegroundColor Yellow }
function Write-Fail  { param($Text) Write-Host "  [XX] $Text" -ForegroundColor Red }

function Prompt-Input {
    param($Question, $Default = "")
    Write-Host ""
    Write-Host "  $Question" -ForegroundColor Yellow
    if ($Default -ne "") {
        Write-Host "  (press Enter to use: $Default)" -ForegroundColor DarkGray
    }
    $val = Read-Host "  >"
    if ($val -eq "" -and $Default -ne "") { return $Default }
    return $val
}

function Prompt-YesNo {
    param($Question, $Default = "Y")
    Write-Host ""
    Write-Host "  $Question" -ForegroundColor Yellow
    if ($Default -eq "Y") {
        Write-Host "  [Y] Yes  [N] No  (default: Y)" -ForegroundColor DarkGray
    } else {
        Write-Host "  [Y] Yes  [N] No  (default: N)" -ForegroundColor DarkGray
    }
    $val = Read-Host "  >"
    if ($val -eq "") { $val = $Default }
    return $val.ToUpper() -eq "Y"
}

function Prompt-Choice {
    param($Question, $Choices)
    Write-Host ""
    Write-Host "  $Question" -ForegroundColor Yellow
    Write-Host ""
    for ($i = 0; $i -lt $Choices.Count; $i++) {
        Write-Host "  [$($i+1)] $($Choices[$i])" -ForegroundColor White
    }
    Write-Host ""
    do {
        $val = Read-Host "  Enter number"
        $num = 0
        $valid = [int]::TryParse($val, [ref]$num) -and $num -ge 1 -and $num -le $Choices.Count
        if (-not $valid) { Write-Warn "Please enter a number between 1 and $($Choices.Count)" }
    } while (-not $valid)
    return $num - 1
}

# ─────────────────────────────────────────────
# Find Visual Studio
# ─────────────────────────────────────────────

function Find-VSVars {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -property installationPath 2>$null
        if ($vsPath) {
            $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
            if (Test-Path $vcvars) { return $vcvars }
        }
    }
    $fallbacks = @(
        "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
    )
    foreach ($f in $fallbacks) {
        if (Test-Path $f) { return $f }
    }
    return $null
}

function Invoke-WithVSEnv {
    param($VcVars)
    $tempEnv = [System.IO.Path]::GetTempFileName()
    $tempBat = [System.IO.Path]::GetTempFileName() + ".bat"
    "@echo off`r`ncall `"$VcVars`" > nul 2>&1`r`nset > `"$tempEnv`"" | Set-Content $tempBat
    cmd /c $tempBat | Out-Null
    Get-Content $tempEnv | ForEach-Object {
        if ($_ -match "^([^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }
    Remove-Item $tempBat, $tempEnv -Force -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

Clear-Host
Write-Header "llama.cpp Builder for LLamaSharp"
Write-Info "This tool clones and compiles llama.cpp into a versioned"
Write-Info "subfolder next to this script. Nothing is ever deleted."
Write-Info ""
Write-Info "Script location: $ScriptDir"

# ── Git ──
Write-Host ""
Write-Info "Checking for git..."
try {
    $gitVer = & git --version 2>&1
    Write-Good "$gitVer"
} catch {
    Write-Fail "git not found. Please install Git for Windows and re-run."
    Read-Host "`n  Press Enter to exit"; exit 1
}

# ── CMake ──
Write-Info "Checking for cmake..."
try {
    $cmakeVer = & cmake --version 2>&1 | Select-Object -First 1
    Write-Good "$cmakeVer"
} catch {
    Write-Fail "cmake not found. Please install CMake and re-run."
    Read-Host "`n  Press Enter to exit"; exit 1
}

# ── Visual Studio ──
Write-Info "Looking for Visual Studio..."
$vcvars = Find-VSVars
if (-not $vcvars) {
    Write-Warn "Could not auto-detect Visual Studio."
    $vcvars = Prompt-Input "Enter full path to vcvars64.bat"
    if ($vcvars -eq "" -or -not (Test-Path $vcvars)) {
        Write-Fail "Cannot build without Visual Studio C++ tools."
        Read-Host "`n  Press Enter to exit"; exit 1
    }
}
Write-Good "Found: $vcvars"

# ─────────────────────────────────────────────
# Step 1 - Version
# ─────────────────────────────────────────────

Write-Header "Step 1 of 3 - llama.cpp Version"
Write-Info "Enter a commit hash, tag, or branch name."
Write-Info ""
Write-Info "  Examples:"
Write-Info "    8d3b962        (short commit hash)"
Write-Info "    b8175          (release tag)"
Write-Info "    master         (latest, may be unstable)"
Write-Info ""
Write-Info "  Find releases at: https://github.com/ggml-org/llama.cpp/releases"
Write-Info ""
$commitInput = Prompt-Input "Which version do you want to build?" "master"
$folderName  = $commitInput -replace "[^a-zA-Z0-9_\-\.]", "_"
$outputDir   = Join-Path $ScriptDir $folderName
$cloneDir    = Join-Path $ScriptDir "_llama.cpp_src"

if (Test-Path $outputDir) {
    Write-Warn "A build for '$folderName' already exists at:"
    Write-Warn "  $outputDir"
    $overwrite = Prompt-YesNo "Delete it and rebuild from scratch?" "N"
    if (-not $overwrite) {
        Write-Info "Nothing changed. Exiting."
        Read-Host "`n  Press Enter to exit"; exit 0
    }
    Remove-Item $outputDir -Recurse -Force
}

# ─────────────────────────────────────────────
# Step 2 - Shared vs Static
# ─────────────────────────────────────────────

Write-Header "Step 2 of 3 - Library Type"
Write-Info "How should llama.cpp be compiled?"
Write-Info ""
Write-Info "  Shared (DLL)"
Write-Info "    Produces llama.dll, ggml.dll, etc."
Write-Info "    This is what LLamaSharp loads at runtime."
Write-Info "    Choose this unless you know you need static."
Write-Info ""
Write-Info "  Static (.lib)"
Write-Info "    Everything compiled into a single .lib file."
Write-Info "    Only useful if you are embedding llama.cpp"
Write-Info "    directly into your own C++ project."
Write-Info ""
$sharedIdx  = Prompt-Choice "Which do you want?" @(
    "Shared library (DLL) - use with LLamaSharp",
    "Static library (.lib) - embed in C++ project"
)
$sharedLibs = ($sharedIdx -eq 0)

# ─────────────────────────────────────────────
# Step 3 - GPU backend
# ─────────────────────────────────────────────

Write-Header "Step 3 of 3 - GPU Acceleration"
Write-Info "llama.cpp can offload model layers to a GPU for faster inference."
Write-Info ""
Write-Info "  CPU only"
Write-Info "    Works on any machine with no extra software."
Write-Info "    Perfectly fine for small models (LFM2.5-VL etc)."
Write-Info "    Slower than GPU for large models (13B+)."
Write-Info ""
Write-Info "  CUDA (NVIDIA only)"
Write-Info "    Dramatically faster for large models."
Write-Info "    Requires: NVIDIA GPU + CUDA Toolkit installed."
Write-Info "    Check toolkit version with: nvcc --version"
Write-Info ""
Write-Info "  Vulkan (any GPU)"
Write-Info "    Works on NVIDIA, AMD, and Intel GPUs."
Write-Info "    No CUDA Toolkit needed - just GPU drivers."
Write-Info "    Good middle ground for non-NVIDIA hardware."
Write-Info ""
$gpuIdx   = Prompt-Choice "Which backend?" @(
    "CPU only  - no GPU required",
    "CUDA      - NVIDIA GPU (requires CUDA Toolkit)",
    "Vulkan    - any GPU (requires Vulkan-capable drivers)"
)
$cudaOn   = ($gpuIdx -eq 1)
$vulkanOn = ($gpuIdx -eq 2)

# ─────────────────────────────────────────────
# Confirm
# ─────────────────────────────────────────────

Write-Header "Summary - Ready to Build"
Write-Info "Version   : $commitInput"
Write-Info "Output    : $outputDir"
Write-Info "Library   : $(if ($sharedLibs) { 'Shared (DLL)' } else { 'Static (.lib)' })"
Write-Info "Backend   : $(if ($cudaOn) { 'CUDA' } elseif ($vulkanOn) { 'Vulkan' } else { 'CPU only' })"
Write-Host ""
$go = Prompt-YesNo "Start the build now?" "Y"
if (-not $go) {
    Write-Info "Cancelled. Nothing was changed."
    Read-Host "`n  Press Enter to exit"; exit 0
}

# ─────────────────────────────────────────────
# Clone / fetch source
# ─────────────────────────────────────────────

Write-Header "Cloning llama.cpp Source"

if (Test-Path $cloneDir) {
    Write-Info "Source folder exists, fetching latest from remote..."
    Push-Location $cloneDir
    & git fetch --all
    Pop-Location
} else {
    Write-Info "Cloning into: $cloneDir"
    & git clone https://github.com/ggml-org/llama.cpp $cloneDir
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "git clone failed."
        Read-Host "`n  Press Enter to exit"; exit 1
    }
}

Push-Location $cloneDir
Write-Info "Checking out: $commitInput"
& git checkout $commitInput
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Checkout failed. Is '$commitInput' a valid commit, tag, or branch?"
    Pop-Location
    Read-Host "`n  Press Enter to exit"; exit 1
}
Pop-Location

# ─────────────────────────────────────────────
# Load VS environment
# ─────────────────────────────────────────────

Write-Header "Loading Visual Studio Build Environment"
Write-Info "Calling: $vcvars"
Invoke-WithVSEnv -VcVars $vcvars
Write-Good "VS environment ready."

# ─────────────────────────────────────────────
# CMake configure
# ─────────────────────────────────────────────

Write-Header "Configuring CMake"

$buildDir   = Join-Path $cloneDir "build_$folderName"

$cmakeArgs = @(
    "-S", $cloneDir,
    "-B", $buildDir,
    "-DBUILD_SHARED_LIBS=$(if ($sharedLibs) { 'ON' } else { 'OFF' })",
    "-DGGML_CUDA=$(if ($cudaOn) { 'ON' } else { 'OFF' })",
    "-DGGML_VULKAN=$(if ($vulkanOn) { 'ON' } else { 'OFF' })",
    "-DLLAMA_BUILD_EXAMPLES=ON"
)

Write-Info "cmake $($cmakeArgs -join ' ')"
Write-Host ""
& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
    Write-Fail "CMake configure step failed. See errors above."
    Read-Host "`n  Press Enter to exit"; exit 1
}

# ─────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────

$jobs = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
Write-Header "Building  (using $jobs parallel jobs - grab a coffee)"
& cmake --build $buildDir --config Release -j $jobs
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Build failed. See errors above."
    Read-Host "`n  Press Enter to exit"; exit 1
}

# ─────────────────────────────────────────────
# Collect output into versioned folder
# ─────────────────────────────────────────────

Write-Header "Collecting Output Files"

# Find where the DLLs ended up
$candidates = @(
    (Join-Path $buildDir "bin\Release"),
    (Join-Path $buildDir "bin"),
    (Join-Path $buildDir "Release"),
    $buildDir
)
$releaseDir = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$copied = 0
foreach ($ext in @("*.dll", "*.lib", "*.pdb")) {
    Get-ChildItem $releaseDir -Filter $ext -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName $outputDir
        Write-Good "Copied: $($_.Name)"
        $copied++
    }
}

if ($copied -eq 0) {
    Write-Warn "No output files found in $releaseDir"
    Write-Warn "The build may have succeeded but outputs are in an unexpected location."
    Write-Warn "Check: $buildDir"
}

# Save build metadata
@"
Build Info
----------
Version   : $commitInput
Folder    : $folderName
Built     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')
Shared    : $sharedLibs
CUDA      : $cudaOn
Vulkan    : $vulkanOn
Source    : $cloneDir
"@ | Set-Content (Join-Path $outputDir "build-info.txt")

# ─────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────

Write-Header "Build Complete!"
Write-Good "Files saved to:"
Write-Info "  $outputDir"
Write-Host ""
Get-ChildItem $outputDir | ForEach-Object { Write-Info "  $($_.Name)" }
Write-Host ""
Write-Info "To use with LLamaSharp:"
Write-Info "  Copy all DLLs from the folder above into your LLamaSharp"
Write-Info "  runtimes folder, e.g:"
Write-Info "    YourProject\LLama\runtimes\win-x64\native\"
Write-Host ""
Read-Host "  Press Enter to exit"

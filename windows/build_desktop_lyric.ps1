# Helper script to build desktop_lyric component
# Modified to copy repository to project directory first due to Pub cache operation restrictions

# Define parameters with default values
param(
    [Parameter(Mandatory=$false, HelpMessage="Build mode: Release or Debug (default: Release)")]
    [ValidateSet("Release", "Debug")]
    [string]$BuildMode = "Release"
)

# Define constants
# Get the script directory
$SCRIPT_DIR = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
# Get project root directory (parent of windows folder)
$PROJECT_ROOT = Split-Path -Path $SCRIPT_DIR -Parent
$PUB_CACHE_GIT_WIN = Join-Path -Path $env:USERPROFILE -ChildPath "AppData\Local\Pub\Cache\git"

# Define new temporary build directory within project (instead of using Pub cache directly)
$TEMP_BUILD_DIR = Join-Path -Path $PROJECT_ROOT -ChildPath "build\desktop_lyric"

# Check if build directory exists
$BUILD_DIR = Join-Path -Path $PROJECT_ROOT -ChildPath "build"
if (-not (Test-Path -Path $BUILD_DIR -PathType Container)) {
    Write-Error "Build directory not found. Please build the main application first."
    exit 1
}

# Determine software output directory (based on build mode)
$BUILD_MODE = $BuildMode
Write-Host "Building in $BUILD_MODE mode"
$SOFTWARE_OUTPUT_DIR = Join-Path -Path $PROJECT_ROOT -ChildPath "build\windows\x64\runner\$BUILD_MODE"
$DESKTOP_LYRIC_TARGET_DIR = Join-Path -Path $SOFTWARE_OUTPUT_DIR -ChildPath "desktop_lyric"

# Read and parse pubspec.yaml to get the exact ref for desktop_lyric
try {
    Write-Host "Reading pubspec.yaml to get exact ref for desktop_lyric..."
    $pubspecContent = Get-Content -Path "$PROJECT_ROOT\pubspec.yaml" -Raw
    
    # Extract the ref value using regex
    $refMatch = [regex]::Match($pubspecContent, 'desktop_lyric:\s+git:\s+url:\s+https:\/\/github\.com\/marscey\/desktop_lyric\.git\s+ref:\s+(\w+)')
    
    if ($refMatch.Success) {
        $DESKTOP_LYRIC_REF = $refMatch.Groups[1].Value
        Write-Host "Found exact ref from pubspec.yaml: $DESKTOP_LYRIC_REF"
        
        # Try to find cache directory with exact ref match
        Write-Host "Searching for desktop_lyric repository with exact ref in Pub cache..."
        $EXACT_CACHE_MATCH = Get-ChildItem -Path $PUB_CACHE_GIT_WIN -Directory | Where-Object { 
            $_.Name -like "*desktop_lyric*$($DESKTOP_LYRIC_REF.Substring(0, 10))*" 
        }
        
        if ($EXACT_CACHE_MATCH.Count -gt 0) {
            $DESKTOP_LYRIC_SOURCE_PATH = $EXACT_CACHE_MATCH[0].FullName
            Write-Host "Found exact cached desktop_lyric: $DESKTOP_LYRIC_SOURCE_PATH"
        } else {
            # Fallback to wildcard search if exact match not found
            Write-Warning "Cannot find exact desktop_lyric ref match. Falling back to wildcard search."
            $CACHE_CANDIDATES = Get-ChildItem -Path $PUB_CACHE_GIT_WIN -Directory | Where-Object { $_.Name -like "*desktop_lyric*" }
            
            if ($CACHE_CANDIDATES.Count -eq 0) {
                Write-Error "Cannot find desktop_lyric repository in Pub cache. Please run 'flutter pub get' first."
                exit 1
            }
            
            # Use the first matching cache directory
            $DESKTOP_LYRIC_SOURCE_PATH = $CACHE_CANDIDATES[0].FullName
            Write-Host "Found cached desktop_lyric (fallback): $DESKTOP_LYRIC_SOURCE_PATH"
        }
    } else {
        # Fallback if we can't parse pubspec.yaml
        Write-Warning "Failed to parse ref from pubspec.yaml. Falling back to wildcard search."
        $CACHE_CANDIDATES = Get-ChildItem -Path $PUB_CACHE_GIT_WIN -Directory | Where-Object { $_.Name -like "*desktop_lyric*" }
        
        if ($CACHE_CANDIDATES.Count -eq 0) {
            Write-Error "Cannot find desktop_lyric repository in Pub cache. Please run 'flutter pub get' first."
            exit 1
        }
        
        # Use the first matching cache directory
        $DESKTOP_LYRIC_SOURCE_PATH = $CACHE_CANDIDATES[0].FullName
        Write-Host "Found cached desktop_lyric (fallback): $DESKTOP_LYRIC_SOURCE_PATH"
    }
} catch {
    Write-Warning "Error reading pubspec.yaml: $_"
    # Fallback to original wildcard search
    $CACHE_CANDIDATES = Get-ChildItem -Path $PUB_CACHE_GIT_WIN -Directory | Where-Object { $_.Name -like "*desktop_lyric*" }
    
    if ($CACHE_CANDIDATES.Count -eq 0) {
        Write-Error "Cannot find desktop_lyric repository in Pub cache. Please run 'flutter pub get' first."
        exit 1
    }
    
    # Use the first matching cache directory
    $DESKTOP_LYRIC_SOURCE_PATH = $CACHE_CANDIDATES[0].FullName
    Write-Host "Found cached desktop_lyric (fallback): $DESKTOP_LYRIC_SOURCE_PATH"
}

# Check if temporary build directory already exists
if (Test-Path -Path $TEMP_BUILD_DIR -PathType Container) {
    Write-Host "Temporary build directory $TEMP_BUILD_DIR already exists, skipping copy from Pub cache."
} else {
    # Create temporary build directory
    Write-Host "Creating temporary build directory at $TEMP_BUILD_DIR..."
    New-Item -ItemType Directory -Force -Path $TEMP_BUILD_DIR | Out-Null
    
    # Copy repository from Pub cache to temporary build directory
    Write-Host "Copying repository from Pub cache to temporary build directory..."
    try {
        Copy-Item -Path "$DESKTOP_LYRIC_SOURCE_PATH\*" -Destination $TEMP_BUILD_DIR -Recurse -Force
    } catch {
        Write-Error "Failed to copy repository: $_"
        exit 1
    }
}

# Ensure target directory exists
Write-Host "Creating target directory for deployment..."
New-Item -ItemType Directory -Force -Path $DESKTOP_LYRIC_TARGET_DIR | Out-Null

# Build desktop_lyric component in the temporary directory
Write-Host "Starting to build desktop_lyric component in temporary directory..."
try {
    Push-Location $TEMP_BUILD_DIR
    
    # Run flutter build command with selected mode
    $buildArgs = @("build", "windows")
    if ($BUILD_MODE -eq "Release") {
        $buildArgs += "--release"
    } elseif ($BUILD_MODE -eq "Debug") {
        $buildArgs += "--debug"
    } else {
        Write-Error "Unknown build mode: $BUILD_MODE. Please use Release or Debug."
        exit 1
    }
    
    flutter $buildArgs
    
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code: $LASTEXITCODE"
    }
} catch {
    Write-Error "Failed to build desktop_lyric component: $_"
    Pop-Location
    exit 1
} finally {
    Pop-Location
}

# Copy build artifacts to target directory
try {
    $BUILD_OUTPUT_PATH = Join-Path -Path $TEMP_BUILD_DIR -ChildPath "build\windows\x64\runner\$BUILD_MODE"
    Write-Host "Copying build artifacts from $BUILD_OUTPUT_PATH to $DESKTOP_LYRIC_TARGET_DIR"
    Copy-Item -Path "$BUILD_OUTPUT_PATH\*" -Destination $DESKTOP_LYRIC_TARGET_DIR -Recurse -Force
} catch {
    Write-Error "Failed to copy build artifacts: $_"
    exit 1
}

# # Clean up temporary build directory
# try {
#     Write-Host "Cleaning up temporary build directory..."
#     Remove-Item -Path $TEMP_BUILD_DIR -Recurse -Force -ErrorAction SilentlyContinue
# } catch {
#     Write-Warning "Warning during cleanup of temporary directory: $_"
#     # Cleanup failures don't affect overall build success
# }

Write-Host -ForegroundColor Green "desktop_lyric component built and deployed successfully in $BUILD_MODE mode!"
exit 0
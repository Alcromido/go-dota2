# PowerShell version of apigen.bash - simplified version
$ErrorActionPreference = "Stop"

# Set GO111MODULE environment variable
$env:GO111MODULE = "on"
# Set GOOS and GOARCH to ensure we build for Windows
$env:GOOS = "windows"
$env:GOARCH = "amd64"

# Clean up any existing executable
if (Test-Path "./apigen.exe") {
    Remove-Item -Force "./apigen.exe"
}
if (Test-Path "./apigen") {
    Remove-Item -Force "./apigen"
}

# Build the apigen tool with a timeout
Write-Host "Building apigen tool..." -ForegroundColor Green
try {
    # Run go mod tidy to ensure dependencies are up to date
    $tidyProcess = Start-Process -FilePath "go" -ArgumentList "mod tidy" -NoNewWindow -PassThru
    $tidyProcess | Wait-Process -Timeout 60 -ErrorAction SilentlyContinue
    if (-not $tidyProcess.HasExited) {
        $tidyProcess | Stop-Process -Force
        Write-Host "Dependency tidying timed out after 60 seconds" -ForegroundColor Red
        exit 1
    }
    
    # Build with a 60-second timeout, explicitly not using vendor and targeting Windows
    $buildProcess = Start-Process -FilePath "go" -ArgumentList "build -v -mod=mod -o apigen.exe ./" -NoNewWindow -PassThru
    $buildProcess | Wait-Process -Timeout 60 -ErrorAction SilentlyContinue
    if (-not $buildProcess.HasExited) {
        $buildProcess | Stop-Process -Force
        Write-Host "Build timed out after 60 seconds" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Error building apigen tool - $($Error[0])" -ForegroundColor Red
    exit 1
}

# Check if apigen was built successfully
if (-not (Test-Path "./apigen.exe")) {
    Write-Host "Failed to build apigen.exe" -ForegroundColor Red
    exit 1
}

# Run the tool directly to test if it works
Write-Host "Testing if apigen.exe works..." -ForegroundColor Green
try {
    $testOutput = & "./apigen.exe" "--help" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error running apigen.exe: $testOutput" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Error testing apigen.exe - $($Error[0])" -ForegroundColor Red
    exit 1
}

# Function to run a command with a timeout but capture output directly
function Run-Command {
    param (
        [string]$Name,
        [string]$Command,
        [string]$OutputFile,
        [int]$TimeoutSeconds = 60
    )
    
    Write-Host "=== $Name ===" -ForegroundColor Green
    
    try {
        # Create a script block from the command
        $scriptBlock = [ScriptBlock]::Create($Command)
        
        # Run the command and capture output
        $output = & $scriptBlock
        
        # Write output to file
        $output | Out-File -FilePath $OutputFile
        
        Write-Host "$Name completed successfully" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "Error executing $Name - $($Error[0])" -ForegroundColor Red
        return $false
    }
}

# Run the commands directly
$typeListSuccess = Run-Command -Name "Type list" -Command "./apigen.exe print-type-list" -OutputFile "snapshot-type-list.txt"
if (-not $typeListSuccess) {
    exit 1
}

$apiGenSuccess = Run-Command -Name "API codegen" -Command "./apigen.exe generate-api" -OutputFile "snapshot-apigen.txt"
if (-not $apiGenSuccess) {
    exit 1
}

$messagesSuccess = Run-Command -Name "Messages list" -Command "./apigen.exe print-messages" -OutputFile "snapshot-messages.txt"
if (-not $messagesSuccess) {
    exit 1
}

Write-Host "API generation completed successfully!" -ForegroundColor Green 
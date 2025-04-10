# PowerShell version of update_protos.bash
# Set error action to stop on errors
$ErrorActionPreference = "Stop"

# Get repository root (equivalent to git rev-parse --show-toplevel)
$REPO_ROOT = (git rev-parse --show-toplevel)
$REPO_PROTOS = Join-Path $REPO_ROOT "protos"
$GAME_DIR = "Protobufs"
$GAME_PATH = Join-Path $REPO_ROOT "generator\$GAME_DIR"

# Navigate to generator directory and update submodule
Push-Location (Join-Path $REPO_ROOT "generator")
git submodule update --init $GAME_DIR
Pop-Location

# Create temporary working directory
$WORK_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path $WORK_DIR | Out-Null
Write-Host "Using working directory: $WORK_DIR"

# Create cleanup function to remove temp directory when script exits
try {
    # Create subdirectories for originals and processed protos
    New-Item -ItemType Directory -Path "$WORK_DIR\orig" | Out-Null
    New-Item -ItemType Directory -Path "$WORK_DIR\protos" | Out-Null
    
    # Copy protobuf files from Dota2 directory
    Push-Location (Join-Path $GAME_PATH "dota2")
    
    # Copy all required proto files to the orig directory
    Get-ChildItem -Path "dota_gcmessages_*.proto", 
                        "dota_client_enums.proto", 
                        "network_connection.proto", 
                        "base_gcmessages.proto", 
                        "gcsdk_gcmessages.proto", 
                        "econ_*.proto", 
                        "dota_match_metadata.proto", 
                        "dota_shared_enums.proto", 
                        "steammessages.proto", 
                        "steammessages_unified_base.steamworkssdk.proto", 
                        "steammessages_steamlearn.steamworkssdk.proto", 
                        "valveextensions.proto", 
                        "gcsystemmsgs.proto" | 
        ForEach-Object { Copy-Item $_ -Destination "$WORK_DIR\orig\" }
    
    Pop-Location
    
    # Create google/protobuf directory and copy files
    New-Item -ItemType Directory -Path "$WORK_DIR\orig\google\protobuf" -Force | Out-Null
    Copy-Item -Path "$GAME_PATH\google\protobuf\*" -Destination "$WORK_DIR\orig\google\protobuf\" -Recurse
    
    # Add valve_extensions.proto
    Copy-Item -Path "$REPO_PROTOS\valve_extensions.proto" -Destination "$WORK_DIR\orig\"
    
    # Process each proto file
    Get-ChildItem -Path "$WORK_DIR\orig\*.proto" | ForEach-Object {
        $fname = $_.Name
        $header = "syntax = `"proto2`";`npackage protocol;`noption go_package = `"./;protocol`";`n`n"
        
        # Read the file content
        $content = Get-Content -Path $_.FullName -Raw
        
        # Apply replacements (equivalent to sed commands)
        $content = $content -replace "optional \.", "optional "
        $content = $content -replace "required \.", "required "
        $content = $content -replace "repeated \.", "repeated "
        $content = $content -replace "google/protobuf/valve_extensions.proto", "valve_extensions.proto"
        $content = $content -replace "\t\.", "`t"
        
        # Write the modified content
        Set-Content -Path "$WORK_DIR\protos\$fname" -Value ($header + $content)
    }
    
    # Fix specific issues in steammessages_steamlearn.steamworkssdk.proto
    $steamLearnFile = "$WORK_DIR\protos\steammessages_steamlearn.steamworkssdk.proto"
    if (Test-Path $steamLearnFile) {
        (Get-Content $steamLearnFile -Raw) -replace "\(.CMsgSteamLearn", "(CMsgSteamLearn" | Set-Content $steamLearnFile
    }
    
    # Generate protobufs using protoc
    Push-Location "$WORK_DIR\protos"
    
    # Get a list of all proto files
    $protoFiles = Get-ChildItem -Path "*.proto" | ForEach-Object { $_.FullName }
    
    # Run protoc on all files
    & protoc -I (Get-Location) --go_out=. $protoFiles
    
    # Copy the generated files to the protocol directory
    # PowerShell equivalent of rsync -rv --delete is to remove destination and copy
    if (Test-Path (Join-Path $REPO_ROOT "protocol")) {
        Remove-Item -Path (Join-Path $REPO_ROOT "protocol") -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Join-Path $REPO_ROOT "protocol") -Force | Out-Null
    Copy-Item -Path (Join-Path (Get-Location) "*") -Destination (Join-Path $REPO_ROOT "protocol") -Recurse
    
    Pop-Location
}
finally {
    # Clean up the temporary directory
    if (Test-Path $WORK_DIR) {
        Remove-Item -Path $WORK_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Protocol files generation completed successfully!" 
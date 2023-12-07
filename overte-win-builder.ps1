
<#
.SYNOPSIS

Build Overte

.DESCRIPTION

This script builds Overte

.PARAMETER Verbose

Verbose output for debugging.

.PARAMETER CleanBuild

Delete build directory and build from scratch

.EXAMPLE 

.\overte-win-builder.ps1

.LINK

https://overte.org

#>
param (
	[switch]$Verbose=$false,
	[switch]$CleanBuild=$false,
	[ValidateSet(2019, 2022)]
	[int]$VSVersion=2019
)

. ".\functions.ps1"


##############################################################################################
# Globals
##############################################################################################
if ( $VSVersion -eq 2019 ) {
	$VCVarsAll = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
} elseif ( $VSVersion -eq 2022 ) {
	$VCVarsAll = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat"
} else {
	throw "Unrecognized Visual Studio version: $VSVersion"
}

#
$Env:HIFI_VCPKG_BASE="${Env:USERPROFILE}\\overte-files-${VSVersion}"
$GitUrl = "https://github.com/overte-org/overte.git"
$SourceDir = ".\overte"
$BuildDir = ".\build"
$OriginalDir = Get-Location

Header "Setting up environment"

# All paths need to be absolute, this avoids any confusion when switching directories

Info "Selected Visual Studio version: $VSVersion"
Info "VCPKG Base: ${Env:HIFI_VCPKG_BASE}"
Info "Initializing VC Vars"
if ( $Env:VS_SELECTED_VERSION -ne $null -And $Env:VS_SELECTED_VERSION -ne $VSVersion ) {
	throw "Environment already initialized for ${Env:VS_SELECTED_VERSION}. Can't switch to $VSVersion. Please start a new PowerShell session."
}

if ( ! $Env:VCINSTALLDIR ) {
	# Import VC vars if not already done. On Windows environment leaks out of the script, gah.
	Invoke-BatchFile "$VCVarsAll" "x64"
	$Env:VS_SELECTED_VERSION = $VSVersion
} else {
    Write-Host "VC environment already imported."
}


Header "Obtaining source code"

#Get-Repo -Url "$GitUrl" -DestDir "$SourceDir" -Tag "master"


#Header "Disabling HifiNeuron"
#Remove-Item -Recurse "$SourceDir\plugins\hifiNeuron"


Header "Building"

if ($CleanBuild && (Test-Path -Path $BuildDir)) {
	Info "Removing build directory for a clean build"
	Remove-Item -Recurse $BuildDir
}


Info "Resolving paths"

if (! (Test-Path -Path $BuildDir)) {
	mkdir $BuildDir
}

$SourceDir = Resolve-Path -Path $SourceDir
$BuildDir = Resolve-Path -Path $BuildDir

Set-Location $BuildDir

# RelWithDebInfo is currently required so that v8 links correctly.
info "Running cmake"
cmake -G Ninja $SourceDir -DCMAKE_BUILD_TYPE=RelWithDebInfo

info "Starting build"
cmake --build . --target interface

Set-Location $OriginalDir
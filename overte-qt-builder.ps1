<#
.SYNOPSIS

Builds Qt


#>

param (
	[switch]$Verbose=$false,
	[switch]$Clean=$false,
	[switch]$StartupOnly=$false
	
)


$QT_SOURCE_URL="https://invent.kde.org/qt/qt/qt5.git"
$QT_WEBENGINE_SOURCE_URL="https://invent.kde.org/qt/qt/qtwebengine.git"
$QT_WEBCHANNEL_SOURCE_URL="https://invent.kde.org/qt/qt/qtwebchannel.git"
$WEBP_SOURCE_URL="https://github.com/webmproject/libwebp"

$JOM_BINARY_URL="http://download.qt.io/official_releases/jom/jom.zip"
$VCVARSALL_PATH = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
$QT_VERSION=5.15


. ".\functions.ps1"
$start_dir = Get-Location



#Run-With-Logging -Command "C:\Windows\System32\Ping.exe" -Arguments "127.0.0.1" -LogFile "$start_dir/ping"


#Get-Child-Process-Info 1456 | Format-List

#exit 1



Header "Starting up"


Info "Importing VC Variables..."

if ( ! $Env:VCINSTALLDIR ) {
	# Import VC vars if not already done.
	Invoke-BatchFile "$VCVARSALL_PATH" "x64"
}

Verify-Command -Command "git"   -Url "https://git-scm.com/download/win"
Verify-Command -Command "perl"  -Url "https://strawberryperl.com/"
Verify-Command -Command "cmake" -Url "https://visualstudio.microsoft.com/downloads/"
Verify-Command -Command "ninja" -Url "https://github.com/ninja-build/ninja/releases"
Verify-Command -Command "7z"    -Url "https://www.7-zip.org/download.html"

Verify-File "C:\Python27\python.exe"

Info "Downloading Jom..."
#Start-Job -Name JomRequest -ScriptBlock {
	Invoke-WebRequest -URI $JOM_BINARY_URL -OutFile jom.zip
#}

#Wait-Job -Name JomRequest
Expand-Archive -LiteralPath jom.zip -Force -DestinationPath "jom_bin"


Header "Obtaining source"

Get-Repo -Url $QT_SOURCE_URL -DestDir "qt5" -Tag "kde/$QT_VERSION" -Recursive -Submodules
Get-Repo -Url $QT_WEBENGINE_SOURCE_URL -DestDir "qtwebengine" -Tag "$QT_VERSION" -Recursive -Submodules
Get-Repo -Url $QT_WEBCHANNEL_SOURCE_URL -DestDir "qtwebchannel" -Tag "kde/$QT_VERSION" -Recursive -Submodules


if ( $Clean ) {
	Info "Removing previous build..."
	
	if ( Test-Path -Path "qt5-build" ) {
		Remove-Item -LiteralPath "qt5-build" -Force -Recurse
	}
	if ( Test-Path -Path "qt5-install" ) {
		Remove-Item -LiteralPath "qt5-install" -Force -Recurse
	}
	
}


Info "Creating directories..."


$dummy = New-Item -ItemType Directory -Force -Path "qt5-build"
$dummy = New-Item -ItemType Directory -Force -Path "qt5-install"

Info "Setting up environment..."

Add-To-Path "C:\Python27"
$Env:CL="/FS"

if ( $StartupOnly ) {
	exit
}

try {
	Set-Location "qt5-build"

	Header "Configuring"

	..\qt5\configure `
		-force-debug-info `
		-opensource `
		-confirm-license `
		-opengl desktop `
		-platform win32-msvc `
		-nomake examples `
		-nomake tests `
		-skip qttranslations `
		-skip qtserialport `
		-skip qt3d `
		-skip qtlocation `
		-skip qtwayland `
		-skip qtsensors `
		-skip qtgamepad `
		-skip qtcharts `
		-skip qtx11extras `
		-skip qtmacextras `
		-skip qtvirtualkeyboard `
		-skip qtpurchasing `
		-skip qtdatavis3d `
		-no-warnings-are-errors `
		-no-pch `
		-prefix ..\qt5-install
		
		
		Run-With-Logging -Command "..\jom_bin\jom.exe" -Arguments "" -LogFile "$start_dir/build"
		
		Run-With-Logging -Command "..\jom_bin\jom.exe install" -Arguments "" -LogFile "$start_dir/install"

		
 
} catch {
	Set-Location $start_dir
	throw
}

Set-Location $start_dir

Info "Compressing..."

& 'C:\Program Files\7-Zip\7z.exe' a -tzip qt5-install.zip qt5-install
 





#	-I %HIFI_VCPKG_BASE_DIR%\include \  -- WHY?
#	-L %HIFI_VCPKG_BASE_DIR%\lib \
# 	-openssl-linked `
#	OPENSSL_LIBS="-llibcrypto -llibssl" 
	
exit



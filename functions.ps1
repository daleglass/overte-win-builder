
function Show-Status-Line {
	param([string]$Status)
	
	Write-Host -NoNewLine "`r" + $Status.PadRight($script:prevStatusLength)
	$script:prevStatusLength = $Status.Length
}

function Clear-Status-Line {
	Write-Host -NoNewLine "`r" + "".PadRight($script:prevStatusLength)
	Write-Host -NoNewLine "`r"
	
	$script:prevStatusLength = 0
}

function Invoke-BatchFile
{
   param([string]$Path, [string]$Parameters)

   $tempFile = [IO.Path]::GetTempFileName()

	Write-Host "Path is $Path"

   ## Store the output of cmd.exe.  We also ask cmd.exe to output
   ## the environment table after the batch file completes
   cmd.exe /c " `"$Path`" $Parameters && set > `"$tempFile`" "

   ## Go through the environment variables in the temp file.
   ## For each of them, set the variable in our local environment.
   Get-Content $tempFile | Foreach-Object {
       if ($_ -match "^(.*?)=(.*)$")
       {
           Set-Content "env:\$($matches[1])" $matches[2]
       }
   }

   Remove-Item $tempFile
}

function New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    do {
      $name = [System.IO.Path]::GetRandomFileName()
      $item = New-Item -Path $parent -Name $name -ItemType "directory" -ErrorAction SilentlyContinue
    } while (-not $item)
    return $Item.FullName
  }
  function Header {
	param([string]$Label)

	$W = ((Get-Host).UI.RawUI.WindowSize.Width)
	$HDR = " " * $W
	$Padding = " " * ((($W-2)/2) - $Label.length / 2)
	$Padding2 = " " * (($W-2) - $Padding.length - $Label.length)

	Write-Host -ForegroundColor white -BackgroundColor blue ("┏" + ("━" * ($W-2)) + "┓")
	Write-Host -ForegroundColor white -BackgroundColor blue "┃${Padding}${Label}${Padding2}┃"
    Write-Host -ForegroundColor white -BackgroundColor blue ("┗" + ("━" * ($W-2)) + "┛")
	

	# Sometimes (randomly) the next line gets the background color. Clear it.
	Write-Host -NoNewLine "$HDR`r"
    Write-Host ""
}

function Info {
    param([string]$Message)

    Write-Host -ForegroundColor white $Message
}

function Get-Repo {
    param(
		[string]$Url,
		[string]$DestDir,
		[string]$Tag,
		[switch]$Recursive=$false,
		[switch]$Submodules=$false
	)

    $curdir = Get-Location

    if (! (Test-Path -Path $DestDir)) {
        Info "Cloning $Url..."
        git clone "$Url" "$DestDir"
    } else {
        Info "Repository dir already exists, updating..."
        Set-Location "$DestDir"
        git fetch
    }

    Set-Location $curdir
    Set-Location $DestDir

    Info "Checking out $Tag"
    git reset --hard origin/$Tag
	
	if ( $Submodules ) {
		Info "Initializing submodules"
		git submodule update --init --recursive
	}

    Set-Location $curdir
}

function Verify-Command {
	param([string]$Command,
	      [string]$Url,
		  [string[]]$Paths)
	
	$SearchPaths = @($Paths)
	$SearchPaths += "$Env:ProgramFiles"
	$SearchPaths += "$Env:ProgramFiles(x86)"
	
	Write-Host -ForegroundColor white -NoNewLine  "Checking if we have $Command in PATH... "
	
	try {
		$Location = Get-Command $Command -ErrorAction Stop
		Write-Host -ForegroundColor green $Location.Source
	}
	catch {
		Write-Host -ForegroundColor Magenta -NoNewLine "Failed, trying known locations... "
		
		foreach ( $Dir in $SearchPaths) {
			if ( $Dir -eq $null ) {
				Continue
			}
			
			#Write-Host "Trying $Dir"
			
			$Location = Get-ChildItem -Path $Dir -Filter $Command -Recurse -Depth 1 -ErrorAction SilentlyContinue 
			if ( ! $Location ) {
				$Location = Get-ChildItem -Path $Dir -Filter "${Command}.exe" -Recurse -Depth 1 -ErrorAction SilentlyContinue 
			}
		
			if ( $Location ) {
				$Path = $Location[0].Directory.FullName
				Write-Host -NoNewLine -ForegroundColor green "Found in dir $Path. "
				Add-To-Path $Path
				return
			}		
		}
		
		Write-Host -ForegroundColor red $Location.Source
		throw "$Command could not be found. Please install the missing dependency from $Url"
	}
}

function Verify-File {
	param([string]$File)
	
	Write-Host -ForegroundColor white -NoNewLine  "Checking if we have $File... "
	
	if ( Test-Path $File -PathType Leaf ) {
		Write-Host -ForegroundColor green "Yes"
	} else {
		Write-Host -ForegroundColor red "No"
		exit 1
	}
}

function Add-To-Path {
	param([string]$Path)
	
	Write-Host -ForegroundColor white -NoNewLine  "Adding $Path to PATH... "
	
	if ( $Env:PATH -like $Path ) {
		Write-Host -ForegroundColor green "Already added"
	} else {
		Write-Host -ForegroundColor green "Added"
		$Env:Path="$Path;$Env:PATH"
	}
}

function Get-Child-Process-Info {
	param(
		[int]$ParentPID
	)

	
	[hashtable]$Return = @{}
	
	$Return.processCount = [int]0
	$Return.cpuTime = [int]0
	$Return.memUsed = [int]0
	$Return.swapUsed = [int]0

	if ($ParentPID -eq 0) {
		return $Return
	}
	
	
	$procs = Get-WmiObject -Class Win32_Process -Filter "ParentProcessId=$ParentPID" | Select-Object UserModeTime,WorkingSetSize,PageFileUsage,ProcessId,ParentProcessId
	
#	$procs | Format-List
	foreach ($proc in $procs) {
		$childData = Get-Child-Process-Info $proc.ProcessID
		
		$Return.processCount += 1 + $childData.processCount
		$Return.cpuTime  += $proc.UserModeTime   + $childData.cpuTime
		$Return.memUsed  += $proc.WorkingSetSize + $childData.memUsed
		$Return.swapUsed += $proc.PageFileUsage  + $childData.swapUsed
		

		
	}
	
	return $Return
}

function Run-With-Logging {
	param(
		[string]$Command,
		[string]$Arguments,
		[string]$LogFile
	)
	
	# File locking on Windows is annoying, so make sure we can
	# open the logs first. Otherwise it proves to be a snag
	# annoyingly often.
	$timestamp = Get-Date -Format "yyyyMMdd_hhmmss"
	
	$outFile = [System.IO.StreamWriter]::new("${LogFile}.${timestamp}.out.txt")
	$errFile = [System.IO.StreamWriter]::new("${LogFile}.${timestamp}.err.txt")
	
	$pinfo = New-Object System.Diagnostics.ProcessStartInfo
	$pinfo.FileName = (Resolve-Path $Command).Path
	$pinfo.RedirectStandardError = $true
	$pinfo.RedirectStandardOutput = $true
	$pinfo.UseShellExecute = $false
	$pinfo.Arguments = $Arguments
	$pinfo.WorkingDirectory = (Get-Location).Path
	$p = New-Object System.Diagnostics.Process
	$p.StartInfo = $pinfo
	
	if (!$p.Start()) {
		try {
			$outFile.Dispose()
			$errFile.Dispose()
		} catch {
			# Nothing
		}
		
		throw "Failed to start process!"
	}
	

	
	
	#$p | Format-List
	#$p | Get-Member	
	$outTask = $null
	$errTask = $null
	$timeoutTask = $null
	$lastLine = ""
	$lastFile = ""
	$fileCount = 0
	$fileMax = 0
	$cpuStr = ""
	
	$totalRam = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).Sum
	$lastStatusTime = Get-Date
	
	
	while(!$p.HasExited) {
		

		if ( !$outTask ) {
			try {
				$global:outTask = $p.StandardOutput.ReadLineAsync() #Async($buffer, 0, $buffer.Length)
			} catch {
			}
		}
		
		if ( !$errTask ) {
			try {
				$global:errTask = $p.StandardError.ReadLineAsync() #Async($buffer, 0, $buffer.Length)
			} catch {
			}
		}
		
		if ( !$timeoutTask ) {
			try {
				$global:timeoutTask = [System.Threading.Tasks.Task]::Delay(1000)
			} catch {
			}
		}
			
			
			
			#$timeout | Get-Member
		
		[System.Threading.Tasks.Task[]] $tasks = @()
		$tasks += $global:outTask
		$tasks += $global:errTask
		$tasks += $global:timeoutTask
		
		$completedTask = [System.Threading.Tasks.Task]::WhenAny($tasks).GetAwaiter().GetResult() #@($outTask, $errTask, $timeout)).Result
	#	$completedTask | Get-Member
		if ($completedTask -eq $global:outTask) {
			$line = $completedTask.Result
			$lastLine = $line
			#Write-Host "OUT:"
			$outFile.WriteLine($line)
			
			$global:outTask = $null
		} elseif ($completedTask -eq $global:errTask) {
			$line = $completedTask.Result
			$errFile.WriteLine($line)
			Clear-Status-Line
			
			Write-Host -ForegroundColor red "$line"
			
			$global:errTask = $null
		} elseif ($completedTask -eq $global:timeoutTask) {
			#Write-Host -NoNewLine "T!"
			$global:timeoutTask = $null
		} else {
			#Write-Host "???"
		}
		
		
		$args = [regex]::split($lastLine, "\s")
		
		foreach ($arg in $args) {
			if ($arg -match "\.cpp$") {
				$lastFile = $arg
				$fileCount = $fileCount + 1
				break
			}
		}
		
		
		$sinceLastStatus = (Get-Date) - $lastStatusTime
		
		if ( $sinceLastStatus.TotalSeconds > 30 ) {
			$info = Get-Child-Process-Info $p.Id
			#$p | Format-List
			#$info | Format-List
			$cpu = [TimeSpan][int64]$info.cpuTime
			#$cpu = New-TimeSpan -Seconds $p.CPU
			$mem = [math]::Ceiling($info.memUsed / ( 1024 * 1024 ))
			$swap = [math]::Ceiling($info.swapUsed / ( 1024 * 1024 ))
			
			$cpuStr = [string]::Format("{0}:{1}:{2}", $cpu.Hours, $cpu.Minutes, $cpu.Seconds)
			$lastStatusTime = Get-Date
		}
		
		#$cpu = $p.CPU
		#$mem = [math]::Ceiling($p.WorkingSet64 / ( 1024 * 1024 ))
		
		#$cpu = [math]::Ceiling((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue)
		#$mem = (Get-Counter '\Memory\Available MBytes').CounterSamples.CookedValue		
		
		Show-Status-Line "[$fileCount/$fileMax - CPU: ${cpuStr}; MEM: ${mem} MiB; SWP: ${swap} MiB] $lastFile"
		#Write-Host $completedTask.Result
	}
	
	
	$outFile.Close()
	$outFile.Dispose()
	
	$errFile.Close()
	$errFile.Dispose()
#	$p.StandardError | Format-List
#	$p.StandardError | Get-Member
	
	#$p.WaitForExit()
	#$stdout = $p.StandardOutput.ReadToEnd()
	#$stderr = $p.StandardError.ReadToEnd()
	#Write-Host "stdout: $stdout"
	#Write-Host "stderr: $stderr"
	#Write-Host "exit code: " + $p.ExitCode	
}
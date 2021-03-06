Function ConvertTo-ValidPath([string]$TestPath)
{

	$invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
	$re = "[{0}]" -f [RegEx]::Escape($invalidChars)
	
	Write-Output ($TestPath -replace $re)

}

Function Write-BackupScript([string]$ServerInstance
	, [string]$DatabaseName=@("")
	, [string]$ExportPath
	, [string]$BackupPath
	, [switch]$CopyOnly=$false
	, [string]$BackupType="FULL")
{

	#Create Directory if needed.
	If((Test-Path -LiteralPath $ExportPath -PathType Container) -eq  $false)
	{
		New-Item -Path $ExportPath -ItemType Container | Out-Null 
		Write-Debug -Message "$(Get-Date) - Creating Export Path $($ExportPath)"
	}
	
	$AllExportFile = [System.IO.Path]::Combine($ExportPath, "!All Database Backup.sql")
	
	If((Test-Path -LiteralPath $AllExportFile -PathType leaf) -eq $true)
	{
		Remove-Item -LiteralPath $AllExportFile -Force -ErrorAction SilentlyContinue 
	}
	
	$Extension = ""
	$CommandStart = ""
	$WITHOptions = ""
	
	Switch ($BackupType)
	{
		("FULL") {$Extension=".BAK"
					$CommandStart = "BACKUP DATABASE"
					if($CopyOnly -eq $true) {$WITHOptions = "COPY_ONLY"}}
		("DIFF") {$Extension=".DIFF"
					$CommandStart = "BACKUP DATABASE"
					$WITHOptions = "DIFFERENTIAL"}
		("LOG") {$Extension=".TRN"
					$CommandStart = "BACKUP LOG"
					$WITHOptions = ""}
	}
	
	#Add With OPTIONS
	If($WITHOptions -ne "")
	{
		$WITHOptions = $WITHOptions + ", "
	}
	
	$WITHOptions = $WITHOptions + "COMPRESSION, NOINIT, CHECKSUM, STATS=5"
	
	#Get the Additional Modules needed for doing the work.
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 

	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance 

	#ForEach Database...
	ForEach($Database In ($SMO.databases | Where-Object -FilterScript {$_.name -ne "tempdb"}))
	{
	
		$Command = New-Object system.Text.StringBuilder
	
		$ExportFile = [System.IO.Path]::Combine($ExportPath, "$($Database.name) - Backup.sql")
		
		If((Test-Path -LiteralPath $ExportFile -PathType leaf) -eq $true)
		{
			Remove-Item -LiteralPath $ExportFile -Force -ErrorAction SilentlyContinue 
		}
		
		$CurrentTime = (Get-Date -Format "yyyy_MM_dd HH_mm_ss tt")
		
		$BackupDestination = $BackupPath + "\" + $Database.name + " " + $CurrentTime + $Extension
		
		$Command.AppendLine("/** Backing up $($Database.name) **/") | Out-Null
		$Command.AppendLine("") | Out-Null
		$Command.AppendLine($CommandStart + " [$($Database.name)]") | Out-Null
		$Command.AppendLine("`t TO DISK=N'$($BackupDestination)'") | Out-Null
		$Command.AppendLine("`t WITH $($WITHOptions)") | Out-Null
		$Command.AppendLine(" ") | Out-Null
		
		$Command.ToString() | Out-File $ExportFile -Encoding "UTF8"
		
		$Command.ToString() | Out-File $AllExportFile -Encoding "UTF8" -Append
		
	
	}

}

Function Write-DatabaseCreation([string]$ServerInstance, [string]$ExportPath)
{

	#Create Directory if needed.
	If((Test-Path -LiteralPath $ExportPath -PathType Container) -eq  $false)
	{
		New-Item -Path $ExportPath -ItemType Container | Out-Null 
		Write-Debug -Message "$(Get-Date) - Creating Export Path $($ExportPath)"
	}
	
	#Get the Additional Modules needed for doing the work.
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 

	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance 
	
	#Build Up Scripter Object...
	$Scripter = new-object ('Microsoft.SqlServer.Management.Smo.Scripter') ($SMO)
	$ScriptOptions = New-Object ('Microsoft.SqlServer.Management.Smo.ScriptingOptions')

	$ScriptOptions.AllowSystemObjects = $false
	$ScriptOptions.ExtendedProperties = $true 
	$ScriptOptions.AnsiPadding = $true 
	$ScriptOptions.WithDependencies = $false
	$ScriptOptions.IncludeHeaders = $true 
	$ScriptOptions.ClusteredIndexes = $true 
	$ScriptOptions.AppendToFile = $true 
	$ScriptOptions.IncludeIfNotExists = $true
	$ScriptOptions.ScriptBatchTerminator = $true
	$ScriptOptions.DriAll = $true 
	$ScriptOptions.Indexes = $true 
	$ScriptOptions.Triggers = $true 
	$ScriptOptions.ToFileOnly = $true 
	$Scripter.PrefetchObjects = $true 

	$Scripter.Options = $ScriptOptions
	
	#ForEach Database...
	ForEach($Database In ($SMO.databases | Where-Object -FilterScript {$_.IsSystemObject -eq $false}))
	{
	
		#Where are we writing the file to?
		$DBName = ConvertTo-ValidPath -TestPath ($Database.name)
		$FileName = [System.IO.Path]::Combine($ExportPath, "$($DBName).sql")
		
		#Overwrite File
		if((Test-Path -LiteralPath $FileName -PathType Leaf) -eq $true)
		{
			Remove-Item -LiteralPath $FileName -ErrorAction SilentlyContinue -Force | Out-Null 		
		}
		
		$Scripter.Options.FileName = $FileName 
		
		$Scripter.Script($Database) | Out-Null
		
		Write-Debug -Message "$(Get-Date) - Wrote Database $($Database.name) to $($FileName)"
		
	}

}

Function ConvertTo-SQLHashString($binhash)
{
	$OutString = "0x"
	$binhash | ForEach {$OutString += ('{0:X}' -f $_).PadLeft(2, '0')}
	
	Write-Output $OutString 
}

Function Write-InstanceLogins([string]$ServerInstance, [string]$ExportPath)
{

	#Create Directory if needed.
	If((Test-Path -LiteralPath $ExportPath -PathType Container) -eq  $false)
	{
		New-Item -Path $ExportPath -ItemType Container | Out-Null 
		Write-Debug -Message "$(Get-Date) - Creating Export Path $($ExportPath)"
	}
	
	#Get the Additional Modules needed for doing the work.
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 

	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance 
	
	#For Each login... skipping local machine accounts.
	ForEach($Login In ($SMO.logins | Where-Object -FilterScript {$_.name -NotLike "NT *" -and $_.IsSystemObject -eq $false}))
	{
	
		$Scripter = new-object ('Microsoft.SqlServer.Management.Smo.Scripter') ($SMO)
		$ScriptOptions = New-Object ('Microsoft.SqlServer.Management.Smo.ScriptingOptions')

		$ScriptOptions.AllowSystemObjects = $false
		$ScriptOptions.ExtendedProperties = $true 
		$ScriptOptions.AnsiPadding = $true 
		$ScriptOptions.WithDependencies = $false
		$ScriptOptions.IncludeHeaders = $true 
		$ScriptOptions.ClusteredIndexes = $true 
		$ScriptOptions.AppendToFile = $true 
		$ScriptOptions.IncludeIfNotExists = $true
		$ScriptOptions.ScriptBatchTerminator = $true
		$ScriptOptions.DriAll = $true 
		$ScriptOptions.Indexes = $true 
		$ScriptOptions.Triggers = $true 
		$ScriptOptions.ToFileOnly = $true 
		$ScriptOptions.LoginSid = $true 
		$Scripter.PrefetchObjects = $true 
		$Scripter.Options = $ScriptOptions
		
		#Script the login (taking care to avoid scripting out the DISABLE unless the login is really disabled...
		If($Login.IsDisabled -eq $true)
		{
			$LoginScript = ($Login.Script($ScriptOptions)) -join " "
		}
		else {
			$LoginScript = ($Login.Script($ScriptOptions) | Where-Object -FilterScript {$_ -notlike 'ALTER LOGIN*DISABLE'}) -join " "
		}
		
		#Modify if a SQL Login.
		If($Login.LoginType -eq "SqlLogin")
		{
			#Get from SQL the hashed password value...
			$Query = "SELECT CONVERT(VARBINARY(256), password_hash) AS hashedpass FROM sys.sql_logins WHERE name='$($Login.name)'"
			$hashedpass = ($SMO.databases['tempdb'].ExecuteWithResults($Query)).Tables.hashedpass
			$passstring = ConvertTo-SQLHashString -binhash $hashedpass
			
			#Identify the random password (and comment) provided by the script engine.
			$RndPass = $LoginScript.SubString($LoginScript.IndexOf("PASSWORD"), ($LoginScript.IndexOf(", SID")-$LoginScript.IndexOf("PASSWORD")))
			$comment = $LoginScript.SubString($LoginScript.IndexOf("/*"),$LoginScript.IndexOf("*/")-$LoginScript.IndexOf("/*")+2)
			
			$LoginScript = $LoginScript.Replace($comment,"").Replace($RndPass,"PASSWORD=$($passstring) HASHED")
		
		}
		
		#Fix some formatting...
		$LoginScript = $LoginScript.Replace("CREATE", "BEGIN`r`n`tCREATE").Replace(" WITH", "`r`n`t`tWITH").Replace(", ","`r`n`t`t, ").Replace(" ALTER", "`r`n`r`n`tALTER").Replace("ADD MEMBER","`r`n`r`n`tADD MEMBER") + "`r`n`r`nEND"
		
		#Write the Login down...
		$LoginName = ConvertTo-ValidPath -TestPath ($Login.name.Replace("\","_"))
		$FileName =[System.IO.Path]::Combine($ExportPath, "$($LoginName).sql")
		
		If((Test-Path -LiteralPath $FileName -PathType leaf) -eq $true)
		{
			Remove-Item -LiteralPath $FileName -Force -ErrorAction SilentlyContinue | Out-Null
		}
		
		$LoginScript | Out-File -LiteralPath $FileName -Encoding UTF8 -Force -ErrorAction SilentlyContinue
	
	}

}

Function Write-SQLAgentJobs([string]$ServerInstance, [string]$ExportPath)
{

	#Create Directory if needed.
	If((Test-Path -LiteralPath $ExportPath -PathType Container) -eq  $false)
	{
		New-Item -Path $ExportPath -ItemType Container | Out-Null 
		Write-Debug -Message "$(Get-Date) - Creating Export Path $($ExportPath)"
	}

	#Get the Additional Modules needed for doing the work.
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 

	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance 
	
	#Build Up Scripter Object...
	$Scripter = new-object ('Microsoft.SqlServer.Management.Smo.Scripter') ($SMO)
	$ScriptOptions = New-Object ('Microsoft.SqlServer.Management.Smo.ScriptingOptions')

	$Scripter.Options.ScriptDrops = $False
	$Scripter.Options.WithDependencies = $False
	$Scripter.Options.IncludeHeaders = $True
	$Scripter.Options.AppendToFile = $False
	$Scripter.Options.ToFileOnly = $True
	$Scripter.Options.ClusteredIndexes = $True
	$Scripter.Options.DriAll = $True
	$Scripter.Options.Indexes = $True
	$Scripter.Options.Triggers = $True

	$Scripter.Options = $ScriptOptions
	
	ForEach($Job In ($SMO.JobServer.Jobs | Where-Object -FilterScript {$_.name -ne ""}))
	{
	
		$JobName = ConvertTo-ValidPath -TestPath ($Job.name)
		$FileName = [System.IO.Path]::Combine($ExportPath, "$($JobName).sql")
		
		If((Test-Path -LiteralPath $FileName -PathType leaf) -eq $true)
		{
			Remove-Item -LiteralPath $FileName -Force -ErrorAction SilentlyContinue | Out-Null
		}
		
		$Scripter.Options.FileName = $FileName
		$Scripter.Script($Job) | Out-Null 
	
	}

}

Function Convert-DBCreation([string]$SourceDirectory, [string]$DestinationDirectory, [string]$NewDataPath, [string]$NewLogPath, [switch]$CreateSubFolders=$false)
{

	If((Test-Path -LiteralPath $DestinationDirectory -PathType Container) -eq $false)
	{
		New-Item -Path $DestinationDirectory -ItemType Container | Out-Null 
	}
	
	$ListOfNewDirectories = @()
	
	ForEach($File In Get-ChildItem -LiteralPath $SourceDirectory -Filter "*.sql" -File)
	{
	
		#Build new file name...
		$NewFileName = [System.IO.Path]::Combine($DestinationDirectory, [System.IO.Path]::GetFileName($File))
		
		If((Test-Path -LiteralPath $NewFileName -PathType Leaf) -eq $true)
		{
			Remove-Item -LiteralPath $NewFileName -Force -ErrorAction SilentlyContinue | Out-Null
		}
		
		ForEach($Line In Get-Content -LiteralPath $File.FullName)
		{
		
			$LineToWrite = $Line
			
			If($Line -ilike "*CREATE DATABASE*")
			{
				$DatabaseName = ConvertTo-ValidPath -TestPath ($Line.SubString($Line.IndexOf("DATABASE ["), $Line.IndexOf("]")-$Line.IndexOf("DATABASE ["))).Replace("DATABASE [","")
			}
			
			If($Line -ilike "*FILENAME = N'*")
			{
			
				#Get Just the filename...
				$OldDBFile = $Line.Substring($Line.IndexOf("FILENAME = N'"), $Line.IndexOf("' ,", $Line.IndexOf("FILENAME = N'"))-$Line.IndexOf("FILENAME = N'")).Replace("FILENAME = N'","")
				
				If([System.IO.Path]::GetExtension($OldDBFile) -ieq ".ldf")
				{
					#Log File.
					$Path = $NewLogPath 
					$Extension = ".LDF"
				}
				else {
					#Data File.
					$Path = $NewDataPath 
					$Extension = [System.IO.Path]::GetExtension($OldDBFile)
				}
				
				$UpdatedDBFile = $Path + "\" + $DatabaseName + "\" + [System.IO.Path]::GetFileName($OldDBFile)
				$LineToWrite = $Line.Replace($OldDBFile, $UpdatedDBFile)
				
				$ListOfNewDirectories += [System.IO.Path]::GetDirectoryName($UpdatedDBFile)

			}
			
			#Write the file...
			$LineToWrite | Out-File -LiteralPath $NewFileName -Append -Encoding UTF8
		}
				
	}

	#Write the list of directories (as a ps1, natch)...
	$NewFileName = [System.IO.Path]::Combine($DestinationDirectory, "!BuildDirectories.ps1")
	
	If((Test-Path -LiteralPath $NewFileName -PathType Leaf) -eq $true)
	{
		Remove-Item -Path $NewFileName -Force -ErrorAction SilentlyContinue | Out-Null 
	}
	
	ForEach($Dir In $ListOfNewDirectories)
	{
	
		$Command = New-Object system.Text.StringBuilder
		$Command.AppendLine("if((test-path -literalpath '$($Dir)' -pathtype container) -eq `$false)") | Out-Null
		$Command.AppendLine("{") | Out-Null
		$Command.AppendLine("`tnew-item -path '$($Dir)' -itemtype container | Out-Null") | Out-Null
		$Command.AppendLine("}") | Out-Null
		$Command.AppendLine() | Out-Null
		
		$Command.ToString() | Out-File -LiteralPath $NewFileName -Append -Encoding UTF8		
	
	}
	
}

Function Write-SQLRestoreScript([String[]]$BackupFiles, [string[]]$DiffBackupFiles=@(), [String[]]$LogFiles=@(), [string]$STOPAT="", [string]$TargetServerInstance, [string]$TargetDBName, [string]$ExportPath, [switch]$Recover=$false)
{

	If((Test-Path -LiteralPath $ExportPath -PathType Container) -eq $false)
	{
		New-Item -Path $ExportPath -ItemType container | Out-Null 
	}

	#Load SSMS
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 
	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $TargetServerInstance
	$Database = $SMO.databases[$TargetDBName]
	
	#Hold the backup commands...
	$BackupCommand = New-Object system.Text.StringBuilder
	
	#Get the list of files in the backup...
	$Query = "RESTORE FILELISTONLY FROM DISK=N'$($BackupFiles[0])'"
	$DBFilesFromBackup = $DBFilesFromBackup = ($Database.ExecuteWithResults($Query)).Tables[0]
	
	#Get the list of files the database expects.
	$Query = "USE [" + $Database.Name + "] SELECT name, physical_name, type_desc FROM sys.database_files ORDER BY [type], size DESC"
	$DBFilesInDatabase = ($Database.ExecuteWithResults($Query)).Tables[0]
	
	#Backup Command Header
	$BackupCommand.AppendLine("/**") | Out-Null 
	$BackupCommand.AppendLine("Restoring Database $($Database.Name)") | Out-Null 
	$BackupCommand.AppendLine("To Server $($TargetServerInstance)") | Out-Null 
	$BackupCommand.AppendLine("**/") | Out-Null 
	
	#Backup Command Single User
	$BackupCommand.AppendLine().AppendLine("--Set to Single User") | Out-Null 
	$BackupCommand.AppendLine("ALTER DATABASE [$($Database.Name)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;") | Out-Null 
	
	#Backup Command Restore
	$BackupCommand.AppendLine().AppendLine("--Restore Database") | Out-Null 
	$BackupCommand.AppendLine("USE [master]") | Out-Null 
	$BackupCommand.AppendLine("RESTORE DATABASE [$($Database.Name)]") | Out-Null 
	
	#Build FROM DISK portion of command.
	$IsFirstDisk = $true 
	ForEach($B in $BackupFiles)
	{
	
		If($IsFirstDisk -eq $true)
		{
			$BackupCommand.AppendLine("FROM DISK = N'$($B)'") | Out-Null 
		}
		else
		{
			$BackupCommand.AppendLine("`t, DISK = N'$($B)'") | Out-Null 
		}
		
		$IsFirstDisk = $false 
	
	}
	
	#Backup Command WITH OPTIONS
	$BackupCommand.AppendLine("WITH REPLACE, NORECOVERY, STATS = 5") | Out-Null 
	
	#Backup Command MOVE
	ForEach($B In $DBFilesFromBackup)
	{
		$BackupCommand.AppendLine("`t, MOVE N'$($B.LogicalName)' TO '" + ($DBFilesInDatabase | Where-Object -FilterScript {$_.name -eq $B.LogicalName} | Select-Object -First 1 -ExpandProperty physical_name) + "'") | Out-Null
	}
	
	$BackupCommand.Append(";") | Out-Null
	
	<# Build out DIFF restores #>
	If(@($DiffBackupFiles).count -ne 0)
	{
	
		#Backup Command Restore
		$BackupCommand.AppendLine() | Out-Null
		$BackupCommand.AppendLine().AppendLine("--Restore Differential Database") | Out-Null 
		$BackupCommand.AppendLine("USE [master]") | Out-Null 
		$BackupCommand.AppendLine("RESTORE DATABASE [$($Database.Name)]") | Out-Null 
		
		$IsFirstDisk = $true 
		ForEach($B in $DiffBackupFiles)
		{
		
			If($IsFirstDisk -eq $true)
			{
				$DiffBackupFiles.AppendLine("FROM DISK = N'$($B)'") | Out-Null 
			}
			else
			{
				$DiffBackupFiles.AppendLine("`t, DISK = N'$($B)'") | Out-Null 
			}
			
			$IsFirstDisk = $false 
		
		}
		
		#Backup Command WITH OPTIONS
		$BackupCommand.AppendLine("WITH NORECOVERY, STATS = 5") | Out-Null 
		
	}
	
	
	#TODO!  Build Commands for processing subsequent log file restores. Include STOPAT for customization
	ForEach($LogFile IN $LogFiles)
	{
	
		$BackupCommand.AppendLine(" ") | Out-Null 
		$BackupCommand.AppendLine(" ") | Out-Null 
		$BackupCommand.AppendLine("--Restore Log File $($LogFile)") | Out-Null 
		$BackupCommand.AppendLine("RESTORE LOG [$($Database.Name)] FROM DISK=N'$($LogFile)'") | Out-Null 
		
		IF([string]::IsNullOrEmpty($STOPAT) -eq $false)
		{
			$BackupCommand.AppendLine("`t WITH NORECOVERY, NOUNLOAD, STATS=5, STOPAT = N'$($STOPAT)'") | Out-Null 
		}
		else {
			$BackupCommand.AppendLine("`t WITH NORECOVERY, NOUNLOAD, STATS=5") | Out-Null 
		}
		
		$BackupCommand.AppendLine(";") | Out-Null 
	
	}
	
	$BackupCommand.AppendLine() | Out-Null
	$BackupCommand.AppendLine() | Out-Null
	
	IF($Recover -eq $true)
	{
		$BackupCommand.AppendLine("/** Not Set to automatically recover, but here are the statements") | Out-Null
	}

	if($Recover -eq $true)
	{
		#Backup Command RECOVERY
		
		$BackupCommand.AppendLine("--Recover") | Out-Null
		$BackupCommand.AppendLine("RESTORE DATABASE [$($Database.Name)] WITH RECOVERY;") | Out-Null
		
		#Backup Command MULTI_USER
		$BackupCommand.AppendLine() | Out-Null
		$BackupCommand.AppendLine("--Set to multi-user") | Out-Null
		$BackupCommand.AppendLine("ALTER DATABASE [$($Database.Name)] SET MULTI_USER;") | Out-Null
	}
	
	IF($Recover -eq $true)
	{
		$BackupCommand.AppendLine("**/") | Out-Null
	}
	
	#Where are we writing the file to?
	$DBName = ConvertTo-ValidPath -TestPath ($Database.name)
	$FileName = [System.IO.Path]::Combine($ExportPath, "$($DBName)-Restore.sql")
	
	$BackupCommand.ToString() | Out-File -LiteralPath $FileName -Encoding UTF8 -Force 

}

Function Get-LatestFullBackup([string]$ServerInstance, [string]$DatabaseName)
{

	$Query = ";WITH LatestSet
			AS (
			SELECT bs.database_name
				, bs.[type]
				, MAX(bs.media_set_id) AS Latest_SetID
			FROM msdb.dbo.backupset bs
			GROUP BY bs.database_name
				, bs.[type]
			)
			SELECT LatestSet.*
				,  mf.physical_device_name
			FROM LatestSet 
				INNER JOIN msdb.dbo.backupmediaset AS ms ON LatestSet.Latest_SetID = ms.media_set_id
				INNER JOIN msdb.dbo.backupmediafamily AS mf ON ms.media_set_id = mf.media_set_id
			WHERE LatestSet.database_name = '$($DatabaseName)'
				AND LatestSet.[type] = 'D'"
				
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 
	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance
	$Database = $SMO.databases["msdb"]
	
	$ListOfFiles = @()
	
	#$Data = ($Database.ExecuteWithResults($Query))
	
	ForEach($Row In ((($Database.ExecuteWithResults($Query)).Tables[0]).Rows))
	{
	
		$ListOfFiles += $Row.physical_device_name
	
	}
	
	Write-Output $ListOfFiles

}

Function Get-LatestLogBackup([string]$ServerInstance, [string]$DatabaseName)
{

	$Query = ";WITH LatestSet
				AS (
				SELECT bs.database_name
					, bs.[type]
					, MAX(bs.media_set_id) AS Latest_SetID
				FROM msdb.dbo.backupset bs
				WHERE [type] IN ('I', 'D')
				GROUP BY bs.database_name
					, bs.[type]
				)
				SELECT mf.physical_device_name
				FROM msdb.dbo.backupmediaset AS ms 
					INNER JOIN msdb.dbo.backupmediafamily AS mf ON ms.media_set_id = mf.media_set_id
					INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = ms.media_set_id
				WHERE bs.database_name = '$($DatabaseName)'
					AND bs.[type] = 'L'
					AND bs.media_set_id >= (SELECT TOP 1 L.Latest_SetID 
												FROM LatestSet L 
												WHERE L.database_name = bs.database_name 
												ORDER BY L.Latest_SetID DESC)"
				
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 
	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance
	$Database = $SMO.databases["msdb"]
	
	$ListOfFiles = @()
	
	#$Data = ($Database.ExecuteWithResults($Query))
	
	ForEach($Row In ((($Database.ExecuteWithResults($Query)).Tables[0]).Rows))
	{
	
		$ListOfFiles += $Row.physical_device_name
	
	}
	
	Write-Output $ListOfFiles

}

Function Get-LatestDiffBackup([string]$ServerInstance, [string]$DatabaseName)
{

	$Query = ";WITH LatestSet
			AS (
			SELECT bs.database_name
				, bs.[type]
				, MAX(bs.media_set_id) AS Latest_SetID
			FROM msdb.dbo.backupset bs
			GROUP BY bs.database_name
				, bs.[type]
			)
			SELECT LatestSet.*
				,  mf.physical_device_name
			FROM LatestSet 
				INNER JOIN msdb.dbo.backupmediaset AS ms ON LatestSet.Latest_SetID = ms.media_set_id
				INNER JOIN msdb.dbo.backupmediafamily AS mf ON ms.media_set_id = mf.media_set_id
			WHERE LatestSet.database_name = '$($DatabaseName)'
				AND LatestSet.[type] = 'I'"
				
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 
	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance
	$Database = $SMO.databases["msdb"]
	
	$ListOfFiles = @()
	
	#$Data = ($Database.ExecuteWithResults($Query))
	
	ForEach($Row In ((($Database.ExecuteWithResults($Query)).Tables[0]).Rows))
	{
	
		$ListOfFiles += $Row.physical_device_name
	
	}
	
	Write-Output $ListOfFiles

}

Function Get-PathChangeObject([string]$OldPath = "", [string]$NewPaths="")
{

	$O = New-Object PSCustomObject
	$O | Add-Member -Name "OriginalPathRoot" -MemberType NoteProperty -Value $OldPath
	$O | Add-Member -Name "UpdatedPathRoot" -MemberType NoteProperty -Value $NewPaths
	
	Write-Output $O
	
}

Function Set-PathUpdate([String[]]$Paths, [Management.Automation.PSObject]$PathUpdater)
{

	$NewPaths = @()

	ForEach($P In $Paths)
	{
		ForEach($U in $PathUpdater)
		{
			If($P -ilike ($U.OriginalPathRoot + "*"))
			{
				$NewP = $P -ireplace $U.OriginalPathRoot, $U.UpdatedPathRoot
				$NewPaths += $NewP
			}
			else {
				$NewPaths += $P
			}
		}
	}
	
	Write-Output $NewPaths

}

Function Write-AllDBRestoreScripts([string]$SourceServerInstance, [string]$TargetServerInstance, [string]$ExportPath, [Management.Automation.PSObject[]]$PathUpdater = @())
{

	If((Test-Path -LiteralPath $ExportPath -PathType Container) -eq $false)
	{
		New-Item -Path $ExportPath -ItemType container | Out-Null 
	}
	
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 
	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $SourceServerInstance
	
	ForEach($Database In ($SMO.Databases | Where-Object -FilterScript {$_.IsSystemObject -eq $false}))
	{
	
		$BackupFiles = @(Get-LatestFullBackup -ServerInstance $SourceServerInstance -DatabaseName $Database.name)
		$DiffBackups = @(Get-LatestDiffBackup -ServerInstance $SourceServerInstance -DatabaseName $Database.name)
		$LogBackups = @(Get-LatestLogBackup -ServerInstance $SourceServerInstance -DatabaseName $Database.name)
		
		If($PathUpdater.Count -ge 0)
		{
			$BackupFiles = Set-PathUpdate -Paths $BackupFiles -PathUpdater $PathUpdater
			$DiffBackups = Set-PathUpdate -Paths $DiffBackups -PathUpdater $PathUpdater
			$LogBackups = Set-PathUpdate -Paths $LogBackups -PathUpdater $PathUpdater
		}
		
		If($BackupFiles.Count -ne 0)
		{
			
			Write-SQLRestoreScript -BackupFiles $BackupFiles -DiffBackupFiles $DiffBackups -LogFiles $LogBackups -TargetServerInstance $TargetServerInstance -TargetDBName $Database.name -ExportPath $ExportPath
			
		}
	
	}

}

Function Get-TimeTrackerObject
{

	$O = New-Object PSCustomObject
	$O | Add-Member -Name "FileName" -MemberType NoteProperty -Value ""
	$O | Add-Member -Name "Start" -MemberType NoteProperty -Value ""
	$O | Add-Member -Name "End" -MemberType NoteProperty -Value ""
	$O | Add-Member -Name "Duration" -MemberType NoteProperty -Value ""
	
	Write-Output $O

}

Function Run-Scripts([string]$ServerInstance, [string]$Database="master", [string]$SourceDirectory)
{
	
	$TimeTracker = @()
	
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 
	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance
	$SMO.ConnectionContext.StatementTimeout=0

	ForEach($File In Get-ChildItem -LiteralPath $SourceDirectory -File)
	{
	
		if([System.IO.Path]::GetExtension($File.FullName) -ieq ".ps1")
		{
		
			Write-Debug -Message "$(Get-Date) - Running $($File.FullName)"
			
			$DateStart = Get-Date
			
			$Query = Get-Content -LiteralPath $File.FullName -Raw
			
			Invoke-Command -ScriptBlock {$Query}
			
			$DateEnd = Get-Date
			
			$Timer = Get-TimeTrackerObject
			$Timer.FileName = $File.FullName
			$Timer.Start = $DateStart.ToString("MM/dd/yyyy HH:mm:ss tt")
			$Timer.End = $DateEnd.ToString("MM/dd/yyyy HH:mm:ss tt")
			$Timer.Duration = (New-TimeSpan -Start $DateStart -End $DateEnd).Minutes
			
			$TimeTracker += $Timer
		
		}
		
		if([System.IO.Path]::GetExtension($File.FullName) -ieq ".sql")
		{
		
			Write-Debug -Message "$(Get-Date) - Running $($File.FullName)"
			
			$DateStart = Get-Date
			
			$DB = $SMO.databases[$Database]
			$Query = Get-Content -LiteralPath $File.FullName -Raw 
			$DB.ExecuteNonQuery($Query)
			
			$DateEnd = Get-Date
			
			$Timer = Get-TimeTrackerObject
			$Timer.FileName = $File.FullName
			$Timer.Start = $DateStart.ToString("MM/dd/yyyy HH:mm:ss tt")
			$Timer.End = $DateEnd.ToString("MM/dd/yyyy HH:mm:ss tt")
			$Timer.Duration = (New-TimeSpan -Start $DateStart -End $DateEnd).Minutes
			
			$TimeTracker += $Timer
		
		}
	
	}
	
	Write-Output $TimeTracker

}

Function Set-OwnerToSA([string]$ServerInstance)
{

	#Get the Additional Modules needed for doing the work.
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 

	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance 
	
	ForEach($Database In ($SMO.databases | Where-Object -FilterScript {$_.IsSystemObject -eq $false}))
	{
	
		$Database.SetOwnwer("sa",$true)
		$Database.Alter()
	
	}

}

Function Set-DatabaseCompatibility([string]$ServerInstance)
{

	#Get the Additional Modules needed for doing the work.
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 
	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance 
	
	$modelLevel = $SMO.databases["model"].CompatibilityLevel
	
	ForEach($Database In ($SMO.databases | Where-Object -FilterScript {$_.IsSystemObject -eq $false}))
	{
	
		If($Database.CompatibilityLevel -ne $modelLevel)
		{
			$Database.CompatibilityLevel = $modelLevel
			$Database.Alter()
		}
	
	}

}

Function Set-AgentJobsDisable([string]$ServerInstance)
{

	#Get the Additional Modules needed for doing the work.
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 

	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance 

	ForEach($Job In ($SMO.JobServer.Jobs | Where-Object -FilterScript {$_.name -ne ""}))
	{
	
		$Job.IsEnabled = $false
		$Job.Alter()
	
	}
	
}

Function Set-AgentJobsEnable([string]$ServerInstance)
{

	#Get the Additional Modules needed for doing the work.
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 

	$SMO = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance 

	ForEach($Job In ($SMO.JobServer.Jobs | Where-Object -FilterScript {$_.name -ne ""}))
	{
	
		$Job.IsEnabled = $true
		$Job.Alter()
	
	}
	
}
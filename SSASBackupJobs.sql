-- ITEMS TO BE REPLACED IN THIS SCRIPT:
-- [target server]: Replace with the name of the SSAS server receiving backups
-- [backup directory]: Replace with the folder or share where backups will be stored/purged
-- [days to keep]: Replace with the number of days backups should be kept
-- [password]: Password used to encrypt backup files
-- ASSIGN A SCHEDULE TO THE JOB AFTER RUNNING THIS SCRIPT

USE [msdb]
GO

/****** Object:  Job [SSAS Database Backups]    Script Date: 1900-01-01-1900:00:00 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 1900-01-01-1900:00:00 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'SSAS Database Backups',
		@enabled=1,
		@notify_level_eventlog=0,
		@notify_level_email=0,
		@notify_level_netsend=0,
		@notify_level_page=0,
		@delete_level=0,
		@description=N'No description available.',
		@category_name=N'[Uncategorized (Local)]',
		@owner_login_name=N'DBA', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Backup Databases]    Script Date: 1900-01-01-1900:00:00 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Backup Databases',
		@step_id=1,
		@cmdexec_success_code=0,
		@on_success_action=3,
		@on_success_step_id=0,
		@on_fail_action=2,
		@on_fail_step_id=0,
		@retry_attempts=0,
		@retry_interval=0,
		@os_run_priority=0, @subsystem=N'PowerShell',
		@command=N'[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.AnalysisServices") > $NULL
$Server = New-Object Microsoft.AnalysisServices.Server
If ($? -eq $False)
{
      Throw "Cannot load Analysis Services assembly"
      EXIT
}

$Server.Connect("DataSource=[target server]")
If ($Server.Connected -eq $False)
{
      Throw "Cannot connect to [target server]"
      EXIT
}

# $BackupDir=($Server.Serverproperties |where-Object {$_.Name -eq "BackupDir"}).Value
# if ($BackupDir -eq "" -or $BackupDir -eq $NULL -or (Test-Path $BackupDir) -eq $False)
# {
       $BackupDir="[backup directory]"
# }

$Mydate=(Date).ToString()
$Mydate=$Mydate.Replace(":"," ")
$Mydate=$Mydate.Replace("/"," ")
$Mydate="_" +$Mydate.Replace(" ","_")

$DBCollection=$Server.Databases

ForEach($DB in $DBCollection)

{
    $BackupFileName=$BackupDir+"\"+$DB.Name+$Mydate+"$.abf"
    $DB.Backup($BackupFilename,$True,$True,$NULL,$True,''[password]'')
    Write-Output ($DB.Name + " backed up.")
}

$Server.Disconnect',
		@database_name=N'master',
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Cleanup old backups]    Script Date: 1900-01-01-1900:00:00 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Cleanup old backups',
		@step_id=2,
		@cmdexec_success_code=0,
		@on_success_action=1,
		@on_success_step_id=0,
		@on_fail_action=2,
		@on_fail_step_id=0,
		@retry_attempts=0,
		@retry_interval=0,
		@os_run_priority=0, @subsystem=N'PowerShell',
		@command=N'$Now = Get-Date
$Days = "[days to keep]"
$TargetFolder = "[backup directory]"

$Success = New-PSDrive -Name Z -PSProvider FileSystem -Root $TargetFolder

$LastWrite = $Now.AddDays(-$days)
$Files = get-childitem "Z:\*" -include *$.abf | Where {$_.LastWriteTime -le "$LastWrite"} | sort-object LastWriteTime

foreach ($File in $Files)
{
	$file12 = $file.name
	If ($file12 -ne $null)
	{
		Write-Output "Deleting File $file12"
		Remove-Item Z:\$File12 -force | out-null
	}
}

Remove-PSDrive -Name Z',
		@database_name=N'master',
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO



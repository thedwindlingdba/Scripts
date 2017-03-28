IF NOT EXISTS (SELECT 1 FROM master.sys.databases WHERE name='xiodba')
CREATE DATABASE xiodba

IF NOT EXISTS (SELECT 1 FROM xiodba.sys.objects WHERE name='TableCheck')
CREATE TABLE xiodba.dbo.TableCheck (StartDatabase nvarchar(256), StartTable nvarchar(256))

TRUNCATE TABLE xiodba.dbo.TableCheck
INSERT INTO xiodba.dbo.TableCheck
VALUES ('xiodba','dbo.TableCheck')

USE xiodba

IF EXISTS (SELECT 1 FROM xiodba.sys.objects WHERE name='NewIntegrityCheck')
DROP PROCEDURE NewIntegrityCheck
GO

USE [xiodba]
GO

/****** Object:  StoredProcedure [dbo].[NewIntegrityCheck]    Script Date: 01-01-1900 9:07:08 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[NewIntegrityCheck]

AS

BEGIN

SET NOCOUNT ON
--These variables are used to make sure the loop terminates if
--it gets through all the DBs in one go. When the loop hits the
--last DB on the instance, it sets @HasLooped to 1, which lets it
--know that if it reaches or passes the start database and table,
--it should stop. 99.999% of the time, it would be fine just to
--check if the current database and table match the start database
--and table, but I wanted to account for the possibility that the
--start table is renamed or dropped.

DECLARE @StartDatabase nvarchar(256)
DECLARE @StartTable nvarchar(256)
DECLARE @HasLooped bit=0

DECLARE @CurrentDatabase nvarchar(256)
DECLARE @CurrentTable nvarchar(256)

DECLARE @CurrentCommand nvarchar(max)

DECLARE @ErrorMessages nvarchar(max)=''



SELECT
@StartDatabase=ISNULL(StartDatabase,''),
@StartTable=ISNULL(StartTable,'')
FROM xiodba.dbo.TableCheck


SELECT
@StartDatabase=ISNULL(@StartDatabase,''),
@StartTable=ISNULL(@StartTable,'')

IF @StartDatabase=''
SET @StartTable=''

SELECT TOP 1 @CurrentDatabase=name
FROM master.sys.databases
WHERE name>=@StartDatabase
AND state=0
ORDER BY name ASC

SELECT @CurrentTable=@StartTable


-- This code, from here until the WHILE @HasLooped=0..., is the code that advances
-- to the next table, or if there is no next table, the next database.
-- There's one instance of it here, outside the loop (to initialize),
-- and one inside the loop to advance.

SET @CurrentCommand='SET @CurrentTableInner=(
SELECT TOP 1 s.name+''.''+t.name AS SchemaTable
FROM '+QUOTENAME(@CurrentDatabase)+'.sys.tables t
INNER JOIN '+QUOTENAME(@CurrentDatabase)+'.sys.schemas s
ON t.schema_id=s.schema_id
WHERE s.name+''.''+t.name>@StartTAbleInner
ORDER by SchemaTable asc)'



BEGIN TRY
EXECUTE sp_executesql @CurrentCommand,
N'@StartTableInner nvarchar(256),
@CurrentTableInner nvarchar(256) OUTPUT',
@StartTableInner=@CurrentTable,
@CurrentTableInner=@CurrentTable OUTPUT
END TRY
BEGIN CATCH
SET @ErrorMessages=@ErrorMessages+ERROR_MESSAGE()+' This occurred when executing the following command:'+CHAR(13)+CHAR(10)+@CurrentCommand+CHAR(13)+CHAR(10)+'With @StartTableInner set to '+@CurrentTable+CHAR(13)+CHAR(10)
END CATCH


WHILE @CurrentTable IS NULL OR @CurrentTable=''

	BEGIN

	SET @CurrentDatabase=(SELECT TOP 1 name
	FROM master.sys.databases
	WHERE name>@CurrentDatabase
	AND name NOT IN ('tempdb') and state=0
	ORDER BY name ASC)

		WHILE @CurrentDatabase IS NULL



		BEGIN

		SET @CurrentDatabase=(SELECT TOP 1 name
		FROM master.sys.databases
		WHERE name not IN ('tempdb')
		ORDER BY name ASC)

		SET @HasLooped=1


		END




	SET @CurrentCommand='SET @CurrentTableInner=(
	SELECT TOP 1 s.name+''.''+t.name SchemaTable
	FROM '+QUOTENAME(@CurrentDatabase)+'.sys.tables t
	INNER JOIN '+QUOTENAME(@CurrentDatabase)+'.sys.schemas s
	ON t.schema_id=s.schema_id
	ORDER by SchemaTable asc)'

	BEGIN TRY
	EXECUTE sp_executesql @CurrentCommand,
		N'@CurrentTableInner nvarchar(256) OUTPUT',
		@CurrentTableInner=@CurrentTable OUTPUT
	END TRY
	BEGIN CATCH
		SET @ErrorMessages=@ErrorMessages+ERROR_MESSAGE()+' This occurred when executing the following command:'+CHAR(13)+CHAR(10)+@CurrentCommand+CHAR(13)+CHAR(10)
	END CATCH


	BEGIN TRY
		DBCC CHECKALLOC (@CurrentDatabase) WITH NO_INFOMSGS
	END TRY
	BEGIN CATCH
		SET @ErrorMessages=@ErrorMessages+ERROR_MESSAGE()+' This occurred when executing CHECKALLOC on '+@CurrentDatabase+CHAR(13)+CHAR(10)
	END CATCH


	BEGIN TRY
		DBCC CHECKCATALOG (@CurrentDatabase)
	END TRY
	BEGIN CATCH
		SET @ErrorMessages=@ErrorMessages+ERROR_MESSAGE()+' This occurred when executing CHECKCATALOG on '+@CurrentDatabase+CHAR(13)+CHAR(10)
	END CATCH

END

WHILE @HasLooped=0 OR @CurrentDatabase<@StartDatabase OR @CurrentTable<@StartTable

BEGIN


PRINT 'Datetime: '+CONVERT(nvarchar,GETDATE(),120)
PRINT 'Table: '+@CurrentDatabase+'.'+@CurrentTable



SET @CurrentCommand='USE '+QUOTENAME(@CurrentDatabase)+'
DBCC CHECKTABLE (@CurrentTableInner) WITH NO_INFOMSGS'


EXECUTE sp_executesql
@CurrentCommand,
N'@CurrentTableInner nvarchar(256)',
@CurrentTableInner=@CurrentTable


UPDATE xiodba.dbo.TableCheck
SET StartDatabase=@CurrentDatabase,
StartTable=@CurrentTable

SET @CurrentCommand='SET @CurrentTableInner=(
SELECT TOP 1 s.name+''.''+t.name AS SchemaTable
FROM '+QUOTENAME(@CurrentDatabase)+'.sys.tables t
INNER JOIN '+QUOTENAME(@CurrentDatabase)+'.sys.schemas s
ON t.schema_id=s.schema_id
WHERE s.name+''.''+t.name>@StartTAbleInner
ORDER by SchemaTable asc)'


BEGIN TRY
EXECUTE sp_executesql @CurrentCommand,
N'@StartTableInner nvarchar(256),
@CurrentTableInner nvarchar(256) OUTPUT',
@StartTableInner=@CurrentTable,
@CurrentTableInner=@CurrentTable OUTPUT
END TRY
BEGIN CATCH
SET @ErrorMessages=@ErrorMessages+ERROR_MESSAGE()+' This occurred when executing the following command:'+CHAR(13)+CHAR(10)+@CurrentCommand+CHAR(13)+CHAR(10)+'With @StartTableInner set to '+@CurrentTable+CHAR(13)+CHAR(10)
END CATCH


WHILE @CurrentTable IS NULL OR @CurrentTable=''

BEGIN

SET @CurrentDatabase=(SELECT TOP 1 name
FROM master.sys.databases
WHERE name>@CurrentDatabase
AND name NOT IN ('tempdb') and state=0
ORDER BY name ASC)

WHILE @CurrentDatabase IS NULL

BEGIN

SET @CurrentDatabase=(SELECT TOP 1 name
FROM master.sys.databases
WHERE name NOT IN ('tempdb') and state=0
ORDER BY name ASC)

SET @HasLooped=1
 cc

END


SET @CurrentCommand='SET @CurrentTableInner=(
SELECT TOP 1 s.name+''.''+t.name SchemaTable
FROM '+QUOTENAME(@CurrentDatabase)+'.sys.tables t
INNER JOIN '+QUOTENAME(@CurrentDatabase)+'.sys.schemas s
ON t.schema_id=s.schema_id
ORDER by SchemaTable asc)'

BEGIN TRY
EXECUTE sp_executesql @CurrentCommand,
N'@CurrentTableInner nvarchar(256) OUTPUT',
@CurrentTableInner=@CurrentTable OUTPUT
END TRY
BEGIN CATCH
SET @ErrorMessages=@ErrorMessages+ERROR_MESSAGE()+' This occurred when executing the following command:'+CHAR(13)+CHAR(10)+@CurrentCommand+CHAR(13)+CHAR(10)
END CATCH

BEGIN TRY
DBCC CHECKALLOC (@CurrentDatabase) WITH NO_INFOMSGS
END TRY
BEGIN CATCH
SET @ErrorMessages=@ErrorMessages+ERROR_MESSAGE()+' This occurred when executing CHECKALLOC on '+@CurrentDatabase+CHAR(13)+CHAR(10)
END CATCH


BEGIN TRY
DBCC CHECKCATALOG (@CurrentDatabase)
END TRY
BEGIN CATCH
SET @ErrorMessages=@ErrorMessages+ERROR_MESSAGE()+' This occurred when executing CHECKCATALOG on '+@CurrentDatabase+CHAR(13)+CHAR(10)
END CATCH


END


END

END


IF @ErrorMessages!=''
RAISERROR (@ErrorMessages, 15,1)




GO



USE [msdb]
GO

/****** Object:  Job [Cosentry_IntegrityCheck]    Script Date: 7/21/2015 9:46:15 AM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 7/21/2015 9:46:15 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Cosentry_IntegrityCheck',
		@enabled=1,
		@notify_level_eventlog=0,
		@notify_level_email=0,
		@notify_level_netsend=0,
		@notify_level_page=0,
		@delete_level=0,
		@description=N'No description available.',
		@category_name=N'[Uncategorized (Local)]',
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [CHECKTABLE]    Script Date: 7/21/2015 9:46:16 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'CHECKTABLE',
		@step_id=1,
		@cmdexec_success_code=0,
		@on_success_action=1,
		@on_success_step_id=0,
		@on_fail_action=2,
		@on_fail_step_id=0,
		@retry_attempts=0,
		@retry_interval=0,
		@os_run_priority=0, @subsystem=N'TSQL',
		@command=N'EXECUTE dbo.NewIntegrityCheck',
		@database_name=N'xioDBA',
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Cosentry_IntegrityCheck',
		@enabled=1,
		@freq_type=4,
		@freq_interval=1,
		@freq_subday_type=1,
		@freq_subday_interval=0,
		@freq_relative_interval=0,
		@freq_recurrence_factor=0,
		@active_start_date=20150612,
		@active_end_date=99991231,
		@active_start_time=010000,
		@active_end_time=235959,
		@schedule_uid=N''
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


USE [msdb]
GO

/****** Object:  Job [Cosentry_Kill_IntegrityCheck]    Script Date: 7/21/2015 9:49:00 AM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 7/21/2015 9:49:00 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Cosentry_Kill_IntegrityCheck',
		@enabled=1,
		@notify_level_eventlog=0,
		@notify_level_email=0,
		@notify_level_netsend=0,
		@notify_level_page=0,
		@delete_level=0,
		@description=N'No description available.',
		@category_name=N'[Uncategorized (Local)]',
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Cosentry_Kill_IntegrityCheck]    Script Date: 7/21/2015 9:49:00 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Cosentry_Kill_IntegrityCheck',
		@step_id=1,
		@cmdexec_success_code=0,
		@on_success_action=1,
		@on_success_step_id=0,
		@on_fail_action=2,
		@on_fail_step_id=0,
		@retry_attempts=0,
		@retry_interval=0,
		@os_run_priority=0, @subsystem=N'TSQL',
		@command=N'select job.Name, job.job_ID, job.Originating_Server, stop_execution_date,
activity.run_requested_Date  as Elapsed
from msdb.dbo.sysjobs_view job
inner join msdb.dbo.sysjobactivity activity
on (job.job_id = activity.job_id)
where run_Requested_date is not null and stop_execution_date is null
and datediff(minute, activity.run_requested_Date, getdate()) < 500
and job.name = ''Cosentry_IntegrityCheck''


if @@ROWCOUNT > 0
BEGIN
	EXEC dbo.sp_stop_job N''Cosentry_IntegrityCheck'';

END',
		@database_name=N'msdb',
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Cosentry_Kill_IntegrityCheck',
		@enabled=1,
		@freq_type=4,
		@freq_interval=1,
		@freq_subday_type=1,
		@freq_subday_interval=0,
		@freq_relative_interval=0,
		@freq_recurrence_factor=0,
		@active_start_date=20121121,
		@active_end_date=99991231,
		@active_start_time=060000,
		@active_end_time=235959,
		@schedule_uid=N''
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


USE [msdb]
GO

/****** Object:  Job [Cosentry_Reindexing]    Script Date: 7/21/2015 9:59:01 AM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 7/21/2015 9:59:01 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Cosentry_Reindexing',
		@enabled=1,
		@notify_level_eventlog=0,
		@notify_level_email=2,
		@notify_level_netsend=0,
		@notify_level_page=0,
		@delete_level=0,
		@description=N'New reindex script to run daily.',
		@category_name=N'[Uncategorized (Local)]',
		@owner_login_name=N'sa',
		@notify_email_operator_name=N'Xiolink', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [IndexOptimize]    Script Date: 7/21/2015 9:59:01 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'IndexOptimize',
		@step_id=1,
		@cmdexec_success_code=0,
		@on_success_action=1,
		@on_success_step_id=0,
		@on_fail_action=2,
		@on_fail_step_id=0,
		@retry_attempts=0,
		@retry_interval=0,
		@os_run_priority=0, @subsystem=N'CmdExec',
		@command=N'sqlcmd -d xioDBA -Q "EXECUTE [dbo].[IndexOptimize] @Databases = ''USER_DATABASES'',  @FragmentationMedium=NULL,  @SortInTempdb=''Y''" -b

',
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Cosentry_Reindexing',
		@enabled=1,
		@freq_type=4,
		@freq_interval=1,
		@freq_subday_type=1,
		@freq_subday_interval=0,
		@freq_relative_interval=0,
		@freq_recurrence_factor=0,
		@active_start_date=20150602,
		@active_end_date=99991231,
		@active_start_time=60000,
		@active_end_time=235959,
		@schedule_uid=N''
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


USE [msdb]
GO

/****** Object:  Job [Cosentry_Kill_Reindexing]    Script Date: 7/21/2015 00:00:00 AM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 7/21/2015 00:00:00 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Cosentry_Kill_Reindexing',
		@enabled=1,
		@notify_level_eventlog=0,
		@notify_level_email=0,
		@notify_level_netsend=0,
		@notify_level_page=0,
		@delete_level=0,
		@description=N'No description available.',
		@category_name=N'[Uncategorized (Local)]',
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Cosentry_Kill_Reindexing]    Script Date: 7/21/2015 00:00:00 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Cosentry_Kill_Reindexing',
		@step_id=1,
		@cmdexec_success_code=0,
		@on_success_action=1,
		@on_success_step_id=0,
		@on_fail_action=2,
		@on_fail_step_id=0,
		@retry_attempts=0,
		@retry_interval=0,
		@os_run_priority=0, @subsystem=N'TSQL',
		@command=N'select job.Name, job.job_ID, job.Originating_Server, stop_execution_date,
activity.run_requested_Date  as Elapsed
from msdb.dbo.sysjobs_view job
inner join msdb.dbo.sysjobactivity activity
on (job.job_id = activity.job_id)
where run_Requested_date is not null and stop_execution_date is null
and datediff(minute, activity.run_requested_Date, getdate()) < 500
and job.name = ''Cosentry_Reindexing''


if @@ROWCOUNT > 0
BEGIN
	EXEC dbo.sp_stop_job N''Cosentry_Reindexing'';

	EXEC msdb.dbo.sp_send_dbmail
	@profile_name = ''XIOLINK'',
   	@recipients = ''xioDBA@xiolink.com'',
    	@subject = ''Optimizations job killed on NG01DB'' ;
END',
		@database_name=N'msdb',
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Cosentry_Kill_Reindexing',
		@enabled=1,
		@freq_type=4,
		@freq_interval=1,
		@freq_subday_type=1,
		@freq_subday_interval=0,
		@freq_relative_interval=0,
		@freq_recurrence_factor=0,
		@active_start_date=20150612,
		@active_end_date=99991231,
		@active_start_time=80000,
		@active_end_time=235959,
		@schedule_uid=N''
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


/*
USE [msdb]
GO

/****** Object:  Job [Optimizations]    Script Date: 7/21/2015 00:00:00 AM ******/
EXEC msdb.dbo.sp_delete_job @job_name='Optimizations', @delete_unused_schedule=1
GO
*/


















--COPYRIGHT DUSTIN MARZOLF 2015
/* This material may not be copied or used without the explict permission of it's Author Dustin Marzolf.
*/







--========================================================================
USE [OakwoodDBA]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[TrueCacheHitQOSBase](
      [PageReads] [bigint] NOT NULL,
      [PageLookups] [bigint] NOT NULL,
      [InstanceStartTime] [datetime] NOT NULL,
      [TrueCacheHitRatio] [decimal] (4,1) NOT NULL
) ON [PRIMARY]

GO

--Populate the base table with the counter values at the time of creation

TRUNCATE TABLE OakwoodDBA.dbo.TrueCacheHitQOSBase
GO
INSERT INTO OakwoodDBA.dbo.TrueCacheHitQOSBase
SELECT PR.cntr_value,PL.cntr_value,I.create_date, CAST(((CAST((PL.cntr_value-Pr.cntr_value) as float)/PL.cntr_value)*100) as decimal(4,1))
FROM sys.dm_os_performance_counters PR
CROSS JOIN sys.dm_os_performance_counters PL
CROSS JOIN sys.databases I
WHERE PR.counter_name='Page Reads/sec' and PL.counter_name='Page Lookups/sec' and I.database_id=2
GO

--========================================================================
USE [msdb]
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'TrueCacheHitUpdate',
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

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'UpdateTrueCacheHit',
            @step_id=1,
            @cmdexec_success_code=0,
            @on_success_action=1,
            @on_success_step_id=0,
            @on_fail_action=2,
            @on_fail_step_id=0,
            @retry_attempts=0,
            @retry_interval=0,
            @os_run_priority=0, @subsystem=N'TSQL',
            @command=N'--Report the number of pages read from memory as a percentage of pages requested
--The CASE statement accounts for instance restarts. If the instance has been restarted
--since the last measurement, the reported value is just the number of pages read from
--memory as a percentage of total pages requested after the restart, since we don''t have
--the page reads and page lookups information from between the last measurement and
--the instance restart


UPDATE OakwoodDBA.dbo.TrueCacheHitQOSBase
SET PageReads=Pr.cntr_value, PageLookups=PL.cntr_value, InstanceStartTime=I.create_date,
TrueCacheHitRatio=CASE
WHEN QOS.InstanceStarttime=(select create_date from sys.databases where database_id=2) THEN CAST(((CAST(((PL.cntr_value-QOS.PageLookups)-(PR.cntr_value-QOS.PageReads)) as float)/(PL.cntr_value-QOS.PageLookups))*100) as decimal(4,1))
ELSE CAST(((CAST((PL.cntr_value-Pr.cntr_value) as float)/PL.cntr_value)*100) as decimal(4,1))
END
FROM sys.dm_os_performance_counters PR
CROSS JOIN sys.dm_os_performance_counters PL
CROSS JOIN sys.databases I
CROSS JOIN OakwoodDBA.dbo.trueCacheHitQOSBase QOS
WHERE PR.counter_name=''Page Reads/sec'' and PL.counter_name=''Page Lookups/sec'' and I.database_id=2

',
            @database_name=N'master',
            @flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'UpdateTrueCacheHit',
            @enabled=1,
            @freq_type=4,
            @freq_interval=1,
            @freq_subday_type=2,
            @freq_subday_interval=60,
            @freq_relative_interval=0,
            @freq_recurrence_factor=0,
            @active_start_date=20121220,
            @active_end_date=99991231,
            @active_start_time=0,
            @active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


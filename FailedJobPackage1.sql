
USE [DBA]
IF EXISTS ( SELECT * FROM sys.objects where name = 'customer_failed_jobs')
BEGIN
DROP TABLE DBA..customer_failed_jobs
END
GO

USE DBA
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO


CREATE TABLE [dbo].[customer_failed_jobs](
	[job_name] [varchar](max) NULL,
	[message] [varchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO


USE [msdb]
IF EXISTS ( SELECT * from msdb.dbo.sysoperators where name = 'Client Operator Failed Jobs')
BEGIN
EXEC sp_delete_operator
		@name = 'Client Operator Failed Jobs'
END
GO

USE msdb
GO
EXEC msdb.dbo.sp_add_operator @name=N'Client Operator Failed Jobs',
		@enabled=1,
		@weekday_pager_start_time=90000,
		@weekday_pager_end_time=180000,
		@saturday_pager_start_time=90000,
		@saturday_pager_end_time=180000,
		@sunday_pager_start_time=90000,
		@sunday_pager_end_time=180000,
		@pager_days=0,
		@category_name=N'[Uncategorized]'

GO



USE [msdb]
IF EXISTS( select * from msdb..sysjobs where name = 'Client_Job_Alert')
BEGIN
EXEC sp_delete_job
	@job_name = N'Client_Job_Alert';
END
GO

USE msdb
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 01-01-1900 9:13:42 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Client_Job_Alert',
		@enabled=1,
		@notify_level_eventlog=0,
		@notify_level_email=0,
		@notify_level_netsend=0,
		@notify_level_page=0,
		@delete_level=0,
		@description=N'This job returns a list of failed jobs and sends an email every morning.',
		@category_name=N'[Uncategorized (Local)]',
		@owner_login_name=N'username', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [job_failure]    Script Date: 01-01-1900 9:13:43 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'job_failure',
		@step_id=1,
		@cmdexec_success_code=0,
		@on_success_action=1,
		@on_success_step_id=0,
		@on_fail_action=2,
		@on_fail_step_id=0,
		@retry_attempts=0,
		@retry_interval=0,
		@os_run_priority=0, @subsystem=N'TSQL',
		@command=N'if exists (
select sj.name,
sjh.message
from msdb..sysjobs sj
inner join msdb..sysjobhistory sjh on sj.job_id = sjh.job_id
left join dba..JobCheckIgnore jci on sj.job_id = jci.job_id
left join
(select sj.name, max(convert(datetime,rtrim(run_date))+ (run_time*9+run_time%10000*6+run_time%100*10)/216e4) as last_run
from msdb..sysjobs sj
inner join msdb..sysjobhistory sjh on sj.job_id = sjh.job_id
and convert(datetime,rtrim(run_date))+ (run_time*9+run_time%10000*6+run_time%100*10)/216e4 > DATEADD(HH,-24,GETDATE())
and sjh.step_id = 1
group by sj.name) runstatus on runstatus.name = sj.name
where sjh.run_status = 0
and sjh.step_id = 0
and sj.enabled = 1
and jci.job_id is null
and convert(datetime,rtrim(run_date))+ (run_time*9+run_time%10000*6+run_time%100*10)/216e4 = runstatus.last_run
)
begin

insert into DBA..customer_failed_jobs

select sj.name,
sjh.message
from msdb..sysjobs sj
inner join msdb..sysjobhistory sjh on sj.job_id = sjh.job_id
left join dba..JobCheckIgnore jci on sj.job_id = jci.job_id
left join
(select sj.name, max(convert(datetime,rtrim(run_date))+ (run_time*9+run_time%10000*6+run_time%100*10)/216e4) as last_run
from msdb..sysjobs sj
inner join msdb..sysjobhistory sjh on sj.job_id = sjh.job_id
and convert(datetime,rtrim(run_date))+ (run_time*9+run_time%10000*6+run_time%100*10)/216e4 > DATEADD(HH,-24,GETDATE())
and sjh.step_id = 1
group by sj.name) runstatus on runstatus.name = sj.name
where sjh.run_status = 0
and sjh.step_id = 0
and sj.enabled = 1
and jci.job_id is null
and convert(datetime,rtrim(run_date))+ (run_time*9+run_time%10000*6+run_time%100*10)/216e4 = runstatus.last_run

declare @Subject VARCHAR(100)
select @Subject = ''Failed Jobs for server '' + @@servername
declare @oper_email nvarchar(100)
set @oper_email = (select email_address from msdb.dbo.sysoperators where name = ''Client Operator Failed Jobs'')

EXEC msdb.dbo.sp_send_dbmail
    @profile_name = ''EMAIL'',
    @recipients = @oper_email,
    @subject = @Subject,
	@body = ''This is a list of jobs that have failed in the last 24 hours. For more detail open SQL Server Managment Studio and navigate to SQL Server Agent > Jobs, then right click the job in question and select "View History".
	'',
    @query = N''SET NOCOUNT ON SELECT * FROM  DBA.dbo.customer_failed_jobs'',
  	@body_format = ''TEXT'',
	@query_result_header = 0

truncate table DBA..customer_failed_jobs
end',
		@database_name=N'master',
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Daily (8am)',
		@enabled=1,
		@freq_type=4,
		@freq_interval=1,
		@freq_subday_type=1,
		@freq_subday_interval=0,
		@freq_relative_interval=0,
		@freq_recurrence_factor=0,
		@active_start_date=20141230,
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
USE [DBA]
IF EXISTS (SELECT * FROM sys.objects where name = 'JobCheckIgnore')
BEGIN
DROP TABLE DBA.dbo.JobCheckIgnore;
END
GO
USE [DBA]
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[JobCheckIgnore](
	[job_ID] [uniqueidentifier] NULL,
	[job_name] [varchar](max) NULL
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO


DECLARE @JobId nvarchar(500)
DECLARE @Jname nvarchar(500)
DECLARE @JobIgnorePopCursor CURSOR

	SET @JobIgnorePopCursor = CURSOR FOR SELECT CAST(Job_Id as nvarchar(500)), Name FROM MSDB.DBO.sysjobs
	WHERE NAME IN
	( 'TrueCacheHitUpdate',
	  'BufferPoolTracking',
	  'Shrink Tlogs',
	  'performance stats collection',
	  'syspolicy_purge_history',
	  'Optimizations',
	  'Client_Job_Alert',
	  'DBA - Blocking',
	'Database Mirroring Monitor Job',
	'Backups.Cleanup Files',
	'Backups.Differential Backups',
	'Backups.TLog Backups',
	' Backups.Full Backups',
	' Backups.Differential',
	' Backups.Full',
	' Backups.Transaction',
	' lock tracking',
	'Optimizations Kill - 8:00 AM',
	'Optimizations Kill - 7:00 AM',
	'Optimizations Kill ',
	' Backups.Subplan_1',
	' Backups.Subplan_2',
	' Backups.Subplan_3',
	' Backups.Subplan_4',
	'_CHECKDB',
	'_Kill CHECKDB @ 5:00 AM',
	'_Kill Reindexing @ 8:00 AM',
	'_Reindexing',
	' Backups.Clean up backup files',
	'LSAlert_',
	'LSAlert_VDB03',
	'LSAlert-VDB04',
	'LSAlert-VDB01',
	'Kill optimization at 8 AM',
	' lock tracking',
	'RPT04 SSAS Database Backups',
	'RPT02 SSAS Database Backups',
	'RPT01 SSAS Database Backups',
	'RPT03 SSAS Database Backups',
	'Optimizations_SFABB01',
	'Optimizations_SFABB01 Kill - 3:50 AM',
	'StandardTraceTableMainteance',
	'Start SQL Trace',
	'_Reindexing',
	'_IntegrityCheck',
	'_Kill_IntegrityCheck',
	'_Kill_Reindexing',
	'Kill Optimizations at 8 AM'



	)


	OPEN @JobIgnorePopCursor

		FETCH NEXT FROM @JobIgnorePopCursor
		INTO @JobID, @Jname

		While @@FETCH_STATUS =0
			BEGIN
				INSERT INTO [DBA].[dbo].[JobCheckIgnore] SELECT  CONVERT(uniqueidentifier,@JobID) ,  @Jname

				FETCH NEXT FROM @JobIgnorePopCursor
				INTO @JobID, @Jname

			END
				CLOSE @JobIgnorePopCursor



DEALLOCATE @JobIgnorePopCursor
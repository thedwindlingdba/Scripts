USE [master]
GO
/****** Object:  Database [DBA]    Script Date: 8/6/2015 6:39:03 AM ******/
CREATE DATABASE [DBA]
 CONTAINMENT = NONE
 ON  PRIMARY
( NAME = N'DBA', SIZE = 8384KB , MAXSIZE = UNLIMITED, FILEGROWTH = 1024KB )
 LOG ON
( NAME = N'DBA_log', SIZE = 832KB , MAXSIZE = 2048GB , FILEGROWTH = 10%)
GO
ALTER DATABASE [DBA] SET COMPATIBILITY_LEVEL = 130
GO
IF (1 = FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'))
begin
EXEC [DBA].[dbo].[sp_fulltext_database] @action = 'enable'
end
GO
ALTER DATABASE [DBA] SET ANSI_NULL_DEFAULT OFF
GO
ALTER DATABASE [DBA] SET ANSI_NULLS OFF
GO
ALTER DATABASE [DBA] SET ANSI_PADDING OFF
GO
ALTER DATABASE [DBA] SET ANSI_WARNINGS OFF
GO
ALTER DATABASE [DBA] SET ARITHABORT OFF
GO
ALTER DATABASE [DBA] SET AUTO_CLOSE OFF
GO
ALTER DATABASE [DBA] SET AUTO_SHRINK OFF
GO
ALTER DATABASE [DBA] SET AUTO_UPDATE_STATISTICS ON
GO
ALTER DATABASE [DBA] SET CURSOR_CLOSE_ON_COMMIT OFF
GO
ALTER DATABASE [DBA] SET CURSOR_DEFAULT  GLOBAL
GO
ALTER DATABASE [DBA] SET CONCAT_NULL_YIELDS_NULL OFF
GO
ALTER DATABASE [DBA] SET NUMERIC_ROUNDABORT OFF
GO
ALTER DATABASE [DBA] SET QUOTED_IDENTIFIER OFF
GO
ALTER DATABASE [DBA] SET RECURSIVE_TRIGGERS OFF
GO
ALTER DATABASE [DBA] SET  ENABLE_BROKER
GO
ALTER DATABASE [DBA] SET AUTO_UPDATE_STATISTICS_ASYNC OFF
GO
ALTER DATABASE [DBA] SET DATE_CORRELATION_OPTIMIZATION OFF
GO
ALTER DATABASE [DBA] SET TRUSTWORTHY OFF
GO
ALTER DATABASE [DBA] SET ALLOW_SNAPSHOT_ISOLATION OFF
GO
ALTER DATABASE [DBA] SET PARAMETERIZATION SIMPLE
GO
ALTER DATABASE [DBA] SET READ_COMMITTED_SNAPSHOT OFF
GO
ALTER DATABASE [DBA] SET HONOR_BROKER_PRIORITY OFF
GO
ALTER DATABASE [DBA] SET RECOVERY FULL
GO
ALTER DATABASE [DBA] SET  MULTI_USER
GO
ALTER DATABASE [DBA] SET PAGE_VERIFY CHECKSUM
GO
ALTER DATABASE [DBA] SET DB_CHAINING OFF
GO
ALTER DATABASE [DBA] SET FILESTREAM( NON_TRANSACTED_ACCESS = OFF )
GO
ALTER DATABASE [DBA] SET TARGET_RECOVERY_TIME = 0 SECONDS
GO
ALTER DATABASE [DBA] SET DELAYED_DURABILITY = DISABLED
GO
USE [DBA]
GO


USE [DBA]
GO
/****** Object:  Table [dbo].[LatencyStats]    Script Date: 8/6/2015 6:52:39 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[LatencyStats]') AND type in (N'U'))
BEGIN
CREATE TABLE [dbo].[LatencyStats](
	[database_id] [int] NOT NULL,
	[start_time] [datetime] NOT NULL,
	[end_time] [datetime] NULL,
	[database_name] [varchar](255) NULL,
	[reads] [bigint] NULL,
	[writes] [bigint] NULL,
	[totalio] [bigint] NULL,
	[latency] [decimal](18, 3) NULL,
	[readlatency] [decimal](18, 3) NULL,
	[writelatency] [decimal](18, 3) NULL,
 CONSTRAINT [pk_LatencyStats] PRIMARY KEY CLUSTERED
(
	[database_id] ASC,
	[start_time] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO
SET ANSI_PADDING OFF
GO

/****** Object:  Table [dbo].[tmpLatencyStats]    Script Date: 8/6/2015 6:52:39 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tmpLatencyStats]') AND type in (N'U'))
BEGIN
CREATE TABLE [dbo].[tmpLatencyStats](
	[database_id] [int] NULL,
	[time] [datetime] NULL,
	[reads] [bigint] NULL,
	[writes] [bigint] NULL,
	[latency] [bigint] NULL,
	[readlatency] [bigint] NULL,
	[writelatency] [bigint] NULL
) ON [PRIMARY]
END
GO
/****** Object:  Table [dbo].[tmpWaitStats]    Script Date: 8/6/2015 6:52:39 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tmpWaitStats]') AND type in (N'U'))
BEGIN
CREATE TABLE [dbo].[tmpWaitStats](
	[time] [datetime] NULL,
	[wait_type] [varchar](255) NOT NULL,
	[wait_time_ms] [decimal](18, 3) NOT NULL,
	[waits] [bigint] NOT NULL
) ON [PRIMARY]
END
GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[TrueCacheHitQOSBase]    Script Date: 8/6/2015 6:52:39 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[TrueCacheHitQOSBase]') AND type in (N'U'))
BEGIN
CREATE TABLE [dbo].[TrueCacheHitQOSBase](
	[PageReads] [bigint] NOT NULL,
	[PageLookups] [bigint] NOT NULL,
	[InstanceStartTime] [datetime] NOT NULL,
	[TrueCacheHitRatio] [decimal](4, 1) NOT NULL
) ON [PRIMARY]
END
GO
--Populate the base table with the counter values at the time of creation

TRUNCATE TABLE DBA.dbo.TrueCacheHitQOSBase
GO
INSERT INTO DBA.dbo.TrueCacheHitQOSBase
SELECT PR.cntr_value,PL.cntr_value,I.create_date, CAST(((CAST((PL.cntr_value-Pr.cntr_value) as float)/PL.cntr_value)*100) as decimal(4,1))
FROM sys.dm_os_performance_counters PR
CROSS JOIN sys.dm_os_performance_counters PL
CROSS JOIN sys.databases I
WHERE PR.counter_name='Page Reads/sec' and PL.counter_name='Page Lookups/sec' and I.database_id=2
GO
/****** Object:  Table [dbo].[WaitStats]    Script Date: 8/6/2015 6:52:39 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[WaitStats]') AND type in (N'U'))
BEGIN
CREATE TABLE [dbo].[WaitStats](
	[start_time] [datetime] NOT NULL,
	[end_time] [datetime] NULL,
	[wait_type] [varchar](255) NOT NULL,
	[wait_time_ms] [decimal](18, 3) NOT NULL,
	[waits] [bigint] NOT NULL,
	[avg_wait_time_ms]  AS ([wait_time_ms]/[waits]),
 CONSTRAINT [pk_WaitStats] PRIMARY KEY CLUSTERED
(
	[start_time] ASC,
	[wait_type] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO
SET ANSI_PADDING OFF
GO
/****** Object:  StoredProcedure [dbo].[retrieveLatencyStats]    Script Date: 8/6/2015 6:52:39 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[retrieveLatencyStats]') AND type in (N'P', N'PC'))
BEGIN
EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE [dbo].[retrieveLatencyStats] AS'
END
GO

ALTER PROCEDURE [dbo].[retrieveLatencyStats] (@DaysToKeepLatency INT = 7)
AS
BEGIN

	BEGIN TRY
		BEGIN TRAN

		--Dump current virtual file stats into temporary table
		INSERT dbo.tmpLatencyStats (database_id, [time], reads, writes, latency, readlatency, writelatency)
		SELECT vfs.DBId,
		getdate(),
		SUM(numberreads) as reads,
		SUM(numberwrites) as Writes,
		SUM(IoStallMS) as latency,
		SUM(IoStallReadMS) as readlatency,

		SUM(IoStallWriteMS) as writelatency

		FROM ::fn_virtualfilestats(NULL,NULL) vfs
		group by vfs.dbid


		DECLARE @cnt INT

		SELECT @cnt=COUNT(Distinct [Time]) FROM dbo.tmpLatencyStats


		-- Previous stats have been recorded so now calculate the latency during that time period

		IF @cnt > 1

		BEGIN

			INSERT INTO [dbo].[LatencyStats]
				   ([database_id]
				   ,[start_time]
				   ,[end_time]
				   ,[database_name]
				   ,[reads]
				   ,[writes]
				   ,[totalio]
				   ,[latency]
				   ,[readlatency]
				   ,[writelatency])
			select pre.database_id, pre.[time], post.[time], cast(DB_NAME(pre.database_ID) as varchar(255)) as database_name,
				(post.reads-pre.reads) as Reads,
				(post.Writes-pre.writes) as Writes,
				(post.writes+post.reads)-(pre.writes+pre.reads) as TotalIO,
				case (post.reads+post.writes)-(pre.reads+pre.writes) when 0 then
					0
				else
					cast(cast(((post.readlatency+post.writelatency)-(pre.readlatency+pre.writelatency)) as float)/((post.reads+post.writes)-(pre.reads+pre.writes)) as decimal(18,3))
				end,
				case (post.reads-pre.reads) when 0 then
					0
				else
					cast(cast((post.readlatency-pre.readlatency) as float)/(post.reads-pre.reads) as decimal(18,3))
				end,
				case (post.writes-pre.writes) when 0 then
					0
				else
					cast(cast((post.writelatency-pre.writelatency) as float)/(post.writes-pre.writes) as decimal(18,3))
				end
			from (select [time],database_id,reads,writes,latency,readlatency,writelatency from dbo.tmpLatencyStats where [time] = (select min([time]) from dbo.tmpLatencyStats)) Pre
			inner join (select [time],database_id,reads,writes,latency,readlatency,writelatency from dbo.tmpLatencyStats where [time] = (select max([time]) from dbo.tmpLatencyStats)) Post
			on pre.database_id=post.database_id

			-- Get time to purge temporary data for
			declare @time datetime
			select @time=min([time]) from dbo.tmpLatencyStats


			-- purge temporary data
			delete dbo.tmpLatencyStats
			where [time]=@time
		END
	END TRY

	BEGIN CATCH
	IF @@TRANCOUNT > 0
		ROLLBACK TRAN

		DECLARE @ErrorMessage NVARCHAR(4000);
		DECLARE @ErrorSeverity INT;
		DECLARE @ErrorState INT;

		SELECT
			@ErrorMessage = ERROR_MESSAGE(),
			@ErrorSeverity = ERROR_SEVERITY(),
			@ErrorState = ERROR_STATE();

		-- Use RAISERROR inside the CATCH block to return error
		-- information about the original error that caused
		-- execution to jump to the CATCH block.
		RAISERROR (@ErrorMessage, -- Message text.
				   @ErrorSeverity, -- Severity.
				   @ErrorState -- State.
				   );

	END CATCH;

	IF @@TRANCOUNT > 0
		COMMIT TRAN

	-- Purge old data
	DELETE dbo.LatencyStats
	WHERE start_time < DATEADD(HOUR,-(@DaysToKeepLatency*24),getdate())

END


GO
/****** Object:  StoredProcedure [dbo].[retrieveWaitStats]    Script Date: 8/6/2015 6:52:39 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[retrieveWaitStats]') AND type in (N'P', N'PC'))
BEGIN
EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE [dbo].[retrieveWaitStats] AS'
END
GO

ALTER PROCEDURE [dbo].[retrieveWaitStats] (@DaysToKeepWaits INT = 7)
AS
BEGIN

	BEGIN TRY
		BEGIN TRAN

		--Dump current wait stats into temporary table
		INSERT dbo.tmpWaitStats ([time], [wait_type], [wait_time_ms], [waits])
		SELECT getdate(), wait_type, wait_time_ms, waiting_tasks_count
		FROM sys.dm_os_wait_stats
		WHERE wait_type NOT IN ('CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK',
			'SLEEP_SYSTEMTASK','SQLTRACE_BUFFER_FLUSH','WAITFOR', 'LOGMGR_QUEUE','CHECKPOINT_QUEUE',
			'REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_MANUAL_EVENT',
			'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT',
			'XE_DISPATCHER_WAIT', 'XE_DISPATCHER_JOIN', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
			'ONDEMAND_TASK_QUEUE', 'BROKER_EVENTHANDLER', 'SLEEP_BPOOL_FLUSH',
			'DIRTY_PAGE_POLL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION') -- DIRTY_PAGE_POLL and HADR_FILESTREAM_IOMGR_IOCOMPLETION are SQL 2012 only
		AND waiting_tasks_count > 0

		DECLARE @cnt INT
		SELECT @cnt=COUNT(Distinct [time]) FROM dbo.tmpWaitStats

		-- Previous stats have been recorded so now calculate the waits during that time period
		IF @cnt > 1
		BEGIN
			-- Get time to purge temporary data for and also to use in insert below
			declare @time datetime
			select @time=min([time]) from dbo.tmpWaitStats

			INSERT INTO [dbo].[WaitStats]
				   ([start_time]
				   ,[end_time]
				   ,[wait_type]
				   ,[wait_time_ms]
				   ,[waits])
			select @time, post.[time], post.[wait_type],
				(post.[wait_time_ms]-ISNULL(pre.[wait_time_ms],0)) as [wait_time_ms],
				(post.[waits]-ISNULL(pre.[waits],0)) as [waits]
			from (select [time],[wait_type],[wait_time_ms],[waits] from dbo.tmpWaitStats where [time] = (select min([time]) from dbo.tmpWaitStats)) Pre
			right outer join (select [time],[wait_type],[wait_time_ms],[waits] from dbo.tmpWaitStats where [time] = (select max([time]) from dbo.tmpWaitStats)) Post
			on pre.[wait_type]=post.[wait_type]
			where (post.[waits]-ISNULL(pre.[waits],0)) > 0

			-- purge temporary data
			delete dbo.tmpWaitStats
			where [time]=@time
		END
	END TRY

	BEGIN CATCH
	IF @@TRANCOUNT > 0
		ROLLBACK TRAN

		DECLARE @ErrorMessage NVARCHAR(4000);
		DECLARE @ErrorSeverity INT;
		DECLARE @ErrorState INT;

		SELECT
			@ErrorMessage = ERROR_MESSAGE(),
			@ErrorSeverity = ERROR_SEVERITY(),
			@ErrorState = ERROR_STATE();

		-- Use RAISERROR inside the CATCH block to return error
		-- information about the original error that caused
		-- execution to jump to the CATCH block.
		RAISERROR (@ErrorMessage, -- Message text.
				   @ErrorSeverity, -- Severity.
				   @ErrorState -- State.
				   );

	END CATCH;

	IF @@TRANCOUNT > 0
		COMMIT TRAN

	-- Purge old data
	DELETE dbo.WaitStats
	WHERE start_time < DATEADD(HOUR,-(@DaysToKeepWaits*24),getdate())

END

GO

GO

USE [msdb]
GO

/****** Object:  Job [performance stats collection]    Script Date: 08/01/2013 09:51:07 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 08/01/2013 09:51:07 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'performance stats collection',
        @enabled=0,
        @notify_level_eventlog=0,
        @notify_level_email=0,
        @notify_level_netsend=0,
        @notify_level_page=0,
        @delete_level=0,
        @description=N'No description available.',
        @category_name=N'[Uncategorized (Local)]',
        @owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Collect latency stats]    Script Date: 08/01/2013 09:51:07 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Collect latency stats',
        @step_id=1,
        @cmdexec_success_code=0,
        @on_success_action=3,
        @on_success_step_id=0,
        @on_fail_action=2,
        @on_fail_step_id=0,
        @retry_attempts=0,
        @retry_interval=0,
        @os_run_priority=0, @subsystem=N'TSQL',
        @command=N'exec dbo.retrieveLatencyStats @DaysToKeepLatency = 7',
        @database_name=N'DBA',
        @flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Collect wait stats]    Script Date: 08/01/2013 09:51:07 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Collect wait stats',
        @step_id=2,
        @cmdexec_success_code=0,
        @on_success_action=1,
        @on_success_step_id=0,
        @on_fail_action=2,
        @on_fail_step_id=0,
        @retry_attempts=0,
        @retry_interval=0,
        @os_run_priority=0, @subsystem=N'TSQL',
        @command=N'exec dbo.retrieveWaitStats @DaysToKeepWaits = 7',
        @database_name=N'DBA',
        @flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Every5mins',
        @enabled=1,
        @freq_type=4,
        @freq_interval=1,
        @freq_subday_type=4,
        @freq_subday_interval=5,
        @freq_relative_interval=0,
        @freq_recurrence_factor=0,
        @active_start_date=20130801,
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


UPDATE DBA.dbo.TrueCacheHitQOSBase
SET PageReads=Pr.cntr_value, PageLookups=PL.cntr_value, InstanceStartTime=I.create_date,
TrueCacheHitRatio=CASE
WHEN QOS.InstanceStarttime=(select create_date from sys.databases where database_id=2) THEN CAST(((CAST(((PL.cntr_value-QOS.PageLookups)-(PR.cntr_value-QOS.PageReads)) as float)/(PL.cntr_value-QOS.PageLookups))*100) as decimal(4,1))
ELSE CAST(((CAST((PL.cntr_value-Pr.cntr_value) as float)/PL.cntr_value)*100) as decimal(4,1))
END
FROM sys.dm_os_performance_counters PR
CROSS JOIN sys.dm_os_performance_counters PL
CROSS JOIN sys.databases I
CROSS JOIN DBA.dbo.trueCacheHitQOSBase QOS
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
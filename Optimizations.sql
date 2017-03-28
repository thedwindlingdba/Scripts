/*
--1900-01-01, DM: Disable SA account and rename SA account. Remote DAC enabled.  Operator renamed to FakeBusiness_DBAs.  Notifications for memory alerts disabled. 

--01/19/2015, DM: Commented out the code for creating the memory alerts that weren't actionable (% memory paged out, and AppDomain unloaded)

--01/21/2015, DM: Added code to change autogrowth settings for model, giving a more reasonable default (no 1 MB, no percentages)

--1900-01-01, DM: Added Mirroring Alerts

--08/13/2015, DM: Uncommented login and added it to sysadmin server role --DM Fixed  Hashing mistake, switched all alerts to use the  operator, and switched the areas that used the Mail profile 

--08/27/2015, DM: Added sp_CPU_Pressure proc for support to use

--09/14/2015, DM: Added FakeMon login

*/

use master
go

--Change autogrowth settings for model. This won't prevent customers from bringing over silly growth settings from migrations/restores,
--but any databases created from scratch will at least have decent settings by default.

ALTER DATABASE model MODIFY FILE (NAME='modeldev', FILEGROWTH=512MB)

ALTER DATABASE model MODIFY FILE (NAME='modelLOG', FILEGROWTH=256MB)

--Disable and renamae SA account
ALTER LOGIN sa DISABLE

ALTER LOGIN sa WITH NAME = [FakeDisable]

--Create Fake Admin account (SQL standard Login)
CREATE LOGIN [FakeBusiness_DBAs] WITH PASSWORD = 0x0100ED95DE714B82A8A0C57EC11A97A818F24F5BFBC29B8B5D03 HASHED, SID = 0x56B658FAAB74F54886F24943CF5B7740, DEFAULT_DATABASE = [master], CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF

ALTER SERVER ROLE [sysadmin] ADD MEMBER [FakeBusiness_DBAs]
GO

--Create FakeMon login
CREATE LOGIN [FakeMon] WITH PASSWORD = 0x0100E5CC81A8C1CC9C6FD296AFC8BE21D7452B6F8D5232CCC80E HASHED, SID = 0x3B34DB2B6B8916448E6BD8EAE0F8E618, DEFAULT_DATABASE = [master], CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF

ALTER SERVER ROLE [sysadmin] ADD MEMBER [FakeMon]
GO


--Enable remote DAC
Use master
GO
/* 0 = Allow Local Connection, 1 = Allow Remote Connections*/ 
sp_configure 'remote admin connections', 1 
GO
RECONFIGURE
GO

--create DBATEST database and BackupCheckIgnore table
--this will hold the names of databases the customer does not want backed up
IF  NOT EXISTS (SELECT name FROM sysdatabases WHERE name = N'DBATEST')
CREATE DATABASE DBATEST
GO

USE [DBATEST]
GO

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name = 'MirrorIgnoreTable')
CREATE TABLE [dbo].[MirrorIgnoreTable](
	[Database_Name] [varchar](50) NOT NULL,
	[Mirroring_State] [varchar](50) NULL
) ON [PRIMARY]

GO

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name = 'tmpLatencyStats')
CREATE TABLE [dbo].[tmpLatencyStats](
	[database_id] [int] NULL,
	[time] [datetime] NULL,
	[reads] [bigint] NULL,
	[writes] [bigint] NULL,
	[latency] [bigint] NULL,
	[readlatency] [bigint] NULL,
	[writelatency] [bigint] NULL
) ON [PRIMARY]

GO

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name = 'JobCheckIgnore')
CREATE TABLE [dbo].[JobCheckIgnore](
	[job_ID] [uniqueidentifier] NULL,
	[job_name] [varchar](max) NULL
) ON [PRIMARY]


GO

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name = 'tmpWaitStats')
CREATE TABLE [dbo].[tmpWaitStats](
	[time] [datetime] NULL,
	[wait_type] [varchar](255) NOT NULL,
	[wait_time_ms] [decimal](18,3) NOT NULL,
	[waits] [bigint] NOT NULL
) ON [PRIMARY]

GO

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name = 'LatencyStats')
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
)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name = 'WaitStats')
CREATE TABLE [dbo].[WaitStats](
	[start_time] [datetime] NOT NULL,
	[end_time] [datetime] NULL,
	[wait_type] [varchar](255) NOT NULL,
	[wait_time_ms] [decimal](18, 3) NOT NULL,
	[waits] [bigint] NOT NULL,
	[avg_wait_time_ms]  AS [wait_time_ms]/[waits],
 CONSTRAINT [pk_WaitStats] PRIMARY KEY CLUSTERED 
(
	[start_time] ASC,
	[wait_type] ASC
)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]
) ON [PRIMARY]

IF  NOT EXISTS (SELECT * FROM sysobjects WHERE name = 'BackupCheckIgnore')
	CREATE TABLE [dbo].[BackupCheckIgnore](
		[database_name] [varchar](128) NULL,
		[backup_type] [varchar](50) NULL,		
	) ON [PRIMARY]

go 

IF NOT EXISTS(select * from syscolumns where id=object_id('BackupCheckIgnore') 
			and name='backup_type')
BEGIN 
	ALTER TABLE backupcheckignore
	ADD backup_type varchar(50)
END

go

--=========================================================================


USE [DBATEST]
GO

IF EXISTS( select * from sys.objects where name='usp_CPU_Pressure' )
	drop PROCEDURE [dbo].[usp_CPU_Pressure]
go

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Brian DeVaney
-- Create date: 08/27/2015
-- Description:	proc for support to run to return data re: CPU pressure to client
-- =============================================
CREATE PROCEDURE [dbo].[usp_CPU_Pressure] 

AS
BEGIN

	SET NOCOUNT ON;

SELECT 
	   sp.spid
      ,DB_NAME((sp.dbid)) AS DB_NAME	
      ,blocked
	  ,waittype
	  ,waittime
	  ,lastwaittype
	  ,waitresource
	  ,cpu
	  ,physical_io
	  ,memusage
	  ,login_time
	  ,last_batch
	  ,hostname
	  ,program_name
	  ,cmd
	  ,nt_domain
	  ,nt_username
	  ,loginame
	  ,object_name(f.objectid,sp.dbid) as Object_Name
	  ,text
	  ,qp.query_plan

FROM master.sys.sysprocesses sp
OUTER APPLY sys.dm_exec_sql_text(sql_handle) f
INNER JOIN sys.dm_exec_requests er
on sp.spid = er.session_id
OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) qp
where sp.status in ('running','runnable')
and spid!=@@spid
order by sp.spid
END

GO



use DBATEST
go

IF EXISTS( select * from sys.objects where name='retrieveLatencyStats' )
	drop PROCEDURE [dbo].[retrieveLatencyStats]
go
	
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[retrieveLatencyStats] (@DaysToKeepLatency INT = 7)
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

IF EXISTS( select * from sys.objects where name='retrieveWaitStats' )
	drop PROCEDURE [dbo].[retrieveWaitStats]
go
	
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[retrieveWaitStats] (@DaysToKeepWaits INT = 7)
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

IF EXISTS( select * from sys.objects where name='CommandExecute' )
	drop PROCEDURE [dbo].[CommandExecute]
go
	
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[CommandExecute]

@Command nvarchar(max),
@Comment nvarchar(max),
@Mode int,
@Execute nvarchar(max)

AS

BEGIN

  ----------------------------------------------------------------------------------------------------
  --// Set options                                                                                //--
  ----------------------------------------------------------------------------------------------------

  SET NOCOUNT ON

  SET LOCK_TIMEOUT 3600000

  ----------------------------------------------------------------------------------------------------
  --// Declare variables                                                                          //--
  ----------------------------------------------------------------------------------------------------

  DECLARE @StartMessage nvarchar(max)
  DECLARE @EndMessage nvarchar(max)
  DECLARE @ErrorMessage nvarchar(max)

  DECLARE @StartTime datetime
  DECLARE @EndTime datetime

  DECLARE @Error int

  SET @Error = 0

  ----------------------------------------------------------------------------------------------------
  --// Check input parameters                                                                     //--
  ----------------------------------------------------------------------------------------------------

  IF @Command IS NULL OR @Command = ''
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Command is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Comment IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Comment is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Mode NOT IN(1,2) OR @Mode IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Mode is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Execute NOT IN('Y','N') OR @Execute IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Execute is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check error variable                                                                       //--
  ----------------------------------------------------------------------------------------------------

  IF @Error <> 0 GOTO ReturnCode

  ----------------------------------------------------------------------------------------------------
  --// Log initial information                                                                    //--
  ----------------------------------------------------------------------------------------------------

  SET @StartTime = CONVERT(datetime,CONVERT(nvarchar,GETDATE(),120),120)

  SET @StartMessage = 'DateTime: ' + CONVERT(nvarchar,@StartTime,120) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Command: ' + @Command
  IF @Comment <> '' SET @StartMessage = @StartMessage + CHAR(13) + CHAR(10) + 'Comment: ' + @Comment
  SET @StartMessage = REPLACE(@StartMessage,'%','%%')
  RAISERROR(@StartMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Execute command                                                                            //--
  ----------------------------------------------------------------------------------------------------

  IF @Mode = 1 AND @Execute = 'Y'
  BEGIN
    EXECUTE(@Command)
    SET @Error = @@ERROR
  END

  IF @Mode = 2 AND @Execute = 'Y'
  BEGIN

    BEGIN TRY
      EXECUTE(@Command)
    END TRY
    BEGIN CATCH
      SET @Error = ERROR_NUMBER()
      SET @ErrorMessage = 'Msg ' + CAST(ERROR_NUMBER() AS nvarchar) + ', ' + ISNULL(ERROR_MESSAGE(),'')
      RAISERROR(@ErrorMessage,16,1) WITH NOWAIT

    END CATCH
    
  END

  ----------------------------------------------------------------------------------------------------
  --// Log completing information                                                                 //--
  ----------------------------------------------------------------------------------------------------

  SET @EndTime = CONVERT(datetime,CONVERT(varchar,GETDATE(),120),120)

  SET @EndMessage = 'Outcome: ' + CASE WHEN @Execute = 'N' THEN 'Not Executed' WHEN @Error = 0 THEN 'Succeeded' ELSE 'Failed' END + CHAR(13) + CHAR(10)
  SET @EndMessage = @EndMessage + 'Duration: ' + CASE WHEN DATEDIFF(ss,@StartTime, @EndTime)/(24*3600) > 0 THEN CAST(DATEDIFF(ss,@StartTime, @EndTime)/(24*3600) AS nvarchar) + '.' ELSE '' END + CONVERT(nvarchar,@EndTime - @StartTime,108) + CHAR(13) + CHAR(10)
  SET @EndMessage = @EndMessage + 'DateTime: ' + CONVERT(nvarchar,@EndTime,120) + CHAR(13) + CHAR(10)
  SET @EndMessage = REPLACE(@EndMessage,'%','%%')
  RAISERROR(@EndMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Return code                                                                                //--
  ----------------------------------------------------------------------------------------------------

  ReturnCode:

  RETURN @Error

  ----------------------------------------------------------------------------------------------------

END
GO
use DBATEST
go

IF EXISTS( select * from sys.objects where name='DatabaseIntegrityCheck' )
	drop PROCEDURE [dbo].[DatabaseIntegrityCheck]
go


SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[DatabaseIntegrityCheck]

@Databases nvarchar(max),
@PhysicalOnly nvarchar(max) = 'N',
@NoIndex nvarchar(max) = 'N',
@ExtendedLogicalChecks nvarchar(max) = 'N',
@Execute nvarchar(max) = 'Y'

AS

BEGIN

  ----------------------------------------------------------------------------------------------------
  --// Set options                                                                                //--
  ----------------------------------------------------------------------------------------------------

  SET NOCOUNT ON

  ----------------------------------------------------------------------------------------------------
  --// Declare variables                                                                          //--
  ----------------------------------------------------------------------------------------------------

  DECLARE @StartMessage nvarchar(max)
  DECLARE @EndMessage nvarchar(max)
  DECLARE @DatabaseMessage nvarchar(max)
  DECLARE @ErrorMessage nvarchar(max)

  DECLARE @CurrentID int
  DECLARE @CurrentDatabase nvarchar(max)
  DECLARE @CurrentIsDatabaseAccessible bit
  DECLARE @CurrentMirroringRole nvarchar(max)

  DECLARE @CurrentCommand01 nvarchar(max)

  DECLARE @CurrentCommandOutput01 int

  DECLARE @tmpDatabases TABLE (ID int IDENTITY PRIMARY KEY,
                               DatabaseName nvarchar(max),
                               Completed bit)

  DECLARE @Error int

  SET @Error = 0

  ----------------------------------------------------------------------------------------------------
  --// Log initial information                                                                    //--
  ----------------------------------------------------------------------------------------------------

  SET @StartMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Server: ' + CAST(SERVERPROPERTY('ServerName') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Version: ' + CAST(SERVERPROPERTY('ProductVersion') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Edition: ' + CAST(SERVERPROPERTY('Edition') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Procedure: ' + QUOTENAME(DB_NAME(DB_ID())) + '.' + (SELECT QUOTENAME(sys.schemas.name) FROM sys.schemas INNER JOIN sys.objects ON sys.schemas.[schema_id] = sys.objects.[schema_id] WHERE [object_id] = @@PROCID) + '.' + QUOTENAME(OBJECT_NAME(@@PROCID)) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Parameters: @Databases = ' + ISNULL('''' + REPLACE(@Databases,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @PhysicalOnly = ' + ISNULL('''' + REPLACE(@PhysicalOnly,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @NoIndex = ' + ISNULL('''' + REPLACE(@NoIndex,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @ExtendedLogicalChecks = ' + ISNULL('''' + REPLACE(@ExtendedLogicalChecks,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @Execute = ' + ISNULL('''' + REPLACE(@Execute,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + CHAR(13) + CHAR(10)
  SET @StartMessage = REPLACE(@StartMessage,'%','%%')
  RAISERROR(@StartMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Select databases                                                                           //--
  ----------------------------------------------------------------------------------------------------

  IF @Databases IS NULL OR @Databases = ''
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Databases is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  INSERT INTO @tmpDatabases (DatabaseName, Completed)
  SELECT DatabaseName AS DatabaseName,
         0 AS Completed
  FROM dbo.DatabaseSelect (@Databases)
  ORDER BY DatabaseName ASC

  IF @@ERROR <> 0 OR (@@ROWCOUNT = 0 AND @Databases <> 'USER_DATABASES')
  BEGIN
    SET @ErrorMessage = 'Error selecting databases.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check input parameters                                                                     //--
  ----------------------------------------------------------------------------------------------------

  IF @PhysicalOnly NOT IN ('Y','N') OR @PhysicalOnly IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @PhysicalOnly is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @NoIndex NOT IN ('Y','N') OR @NoIndex IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @NoIndex is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @ExtendedLogicalChecks NOT IN ('Y','N') OR @ExtendedLogicalChecks IS NULL OR (@ExtendedLogicalChecks = 'Y' AND NOT (CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar), CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar)) - 1) AS int) >= 10))
  BEGIN
    SET @ErrorMessage = 'The value for parameter @ExtendedLogicalChecks is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF (@ExtendedLogicalChecks = 'Y' AND NOT (CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar), CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar)) - 1) AS int) >= 10))
  BEGIN
    SET @ErrorMessage = 'Extended logical checks are only supported in SQL Server 2008.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Execute NOT IN('Y','N') OR @Execute IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Execute is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check error variable                                                                       //--
  ----------------------------------------------------------------------------------------------------

  IF @Error <> 0 GOTO Logging

  ----------------------------------------------------------------------------------------------------
  --// Execute commands                                                                           //--
  ----------------------------------------------------------------------------------------------------

  WHILE EXISTS (SELECT * FROM @tmpDatabases WHERE Completed = 0)
  BEGIN

    SELECT TOP 1 @CurrentID = ID,
                 @CurrentDatabase = DatabaseName
    FROM @tmpDatabases
    WHERE Completed = 0
    ORDER BY ID ASC

    IF EXISTS (SELECT * FROM sys.database_recovery_status WHERE database_id = DB_ID(@CurrentDatabase) AND database_guid IS NOT NULL)
    BEGIN
      SET @CurrentIsDatabaseAccessible = 1
    END
    ELSE
    BEGIN
      SET @CurrentIsDatabaseAccessible = 0
    END

    SELECT @CurrentMirroringRole = mirroring_role_desc
    FROM sys.database_mirroring
    WHERE database_id = DB_ID(@CurrentDatabase)

    -- Set database message
    SET @DatabaseMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Database: ' + QUOTENAME(@CurrentDatabase) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Status: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Status') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Mirroring role: ' + ISNULL(@CurrentMirroringRole,'None') + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Standby: ' + CASE WHEN DATABASEPROPERTYEX(@CurrentDatabase,'IsInStandBy') = 1 THEN 'Yes' ELSE 'No' END + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Updateability: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Updateability') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'User access: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'UserAccess') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Is accessible: ' + CASE WHEN @CurrentIsDatabaseAccessible = 1 THEN 'Yes' ELSE 'No' END + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Recovery model: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Recovery') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = REPLACE(@DatabaseMessage,'%','%%')
    RAISERROR(@DatabaseMessage,10,1) WITH NOWAIT

    IF DATABASEPROPERTYEX(@CurrentDatabase,'Status') = 'ONLINE'
    AND NOT (DATABASEPROPERTYEX(@CurrentDatabase,'UserAccess') = 'SINGLE_USER' AND @CurrentIsDatabaseAccessible = 0)
    BEGIN
      SET @CurrentCommand01 = 'DBCC CHECKDB (' + QUOTENAME(@CurrentDatabase)
      IF @NoIndex = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + ', NOINDEX'
      SET @CurrentCommand01 = @CurrentCommand01 + ') WITH NO_INFOMSGS, ALL_ERRORMSGS'
      IF @PhysicalOnly = 'N' SET @CurrentCommand01 = @CurrentCommand01 + ', DATA_PURITY'
      IF @PhysicalOnly = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + ', PHYSICAL_ONLY'
      IF @ExtendedLogicalChecks = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + ', EXTENDED_LOGICAL_CHECKS'

      EXECUTE @CurrentCommandOutput01 = [dbo].[CommandExecute] @CurrentCommand01, '', 1, @Execute
      SET @Error = @@ERROR
      IF @Error <> 0 SET @CurrentCommandOutput01 = @Error
    END

    -- Update that the database is completed
    UPDATE @tmpDatabases
    SET Completed = 1
    WHERE ID = @CurrentID

    -- Clear variables
    SET @CurrentID = NULL
    SET @CurrentDatabase = NULL
    SET @CurrentIsDatabaseAccessible = NULL
    SET @CurrentMirroringRole = NULL

    SET @CurrentCommand01 = NULL

    SET @CurrentCommandOutput01 = NULL

  END

  ----------------------------------------------------------------------------------------------------
  --// Log completing information                                                                 //--
  ----------------------------------------------------------------------------------------------------

  Logging:
  SET @EndMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120)
  SET @EndMessage = REPLACE(@EndMessage,'%','%%')
  RAISERROR(@EndMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------

END
GO
use DBATEST
go
IF EXISTS( select * from sys.objects where name='DatabaseSelect' )
	drop function [dbo].[DatabaseSelect]
go

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[DatabaseSelect] (@DatabaseList nvarchar(max))

RETURNS @Database TABLE (DatabaseName nvarchar(max) NOT NULL)

AS

BEGIN

  ----------------------------------------------------------------------------------------------------
  --// Declare variables                                                                          //--
  ----------------------------------------------------------------------------------------------------

  DECLARE @DatabaseItem nvarchar(max)
  DECLARE @Position int

  DECLARE @CurrentID int
  DECLARE @CurrentDatabaseName nvarchar(max)
  DECLARE @CurrentDatabaseStatus bit

  DECLARE @Database01 TABLE (DatabaseName nvarchar(max))

  DECLARE @Database02 TABLE (ID int IDENTITY PRIMARY KEY,
                             DatabaseName nvarchar(max),
                             DatabaseStatus bit,
                             Completed bit)

  DECLARE @Database03 TABLE (DatabaseName nvarchar(max),
                             DatabaseStatus bit)

  DECLARE @Sysdatabases TABLE (DatabaseName nvarchar(max))

  ----------------------------------------------------------------------------------------------------
  --// Split input string into elements                                                           //--
  ----------------------------------------------------------------------------------------------------

  SET @DatabaseList = REPLACE(REPLACE(REPLACE(REPLACE(@DatabaseList,'[',''),']',''),'''',''),'"','')

  WHILE CHARINDEX(',,',@DatabaseList) > 0 SET @DatabaseList = REPLACE(@DatabaseList,',,',',')
  WHILE CHARINDEX(', ',@DatabaseList) > 0 SET @DatabaseList = REPLACE(@DatabaseList,', ',',')
  WHILE CHARINDEX(' ,',@DatabaseList) > 0 SET @DatabaseList = REPLACE(@DatabaseList,' ,',',')

  IF RIGHT(@DatabaseList,1) = ',' SET @DatabaseList = LEFT(@DatabaseList,LEN(@DatabaseList) - 1)
  IF LEFT(@DatabaseList,1) = ','  SET @DatabaseList = RIGHT(@DatabaseList,LEN(@DatabaseList) - 1)

  SET @DatabaseList = LTRIM(RTRIM(@DatabaseList))

  WHILE LEN(@DatabaseList) > 0
  BEGIN
    SET @Position = CHARINDEX(',', @DatabaseList)
    IF @Position = 0
    BEGIN
      SET @DatabaseItem = @DatabaseList
      SET @DatabaseList = ''
    END
    ELSE
    BEGIN
      SET @DatabaseItem = LEFT(@DatabaseList, @Position - 1)
      SET @DatabaseList = RIGHT(@DatabaseList, LEN(@DatabaseList) - @Position)
    END
    IF @DatabaseItem <> '-' INSERT INTO @Database01 (DatabaseName) VALUES(@DatabaseItem)
  END

  ----------------------------------------------------------------------------------------------------
  --// Handle database exclusions                                                                 //--
  ----------------------------------------------------------------------------------------------------

  INSERT INTO @Database02 (DatabaseName, DatabaseStatus, Completed)
  SELECT DISTINCT DatabaseName = CASE WHEN DatabaseName LIKE '-%' THEN RIGHT(DatabaseName,LEN(DatabaseName) - 1) ELSE DatabaseName END,
                  DatabaseStatus = CASE WHEN DatabaseName LIKE '-%' THEN 0 ELSE 1 END,
                  0 AS Completed
  FROM @Database01

  ----------------------------------------------------------------------------------------------------
  --// Resolve elements                                                                           //--
  ----------------------------------------------------------------------------------------------------

  WHILE EXISTS (SELECT * FROM @Database02 WHERE Completed = 0)
  BEGIN

    SELECT TOP 1 @CurrentID = ID,
                 @CurrentDatabaseName = DatabaseName,
                 @CurrentDatabaseStatus = DatabaseStatus
    FROM @Database02
    WHERE Completed = 0
    ORDER BY ID ASC

    IF @CurrentDatabaseName = 'SYSTEM_DATABASES'
    BEGIN
      INSERT INTO @Database03 (DatabaseName, DatabaseStatus)
      SELECT [name], @CurrentDatabaseStatus
      FROM sys.databases
      WHERE database_id <= 4
    END
    ELSE IF @CurrentDatabaseName = 'USER_DATABASES'
    BEGIN
      INSERT INTO @Database03 (DatabaseName, DatabaseStatus)
      SELECT [name], @CurrentDatabaseStatus
      FROM sys.databases
      WHERE database_id > 4
    END
    ELSE IF @CurrentDatabaseName = 'ALL_DATABASES'
    BEGIN
      INSERT INTO @Database03 (DatabaseName, DatabaseStatus)
      SELECT [name], @CurrentDatabaseStatus
      FROM sys.databases
    END
    ELSE IF CHARINDEX('%',@CurrentDatabaseName) > 0
    BEGIN
      INSERT INTO @Database03 (DatabaseName, DatabaseStatus)
      SELECT [name], @CurrentDatabaseStatus
      FROM sys.databases
      WHERE [name] LIKE REPLACE(@CurrentDatabaseName,'_','[_]')
    END
    ELSE
    BEGIN
      INSERT INTO @Database03 (DatabaseName, DatabaseStatus)
      SELECT [name], @CurrentDatabaseStatus
      FROM sys.databases
      WHERE [name] = @CurrentDatabaseName
    END

    UPDATE @Database02
    SET Completed = 1
    WHERE ID = @CurrentID

    SET @CurrentID = NULL
    SET @CurrentDatabaseName = NULL
    SET @CurrentDatabaseStatus = NULL

  END

  ----------------------------------------------------------------------------------------------------
  --// Handle tempdb and database snapshots                                                       //--
  ----------------------------------------------------------------------------------------------------

  INSERT INTO @Sysdatabases (DatabaseName)
  SELECT [name]
  FROM sys.databases
  WHERE [name] <> 'tempdb'
  AND source_database_id IS NULL

  ----------------------------------------------------------------------------------------------------
  --// Return results                                                                             //--
  ----------------------------------------------------------------------------------------------------

  INSERT INTO @Database (DatabaseName)
  SELECT DatabaseName
  FROM @Sysdatabases
  INTERSECT
  SELECT DatabaseName
  FROM @Database03
  WHERE DatabaseStatus = 1
  EXCEPT
  SELECT DatabaseName
  FROM @Database03
  WHERE DatabaseStatus = 0

  RETURN

  ----------------------------------------------------------------------------------------------------

END
GO
use DBATEST
go

IF EXISTS( select * from sys.objects where name='IndexOptimize' )
	drop PROCEDURE [dbo].[IndexOptimize]


SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[IndexOptimize]

@Databases nvarchar(max),
@FragmentationHigh nvarchar(max) = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
@FragmentationMedium nvarchar(max) = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
@FragmentationLow nvarchar(max) = NULL,
@FragmentationLevel1 int = 5,
@FragmentationLevel2 int = 30,
@PageCountLevel int = 1000,
@SortInTempdb nvarchar(max) = 'N',
@MaxDOP int = NULL,
@FillFactor int = NULL,
@PadIndex nvarchar(max) = NULL,
@LOBCompaction nvarchar(max) = 'Y',
@UpdateStatistics nvarchar(max) = NULL,
@OnlyModifiedStatistics nvarchar(max) = 'N',
@StatisticsSample int = NULL,
@StatisticsResample nvarchar(max) = 'N',
@PartitionLevel nvarchar(max) = 'N',
@TimeLimit int = NULL,
@Indexes nvarchar(max) = NULL,
@Delay int = NULL,
@Execute nvarchar(max) = 'Y'

AS

BEGIN

  ----------------------------------------------------------------------------------------------------
  --// Set options                                                                                //--
  ----------------------------------------------------------------------------------------------------

  SET NOCOUNT ON

  SET LOCK_TIMEOUT 3600000

  ----------------------------------------------------------------------------------------------------
  --// Declare variables                                                                          //--
  ----------------------------------------------------------------------------------------------------

  DECLARE @StartMessage nvarchar(max)
  DECLARE @EndMessage nvarchar(max)
  DECLARE @DatabaseMessage nvarchar(max)
  DECLARE @ErrorMessage nvarchar(max)

  DECLARE @Version numeric(18,10)

  DECLARE @StartTime datetime

  DECLARE @CurrentIndexList nvarchar(max)
  DECLARE @CurrentIndexItem nvarchar(max)
  DECLARE @CurrentIndexPosition int

  DECLARE @CurrentID int
  DECLARE @CurrentDatabase nvarchar(max)
  DECLARE @CurrentIsDatabaseAccessible bit
  DECLARE @CurrentMirroringRole nvarchar(max)

  DECLARE @CurrentCommandSelect01 nvarchar(max)
  DECLARE @CurrentCommandSelect02 nvarchar(max)
  DECLARE @CurrentCommandSelect03 nvarchar(max)
  DECLARE @CurrentCommandSelect04 nvarchar(max)
  DECLARE @CurrentCommandSelect05 nvarchar(max)
  DECLARE @CurrentCommandSelect06 nvarchar(max)
  DECLARE @CurrentCommandSelect07 nvarchar(max)
  DECLARE @CurrentCommandSelect08 nvarchar(max)

  DECLARE @CurrentCommand01 nvarchar(max)
  DECLARE @CurrentCommand02 nvarchar(max)

  DECLARE @CurrentCommandOutput01 int
  DECLARE @CurrentCommandOutput02 int

  DECLARE @CurrentIxID int
  DECLARE @CurrentSchemaID int
  DECLARE @CurrentSchemaName nvarchar(max)
  DECLARE @CurrentObjectID int
  DECLARE @CurrentObjectName nvarchar(max)
  DECLARE @CurrentObjectType nvarchar(max)
  DECLARE @CurrentIndexID int
  DECLARE @CurrentIndexName nvarchar(max)
  DECLARE @CurrentIndexType int
  DECLARE @CurrentStatisticsID int
  DECLARE @CurrentStatisticsName nvarchar(max)
  DECLARE @CurrentPartitionID bigint
  DECLARE @CurrentPartitionNumber int
  DECLARE @CurrentPartitionCount int
  DECLARE @CurrentIsPartition bit
  DECLARE @CurrentIndexExists bit
  DECLARE @CurrentStatisticsExists bit
  DECLARE @CurrentIsLOB bit
  DECLARE @CurrentAllowPageLocks bit
  DECLARE @CurrentNoRecompute bit
  DECLARE @CurrentStatisticsModified bit
  DECLARE @CurrentOnReadOnlyFileGroup bit
  DECLARE @CurrentFragmentationLevel float
  DECLARE @CurrentPageCount bigint
  DECLARE @CurrentFragmentationGroup nvarchar(max)
  DECLARE @CurrentAction nvarchar(max)
  DECLARE @CurrentMaxDOP int
  DECLARE @CurrentUpdateStatistics nvarchar(max)
  DECLARE @CurrentComment nvarchar(max)
  DECLARE @CurrentDelay datetime

  DECLARE @tmpDatabases TABLE (ID int IDENTITY PRIMARY KEY,
                               DatabaseName nvarchar(max),
                               Completed bit)

  DECLARE @tmpIndexesStatistics TABLE (IxID int IDENTITY,
                                       SchemaID int,
                                       SchemaName nvarchar(max),
                                       ObjectID int,
                                       ObjectName nvarchar(max),
                                       ObjectType nvarchar(max),
                                       IndexID int,
                                       IndexName nvarchar(max),
                                       IndexType int,
                                       StatisticsID int,
                                       StatisticsName nvarchar(max),
                                       PartitionID bigint,
                                       PartitionNumber int,
                                       PartitionCount int,
                                       Selected bit,
                                       Completed bit,
                                       PRIMARY KEY(Selected, Completed, IxID))

  DECLARE @SelectedIndexes TABLE (DatabaseName nvarchar(max),
                                  SchemaName nvarchar(max),
                                  ObjectName nvarchar(max),
                                  IndexName nvarchar(max),
                                  Selected bit)

  DECLARE @Actions TABLE ([Action] nvarchar(max))

  INSERT INTO @Actions([Action]) VALUES('INDEX_REBUILD_ONLINE')
  INSERT INTO @Actions([Action]) VALUES('INDEX_REBUILD_OFFLINE')
  INSERT INTO @Actions([Action]) VALUES('INDEX_REORGANIZE')

  DECLARE @ActionsPreferred TABLE (FragmentationGroup nvarchar(max),
                                   [Priority] int,
                                   [Action] nvarchar(max))

  DECLARE @CurrentActionsAllowed TABLE ([Action] nvarchar(max))

  DECLARE @Error int

  SET @Error = 0

  SET @Version = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)), LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))),'.','') AS numeric(18,10))

  SET @CurrentDelay = DATEADD(ss,@Delay,'1900-01-01')

  ----------------------------------------------------------------------------------------------------
  --// Log initial information                                                                    //--
  ----------------------------------------------------------------------------------------------------

  SET @StartTime = CONVERT(datetime,CONVERT(nvarchar,GETDATE(),120),120)

  SET @StartMessage = 'DateTime: ' + CONVERT(nvarchar,@StartTime,120) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Server: ' + CAST(SERVERPROPERTY('ServerName') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Version: ' + CAST(SERVERPROPERTY('ProductVersion') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Edition: ' + CAST(SERVERPROPERTY('Edition') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Procedure: ' + QUOTENAME(DB_NAME(DB_ID())) + '.' + (SELECT QUOTENAME(schemas.name) FROM sys.schemas schemas INNER JOIN sys.objects objects ON schemas.[schema_id] = objects.[schema_id] WHERE [object_id] = @@PROCID) + '.' + QUOTENAME(OBJECT_NAME(@@PROCID)) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Parameters: @Databases = ' + ISNULL('''' + REPLACE(@Databases,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @FragmentationHigh = ' + ISNULL('''' + REPLACE(@FragmentationHigh,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @FragmentationMedium = ' + ISNULL('''' + REPLACE(@FragmentationMedium,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @FragmentationLow = ' + ISNULL('''' + REPLACE(@FragmentationLow,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @FragmentationLevel1 = ' + ISNULL(CAST(@FragmentationLevel1 AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @FragmentationLevel2 = ' + ISNULL(CAST(@FragmentationLevel2 AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @PageCountLevel = ' + ISNULL(CAST(@PageCountLevel AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @SortInTempdb = ' + ISNULL('''' + REPLACE(@SortInTempdb,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @MaxDOP = ' + ISNULL(CAST(@MaxDOP AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @FillFactor = ' + ISNULL(CAST(@FillFactor AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @PadIndex = ' + ISNULL('''' + REPLACE(@PadIndex,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @LOBCompaction = ' + ISNULL('''' + REPLACE(@LOBCompaction,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @UpdateStatistics = ' + ISNULL('''' + REPLACE(@UpdateStatistics,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @OnlyModifiedStatistics = ' + ISNULL('''' + REPLACE(@OnlyModifiedStatistics,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @StatisticsSample = ' + ISNULL(CAST(@StatisticsSample AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @StatisticsResample = ' + ISNULL('''' + REPLACE(@StatisticsResample,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @PartitionLevel = ' + ISNULL('''' + REPLACE(@PartitionLevel,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @TimeLimit = ' + ISNULL(CAST(@TimeLimit AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @Indexes = ' + ISNULL('''' + REPLACE(@Indexes,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @Delay = ' + ISNULL(CAST(@Delay AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @Execute = ' + ISNULL('''' + REPLACE(@Execute,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + CHAR(13) + CHAR(10)
  SET @StartMessage = REPLACE(@StartMessage,'%','%%')
  RAISERROR(@StartMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Select databases                                                                           //--
  ----------------------------------------------------------------------------------------------------

  IF @Databases IS NULL OR @Databases = ''
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Databases is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  INSERT INTO @tmpDatabases (DatabaseName, Completed)
  SELECT DatabaseName AS DatabaseName,
         0 AS Completed
  FROM dbo.DatabaseSelect (@Databases)
  ORDER BY DatabaseName ASC

  IF @@ERROR <> 0 OR (@@ROWCOUNT = 0 AND @Databases <> 'USER_DATABASES')
  BEGIN
    SET @ErrorMessage = 'Error selecting databases.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Select indexes                                                                             //--
  ----------------------------------------------------------------------------------------------------

  SET @CurrentIndexList = @Indexes

  SET @CurrentIndexList = REPLACE(REPLACE(@CurrentIndexList,'''',''),'"','')

  WHILE CHARINDEX(', ',@CurrentIndexList) > 0 SET @CurrentIndexList = REPLACE(@CurrentIndexList,', ',',')
  WHILE CHARINDEX(' ,',@CurrentIndexList) > 0 SET @CurrentIndexList = REPLACE(@CurrentIndexList,' ,',',')
  WHILE CHARINDEX(',,',@CurrentIndexList) > 0 SET @CurrentIndexList = REPLACE(@CurrentIndexList,',,',',')

  IF RIGHT(@CurrentIndexList,1) = ',' SET @CurrentIndexList = LEFT(@CurrentIndexList,LEN(@CurrentIndexList) - 1)
  IF LEFT(@CurrentIndexList,1) = ',' SET @CurrentIndexList = RIGHT(@CurrentIndexList,LEN(@CurrentIndexList) - 1)

  SET @CurrentIndexList = LTRIM(RTRIM(@CurrentIndexList))

  WHILE LEN(@CurrentIndexList) > 0
  BEGIN
    SET @CurrentIndexPosition = CHARINDEX(',', @CurrentIndexList)
    IF @CurrentIndexPosition = 0
    BEGIN
      SET @CurrentIndexItem = @CurrentIndexList
      SET @CurrentIndexList = ''
    END
    ELSE
    BEGIN
      SET @CurrentIndexItem = LEFT(@CurrentIndexList, @CurrentIndexPosition - 1)
      SET @CurrentIndexList = RIGHT(@CurrentIndexList, LEN(@CurrentIndexList) - @CurrentIndexPosition)
    END;

    WITH IndexItem01 (IndexItem, Selected) AS (
    SELECT CASE WHEN @CurrentIndexItem LIKE '-%' THEN RIGHT(@CurrentIndexItem,LEN(@CurrentIndexItem) - 1) ELSE @CurrentIndexItem END AS IndexItem,
           CASE WHEN @CurrentIndexItem LIKE '-%' THEN 0 ELSE 1 END AS Selected),
    IndexItem02 (IndexItem, Selected) AS (
    SELECT CASE WHEN IndexItem = 'ALL_INDEXES' THEN '%.%.%.%' ELSE IndexItem END AS IndexItem,
           Selected
    FROM IndexItem01)
    INSERT INTO @SelectedIndexes (DatabaseName, SchemaName, ObjectName, IndexName, Selected)
    SELECT DatabaseName = CASE WHEN PARSENAME(IndexItem,4) IS NULL THEN PARSENAME(IndexItem,3) ELSE PARSENAME(IndexItem,4) END,
           SchemaName = CASE WHEN PARSENAME(IndexItem,4) IS NULL THEN PARSENAME(IndexItem,2) ELSE PARSENAME(IndexItem,3) END,
           ObjectName = CASE WHEN PARSENAME(IndexItem,4) IS NULL THEN PARSENAME(IndexItem,1) ELSE PARSENAME(IndexItem,2) END,
           IndexName = CASE WHEN PARSENAME(IndexItem,4) IS NULL THEN '%' ELSE PARSENAME(IndexItem,1) END,
           Selected
    FROM IndexItem02
  END

  IF EXISTS(SELECT * FROM @SelectedIndexes WHERE DatabaseName IS NULL OR SchemaName IS NULL OR ObjectName IS NULL OR IndexName IS NULL) OR (@Indexes IS NOT NULL AND NOT EXISTS(SELECT * FROM @SelectedIndexes))
  BEGIN
    SET @ErrorMessage = 'Error selecting indexes.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END;

  ----------------------------------------------------------------------------------------------------
  --// Select actions                                                                             //--
  ----------------------------------------------------------------------------------------------------

  WITH FragmentationHigh AS
  (
  SELECT CASE WHEN CHARINDEX(',', @FragmentationHigh) = 0 THEN @FragmentationHigh ELSE SUBSTRING(@FragmentationHigh, 1, CHARINDEX(',', @FragmentationHigh) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', @FragmentationHigh) = 0 THEN '' ELSE SUBSTRING(@FragmentationHigh, CHARINDEX(',', @FragmentationHigh) + 1, LEN(@FragmentationHigh)) END AS String,
         1 AS [Priority],
         CASE WHEN CHARINDEX(',', @FragmentationHigh) = 0 THEN 0 ELSE 1 END [Continue]
  WHERE @FragmentationHigh IS NOT NULL
  UNION ALL
  SELECT CASE WHEN CHARINDEX(',', String) = 0 THEN String ELSE SUBSTRING(String, 1, CHARINDEX(',', String) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', String) = 0 THEN '' ELSE SUBSTRING(String, CHARINDEX(',', String) + 1, LEN(String)) END AS String,
         [Priority] + 1  AS [Priority],
         CASE WHEN CHARINDEX(',', String) = 0 THEN 0 ELSE 1 END [Continue]
  FROM FragmentationHigh
  WHERE [Continue] = 1
  ),
  FragmentationMedium AS
  (
  SELECT CASE WHEN CHARINDEX(',', @FragmentationMedium) = 0 THEN @FragmentationMedium ELSE SUBSTRING(@FragmentationMedium, 1, CHARINDEX(',', @FragmentationMedium) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', @FragmentationMedium) = 0 THEN '' ELSE SUBSTRING(@FragmentationMedium, CHARINDEX(',', @FragmentationMedium) + 1, LEN(@FragmentationMedium)) END AS String,
         1 AS [Priority],
         CASE WHEN CHARINDEX(',', @FragmentationMedium) = 0 THEN 0 ELSE 1 END [Continue]
  WHERE @FragmentationMedium IS NOT NULL
  UNION ALL
  SELECT CASE WHEN CHARINDEX(',', String) = 0 THEN String ELSE SUBSTRING(String, 1, CHARINDEX(',', String) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', String) = 0 THEN '' ELSE SUBSTRING(String, CHARINDEX(',', String) + 1, LEN(String)) END AS String,
         [Priority] + 1  AS [Priority],
         CASE WHEN CHARINDEX(',', String) = 0 THEN 0 ELSE 1 END [Continue]
  FROM FragmentationMedium
  WHERE [Continue] = 1
  ),
  FragmentationLow AS
  (
  SELECT CASE WHEN CHARINDEX(',', @FragmentationLow) = 0 THEN @FragmentationLow ELSE SUBSTRING(@FragmentationLow, 1, CHARINDEX(',', @FragmentationLow) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', @FragmentationLow) = 0 THEN '' ELSE SUBSTRING(@FragmentationLow, CHARINDEX(',', @FragmentationLow) + 1, LEN(@FragmentationLow)) END AS String,
         1 AS [Priority],
         CASE WHEN CHARINDEX(',', @FragmentationLow) = 0 THEN 0 ELSE 1 END [Continue]
  WHERE @FragmentationLow IS NOT NULL
  UNION ALL
  SELECT CASE WHEN CHARINDEX(',', String) = 0 THEN String ELSE SUBSTRING(String, 1, CHARINDEX(',', String) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', String) = 0 THEN '' ELSE SUBSTRING(String, CHARINDEX(',', String) + 1, LEN(String)) END AS String,
         [Priority] + 1  AS [Priority],
         CASE WHEN CHARINDEX(',', String) = 0 THEN 0 ELSE 1 END [Continue]
  FROM FragmentationLow
  WHERE [Continue] = 1
  )
  INSERT INTO @ActionsPreferred(FragmentationGroup, [Priority], [Action])
  SELECT 'High' AS FragmentationGroup, [Priority], [Action]
  FROM FragmentationHigh
  UNION
  SELECT 'Medium' AS FragmentationGroup, [Priority], [Action]
  FROM FragmentationMedium
  UNION
  SELECT 'Low' AS FragmentationGroup, [Priority], [Action]
  FROM FragmentationLow

  ----------------------------------------------------------------------------------------------------
  --// Check input parameters                                                                     //--
  ----------------------------------------------------------------------------------------------------

  IF EXISTS (SELECT [Action] FROM @ActionsPreferred WHERE FragmentationGroup = 'High' AND [Action] NOT IN(SELECT * FROM @Actions))
  OR EXISTS(SELECT * FROM @ActionsPreferred WHERE FragmentationGroup = 'High' GROUP BY [Action] HAVING COUNT(*) > 1)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FragmentationHigh is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF EXISTS (SELECT [Action] FROM @ActionsPreferred WHERE FragmentationGroup = 'Medium' AND [Action] NOT IN(SELECT * FROM @Actions))
  OR EXISTS(SELECT * FROM @ActionsPreferred WHERE FragmentationGroup = 'Medium' GROUP BY [Action] HAVING COUNT(*) > 1)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FragmentationMedium is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF EXISTS (SELECT [Action] FROM @ActionsPreferred WHERE FragmentationGroup = 'Low' AND [Action] NOT IN(SELECT * FROM @Actions))
  OR EXISTS(SELECT * FROM @ActionsPreferred WHERE FragmentationGroup = 'Low' GROUP BY [Action] HAVING COUNT(*) > 1)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FragmentationLow is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @FragmentationLevel1 <= 0 OR @FragmentationLevel1 >= 100 OR @FragmentationLevel1 >= @FragmentationLevel2 OR @FragmentationLevel1 IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FragmentationLevel1 is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @FragmentationLevel2 <= 0 OR @FragmentationLevel2 >= 100 OR @FragmentationLevel2 <= @FragmentationLevel1 OR @FragmentationLevel2 IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FragmentationLevel2 is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @PageCountLevel < 0 OR @PageCountLevel IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @PageCountLevel is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @SortInTempdb NOT IN('Y','N') OR @SortInTempdb IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @SortInTempdb is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @MaxDOP < 0 OR @MaxDOP > 64 OR @MaxDOP > (SELECT cpu_count FROM sys.dm_os_sys_info) OR (@MaxDOP > 1 AND SERVERPROPERTY('EngineEdition') <> 3)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @MaxDOP is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @MaxDOP > 1 AND SERVERPROPERTY('EngineEdition') <> 3
  BEGIN
    SET @ErrorMessage = 'Parallel index operations are only supported in Enterprise, Developer and Datacenter Edition.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @FillFactor <= 0 OR @FillFactor > 100
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FillFactor is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @PadIndex NOT IN('Y','N')
  BEGIN
    SET @ErrorMessage = 'The value for parameter @PadIndex is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @LOBCompaction NOT IN('Y','N') OR @LOBCompaction IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @LOBCompaction is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @UpdateStatistics NOT IN('ALL','COLUMNS','INDEX')
  BEGIN
    SET @ErrorMessage = 'The value for parameter @UpdateStatistics is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @OnlyModifiedStatistics NOT IN('Y','N') OR @OnlyModifiedStatistics IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @OnlyModifiedStatistics is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @StatisticsSample <= 0 OR @StatisticsSample  > 100
  BEGIN
    SET @ErrorMessage = 'The value for parameter @StatisticsSample is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @StatisticsResample NOT IN('Y','N') OR @StatisticsResample IS NULL OR (@StatisticsResample = 'Y' AND @StatisticsSample IS NOT NULL)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @StatisticsResample is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @PartitionLevel NOT IN('Y','N') OR @PartitionLevel IS NULL OR (@PartitionLevel = 'Y' AND SERVERPROPERTY('EngineEdition') <> 3)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @PartitionLevel is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @PartitionLevel = 'Y' AND SERVERPROPERTY('EngineEdition') <> 3
  BEGIN
    SET @ErrorMessage = 'Table partitioning is only supported in Enterprise, Developer and Datacenter Edition.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @TimeLimit < 0
  BEGIN
    SET @ErrorMessage = 'The value for parameter @TimeLimit is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Delay < 0
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Delay is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Execute NOT IN('Y','N') OR @Execute IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Execute is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check error variable                                                                       //--
  ----------------------------------------------------------------------------------------------------

  IF @Error <> 0 GOTO Logging

  ----------------------------------------------------------------------------------------------------
  --// Execute commands                                                                           //--
  ----------------------------------------------------------------------------------------------------

  WHILE EXISTS (SELECT * FROM @tmpDatabases WHERE Completed = 0)
  BEGIN

    SELECT TOP 1 @CurrentID = ID,
                 @CurrentDatabase = DatabaseName
    FROM @tmpDatabases
    WHERE Completed = 0
    ORDER BY ID ASC

    IF EXISTS (SELECT * FROM sys.database_recovery_status WHERE database_id = DB_ID(@CurrentDatabase) AND database_guid IS NOT NULL)
    BEGIN
      SET @CurrentIsDatabaseAccessible = 1
    END
    ELSE
    BEGIN
      SET @CurrentIsDatabaseAccessible = 0
    END

    SELECT @CurrentMirroringRole = mirroring_role_desc
    FROM sys.database_mirroring
    WHERE database_id = DB_ID(@CurrentDatabase)

    -- Set database message
    SET @DatabaseMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Database: ' + QUOTENAME(@CurrentDatabase) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Status: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Status') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Mirroring role: ' + ISNULL(@CurrentMirroringRole,'None') + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Standby: ' + CASE WHEN DATABASEPROPERTYEX(@CurrentDatabase,'IsInStandBy') = 1 THEN 'Yes' ELSE 'No' END + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Updateability: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Updateability') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'User access: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'UserAccess') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Is accessible: ' + CASE WHEN @CurrentIsDatabaseAccessible = 1 THEN 'Yes' ELSE 'No' END + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Recovery model: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Recovery') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = REPLACE(@DatabaseMessage,'%','%%')
    RAISERROR(@DatabaseMessage,10,1) WITH NOWAIT

    IF DATABASEPROPERTYEX(@CurrentDatabase,'Status') = 'ONLINE'
    AND NOT (DATABASEPROPERTYEX(@CurrentDatabase,'UserAccess') = 'SINGLE_USER' AND @CurrentIsDatabaseAccessible = 0)
    AND DATABASEPROPERTYEX(@CurrentDatabase,'Updateability') = 'READ_WRITE'
    BEGIN

      -- Select indexes in the current database
      IF EXISTS(SELECT * FROM @ActionsPreferred) OR @UpdateStatistics IS NOT NULL
      BEGIN
        SET @CurrentCommandSelect01 = 'SELECT SchemaID, SchemaName, ObjectID, ObjectName, ObjectType, IndexID, IndexName, IndexType, StatisticsID, StatisticsName, PartitionID, PartitionNumber, PartitionCount, Selected, Completed FROM ('

        IF EXISTS(SELECT * FROM @ActionsPreferred) OR @UpdateStatistics IN('ALL','INDEX')
        BEGIN
          SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + 'SELECT schemas.[schema_id] AS SchemaID, schemas.[name] AS SchemaName, objects.[object_id] AS ObjectID, objects.[name] AS ObjectName, RTRIM(objects.[type]) AS ObjectType, indexes.index_id AS IndexID, indexes.[name] AS IndexName, indexes.[type] AS IndexType, stats.stats_id AS StatisticsID, stats.name AS StatisticsName'
          IF @PartitionLevel = 'Y' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ', partitions.partition_id AS PartitionID, partitions.partition_number AS PartitionNumber, IndexPartitions.partition_count AS PartitionCount'
          IF @PartitionLevel = 'N' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ', NULL AS PartitionID, NULL AS PartitionNumber, NULL AS PartitionCount'
          SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ', 0 AS Selected, 0 AS Completed FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes indexes INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.objects objects ON indexes.[object_id] = objects.[object_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas schemas ON objects.[schema_id] = schemas.[schema_id] LEFT OUTER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.stats stats ON indexes.[object_id] = stats.[object_id] AND indexes.[index_id] = stats.[stats_id]'
          IF @PartitionLevel = 'Y' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ' LEFT OUTER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions partitions ON indexes.[object_id] = partitions.[object_id] AND indexes.index_id = partitions.index_id LEFT OUTER JOIN (SELECT partitions.[object_id], partitions.index_id, COUNT(*) AS partition_count FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions partitions GROUP BY partitions.[object_id], partitions.index_id) IndexPartitions ON partitions.[object_id] = IndexPartitions.[object_id] AND partitions.[index_id] = IndexPartitions.[index_id]'
          IF @PartitionLevel = 'Y' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ' LEFT OUTER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.dm_db_partition_stats dm_db_partition_stats ON indexes.[object_id] = dm_db_partition_stats.[object_id] AND indexes.[index_id] = dm_db_partition_stats.[index_id] AND partitions.partition_id = dm_db_partition_stats.partition_id'
          IF @PartitionLevel = 'N' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ' LEFT OUTER JOIN (SELECT dm_db_partition_stats.[object_id], dm_db_partition_stats.[index_id], SUM(dm_db_partition_stats.in_row_data_page_count) AS in_row_data_page_count FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.dm_db_partition_stats dm_db_partition_stats GROUP BY dm_db_partition_stats.[object_id], dm_db_partition_stats.[index_id]) dm_db_partition_stats ON indexes.[object_id] = dm_db_partition_stats.[object_id] AND indexes.[index_id] = dm_db_partition_stats.[index_id]'
          SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ' WHERE objects.[type] IN(''U'',''V'') AND objects.is_ms_shipped = 0 AND indexes.[type] IN(1,2,3,4) AND indexes.is_disabled = 0 AND indexes.is_hypothetical = 0'
          IF (@UpdateStatistics NOT IN('ALL','INDEX') OR @UpdateStatistics IS NULL) AND @PageCountLevel > 0 SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ' AND (dm_db_partition_stats.in_row_data_page_count >= @ParamPageCountLevel OR dm_db_partition_stats.in_row_data_page_count IS NULL)'
          IF NOT EXISTS(SELECT * FROM @ActionsPreferred) SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ' AND stats.stats_id IS NOT NULL'
        END

        IF (EXISTS(SELECT * FROM @ActionsPreferred) AND @UpdateStatistics = 'COLUMNS') OR @UpdateStatistics = 'ALL' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ' UNION '

        IF @UpdateStatistics IN('ALL','COLUMNS') SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + 'SELECT schemas.[schema_id] AS SchemaID, schemas.[name] AS SchemaName, objects.[object_id] AS ObjectID, objects.[name] AS ObjectName, RTRIM(objects.[type]) AS ObjectType, NULL AS IndexID, NULL AS IndexName, NULL AS IndexType, stats.stats_id AS StatisticsID, stats.name AS StatisticsName, NULL AS PartitionID, NULL AS PartitionNumber, NULL AS PartitionCount, 0 AS Selected, 0 AS Completed FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.stats stats INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.objects objects ON stats.[object_id] = objects.[object_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas schemas ON objects.[schema_id] = schemas.[schema_id] WHERE objects.[type] IN(''U'',''V'') AND objects.is_ms_shipped = 0 AND NOT EXISTS(SELECT * FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes indexes WHERE indexes.[object_id] = stats.[object_id] AND indexes.index_id = stats.stats_id)'

        SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ') IndexesStatistics ORDER BY SchemaName ASC, ObjectName ASC'
        IF (EXISTS(SELECT * FROM @ActionsPreferred) AND @UpdateStatistics = 'COLUMNS') OR @UpdateStatistics = 'ALL' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ', CASE WHEN IndexType IS NULL THEN 1 ELSE 0 END ASC'
        IF EXISTS(SELECT * FROM @ActionsPreferred) OR @UpdateStatistics IN('ALL','INDEX') SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ', IndexType ASC, IndexName ASC'
        IF @UpdateStatistics IN('ALL','COLUMNS') SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ', StatisticsName ASC'
        IF @PartitionLevel = 'Y' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ', PartitionNumber ASC'

        INSERT INTO @tmpIndexesStatistics (SchemaID, SchemaName, ObjectID, ObjectName, ObjectType, IndexID, IndexName, IndexType, StatisticsID, StatisticsName, PartitionID, PartitionNumber, PartitionCount, Selected, Completed)
        EXECUTE sp_executesql @statement = @CurrentCommandSelect01, @params = N'@ParamPageCountLevel int', @ParamPageCountLevel = @PageCountLevel
        SET @Error = @@ERROR
        IF @Error = 1222
        BEGIN
          SET @ErrorMessage = 'The system tables are locked in the database ' + QUOTENAME(@CurrentDatabase) + '.' + CHAR(13) + CHAR(10)
          SET @ErrorMessage = REPLACE(@ErrorMessage,'%','%%')
          RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
        END
      END

      IF @Indexes IS NULL
      BEGIN
        UPDATE tmpIndexesStatistics
        SET tmpIndexesStatistics.Selected = 1
        FROM @tmpIndexesStatistics tmpIndexesStatistics
      END
      ELSE
      BEGIN
        UPDATE tmpIndexesStatistics
        SET tmpIndexesStatistics.Selected = SelectedIndexes.Selected
        FROM @tmpIndexesStatistics tmpIndexesStatistics
        INNER JOIN @SelectedIndexes SelectedIndexes
        ON @CurrentDatabase LIKE REPLACE(SelectedIndexes.DatabaseName,'_','[_]') AND tmpIndexesStatistics.SchemaName LIKE REPLACE(SelectedIndexes.SchemaName,'_','[_]') AND tmpIndexesStatistics.ObjectName LIKE REPLACE(SelectedIndexes.ObjectName,'_','[_]') AND COALESCE(tmpIndexesStatistics.IndexName,tmpIndexesStatistics.StatisticsName) LIKE REPLACE(SelectedIndexes.IndexName,'_','[_]')
        WHERE SelectedIndexes.Selected = 1

        UPDATE tmpIndexesStatistics
        SET tmpIndexesStatistics.Selected = SelectedIndexes.Selected
        FROM @tmpIndexesStatistics tmpIndexesStatistics
        INNER JOIN @SelectedIndexes SelectedIndexes
        ON @CurrentDatabase LIKE REPLACE(SelectedIndexes.DatabaseName,'_','[_]') AND tmpIndexesStatistics.SchemaName LIKE REPLACE(SelectedIndexes.SchemaName,'_','[_]') AND tmpIndexesStatistics.ObjectName LIKE REPLACE(SelectedIndexes.ObjectName,'_','[_]') AND COALESCE(tmpIndexesStatistics.IndexName,tmpIndexesStatistics.StatisticsName) LIKE REPLACE(SelectedIndexes.IndexName,'_','[_]')
        WHERE SelectedIndexes.Selected = 0
      END

      WHILE EXISTS (SELECT * FROM @tmpIndexesStatistics WHERE Selected = 1 AND Completed = 0)
      BEGIN

        SELECT TOP 1 @CurrentIxID = IxID,
                     @CurrentSchemaID = SchemaID,
                     @CurrentSchemaName = SchemaName,
                     @CurrentObjectID = ObjectID,
                     @CurrentObjectName = ObjectName,
                     @CurrentObjectType = ObjectType,
                     @CurrentIndexID = IndexID,
                     @CurrentIndexName = IndexName,
                     @CurrentIndexType = IndexType,
                     @CurrentStatisticsID = StatisticsID,
                     @CurrentStatisticsName = StatisticsName,
                     @CurrentPartitionID = PartitionID,
                     @CurrentPartitionNumber = PartitionNumber,
                     @CurrentPartitionCount = PartitionCount
        FROM @tmpIndexesStatistics
        WHERE Selected = 1
        AND Completed = 0
        ORDER BY IxID ASC

        -- Is the index a partition?
        IF @CurrentPartitionNumber IS NULL OR @CurrentPartitionCount = 1 BEGIN SET @CurrentIsPartition = 0 END ELSE BEGIN SET @CurrentIsPartition = 1 END

        -- Does the index exist?
        IF @CurrentIndexID IS NOT NULL AND EXISTS(SELECT * FROM @ActionsPreferred)
        BEGIN
          IF @CurrentIsPartition = 0 SET @CurrentCommandSelect02 = 'IF EXISTS(SELECT * FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes indexes INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.objects objects ON indexes.[object_id] = objects.[object_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas schemas ON objects.[schema_id] = schemas.[schema_id] WHERE objects.[type] IN(''U'',''V'') AND objects.is_ms_shipped = 0 AND indexes.[type] IN(1,2,3,4) AND indexes.is_disabled = 0 AND indexes.is_hypothetical = 0 AND schemas.[schema_id] = @ParamSchemaID AND schemas.[name] = @ParamSchemaName AND objects.[object_id] = @ParamObjectID AND objects.[name] = @ParamObjectName AND objects.[type] = @ParamObjectType AND indexes.index_id = @ParamIndexID AND indexes.[name] = @ParamIndexName AND indexes.[type] = @ParamIndexType) BEGIN SET @ParamIndexExists = 1 END ELSE BEGIN SET @ParamIndexExists = 0 END'
          IF @CurrentIsPartition = 1 SET @CurrentCommandSelect02 = 'IF EXISTS(SELECT * FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes indexes INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.objects objects ON indexes.[object_id] = objects.[object_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas schemas ON objects.[schema_id] = schemas.[schema_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions partitions ON indexes.[object_id] = partitions.[object_id] AND indexes.index_id = partitions.index_id WHERE objects.[type] IN(''U'',''V'') AND objects.is_ms_shipped = 0 AND indexes.[type] IN(1,2,3,4) AND indexes.is_disabled = 0 AND indexes.is_hypothetical = 0 AND schemas.[schema_id] = @ParamSchemaID AND schemas.[name] = @ParamSchemaName AND objects.[object_id] = @ParamObjectID AND objects.[name] = @ParamObjectName AND objects.[type] = @ParamObjectType AND indexes.index_id = @ParamIndexID AND indexes.[name] = @ParamIndexName AND indexes.[type] = @ParamIndexType AND partitions.partition_id = @ParamPartitionID AND partitions.partition_number = @ParamPartitionNumber) BEGIN SET @ParamIndexExists = 1 END ELSE BEGIN SET @ParamIndexExists = 0 END'

          EXECUTE sp_executesql @statement = @CurrentCommandSelect02, @params = N'@ParamSchemaID int, @ParamSchemaName sysname, @ParamObjectID int, @ParamObjectName sysname, @ParamObjectType sysname, @ParamIndexID int, @ParamIndexName sysname, @ParamIndexType int, @ParamPartitionID bigint, @ParamPartitionNumber int, @ParamIndexExists bit OUTPUT', @ParamSchemaID = @CurrentSchemaID, @ParamSchemaName = @CurrentSchemaName, @ParamObjectID = @CurrentObjectID, @ParamObjectName = @CurrentObjectName, @ParamObjectType = @CurrentObjectType, @ParamIndexID = @CurrentIndexID, @ParamIndexName = @CurrentIndexName, @ParamIndexType = @CurrentIndexType, @ParamPartitionID = @CurrentPartitionID, @ParamPartitionNumber = @CurrentPartitionNumber, @ParamIndexExists = @CurrentIndexExists OUTPUT

          IF @CurrentIndexExists = 0 GOTO NoAction
        END

        -- Does the statistics exist?
        IF @CurrentStatisticsID IS NOT NULL AND @UpdateStatistics IS NOT NULL
        BEGIN
          SET @CurrentCommandSelect03 = 'IF EXISTS(SELECT * FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.stats stats INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.objects objects ON stats.[object_id] = objects.[object_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas schemas ON objects.[schema_id] = schemas.[schema_id] WHERE objects.[type] IN(''U'',''V'') AND objects.is_ms_shipped = 0 AND schemas.[schema_id] = @ParamSchemaID AND schemas.[name] = @ParamSchemaName AND objects.[object_id] = @ParamObjectID AND objects.[name] = @ParamObjectName AND objects.[type] = @ParamObjectType AND stats.stats_id = @ParamStatisticsID AND stats.[name] = @ParamStatisticsName) BEGIN SET @ParamStatisticsExists = 1 END ELSE BEGIN SET @ParamStatisticsExists = 0 END'

          EXECUTE sp_executesql @statement = @CurrentCommandSelect03, @params = N'@ParamSchemaID int, @ParamSchemaName sysname, @ParamObjectID int, @ParamObjectName sysname, @ParamObjectType sysname, @ParamStatisticsID int, @ParamStatisticsName sysname, @ParamStatisticsExists bit OUTPUT', @ParamSchemaID = @CurrentSchemaID, @ParamSchemaName = @CurrentSchemaName, @ParamObjectID = @CurrentObjectID, @ParamObjectName = @CurrentObjectName, @ParamObjectType = @CurrentObjectType, @ParamStatisticsID = @CurrentStatisticsID, @ParamStatisticsName = @CurrentStatisticsName, @ParamStatisticsExists = @CurrentStatisticsExists OUTPUT

          IF @CurrentStatisticsExists = 0 GOTO NoAction
        END

        -- Does the index contain a LOB?
        IF @CurrentIndexID IS NOT NULL AND @CurrentIndexType IN(1,2) AND EXISTS(SELECT * FROM @ActionsPreferred)
        BEGIN
          IF @CurrentIndexType = 1 SET @CurrentCommandSelect04 = 'IF EXISTS(SELECT * FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.columns columns INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.types types ON columns.system_type_id = types.user_type_id OR (columns.user_type_id = types.user_type_id AND types.is_assembly_type = 1) WHERE columns.[object_id] = @ParamObjectID AND (types.name IN(''xml'',''image'',''text'',''ntext'') OR (types.name IN(''varchar'',''nvarchar'',''varbinary'') AND columns.max_length = -1) OR (types.is_assembly_type = 1 AND columns.max_length = -1))) BEGIN SET @ParamIsLOB = 1 END ELSE BEGIN SET @ParamIsLOB = 0 END'
          IF @CurrentIndexType = 2 SET @CurrentCommandSelect04 = 'IF EXISTS(SELECT * FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.index_columns index_columns INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.columns columns ON index_columns.[object_id] = columns.[object_id] AND index_columns.column_id = columns.column_id INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.types types ON columns.system_type_id = types.user_type_id OR (columns.user_type_id = types.user_type_id AND types.is_assembly_type = 1) WHERE index_columns.[object_id] = @ParamObjectID AND index_columns.index_id = @ParamIndexID AND (types.[name] IN(''xml'',''image'',''text'',''ntext'') OR (types.[name] IN(''varchar'',''nvarchar'',''varbinary'') AND columns.max_length = -1) OR (types.is_assembly_type = 1 AND columns.max_length = -1))) BEGIN SET @ParamIsLOB = 1 END ELSE BEGIN SET @ParamIsLOB = 0 END'

          EXECUTE sp_executesql @statement = @CurrentCommandSelect04, @params = N'@ParamObjectID int, @ParamIndexID int, @ParamIsLOB bit OUTPUT', @ParamObjectID = @CurrentObjectID, @ParamIndexID = @CurrentIndexID, @ParamIsLOB = @CurrentIsLOB OUTPUT
        END

        -- Is Allow_Page_Locks set to On?
        IF @CurrentIndexID IS NOT NULL AND EXISTS(SELECT * FROM @ActionsPreferred)
        BEGIN
          SET @CurrentCommandSelect05 = 'IF EXISTS(SELECT * FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes indexes WHERE indexes.[object_id] = @ParamObjectID AND indexes.[index_id] = @ParamIndexID AND indexes.[allow_page_locks] = 1) BEGIN SET @ParamAllowPageLocks = 1 END ELSE BEGIN SET @ParamAllowPageLocks = 0 END'

          EXECUTE sp_executesql @statement = @CurrentCommandSelect05, @params = N'@ParamObjectID int, @ParamIndexID int, @ParamAllowPageLocks bit OUTPUT', @ParamObjectID = @CurrentObjectID, @ParamIndexID = @CurrentIndexID, @ParamAllowPageLocks = @CurrentAllowPageLocks OUTPUT
        END

        -- Is No_Recompute set to On?
        IF @CurrentStatisticsID IS NOT NULL AND @UpdateStatistics IS NOT NULL
        BEGIN
          SET @CurrentCommandSelect06 = 'IF EXISTS(SELECT * FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.stats stats WHERE stats.[object_id] = @ParamObjectID AND stats.[stats_id] = @ParamStatisticsID AND stats.[no_recompute] = 1) BEGIN SET @ParamNoRecompute = 1 END ELSE BEGIN SET @ParamNoRecompute = 0 END'

          EXECUTE sp_executesql @statement = @CurrentCommandSelect06, @params = N'@ParamObjectID int, @ParamStatisticsID int, @ParamNoRecompute bit OUTPUT', @ParamObjectID = @CurrentObjectID, @ParamStatisticsID = @CurrentStatisticsID, @ParamNoRecompute = @CurrentNoRecompute OUTPUT
        END

        -- Has the data in the statistics been modified since the statistics was last updated?
        IF @CurrentStatisticsID IS NOT NULL AND @UpdateStatistics IS NOT NULL AND @OnlyModifiedStatistics = 'Y'
        BEGIN
          SET @CurrentCommandSelect07 = 'IF EXISTS(SELECT * FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.sysindexes sysindexes WHERE sysindexes.[id] = @ParamObjectID AND sysindexes.[indid] = @ParamStatisticsID AND sysindexes.[rowmodctr] <> 0) BEGIN SET @ParamStatisticsModified = 1 END ELSE BEGIN SET @ParamStatisticsModified = 0 END'

          EXECUTE sp_executesql @statement = @CurrentCommandSelect07, @params = N'@ParamObjectID int, @ParamStatisticsID int, @ParamStatisticsModified bit OUTPUT', @ParamObjectID = @CurrentObjectID, @ParamStatisticsID = @CurrentStatisticsID, @ParamStatisticsModified = @CurrentStatisticsModified OUTPUT
        END

        -- Is the index on a read-only filegroup?
        IF @CurrentIndexID IS NOT NULL AND EXISTS(SELECT * FROM @ActionsPreferred)
        BEGIN
          SET @CurrentCommandSelect08 = 'IF EXISTS(SELECT * FROM (SELECT filegroups.data_space_id FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes indexes INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.destination_data_spaces destination_data_spaces ON indexes.data_space_id = destination_data_spaces.partition_scheme_id INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups filegroups ON destination_data_spaces.data_space_id = filegroups.data_space_id WHERE filegroups.is_read_only = 1 AND indexes.[object_id] = @ParamObjectID AND indexes.[index_id] = @ParamIndexID'
          IF @CurrentIsPartition = 1 SET @CurrentCommandSelect08 = @CurrentCommandSelect08 + ' AND destination_data_spaces.destination_id = @ParamPartitionNumber'
          SET @CurrentCommandSelect08 = @CurrentCommandSelect08 + ' UNION SELECT filegroups.data_space_id FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes indexes INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups ON indexes.data_space_id = filegroups.data_space_id WHERE filegroups.is_read_only = 1 AND indexes.[object_id] = @ParamObjectID AND indexes.[index_id] = @ParamIndexID'
          IF @CurrentIndexType = 1 SET @CurrentCommandSelect08 = @CurrentCommandSelect08 + ' UNION SELECT filegroups.data_space_id FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.tables tables INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups filegroups ON tables.lob_data_space_id = filegroups.data_space_id WHERE filegroups.is_read_only = 1 AND tables.[object_id] = @ParamObjectID'
          SET @CurrentCommandSelect08 = @CurrentCommandSelect08 + ') ReadOnlyFileGroups) BEGIN SET @ParamOnReadOnlyFileGroup = 1 END ELSE BEGIN SET @ParamOnReadOnlyFileGroup = 0 END'

          EXECUTE sp_executesql @statement = @CurrentCommandSelect08, @params = N'@ParamObjectID int, @ParamIndexID int, @ParamPartitionNumber int, @ParamOnReadOnlyFileGroup bit OUTPUT', @ParamObjectID = @CurrentObjectID, @ParamIndexID = @CurrentIndexID, @ParamPartitionNumber = @CurrentPartitionNumber, @ParamOnReadOnlyFileGroup = @CurrentOnReadOnlyFileGroup OUTPUT
        END

        -- Is the index fragmented?
        IF @CurrentIndexID IS NOT NULL
        AND EXISTS(SELECT * FROM @ActionsPreferred)
        AND (EXISTS(SELECT [Priority], [Action], COUNT(*) FROM @ActionsPreferred GROUP BY [Priority], [Action] HAVING COUNT(*) <> 3) OR @PageCountLevel > 0)
        BEGIN
          SELECT @CurrentFragmentationLevel = MAX(avg_fragmentation_in_percent),
                 @CurrentPageCount = SUM(page_count)
          FROM sys.dm_db_index_physical_stats(DB_ID(@CurrentDatabase), @CurrentObjectID, @CurrentIndexID, @CurrentPartitionNumber, 'LIMITED')
          WHERE alloc_unit_type_desc = 'IN_ROW_DATA'
          AND index_level = 0
          SET @Error = @@ERROR
          IF @Error = 1222
          BEGIN
            SET @ErrorMessage = 'The dynamic management view sys.dm_db_index_physical_stats is locked on the index ' + QUOTENAME(@CurrentSchemaName) + '.' + QUOTENAME(@CurrentObjectName) + '.' + QUOTENAME(@CurrentIndexName) + '.' + CHAR(13) + CHAR(10)
            SET @ErrorMessage = REPLACE(@ErrorMessage,'%','%%')
            RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
            GOTO NoAction
          END
        END

        -- Select fragmentation group
        IF @CurrentIndexID IS NOT NULL AND EXISTS(SELECT * FROM @ActionsPreferred)
        BEGIN
          SET @CurrentFragmentationGroup = CASE
          WHEN @CurrentFragmentationLevel >= @FragmentationLevel2 THEN 'High'
          WHEN @CurrentFragmentationLevel >= @FragmentationLevel1 AND @CurrentFragmentationLevel < @FragmentationLevel2 THEN 'Medium'
          WHEN @CurrentFragmentationLevel < @FragmentationLevel1 THEN 'Low'
          END
        END

        -- Which actions are allowed?
        IF @CurrentIndexID IS NOT NULL AND EXISTS(SELECT * FROM @ActionsPreferred)
        BEGIN
          IF @CurrentOnReadOnlyFileGroup = 0 AND @CurrentAllowPageLocks = 1
          BEGIN
            INSERT INTO @CurrentActionsAllowed ([Action])
            VALUES ('INDEX_REORGANIZE')
          END
          IF @CurrentOnReadOnlyFileGroup = 0
          BEGIN
            INSERT INTO @CurrentActionsAllowed ([Action])
            VALUES ('INDEX_REBUILD_OFFLINE')
          END
          IF @CurrentOnReadOnlyFileGroup = 0 AND @CurrentIndexType IN(1,2) AND @CurrentIsLOB = 0 AND @CurrentIsPartition = 0 AND SERVERPROPERTY('EngineEdition') = 3
          BEGIN
            INSERT INTO @CurrentActionsAllowed ([Action])
            VALUES ('INDEX_REBUILD_ONLINE')
          END
        END

        -- Decide action
        IF @CurrentIndexID IS NOT NULL
        AND EXISTS(SELECT * FROM @ActionsPreferred)
        AND (@CurrentPageCount >= @PageCountLevel OR @PageCountLevel = 0)
        BEGIN
          IF EXISTS(SELECT [Priority], [Action], COUNT(*) FROM @ActionsPreferred GROUP BY [Priority], [Action] HAVING COUNT(*) <> 3)
          BEGIN
            SELECT @CurrentAction = [Action]
            FROM @ActionsPreferred
            WHERE FragmentationGroup = @CurrentFragmentationGroup
            AND [Priority] = (SELECT MIN([Priority])
                              FROM @ActionsPreferred
                              WHERE FragmentationGroup = @CurrentFragmentationGroup
                              AND [Action] IN (SELECT [Action] FROM @CurrentActionsAllowed))
          END
          ELSE
          BEGIN
            SELECT @CurrentAction = [Action]
            FROM @ActionsPreferred
            WHERE [Priority] = (SELECT MIN([Priority])
                                FROM @ActionsPreferred
                                WHERE [Action] IN (SELECT [Action] FROM @CurrentActionsAllowed))
          END
        END

        -- Workaround for a bug in SQL Server 2005, SQL Server 2008 and SQL Server 2008 R2
        IF @CurrentIndexID IS NOT NULL
        BEGIN
          SET @CurrentMaxDOP = @MaxDOP
          IF @Version < 11 AND @CurrentAction = 'INDEX_REBUILD_ONLINE' AND @CurrentAllowPageLocks = 0
          BEGIN
            SET @CurrentMaxDOP = 1
          END
        END

        -- Update statistics?
        IF @CurrentStatisticsID IS NOT NULL
        AND (@UpdateStatistics = 'ALL' OR (@UpdateStatistics = 'INDEX' AND @CurrentIndexID IS NOT NULL) OR (@UpdateStatistics = 'COLUMNS' AND @CurrentIndexID IS NULL))
        AND (@CurrentStatisticsModified = 1 OR @OnlyModifiedStatistics = 'N')
        AND ((@CurrentIsPartition = 0 AND (@CurrentAction NOT IN('INDEX_REBUILD_ONLINE','INDEX_REBUILD_OFFLINE') OR @CurrentAction IS NULL)) OR (@CurrentIsPartition = 1 AND @CurrentPartitionNumber = @CurrentPartitionCount))
        BEGIN
          SET @CurrentUpdateStatistics = 'Y'
        END
        ELSE
        BEGIN
          SET @CurrentUpdateStatistics = 'N'
        END

        -- Create comment
        IF @CurrentIndexID IS NOT NULL
        BEGIN
          SET @CurrentComment = 'ObjectType: ' + CASE WHEN @CurrentObjectType = 'U' THEN 'Table' WHEN @CurrentObjectType = 'V' THEN 'View' ELSE 'N/A' END + ', '
          SET @CurrentComment = @CurrentComment + 'IndexType: ' + CASE WHEN @CurrentIndexType = 1 THEN 'Clustered' WHEN @CurrentIndexType = 2 THEN 'NonClustered' WHEN @CurrentIndexType = 3 THEN 'XML' WHEN @CurrentIndexType = 4 THEN 'Spatial' ELSE 'N/A' END + ', '
          SET @CurrentComment = @CurrentComment + 'LOB: ' + CASE WHEN @CurrentIsLOB = 1 THEN 'Yes' WHEN @CurrentIsLOB = 0 THEN 'No' ELSE 'N/A' END + ', '
          SET @CurrentComment = @CurrentComment + 'AllowPageLocks: ' + CASE WHEN @CurrentAllowPageLocks = 1 THEN 'Yes' WHEN @CurrentAllowPageLocks = 0 THEN 'No' ELSE 'N/A' END + ', '
          SET @CurrentComment = @CurrentComment + 'PageCount: ' + ISNULL(CAST(@CurrentPageCount AS nvarchar),'N/A') + ', '
          SET @CurrentComment = @CurrentComment + 'Fragmentation: ' + ISNULL(CAST(@CurrentFragmentationLevel AS nvarchar),'N/A')
        END

        -- Check time limit
        IF GETDATE() >= DATEADD(ss,@TimeLimit,@StartTime)
        BEGIN
          SET @Execute = 'N'
        END

        IF @CurrentIndexID IS NOT NULL AND @CurrentAction IS NOT NULL
        BEGIN
          SET @CurrentCommand01 = 'ALTER INDEX ' + QUOTENAME(@CurrentIndexName) + ' ON ' + QUOTENAME(@CurrentDatabase) + '.' + QUOTENAME(@CurrentSchemaName) + '.' + QUOTENAME(@CurrentObjectName)

          IF @CurrentAction IN('INDEX_REBUILD_ONLINE','INDEX_REBUILD_OFFLINE')
          BEGIN
            SET @CurrentCommand01 = @CurrentCommand01 + ' REBUILD'
            IF @CurrentIsPartition = 1 SET @CurrentCommand01 = @CurrentCommand01 + ' PARTITION = ' + CAST(@CurrentPartitionNumber AS nvarchar)
            SET @CurrentCommand01 = @CurrentCommand01 + ' WITH ('
            IF @SortInTempdb = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + 'SORT_IN_TEMPDB = ON'
            IF @SortInTempdb = 'N' SET @CurrentCommand01 = @CurrentCommand01 + 'SORT_IN_TEMPDB = OFF'
            IF @CurrentAction = 'INDEX_REBUILD_ONLINE' AND @CurrentIsPartition = 0 SET @CurrentCommand01 = @CurrentCommand01 + ', ONLINE = ON'
            IF @CurrentAction = 'INDEX_REBUILD_OFFLINE' AND @CurrentIsPartition = 0 SET @CurrentCommand01 = @CurrentCommand01 + ', ONLINE = OFF'
            IF @CurrentMaxDOP IS NOT NULL SET @CurrentCommand01 = @CurrentCommand01 + ', MAXDOP = ' + CAST(@CurrentMaxDOP AS nvarchar)
            IF @FillFactor IS NOT NULL AND @CurrentIsPartition = 0 SET @CurrentCommand01 = @CurrentCommand01 + ', FILLFACTOR = ' + CAST(@FillFactor AS nvarchar)
            IF @PadIndex = 'Y' AND @CurrentIsPartition = 0 SET @CurrentCommand01 = @CurrentCommand01 + ', PAD_INDEX = ON'
            IF @PadIndex = 'N' AND @CurrentIsPartition = 0 SET @CurrentCommand01 = @CurrentCommand01 + ', PAD_INDEX = OFF'
            SET @CurrentCommand01 = @CurrentCommand01 + ')'
          END

          IF @CurrentAction IN('INDEX_REORGANIZE')
          BEGIN
            SET @CurrentCommand01 = @CurrentCommand01 + ' REORGANIZE'
            IF @CurrentIsPartition = 1 SET @CurrentCommand01 = @CurrentCommand01 + ' PARTITION = ' + CAST(@CurrentPartitionNumber AS nvarchar)
            SET @CurrentCommand01 = @CurrentCommand01 + ' WITH ('
            IF @LOBCompaction = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + 'LOB_COMPACTION = ON'
            IF @LOBCompaction = 'N' SET @CurrentCommand01 = @CurrentCommand01 + 'LOB_COMPACTION = OFF'
            SET @CurrentCommand01 = @CurrentCommand01 + ')'
          END

          EXECUTE @CurrentCommandOutput01 = [dbo].[CommandExecute] @Command = @CurrentCommand01, @Comment = @CurrentComment, @Mode = 2, @Execute = @Execute
          SET @Error = @@ERROR
          IF @Error <> 0 SET @CurrentCommandOutput01 = @Error

          IF @CurrentDelay IS NOT NULL
          BEGIN
            WAITFOR DELAY @CurrentDelay
          END
        END

        IF @CurrentStatisticsID IS NOT NULL AND @CurrentUpdateStatistics = 'Y'
        BEGIN
          SET @CurrentCommand02 = 'UPDATE STATISTICS ' + QUOTENAME(@CurrentDatabase) + '.' + QUOTENAME(@CurrentSchemaName) + '.' + QUOTENAME(@CurrentObjectName) + ' ' + QUOTENAME(@CurrentStatisticsName)
          IF @StatisticsSample IS NOT NULL OR @StatisticsResample = 'Y' OR @CurrentNoRecompute = 1 SET @CurrentCommand02 = @CurrentCommand02 + ' WITH'
          IF @StatisticsSample = 100 SET @CurrentCommand02 = @CurrentCommand02 + ' FULLSCAN'
          IF @StatisticsSample IS NOT NULL AND @StatisticsSample <> 100 SET @CurrentCommand02 = @CurrentCommand02 + ' SAMPLE ' + CAST(@StatisticsSample AS nvarchar) + ' PERCENT'
          IF @StatisticsResample = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + ' RESAMPLE'
          IF (@StatisticsSample IS NOT NULL OR @StatisticsResample = 'Y') AND @CurrentNoRecompute = 1 SET @CurrentCommand02 = @CurrentCommand02 + ','
          IF @CurrentNoRecompute = 1 SET @CurrentCommand02 = @CurrentCommand02 + ' NORECOMPUTE'

          EXECUTE @CurrentCommandOutput02 = [dbo].[CommandExecute] @Command = @CurrentCommand02, @Comment = '', @Mode = 2, @Execute = @Execute
          SET @Error = @@ERROR
          IF @Error <> 0 SET @CurrentCommandOutput02 = @Error
        END

        NoAction:

        -- Update that the index is completed
        UPDATE @tmpIndexesStatistics
        SET Completed = 1
        WHERE Selected = 1
        AND Completed = 0
        AND IxID = @CurrentIxID

        -- Clear variables
        SET @CurrentCommandSelect02 = NULL
        SET @CurrentCommandSelect03 = NULL
        SET @CurrentCommandSelect04 = NULL
        SET @CurrentCommandSelect05 = NULL
        SET @CurrentCommandSelect06 = NULL
        SET @CurrentCommandSelect07 = NULL
        SET @CurrentCommandSelect08 = NULL

        SET @CurrentCommand01 = NULL
        SET @CurrentCommand02 = NULL

        SET @CurrentCommandOutput01 = NULL
        SET @CurrentCommandOutput02 = NULL

        SET @CurrentIxID = NULL
        SET @CurrentSchemaID = NULL
        SET @CurrentSchemaName = NULL
        SET @CurrentObjectID = NULL
        SET @CurrentObjectName = NULL
        SET @CurrentObjectType = NULL
        SET @CurrentIndexID = NULL
        SET @CurrentIndexName = NULL
        SET @CurrentIndexType = NULL
        SET @CurrentStatisticsID = NULL
        SET @CurrentStatisticsName = NULL
        SET @CurrentPartitionID = NULL
        SET @CurrentPartitionNumber = NULL
        SET @CurrentPartitionCount = NULL
        SET @CurrentIsPartition = NULL
        SET @CurrentIndexExists = NULL
        SET @CurrentStatisticsExists = NULL
        SET @CurrentIsLOB = NULL
        SET @CurrentAllowPageLocks = NULL
        SET @CurrentNoRecompute = NULL
        SET @CurrentStatisticsModified = NULL
        SET @CurrentOnReadOnlyFileGroup = NULL
        SET @CurrentFragmentationLevel = NULL
        SET @CurrentPageCount = NULL
        SET @CurrentFragmentationGroup = NULL
        SET @CurrentAction = NULL
        SET @CurrentMaxDOP = NULL
        SET @CurrentUpdateStatistics = NULL
        SET @CurrentComment = NULL

        DELETE FROM @CurrentActionsAllowed

      END

    END

    -- Update that the database is completed
    UPDATE @tmpDatabases
    SET Completed = 1
    WHERE ID = @CurrentID

    -- Clear variables
    SET @CurrentID = NULL
    SET @CurrentDatabase = NULL
    SET @CurrentIsDatabaseAccessible = NULL
    SET @CurrentMirroringRole = NULL

    SET @CurrentCommandSelect01 = NULL

    DELETE FROM @tmpIndexesStatistics

  END

  ----------------------------------------------------------------------------------------------------
  --// Log completing information                                                                 //--
  ----------------------------------------------------------------------------------------------------

  Logging:
  SET @EndMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120)
  SET @EndMessage = REPLACE(@EndMessage,'%','%%')
  RAISERROR(@EndMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------

END
GO
--========================================================================
USE [msdb]
GO
IF NOT EXISTS (select name from sysoperators where name='FakeBusiness_DBAs')
	EXEC msdb.dbo.sp_add_operator @name=N'FakeBusiness_DBAs', 
		@enabled=1, 
		@pager_days=0, 
		@email_address=N'SL.DBAS@Fake.com'

--========================================================================
IF NOT EXISTS (select name from msdb.dbo.sysmail_profile where name='Fake')
BEGIN
	--Enabling Database Mail
	exec sp_configure 'show advanced options',1
	reconfigure										  
	exec sp_configure 'Database Mail XPs',1							  
	reconfigure 
	exec sp_configure 'xp_cmdshell', 1
	RECONFIGURE WITH OVERRIDE

	-- Determine SMTP IP based on server location
	DECLARE @SMTP_IP varchar(15)
    SET @SMTP_IP = '10.232.0.230' -- DEFAULT TO COMMSRV02
    CREATE TABLE #temp (ipLine varchar(200))
    INSERT #temp EXEC MASTER..xp_cmdshell 'ipconfig'
    IF EXISTS (select top 1 ipLine from #temp where ipLine LIKE '%10.254.%')
		set @SMTP_IP = '10.0.0.240'
	IF EXISTS (select top 1 ipLine from #temp where ipLine LIKE '%10.238.%')
		set @SMTP_IP = '10.232.0.230'
	exec sp_configure 'xp_cmdshell', 0
	RECONFIGURE WITH OVERRIDE

	-- Determine Server Email Address
	DECLARE @SERVER_EMAIL varchar(255)
	DECLARE @DISPLAY_NAME varchar(255)
	select @SERVER_EMAIL = REPLACE(@@SERVERNAME,'\','_') + '.sql@Fake.com'
	select @DISPLAY_NAME = REPLACE(@@SERVERNAME,'\','_')

	--Creating a Profile
	EXECUTE msdb.dbo.sysmail_add_profile_sp
	@profile_name = 'Fake',
	@description = 'Fake mail profile'

	EXECUTE msdb.dbo.sysmail_add_account_sp
	@account_name = 'Fake',
	@email_address = @SERVER_EMAIL,
	@mailserver_name = @SMTP_IP,
	@display_name = @DISPLAY_NAME,
	@port=25,
	@enable_ssl=0

	-- Adding the account to the profile
	EXECUTE msdb.dbo.sysmail_add_profileaccount_sp
	@profile_name = 'Fake',
	@account_name = 'Fake',
	@sequence_number =1

	-- Granting access to the profile to the DatabaseMailUserRole of MSDB
	EXECUTE msdb.dbo.sysmail_add_principalprofile_sp
	@profile_name = 'Fake',
	@principal_id = 0,
	@is_default = 1

	EXEC msdb.dbo.sp_set_sqlagent_properties @email_save_in_sent_folder=1, 
		@databasemail_profile=N'Fake', 
		@use_databasemail=1
END

--========================================================================
USE [DBATEST]
GO

/****** Object:  Table [dbo].[TrueCacheHitQOSBase]    Script Date: 12/20/2012 00:00:00 ******/
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

TRUNCATE TABLE DBATEST.dbo.TrueCacheHitQOSBase
GO
INSERT INTO DBATEST.dbo.TrueCacheHitQOSBase
SELECT PR.cntr_value,PL.cntr_value,I.create_date, CAST(((CAST((PL.cntr_value-Pr.cntr_value) as float)/PL.cntr_value)*100) as decimal(4,1))
FROM sys.dm_os_performance_counters PR
CROSS JOIN sys.dm_os_performance_counters PL
CROSS JOIN sys.databases I
WHERE PR.counter_name='Page Reads/sec' and PL.counter_name='Page Lookups/sec' and I.database_id=2
GO

--========================================================================
USE [msdb]
GO

/****** Object:  Job [FakeBusiness performance stats collection]    Script Date: 1900-01-01-1900:00:00 ******/
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
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'FakeBusiness performance stats collection', 
		@enabled=0, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'FakeBusiness_DBAs', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Collect latency stats]    Script Date: 1900-01-01-1900:00:00 ******/
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
		@database_name=N'DBATEST', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Collect wait stats]    Script Date: 1900-01-01-1900:00:00 ******/
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
		@database_name=N'DBATEST', 
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

/****** Object:  Job [TrueCacheHitUpdate]    Script Date: 12/20/2012 00:00:00 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 12/20/2012 00:00:00 ******/
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
            @owner_login_name=N'FakeBusiness_DBAs', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [UpdateTrueCacheHit]    Script Date: 12/20/2012 00:00:00 ******/
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
--memory as a percentage of total pages requested after the restart, since we dont have 
--the page reads and page lookups information from between the last measurement and 
--the instance restart


UPDATE DBATEST.dbo.TrueCacheHitQOSBase
SET PageReads=Pr.cntr_value, PageLookups=PL.cntr_value, InstanceStartTime=I.create_date,
TrueCacheHitRatio=CASE
WHEN QOS.InstanceStarttime=(select create_date from sys.databases where database_id=2) THEN CAST(((CAST(((PL.cntr_value-QOS.PageLookups)-(PR.cntr_value-QOS.PageReads))+1 as float)/((PL.cntr_value-QOS.PageLookups)+1))*100) as decimal(4,1))
ELSE CAST(((CAST((PL.cntr_value-Pr.cntr_value)+1 as float)/(PL.cntr_value+1))*100) as decimal(4,1))
END
FROM sys.dm_os_performance_counters PR
CROSS JOIN sys.dm_os_performance_counters PL
CROSS JOIN sys.databases I
CROSS JOIN DBATEST.dbo.trueCacheHitQOSBase QOS
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


--========================================================================
USE [msdb]
GO

if exists ( SELECT * FROM msdb.dbo.sysjobs WHERE (name = N'Optimizations')  )
	EXEC msdb.dbo.sp_delete_job @job_name = N'Optimizations'
go 

/****** Object:  Job [Optimizations]    Script Date: 1900-01-01-1900:00:00 ******/
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
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Optimizations', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'New reindex script to run daily.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'FakeBusiness_DBAs', 
		@notify_email_operator_name=N'FakeBusiness_DBAs', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [DatabaseIntegrityCheck]    Script Date: 1900-01-01-1900:00:00 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'DatabaseIntegrityCheck', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'if datename(weekday, (getdate())) = ''Sunday''
begin
	EXECUTE [DBATEST].[dbo].[DatabaseIntegrityCheck]
	   @Databases = ''ALL_DATABASES'' 
end
else
begin
	EXECUTE [DBATEST].[dbo].[DatabaseIntegrityCheck]
	   @Databases = ''ALL_DATABASES'', @PhysicalOnly = ''Y''
end
', 
		@database_name=N'DBATEST', 
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [IndexOptimize]    Script Date: 1900-01-01-1900:00:00 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'IndexOptimize', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXECUTE [dbo].[IndexOptimize] @Databases = ''USER_DATABASES'',  @SortInTempdb=''Y''', 
		@database_name=N'DBATEST', 
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Daily2am', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20091005, 
		@active_end_date=99991231, 
		@active_start_time=20000, 
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


--===============================================================================
/* This block ups the Agent history */
USE [msdb]
GO
EXEC msdb.dbo.sp_set_sqlagent_properties @jobhistory_max_rows=50000, 
		@jobhistory_max_rows_per_job=1000
GO

--===============================================================================
/* Ths creates the manual shrink job */
use [DBATEST] 
go

IF EXISTS( select * from sys.objects where name='FakeMonShrinkTlogs' )
	drop PROCEDURE [dbo].FakeMonShrinkTlogs
go
/****** Object:  StoredProcedure [dbo].[FakeMonShrinkTlogs]    Script Date: 1900-01-01-1900:00:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create procedure [dbo].[FakeMonShrinkTlogs] 
as 
BEGIN


SET NOCOUNT ON
DECLARE @execute int
select @execute = 1

DECLARE @cmd1 VARCHAR(8000)
DECLARE @cmd2 VARCHAR(8000)
DECLARE @cmd3 VARCHAR(8000)

CREATE TABLE #log(
        id int identity(1,1) not null,
        groupid      INT DEFAULT 0 NULL,
        dbname       sysname NOT NULL,
        dbcompat VARCHAR(10),
--      LogSize      numeric(15,7) NOT NULL,
        LogSize      numeric(38,7) NOT NULL,
--      LogUsed      numeric(9,5) NOT NULL,
        LogUsed      numeric(38,6) NOT NULL,
        Status       int NOT NULL,
        [Name]   VARCHAR(300) NULL,
        FilePath     VARCHAR(500) NULL,
        Autogrowth       VARCHAR(500) NULL,
        init_size_MB DECIMAL (38,7) NULL,
        tempdb_growth_MB DECIMAL (38,7) NULL )

CREATE TABLE #dblog(
        dbname       sysname NOT NULL,
        LogSize      numeric(38,7) NOT NULL,
        LogUsed      numeric(38,6) NOT NULL,
        Status       int NOT NULL,
)

DECLARE @DBs table (name sysname, status varchar(100), dbcompat varchar(10))
DECLARE @CurrDB varchar(500)
DECLARE @CurrCmptlevel varchar(10)

INSERT INTO @DBs (name, dbcompat)
	SELECT	name, cmptlevel
	FROM	master..sysdatabases 
	WHERE category IN ('0', '1','16') 
	AND CAST(DATABASEPROPERTYEX (name, 'status') AS VARCHAR(500)) = 'ONLINE'
	ORDER BY name

SELECT @CurrDB = MIN(name) FROM @DBs
SELECT @CurrCmptlevel = dbcompat FROM @DBs WHERE name = @CurrDB

SELECT @CurrDB = MIN(name) FROM @DBs
SELECT @CurrCmptlevel = dbcompat FROM @DBs WHERE name = @CurrDB

--Log files
WHILE @CurrDB IS NOT NULL
BEGIN
        --Update log file logical names
        SET @cmd3 = 'USE [' + @CurrDB + ']; TRUNCATE TABLE #dblog; INSERT #dblog (dbname, LogSize, LogUsed, Status) EXEC(''DBCC sqlperf(logspace) with no_infomsgs''); INSERT #log (dbname, Name, FilePath, Autogrowth, LogSize, LogUsed, Status) SELECT ''' + @CurrDB + ''',[Name] = s.name,[FilePath] = s.filename,Autogrowth = ''Autogrowth: '' + CASE WHEN (s.status & 0x100000 = 0 AND CEILING((s.growth * 8192.0)/(1024.0*1024.0)) = 0.00) OR s.growth = 0 THEN ''None'' WHEN s.status & 0x100000 = 0 THEN ''By '' + CONVERT(VARCHAR,CEILING((s.growth * 8192.0)/(1024.0*1024.0))) + '' MB'' ELSE ''By '' + CONVERT(VARCHAR, s.growth) + '' percent'' END + CASE WHEN (s.status & 0x100000 = 0 AND CEILING((s.growth * 8192.0)/(1024.0*1024.0)) = 0.00) OR s.growth = 0 THEN '''' WHEN CAST([maxsize]*8.0/1024 AS DEC(20,2)) <= 0.00 THEN '', unrestricted growth'' ELSE '', restricted growth to '' + CAST(CAST([maxsize]*8.0/1024 AS DEC(20)) AS VARCHAR) + '' MB'' END ,LogSize = 0,LogUsed = 0,Status = 0 from dbo.sysfiles s where s.groupid = 0; UPDATE #log SET LogSize = d.LogSize,LogUsed = d.LogUsed,Status = d.Status, dbcompat = ''' + @CurrCmptlevel + ''' FROM #log l INNER JOIN #dblog d on l.dbname = d.dbname where l.dbname = ''' + @currDB + ''''
        EXEC (@cmd3)

        SELECT @CurrDB = MIN(name) FROM @DBs WHERE name > @CurrDB
        SELECT @CurrCmptlevel = dbcompat FROM @DBs WHERE name = @CurrDB
END

DELETE #log where Name IS NULL --Clean up #log

DELETE #log FROM #log l
	lEFT JOIN (	
		SELECT	dbname, Name, MIN(id) AS id 
		FROM	#log GROUP BY dbname, Name  ) k
		ON l.dbname = k.dbname AND l.Name = k.Name AND l.id = k.id
	WHERE k.id IS NULL

--Get tempdb initial file sizes - update tempdb log file init sizes
UPDATE [#log]
SET [init_size_MB] = a.Initial_Size_MB
FROM #log l
INNER JOIN (
        SELECT	[DB_Name] = 'tempdb',
				f.[name] AS logical_file_Name,
                (CAST(f.[size] AS DECIMAL) * 8192) / 1024 /1024 AS Initial_Size_MB
        FROM master..sysaltfiles f
                INNER JOIN master..sysdatabases d
                ON f.dbid = d.dbid
        WHERE d.name = 'tempdb') AS a
ON l.dbname = a.[DB_Name]
AND l.[Name] = a.logical_file_Name

--Calculate tempdb files growth
UPDATE [#log]
SET [tempdb_growth_MB] =
CASE 
        WHEN LogSize - init_size_MB < 0.00 THEN 0.00
        ELSE LogSize - init_size_MB
END

/* This shows the main table that enables the magic :) */
if @execute=0
	SELECT	dbname + ' (' + CAST(DATABASEPROPERTYEX (dbname, 'recovery') AS VARCHAR(500)) + ') (' + dbcompat + ')' AS [DB_NAME],
			dbname AS DB_NAME_2,    
			'TLog File' AS [Type],
			[Name] AS [NAME],
			[FilePath],
			init_size_MB,
			LogSize AS [TotalMB],
			tempdb_growth_MB,
			((LogUsed/100)*LogSize) as [UsedMB],
			LogSize - ((LogUsed/100)*LogSize) AS [FreeMB],
			[Autogrowth]
	FROM #log 
	--ORDER BY 1, [Type], [Name]
	ORDER BY [Type] desc, [FreeMB] desc

/* Build commands to shrink logs */
declare @commandlist table (cmd varchar(max))
declare @command varchar(max)
declare @c_dbname varchar(max)
declare @c_name varchar(max)

declare dblog_cur cursor for select dbname, name from #log where LogSize - ((LogUsed/100)*LogSize) > 2000
open dblog_cur
fetch next from dblog_cur into @c_dbname, @c_name
while @@FETCH_STATUS=0
begin

	select @command = 'use [' + @c_dbname + '] ' + CHAR(10) + '; ' + CHAR(10) + 'dbcc shrinkfile (''' + @c_name + ''',1000)' + char(10)
	from #log
	where LogSize - ((LogUsed/100)*LogSize) > 2000
	
	if @execute=1
		exec (@command)
	else
		insert into @commandlist (cmd) values (@command)

	fetch next from dblog_cur into @c_dbname, @c_name
end
close dblog_cur
deallocate dblog_cur

DROP TABLE #log
DROP TABLE #dblog
select * from @commandlist

END

go
--===============================================================
USE [msdb]
GO

if exists ( SELECT * FROM msdb.dbo.sysjobs WHERE (name = N'Shrink Tlogs')  )
	EXEC msdb.dbo.sp_delete_job @job_name = N'Shrink Tlogs'


/****** Object:  Job [Shrink Tlogs]    Script Date: 1900-01-01-1900:00:00 ******/
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
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Shrink Tlogs', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'FakeBusiness_DBAs', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [ShrinkThem]    Script Date: 1900-01-01-1900:00:00 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'ShrinkThem', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec FakeMonShrinkTlogs', 
		@database_name=N'DBATEST', 
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
USE [master]
GO
sp_configure 'show advanced options',1
go
reconfigure
go
sp_configure 'fill factor (%)',90
go
reconfigure
go
print 'Please restart the SQL Server service to register changes'
go
EXEC msdb.dbo.sp_add_alert @name=N'Severity-19', 
		@message_id=0, 
		@severity=19, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''
GO
--Changed @operator_name from FakeBusiness to 
EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity-19', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO
EXEC msdb.dbo.sp_add_alert @name=N'Severity-20', 
		@message_id=0, 
		@severity=20, 
		@enabled=0, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''
GO
EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity-20', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO
EXEC msdb.dbo.sp_add_alert @name=N'Severity-21', 
		@message_id=0, 
		@severity=21, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''
GO
EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity-21', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO
EXEC msdb.dbo.sp_add_alert @name=N'Severity-22', 
		@message_id=0, 
		@severity=22, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''
GO
EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity-22', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO
EXEC msdb.dbo.sp_add_alert @name=N'Severity-23', 
		@message_id=0, 
		@severity=23, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''
GO
EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity-23', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO
EXEC msdb.dbo.sp_add_alert @name=N'Severity-24', 
		@message_id=0, 
		@severity=24, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''
GO
EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity-24', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO
EXEC msdb.dbo.sp_add_alert @name=N'Severity-25', 
		@message_id=0, 
		@severity=25, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''
GO
EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity-25', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO
IF EXISTS(SELECT * FROM sysmessages where error=802)
BEGIN
EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 17-802', 
		@message_id=802, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''

END
IF EXISTS(SELECT * FROM sysmessages where error=8645)
BEGIN
EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 17-8645', 
		@message_id=8645, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''

END
IF EXISTS(SELECT * FROM sysmessages where error=8675)
BEGIN
EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 17-8675', 
		@message_id=8675, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''

END
IF EXISTS(SELECT * FROM sysmessages where error=30094)
BEGIN
EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 17-30094', 
		@message_id=30094, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''

END
IF EXISTS(SELECT * FROM sysmessages where error=708)
BEGIN
EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 10-708', 
		@message_id=708, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''

END
IF EXISTS(SELECT * FROM sysmessages where error=8556)
BEGIN
EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 10-8556', 
		@message_id=8556, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''

END
IF EXISTS(SELECT * FROM sysmessages where error=9769)
BEGIN
EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 10-9769', 
		@message_id=9769, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''

END
--IF EXISTS(SELECT * FROM sysmessages where error=10311)
--BEGIN
--EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 10-10311', 
--		@message_id=10311, 
--		@severity=0, 
--		@enabled=1, 
--		@delay_between_responses=3600, 
--		@include_event_description_in=1, 
--		@database_name=N'', 
--		@notification_message=N'', 
--		@event_description_keyword=N'', 
--		@performance_condition=N'', 
--		@job_id=N''

--END
--IF EXISTS(SELECT * FROM sysmessages where error=17890)
--BEGIN
--EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 10-17890', 
--		@message_id=17890, 
--		@severity=0, 
--		@enabled=1, 
--		@delay_between_responses=3600, 
--		@include_event_description_in=1, 
--		@database_name=N'', 
--		@notification_message=N'', 
--		@event_description_keyword=N'', 
--		@performance_condition=N'', 
--		@job_id=N''

--END
IF EXISTS(SELECT * FROM sysmessages where error=28026)
BEGIN
EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 10-28026', 
		@message_id=28026, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''

END
IF EXISTS(SELECT * FROM sysmessages where error=701)
BEGIN
EXEC msdb.dbo.sp_add_alert @name=N'Memory Alert 17-701', 
		@message_id=701, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=3600, 
		@include_event_description_in=1, 
		@database_name=N'', 
		@notification_message=N'', 
		@event_description_keyword=N'', 
		@performance_condition=N'', 
		@job_id=N''

END
IF EXISTS(SELECT * FROM sysmessages where error=19406)
BEGIN
EXEC msdb.dbo.sp_add_alert @name=N'AGFailoverAlert 19406', 
		@message_id=19406, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=300, 
		@include_event_description_in=1, 
		@category_name=N'[Uncategorized]', 
		@job_id=N''

END
GO

--------------------------mirroring alerts-----------------------------------------------------

IF NOT EXISTS ( SELECT name FROM msdb.dbo.syscategories WHERE name = N'Database Mirroring' AND category_class = 2 ) 
BEGIN
EXEC msdb.dbo.sp_add_category @class = N'ALERT', @type = N'NONE', @name = N'Database Mirroring' ;
END ;

USE [msdb]
GO

/****** Object:  Alert [DBM State: Automatic Failover]    Script Date: 01-01-1900 00:00:00 PM ******/
EXEC msdb.dbo.sp_add_alert @name=N'DBM State: Automatic Failover', 
		@message_id=0, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=1800, 
		@include_event_description_in=1, 
		@notification_message=N'Please verify that database mirroring is functioning properly by following the steps in this KB article: http://kb.FakeBusiness.com/Policy and Procedures/Forms/DispForm.aspx?ID=199', 
		@category_name=N'Database Mirroring', 
		@wmi_namespace=N'\\.\root\Microsoft\SqlServer\ServerEvents\MSSQLSERVER', 
		@wmi_query=N'SELECT * from DATABASE_MIRRORING_STATE_CHANGE 
   WHERE State = 8', 
		@job_id=N''
GO

USE [msdb]
GO

/****** Object:  Alert [DBM State: Manual Failover]    Script Date: 01-01-1900 00:00:00 PM ******/
EXEC msdb.dbo.sp_add_alert @name=N'DBM State: Manual Failover', 
		@message_id=0, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=1800, 
		@include_event_description_in=1, 
		@notification_message=N'Please verify that database mirroring is functioning properly by following the steps in this KB article: http://kb.FakeBusiness.com/Policy and Procedures/Forms/DispForm.aspx?ID=199', 
		@category_name=N'Database Mirroring', 
		@wmi_namespace=N'\\.\root\Microsoft\SqlServer\ServerEvents\MSSQLSERVER', 
		@wmi_query=N'SELECT * from DATABASE_MIRRORING_STATE_CHANGE 
   WHERE State = 7', 
		@job_id=N''
GO

USE [msdb]
GO

/****** Object:  Alert [DBM State: Mirror Connection Lost]    Script Date: 01-01-1900 00:00:00 PM ******/
EXEC msdb.dbo.sp_add_alert @name=N'DBM State: Mirror Connection Lost', 
		@message_id=0, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=1800, 
		@include_event_description_in=1, 
		@notification_message=N'Please verify that database mirroring is functioning properly by following the steps in this KB article: http://kb.FakeBusiness.com/Policy and Procedures/Forms/DispForm.aspx?ID=199', 
		@category_name=N'Database Mirroring', 
		@wmi_namespace=N'\\.\root\Microsoft\SqlServer\ServerEvents\MSSQLSERVER', 
		@wmi_query=N'SELECT * from DATABASE_MIRRORING_STATE_CHANGE 
   WHERE State = 6 ', 
		@job_id=N''
GO

USE [msdb]
GO

/****** Object:  Alert [DBM State: Mirroring Suspended]    Script Date: 01-01-1900 00:00:00 PM ******/
EXEC msdb.dbo.sp_add_alert @name=N'DBM State: Mirroring Suspended', 
		@message_id=0, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=1800, 
		@include_event_description_in=1, 
		@notification_message=N'Please verify that database mirroring is functioning properly by following the steps in this KB article: http://kb.FakeBusiness.com/Policy and Procedures/Forms/DispForm.aspx?ID=199', 
		@category_name=N'Database Mirroring', 
		@wmi_namespace=N'\\.\root\Microsoft\SqlServer\ServerEvents\MSSQLSERVER', 
		@wmi_query=N'SELECT * from DATABASE_MIRRORING_STATE_CHANGE 
   WHERE State = 9', 
		@job_id=N''
GO

USE [msdb]
GO

/****** Object:  Alert [DBM State: No Quorum]    Script Date: 01-01-1900 00:00:00 PM ******/
EXEC msdb.dbo.sp_add_alert @name=N'DBM State: No Quorum', 
		@message_id=0, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=1800, 
		@include_event_description_in=1, 
		@notification_message=N'Please verify that database mirroring is functioning properly by following the steps in this KB article: http://kb.FakeBusiness.com/Policy and Procedures/Forms/DispForm.aspx?ID=199', 
		@category_name=N'Database Mirroring', 
		@wmi_namespace=N'\\.\root\Microsoft\SqlServer\ServerEvents\MSSQLSERVER', 
		@wmi_query=N'SELECT * from DATABASE_MIRRORING_STATE_CHANGE 
   WHERE State = 10', 
		@job_id=N''
GO

USE [msdb]
GO

/****** Object:  Alert [DBM State: Principal Connection Lost]    Script Date: 01-01-1900 00:00:00 PM ******/
EXEC msdb.dbo.sp_add_alert @name=N'DBM State: Principal Connection Lost', 
		@message_id=0, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=1800, 
		@include_event_description_in=1, 
		@notification_message=N'Please verify that database mirroring is functioning properly by following the steps in this KB article: http://kb.FakeBusiness.com/Policy and Procedures/Forms/DispForm.aspx?ID=199', 
		@category_name=N'Database Mirroring', 
		@wmi_namespace=N'\\.\root\Microsoft\SqlServer\ServerEvents\MSSQLSERVER', 
		@wmi_query=N'SELECT * from DATABASE_MIRRORING_STATE_CHANGE 
   WHERE State = 5', 
		@job_id=N''
GO

USE [msdb]
GO

/****** Object:  Alert [DBM Perf: Mirror Commit Overhead Threshold]    Script Date: 01-01-1900 00:00:00 PM ******/
EXEC msdb.dbo.sp_add_alert @name=N'DBM Perf: Mirror Commit Overhead Threshold', 
		@message_id=32044, 
		@severity=0, 
		@enabled=0, 
		@delay_between_responses=1800, 
		@include_event_description_in=1, 
		@notification_message=N'Please verify that database mirroring is functioning properly by following the steps in this KB article: http://kb.FakeBusiness.com/Policy and Procedures/Forms/DispForm.aspx?ID=199', 
		@category_name=N'Database Mirroring', 
		@job_id=N''
GO

USE [msdb]
GO

/****** Object:  Alert [DBM Perf: Oldest Unsent Transaction Threshold]    Script Date: 01-01-1900 00:00:00 PM ******/
EXEC msdb.dbo.sp_add_alert @name=N'DBM Perf: Oldest Unsent Transaction Threshold', 
		@message_id=32040, 
		@severity=0, 
		@enabled=0, 
		@delay_between_responses=1800, 
		@include_event_description_in=1, 
		@notification_message=N'Please verify that database mirroring is functioning properly by following the steps in this KB article: http://kb.FakeBusiness.com/Policy and Procedures/Forms/DispForm.aspx?ID=199', 
		@category_name=N'Database Mirroring', 
		@job_id=N''
GO

USE [msdb]
GO

/****** Object:  Alert [DBM Perf: Unrestored Log Threshold]    Script Date: 01-01-1900 00:00:00 PM ******/
EXEC msdb.dbo.sp_add_alert @name=N'DBM Perf: Unrestored Log Threshold', 
		@message_id=32043, 
		@severity=0, 
		@enabled=0, 
		@delay_between_responses=1800, 
		@include_event_description_in=1, 
		@notification_message=N'Please verify that database mirroring is functioning properly by following the steps in this KB article: http://kb.FakeBusiness.com/Policy and Procedures/Forms/DispForm.aspx?ID=199', 
		@category_name=N'Database Mirroring', 
		@job_id=N''
GO

USE [msdb]
GO

/****** Object:  Alert [DBM Perf: Unsent Log Threshold]    Script Date: 01-01-1900 00:00:00 PM ******/
EXEC msdb.dbo.sp_add_alert @name=N'DBM Perf: Unsent Log Threshold', 
		@message_id=32042, 
		@severity=0, 
		@enabled=0, 
		@delay_between_responses=1800, 
		@include_event_description_in=1, 
		@notification_message=N'Please verify that database mirroring is functioning properly by following the steps in this KB article: http://kb.FakeBusiness.com/Policy and Procedures/Forms/DispForm.aspx?ID=199', 
		@category_name=N'Database Mirroring', 
		@job_id=N''
GO


EXEC msdb.dbo.sp_add_notification @alert_name=N'DBM State: Automatic Failover', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO

EXEC msdb.dbo.sp_add_notification @alert_name=N'DBM State: Manual Failover', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO

EXEC msdb.dbo.sp_add_notification @alert_name=N'DBM State: Mirror Connection Lost', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO

EXEC msdb.dbo.sp_add_notification @alert_name=N'DBM State: Mirroring Suspended', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO

EXEC msdb.dbo.sp_add_notification @alert_name=N'DBM State: No Quorum', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO

EXEC msdb.dbo.sp_add_notification @alert_name=N'DBM State: Principal Connection Lost', @operator_name=N'FakeBusiness_DBAs', @notification_method = 1
GO



--create customer_failed_jobs table

USE [DBATEST]
GO

/****** Object:  Table [dbo].[customer_failed_jobs]    Script Date: 12/30/2014 1:18:04 PM ******/
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

--create Client Operator for Failed Jobs
-- DM Changed Email address from sl.DBATEST to Sl.DBAs@Fake.com, because I am pretty sure the sl.DBATESTs doesn't work any longer. 
USE [msdb]
GO

/****** Object:  Operator [Client Operator Failed Jobs]    Script Date: 1900-01-01-1900:00:00 ******/
EXEC msdb.dbo.sp_add_operator @name=N'Client Operator Failed Jobs', 
		@enabled=1, 
		@weekday_pager_start_time=90000, 
		@weekday_pager_end_time=180000, 
		@saturday_pager_start_time=90000, 
		@saturday_pager_end_time=180000, 
		@sunday_pager_start_time=90000, 
		@sunday_pager_end_time=180000, 
		@pager_days=0, 
		@email_address=N'sl.DBAs@Fake.com', 
		@category_name=N'[Uncategorized]'
GO




--create Client_Job_Alert 

USE [msdb]
GO

/****** Object:  Job [Client_Job_Alert]    Script Date: 01-01-1900 9:13:42 AM ******/
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
		@owner_login_name=N'FakeBusiness_DBAs', @job_id = @jobId OUTPUT
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
left join DBATEST..JobCheckIgnore jci on sj.job_id = jci.job_id
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

insert into DBATEST..customer_failed_jobs

select sj.name,
sjh.message
from msdb..sysjobs sj
inner join msdb..sysjobhistory sjh on sj.job_id = sjh.job_id
left join DBATEST..JobCheckIgnore jci on sj.job_id = jci.job_id
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
    @profile_name = ''Fake'',
    @recipients = @oper_email,
    @subject = @Subject,
	@body = ''This is a list of jobs that have failed in the last 24 hours. For more detail open SQL Server Managment Studio and navigate to SQL Server Agent > Jobs, then right click the job in question and select "View History".
	'',
    @query = N''SET NOCOUNT ON SELECT * FROM  DBATEST.dbo.customer_failed_jobs'',
  	@body_format = ''TEXT'',
	@query_result_header = 0 

truncate table DBATEST..customer_failed_jobs
end', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Daily (8am)', 
		@enabled=0, 
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

insert into [DBATEST].[dbo].[BackupCheckIgnore]
  values ('tempdb','full')



USE [DBATEST]
GO


DECLARE @JobId nvarchar(500)
DECLARE @Jname nvarchar(500) 
DECLARE @JobIgnorePopCursor CURSOR 

	SET @JobIgnorePopCursor = CURSOR FOR SELECT CAST(Job_Id as nvarchar(500)), Name FROM MSDB.DBO.sysjobs 
	WHERE NAME IN 
	( 'TrueCacheHitUpdate',
	  'BufferPoolTracking',
	  'Shrink Tlogs',
	  'FakeBusiness performance stats collection',
	  'syspolicy_purge_history',
	  'Optimizations', 
	  'Client_Job_Alert',
	  'DBATEST - Blocking',
	'Database Mirroring Monitor Job'
	)

	OPEN @JobIgnorePopCursor 

		FETCH NEXT FROM @JobIgnorePopCursor
		INTO @JobID, @Jname

		While @@FETCH_STATUS =0
			BEGIN 
				INSERT INTO [DBATEST].[dbo].[JobCheckIgnore] SELECT  CONVERT(uniqueidentifier,@JobID) ,  @Jname
				 
				FETCH NEXT FROM @JobIgnorePopCursor
				INTO @JobID, @Jname 

			END 
				CLOSE @JobIgnorePopCursor
				DEALLOCATE @JobIgnorePopCursor
				GO


USE [master]
GO
DECLARE @cpu_count      int,
        @file_count     int,
        @logical_name   sysname,
        @file_name      nvarchar(520),
        @physical_name  nvarchar(520),
        @size           int,
        @growth         int,
        @alter_command  nvarchar(max)
ALTER DATABASE [tempdb] MODIFY FILE ( NAME=N'templog' , SIZE = 1024MB, FILEGROWTH = 256MB, MAXSIZE=N'Unlimited' )

ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'tempdev', SIZE = 1024MB , FILEGROWTH = 256MB , MAXSIZE=N'Unlimited' )


SELECT  @physical_name = physical_name,
        @size = 1024, 
         @growth = growth / 128
FROM    tempdb.sys.database_files
WHERE   name = 'tempdev'

SELECT  @file_count = COUNT(*)
FROM    tempdb.sys.database_files
WHERE   type_desc = 'ROWS'

SELECT  @cpu_count = cpu_count
FROM    sys.dm_os_sys_info

WHILE @file_count < @cpu_count -- Add * 0.25 here to add 1 file for every 4 cpus, * .5 for every 2 etc.
 BEGIN
    SELECT  @logical_name = 'tempdev' + CAST(@file_count AS nvarchar)
    SELECT  @file_name = REPLACE(@physical_name, 'tempdb.mdf', @logical_name + '.ndf')
    SELECT  @alter_command = 'ALTER DATABASE [tempdb] ADD FILE ( NAME =N' +CHAR(39) + @logical_name + CHAR(39)+ ', FILENAME =N'+CHAR(39) +  @file_name +CHAR(39)+ ', SIZE = ' + CAST(@size AS nvarchar) + 'MB, FILEGROWTH='+ CAST(@growth AS nvarchar) + 'MB, MAXSIZE=N'+ CHAR(39)+'Unlimited'+ CHAR(39)+')'
    PRINT   @alter_command
   EXEC    sp_executesql @alter_command
  SELECT  @file_count = @file_count + 1
 END
 GO
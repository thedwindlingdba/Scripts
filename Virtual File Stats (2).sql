

/** Virtual File Stats


	Author: Dustin Marzolf


	Purpose: To improve Virtual File Stats data gathering.

	Based on http://sqlperformance.com/2013/10/t-sql-queries/io-latency
	by Erin Stellato

	Usage:
	* Specify How many samples youw ant in @TotalSamples.  At least 2
	* Specify how long you want to wait between samples, @DelayTimeBetweenSamples, specified in hh:mm:ss

	

DECLARE @TotalSamples INT = 2;
DECLARE @DelayTimeBetweenSamples CHAR(8) = '00:00:30'; --hh:mm:ss


/******************************************************************************/
IF OBJECT_ID('tempdb..#FileLatency') IS NULL
BEGIN
       
	CREATE TABLE #FileLatency
		(
		  [RowID] [INT] IDENTITY(1, 1) NOT NULL
		, [CaptureID] [INT] NOT NULL
		, [CaptureDate] [DATETIME2](7) NULL
		, [ReadLatency] [BIGINT] NULL
		, [WriteLatency] [BIGINT] NULL
		, [Latency] [BIGINT] NULL
		, [AvgBPerRead] [BIGINT] NULL
		, [AvgBPerWrite] [BIGINT] NULL
		, [AvgBPerTransfer] [BIGINT] NULL
		, [Drive] [NVARCHAR](2) NULL
		, [DB] [NVARCHAR](128) NULL
		, [database_id] [SMALLINT] NOT NULL
		, [file_id] [SMALLINT] NOT NULL
		, [sample_ms] [INT] NOT NULL
		, [num_of_reads] [BIGINT] NOT NULL
		, [num_of_bytes_read] [BIGINT] NOT NULL
		, [io_stall_read_ms] [BIGINT] NOT NULL
		, [num_of_writes] [BIGINT] NOT NULL
		, [num_of_bytes_written] [BIGINT] NOT NULL
		, [io_stall_write_ms] [BIGINT] NOT NULL
		, [io_stall] [BIGINT] NOT NULL
		, [size_on_disk_MB] [NUMERIC](25, 6) NULL
		, [file_handle] [VARBINARY](8) NOT NULL
		, [physical_name] [NVARCHAR](260) NOT NULL
		);

	CREATE CLUSTERED INDEX IDC_TempFileLatencyCaptureDateRowID ON #FileLatency ([CaptureDate], [RowID]);
 
	CREATE NONCLUSTERED INDEX IDX_TempFileLatencyCaptureID ON #FileLatency ([CaptureID]);

END;

DECLARE @CaptureID INT = ISNULL((SELECT MAX(CaptureID) FROM #FileLatency), 0) + 1;
SET @TotalSamples = @TotalSamples + (@CaptureID - 1)

WHILE @CaptureID <= @TotalSamples
    BEGIN

        PRINT 'Getting Virtual Stat Information for cycle: ' + CAST(@CaptureID AS VARCHAR(10));

        INSERT  INTO #FileLatency
                ( CaptureID
                , CaptureDate
                , ReadLatency
                , WriteLatency
                , Latency
                , AvgBPerRead
                , AvgBPerWrite
                , AvgBPerTransfer
                , Drive
                , DB
                , database_id
                , file_id
                , sample_ms
                , num_of_reads
                , num_of_bytes_read
                , io_stall_read_ms
                , num_of_writes
                , num_of_bytes_written
                , io_stall_write_ms
                , io_stall
                , size_on_disk_MB
                , file_handle
                , physical_name
	            )
                SELECT  @CaptureID
                      , GETDATE()
                      , CASE WHEN [num_of_reads] = 0 THEN 0
                             ELSE ( [io_stall_read_ms] / [num_of_reads] )
                        END [ReadLatency]
                      , CASE WHEN [io_stall_write_ms] = 0 THEN 0
                             ELSE ( [io_stall_write_ms] / [num_of_writes] )
                        END [WriteLatency]
                      , CASE WHEN ( [num_of_reads] = 0
                                    AND [num_of_writes] = 0
                                  ) THEN 0
                             ELSE ( [io_stall] / ( [num_of_reads]
                                                   + [num_of_writes] ) )
                        END [Latency]
                      ,
                        CASE WHEN [num_of_reads] = 0 THEN 0
                             ELSE ( [num_of_bytes_read] / [num_of_reads] )
                        END [AvgBPerRead]
                      , CASE WHEN [io_stall_write_ms] = 0 THEN 0
                             ELSE ( [num_of_bytes_written] / [num_of_writes] )
                        END [AvgBPerWrite]
                      , CASE WHEN ( [num_of_reads] = 0
                                    AND [num_of_writes] = 0
                                  ) THEN 0
                             ELSE ( ( [num_of_bytes_read]
                                      + [num_of_bytes_written] )
                                    / ( [num_of_reads] + [num_of_writes] ) )
                        END [AvgBPerTransfer]
                      , LEFT([mf].[physical_name], 2) [Drive]
                      , DB_NAME([vfs].[database_id]) [DB]
                      , [vfs].[database_id]
                      , [vfs].[file_id]
                      , [vfs].[sample_ms]
                      , [vfs].[num_of_reads]
                      , [vfs].[num_of_bytes_read]
                      , [vfs].[io_stall_read_ms]
                      , [vfs].[num_of_writes]
                      , [vfs].[num_of_bytes_written]
                      , [vfs].[io_stall_write_ms]
                      , [vfs].[io_stall]
                      , [vfs].[size_on_disk_bytes] / 1024 / 1024. [size_on_disk_MB]
                      , [vfs].[file_handle]
                      , [mf].[physical_name]
                FROM    [sys].[dm_io_virtual_file_stats](NULL, NULL) AS vfs
                        JOIN [sys].[master_files] [mf] ON [vfs].[database_id] = [mf].[database_id]
                                                          AND [vfs].[file_id] = [mf].[file_id]
                ORDER BY [Latency] DESC;


	--Delay
        PRINT 'Waiting';
        WAITFOR DELAY @DelayTimeBetweenSamples;

	--Increment @CaptureID
        SET @CaptureID = @CaptureID + 1;

    END;

/** Reporting...*/

DECLARE @PreviousID INT;
DECLARE @LatestCaptueID INT ;

SET @PreviousID = (SELECT MIN(CaptureID) FROM #FileLatency);
SET @LatestCaptueID = (SELECT MAX(CaptureID) FROM #FileLatency);

--Generate Report.
WITH [p] AS (	SELECT	
				[CaptureDate], 
				[database_id], 
				[file_id], 
				[ReadLatency], 
				[WriteLatency], 
				[num_of_reads], 
				[io_stall_read_ms], 
				[num_of_writes], 
				[io_stall_write_ms]
			FROM #FileLatency
			WHERE [CaptureID] = @PreviousID
		)
SELECT	
	[c].[CaptureDate] [CurrentCaptureDate],
	[p].[CaptureDate] [PreviousCaptureDate],
	DATEDIFF(MINUTE, [p].[CaptureDate], [c].[CaptureDate]) [MinBetweenCaptures],
	[c].[DB],
	[c].[physical_name],
	[c].[ReadLatency] [CurrentReadLatency], 
	[p].[ReadLatency] [PreviousReadLatency], 
	[c].[WriteLatency] [CurrentWriteLatency], 
	[p].[WriteLatency] [PreviousWriteLatency],
	[c].[io_stall_read_ms]- [p].[io_stall_read_ms] [delta_io_stall_read],
	[c].[num_of_reads] - [p].[num_of_reads] [delta_num_of_reads],
	[c].[io_stall_write_ms] - [p].[io_stall_write_ms] [delta_io_stall_write],
	[c].[num_of_writes] - [p].[num_of_writes] [delta_num_of_writes],
	CASE
		WHEN ([c].[num_of_reads] - [p].[num_of_reads]) = 0 THEN NULL
		ELSE ([c].[io_stall_read_ms] - [p].[io_stall_read_ms])/([c].[num_of_reads] - [p].[num_of_reads])
	END [IntervalReadLatency],
	CASE
		WHEN ([c].[num_of_writes] - [p].[num_of_writes]) = 0 THEN NULL
		ELSE ([c].[io_stall_write_ms] - [p].[io_stall_write_ms])/([c].[num_of_writes] - [p].[num_of_writes])
	END [IntervalWriteLatency]
FROM #FileLatency [c]
JOIN [p] ON [c].[database_id] = [p].[database_id] AND [c].[file_id] = [p].[file_id]
WHERE [c].[CaptureID] = @LatestCaptueID 
ORDER BY DB, c.physical_name


/** Cleanup. Commented out for convenience... Don't forget to cleanup...
IF OBJECT_ID('tempdb..#FileLatency') IS NOT NULL
    BEGIN
        DROP TABLE #FileLatency;
    END;

	*/


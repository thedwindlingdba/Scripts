/** Name: Database File Utilization
	Author: JDustin Marzolf


	Purpose: To detail all database files that are in use and:
		- Display configuration information (path, max size, growth pattern, etc.)
		- Display size information (current size on disk, space used in file, free space)
		- Calculate an Ideal Size for the file
		- Generate a change script to bring all of this into line.

	CONFIGURATION:
		- Change the @IdealPercentageUsed to the appropriate percentage for your environment.  
			.90 will set the ideal size to leave 10% free space.
		

	USAGE:
		- Execute the script.  The first result set will have the various information about the files.
		- The second result set has the change script.  Execute the produced statements if you need too or they are appropriate for your situation 

	

*******************/

/** CONFIGURATION **/
DECLARE @IdealPercentageUsed DECIMAL(3,2) = .90

--Whether to show these commands when the fix script is generated.
DECLARE @Fix_ShrinkFiles BIT = 1
DECLARE @Fix_ExpandFiles BIT = 1
DECLARE @Fix_LogFiles BIT = 0
DECLARE @Fix_MaxSize BIT = 1
DECLARE @Fix_GrowthRate BIT = 1

/********************************************************/
/** You shouldn't need to change anything below here.  **/
DECLARE @DatabaseName SYSNAME
DECLARE @Query NVARCHAR(4000)

IF OBJECT_ID('tempdb..#DatabaseSpace') IS NOT NULL
BEGIN
	DROP TABLE #DatabaseSpace 
END

CREATE TABLE #DatabaseSpace
	(
	DatabaseName SYSNAME NULL
	, DBFileName SYSNAME NULL
	, FileType CHAR(4) NULL
	, FileState VARCHAR(10) NULL
	, FileID INT NULL
	, GrowthRate INT NULL
	, MaxSize INT NULL
	, IsPercent BIT NULL
	, PhysicalPath VARCHAR(3000) NULL
	, CurrentSize_MB DECIMAL(10,2) NULL
	, SpaceUsed_MB DECIMAL(10,2) NULL
	, FreeSpace_MB DECIMAL(10,2) NULL
	, FreeSpace_Percent DECIMAL(10,2) NULL
	, IdealSize_MB DECIMAL(10,2) NULL
	)

DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY
FOR	SELECT D.name
	FROM sys.databases D
	WHERE D.state_desc = 'ONLINE'
	ORDER BY D.database_id

OPEN curDB

FETCH NEXT FROM curDB
INTO @DatabaseName

WHILE @@FETCH_STATUS = 0
BEGIN

	SET @Query = 'USE ' + QUOTENAME(@DatabaseName) + '; '
		+ 'INSERT INTO #DatabaseSpace '
		+ '(DatabaseName, DBFileName, FileType, FileState, FileID, GrowthRate, MaxSize, IsPercent, PhysicalPath, CurrentSize_MB, SpaceUsed_MB) '
		+ 'SELECT DB_NAME() AS DatabaseName'
		+ ', F.name'
		+ ', F.type_desc '
		+ ', F.state_desc '
		+ ', F.file_id '
		+ ', F.growth '
		+ ', F.max_size'
		+ ', F.is_percent_growth'
		+ ', F.physical_name'
		+ ', F.size/128.0 AS CurrentSize_MB'
		+ ', FILEPROPERTY(F.name, ' + QUOTENAME('SpaceUsed', '''') + ')/128.0 AS SpaceUsed_MB'
		+ ' FROM sys.database_files F '

	EXEC sp_executesql @Query 

	--Get Next Database
	FETCH NEXT FROM curDB
	INTO @DatabaseName

END

--Cleanup.
CLOSE curDB
DEALLOCATE curDB

--Update freespace numbers.
UPDATE #DatabaseSpace
SET FreeSpace_MB = ISNULL(CurrentSize_MB, 0.0) - ISNULL(SpaceUsed_MB, 0.0)
	, FreeSpace_Percent = ((ISNULL(CurrentSize_MB, 0.0) - ISNULL(SpaceUsed_MB, 0.0)) / ISNULL(CurrentSize_MB, 1.0) * 100)
	, IdealSize_MB = CASE WHEN FileType = 'ROWS' THEN ROUND(ISNULL(SpaceUsed_MB + 1.0, 0.0) / @IdealPercentageUsed, 0)
							ELSE ROUND(ISNULL(CurrentSize_MB + 1.0, 0.0) /2.0, 0)
							END

/** Display Dataset results.  **/
SELECT * 
FROM #DatabaseSpace 
ORDER BY DatabaseName

--Generate Change Script.
SELECT DISTINCT E.*
FROM (
	--FileSize Fix (shrink or expand).
	SELECT DatabaseName
		, StatementInt = 5
		, Statements = 	CASE WHEN IdealSize_MB < CurrentSize_MB
								THEN 'USE ' + QUOTENAME(DatabaseName) + '; DBCC SHRINKFILE(' + QUOTENAME(DBFileName, '''') + ', ' + CAST(CAST(IdealSize_MB AS INT) AS VARCHAR(10)) + ')'
						ELSE 'USE [master]; ALTER DATABASE ' + QUOTENAME(DatabaseName) + ' MODIFY FILE ( NAME = ' + QUOTENAME(DBFileName, '''') + ', SIZE = ' + CAST(CAST(IdealSize_MB AS INT) AS VARCHAR(10)) + 'MB)'
						END
	FROM #DatabaseSpace 
	WHERE DatabaseName <> 'tempdb'
		AND (
				(@Fix_ExpandFiles = 1 AND IdealSize_MB > CurrentSize_MB)
				OR
				(@Fix_ShrinkFiles = 1 AND IdealSize_MB < CurrentSize_MB)
			)
		AND NOT(IdealSize_MB = CurrentSize_MB)
		AND (@Fix_LogFiles = 1 OR (@Fix_LogFiles = 0 AND FileType <> 'LOG'))
	UNION ALL
	--Growth Pattern.
	SELECT DatabaseName
		, StatementInt = 3
		, Statements = CASE WHEN IsPercent = 0 THEN ''
							ELSE 'USE [master]; ALTER DATABASE ' + QUOTENAME(DatabaseName) + ' MODIFY FILE ( NAME = ' + QUOTENAME(DBFileName, '''') + ', FILEGROWTH=' + CASE WHEN IdealSize_MB >= 100000 THEN '5120MB' WHEN IdealSize_MB >= 50000 THEN '2048MB' WHEN IdealSize_MB >= 10000 THEN '1024MB' WHEN IdealSize_MB >= 1000 THEN '100MB' ELSE '10MB' END + ');'
							END
	FROM #DatabaseSpace
	WHERE (IsPercent = 1 AND @Fix_GrowthRate = 1)
	UNION ALL
	--Comment Line.
	SELECT DatabaseName
		, StatementInt = 2
		, '/** Fixing Database: ' + CAST(DatabaseName AS VARCHAR(20)) + '**/'
	FROM #DatabaseSpace 
	UNION ALL
	--Comment Line.
	SELECT DatabaseName
		, StatementInt = 1
		, '' AS Statements
	FROM #DatabaseSpace 
	UNION ALL
	--Go Line.
	SELECT DatabaseName
		, StatementInt = 10
		, 'GO' AS Statements
	FROM #DatabaseSpace 
	UNION ALL
	--Max Size.
	SELECT DatabaseName
		, StatementInt = 4
		, Statements = 'USE [master]; ALTER DATABASE ' + QUOTENAME(DatabaseName) + ' MODIFY FILE ( NAME = ' + QUOTENAME(DBFileName, '''') + ', MAXSIZE=UNLIMITED)'
	FROM #DatabaseSpace
	WHERE MaxSize <> -1
		AND @Fix_MaxSize = 1
) E
ORDER BY E.DatabaseName, StatementInt


--Cleanup...
IF OBJECT_ID('tempdb..#DatabaseSpace') IS NOT NULL
BEGIN
	DROP TABLE #DatabaseSpace 
END

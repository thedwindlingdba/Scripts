/** 
Name: Memory Usage Query

Author: Dustin - based upon script by Jes Borland (brentozar.com)


Purpose: Identify memory pressure in system.  

This will generate three queries of output.
 Set 1 - Shows variuos pieces of information about the server and it's configuration.
	
Set 2 - shows the items that are consuming the most memory, including type and description.
	
 Set 3 - shows the data from result set 2 without the type information, grouped by description.
	.

Based Upon:
/*
SQL Server Max Memory Myths 
Jes Schultz Borland 
Consultant @ Brent Ozar PLF 
http://brentozar.com  
*/

**/



--Cleanup.
IF OBJECT_ID('tempdb..#Temp') IS NOT NULL
BEGIN
	DROP TABLE #Temp;
END

CREATE TABLE #Temp
	(
	[type] NVARCHAR(4000) NULL
	, [Description] NVARCHAR(4000) NULL
	, [Memory Utilized in MB] NUMERIC(10,3) NULL
	, [Free Space on Cached Pages MB] NUMERIC(10,3) NULL
	)
	
--First bit of data.
INSERT INTO #Temp
([type], [Description], [Memory Utilized in MB], [Free Space on Cached Pages MB])
SELECT C.[type]
	, C.name AS [Description]
	, [Memory Utilized in MB] = CAST(COUNT(C.pages_allocated_count) * 8 / 1024.0 AS NUMERIC(10,2))
	, 0 AS [Free Space on Cached Pages MB]
FROM sys.dm_os_memory_cache_entries C
GROUP BY C.name, C.[type]
OPTION (MAXDOP 0);

--Second bit of data.
INSERT INTO #Temp
([type], [Description], [Memory Utilized in MB], [Free Space on Cached Pages MB])
SELECT 'buffer pool' AS [type]
	, [Description] = CASE	WHEN D.database_id = 32767 
								THEN 'ResourceDb' 
							ELSE DB_NAME(D.database_id) 
							END
	, [Memory Utilized in MB] = CAST(COUNT(D.page_id) * 8 / 1024.0 AS NUMERIC(10, 2))
	, [Free Space on Cached Pages MB] = CAST(SUM(CAST(free_space_in_bytes AS BIGINT)) / 1024. / 1024. AS NUMERIC(10,2))
FROM sys.dm_os_buffer_descriptors D
GROUP BY CASE	WHEN D.database_id = 32767 
					THEN 'ResourceDb' 
				ELSE DB_NAME(D.database_id) 
				END
	, D.database_id
OPTION (MAXDOP 0);

--For percentages.
DECLARE @TotalMemory NUMERIC(10,2)

SET @TotalMemory = (SELECT SUM(E.[Memory Utilized in MB]) FROM #Temp E)

/** Return the Results **/

--Information about the server and memory configuration.
SELECT [Physical Memory _MB] = M.total_physical_memory_kb / 1024
	, [Max Memory Configured _MB] = C.value_in_use
	, @TotalMemory AS [Total Memory Consumed]
	, [Memory Consumed %] = @TotalMemory / CAST(C.value_in_use AS NUMERIC(10,2))
FROM sys.dm_os_sys_memory M
	CROSS JOIN master.sys.configurations C
WHERE C.name = 'max server memory (MB)'

--Details of where memory is and what is using it.
SELECT E.[type]
	, E.[Description]
	, E.[Memory Utilized in MB] 
	, [Memory Utilized %] = E.[Memory Utilized in MB] / @TotalMemory
	, E.[Free Space on Cached Pages MB] 
FROM #Temp E
ORDER BY E.[Memory Utilized in MB] DESC

--Summary by Description.
SELECT E.[Description]
	, SUM(E.[Memory Utilized in MB]) AS [Memory Utilized in MB]
	, [Memory Utilized %] = SUM(E.[Memory Utilized in MB]) / @TotalMemory
FROM #Temp E
GROUP BY E.[Description]
ORDER BY SUM(E.[Memory Utilized in MB]) DESC

IF OBJECT_ID('tempdb..#Temp') IS NOT NULL
BEGIN
	DROP TABLE #Temp;
END

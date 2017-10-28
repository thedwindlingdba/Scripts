IF OBJECT_ID('tempdb..#Processes') IS NOT NULL
BEGIN
	DROP TABLE #Processes 
END

SELECT DB_NAME(P.dbid) AS DatabaseName
	, P.*
	, qt.dbid AS QueryDBID
	, DB_NAME(qt.dbid) AS QueryDatabaesName
	, qt.[text] AS QueryText
	, qt.objectid AS QueryObjectID
	, O.name AS ObjectName
INTO #Processes
FROM sys.sysprocesses P 
	CROSS APPLY sys.dm_exec_sql_text(P.sql_handle) qt
	LEFT OUTER JOIN sys.objects O ON O.object_id = qt.objectid

--Show All
SELECT * FROM #Processes

/** 
--Show Blocked Processes only.
SELECT * FROM #Processes WHERE blocked <> 0

--Show where the waitresource is not blank.
SELECT * FROM #Processes WHERE waitresource <> ''

--Get a list of hostname and user names and the spid count for that.
SELECT hostname, nt_username, COUNT(spid) AS SPIDCount
FROM #Processes
GROUP BY hostname, nt_username

--Get a list of all program names and their spid count.
SELECT [program_name]
	, COUNT(spid) AS SPIDCount 
FROM #Processes
GROUP BY [program_name]

--Group data by the last wait type.
SELECT lastwaittype
	, COUNT(spid) SPIDCount
FROM #Processes
WHERE lastwaittype <> 'MISCELLANEOUS'
GROUP BY Lastwaittype

**/




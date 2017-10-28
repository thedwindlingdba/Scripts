/***
	Author: Dustin Marzolf
	Purpose: To enable the transmission of execution plan cache details through Excel or plain text without worrying about control characters.
	The statement text and execution plan are converted to base64 for transmission, then can be converted back as desired (see below)

	DECLARE @Value VARCHAR(MAX)

	SET @Value = 'KCkKIHNlbGVjdCB0YWJsZV9pZCwgaXRlbV9ndWlkLCBvcGxzbl9mc2Vxbm8sIG9wbHNuX2JPZmZzZXQsIG9wbHNuX3Nsb3RpZAogZnJvbSBbQXp1cmVVcE5ld10uW3N5c10uW2ZpbGV0YWJsZV91cGRhdGVzXzIxMDUwNTg1MzVdIHdpdGggKHJlYWRwYXN0KSBvcmRlciBieSB0YWJsZV9pZA=='

	SELECT CONVERT(VARCHAR(MAX), CAST(N'' AS XML).value('xs:base64Binary(sql:variable("@Value"))', 'VARBINARY(MAX)'))

*/


;WITH CTE_EXEC AS
	(
SELECT TOP 100 
	@@SERVERNAME AS ServerName
	, GETDATE() AS CurrentDate
	, S.total_elapsed_time/1000 AS TotalElapsedTime_MS
	, S.execution_count AS ExecutionCount
	, AverageExecutionTime_MS = ISNULL(S.total_elapsed_time / S.execution_count, 0)/1000
	
	, LastElapsedTime_MS = S.last_elapsed_time/1000
	, S.plan_generation_num AS PlanGenerationCount
	, ExecutionsPerDay = ISNULL(S.execution_count / CASE	WHEN CAST(S.creation_time AS DATE) = CAST(S.last_execution_time AS DATE) THEN 1 
															ELSE DATEDIFF(DAY, S.creation_time, S.last_execution_time) 
															END, 0)
	, AverageRowsReturned = ISNULL(S.total_rows, 0)/ISNULL(S.execution_count, 1)
	, MaxRowsReturned = S.max_rows
	, DatabaseName = DB_NAME(T.dbid)
	, ObjectName = CASE WHEN T.objectid IS NOT NULL AND T.dbid > 0 THEN OBJECT_NAME(T.objectid, T.dbid) 
						ELSE NULL 
						END
	, QueryCost = (ISNULL(S.total_physical_reads, 0) + ISNULL(S.total_logical_writes, 0) + ISNULL(S.total_logical_reads, 0) + ISNULL(S.total_logical_writes, 0))/S.execution_count
	, CAST(CONVERT(VARCHAR(MAX), T.[TEXT]) AS VARBINARY(MAX)) AS SQLStatement_VAR
	, CAST(P.query_plan AS VARBINARY(MAX)) AS QueryPlan
FROM sys.dm_exec_query_stats S 
	CROSS APPLY sys.dm_exec_sql_text(S.sql_handle) T
	CROSS APPLY sys.dm_exec_query_plan(S.plan_handle) P
ORDER BY S.execution_count DESC
)
SELECT CTE_EXEC.ServerName
	, CTE_EXEC.CurrentDate
	 , CTE_EXEC.TotalElapsedTime_MS
	 , CTE_EXEC.ExecutionCount
	 , CTE_EXEC.AverageExecutionTime_MS
	 , CTE_EXEC.LastElapsedTime_MS
	 , CTE_EXEC.PlanGenerationCount
	 , CTE_EXEC.ExecutionsPerDay
	 , CTE_EXEC.AverageRowsReturned
	 , CTE_EXEC.MaxRowsReturned
	 , CTE_EXEC.DatabaseName
	 , CTE_EXEC.ObjectName
	 , CTE_EXEC.QueryCost
	 , [QueryEnc] = CAST(N'' AS XML).value('xs:base64Binary(sql:column("SQLStatement_VAR"))', 'VARCHAR(MAX)')
	 , [QueryPlanEnc] = CAST(N'' AS XML).value('xs:base64Binary(sql:column("QueryPlan"))', 'VARCHAR(MAX)')
FROM CTE_EXEC 



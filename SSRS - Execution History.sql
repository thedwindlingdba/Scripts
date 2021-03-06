/****** Script for SelectTopNRows command from SSMS  ******/


USE ReportServer

SELECT MIN(TimeStart) AS EarliestData FROM ExecutionLog;

WITH CTE_ExecutionLog AS (

SELECT E.[InstanceName]
      , E.[ReportID]
      , E.[UserName]
      , E.[RequestType]
      , E.[Format]
      , E.[Parameters]
      , E.[TimeStart]
      , E.[TimeEnd]
      , E.[TimeDataRetrieval]
      , E.[TimeProcessing]
      , E.[TimeRendering]
      , E.[Source]
      , E.[Status]
      , E.[ByteCount]
      , E.[RowCount]
	  , C.Name AS ReportName
	  , C.Path AS ReportPath
FROM [ReportServer].[dbo].[Catalog] C
	LEFT OUTER JOIN [ReportServer].[dbo].[ExecutionLog] E ON E.ReportID = C.ItemID
WHERE C.[Type] <> 1
)
SELECT L.ReportName	
	, L.ReportPath
	, MAX(L.TimeEnd) AS LastRunTime
	, COUNT(L.TimeEnd) AS ExecutionCount
	, AVG(L.TimeDataRetrieval) AS AverageTimeDataRetrieval
	, AVG(L.TimeProcessing) AS AverageTimeProcessing
	, AVG(L.TimeRendering) AS AverageTimeRendering
	, AVG(L.[RowCount]) AS AverageRowCount
	, AVG(L.ByteCount) AS AverageByteCount
FROM CTE_ExecutionLog L
WHERE ReportName <> ''
GROUP BY L.ReportName	
	, L.ReportPath


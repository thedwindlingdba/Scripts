USE Watlow_DataStore 
GO

/** This query gets the stats for the typical pacakge run (where the event count = 338).
	Average Runtime is 182 minutes with a standard deviation of 82 minutes.
	Max Runtime is 547
	Min Runtime is 107
**/
SELECT AVG(D.DurationMin) AS AverageDuration
	, MAX(D.DurationMin) AS MaxDuration
	, MIN(D.DurationMin) AS MinDuration
	, STDEV(D.DurationMin) AS STDDuration
FROM (
SELECT L.source, L.sourceid, L.executionid, L.starttime, C.EventCount, C.EarlyStart, C.LatestEnd, DurationMin = DATEDIFF(MINUTE, C.EarlyStart, C.LatestEnd)
FROM dbo.sysssislog AS L 
	LEFT OUTER JOIN (
					SELECT L2.executionid, COUNT(L2.id) AS EventCount, MIN(starttime) AS EarlyStart, MAX(endtime) AS LatestEnd
					FROM dbo.sysssislog L2
					GROUP BY L2.executionid
					) AS C ON C.executionid = L.executionid
WHERE source = 'PAR-VizionInsights_MasterETL'
	AND starttime >= '6/1/2015'
	AND [event] = 'PackageStart'
) AS D
WHERE D.EventCount = 338

/** This query identifies exeuctions that never terminated properly.  
	I.E. ones that were cancelled by the administrator.
**/
SELECT L.*
FROM dbo.sysssislog AS L
	LEFT OUTER JOIN dbo.sysssislog E ON E.executionid = L.executionid AND E.event = 'PackageEnd'
WHERE L.source = 'PAR-VizionInsights_MasterETL'
	AND L.starttime >= '1/1/2015'
	AND L.[event] = 'PackageStart'
	AND E.id IS NULL
ORDER BY starttime DESC

/** The following queries were an attempt to determine if there was a consistent step that was
	failing / timing out amongst the four identified exeuctions that were cancelled by the
	administrator.  
	
	Unfortunately, no pattern was identified.  
	
	The fifth query is a successful run for comparison purposes.
**/	

--5/27/2016, cancelled, 124 steps.
SELECT * FROM dbo.sysssislog WHERE executionid = '371F5476-CDC0-4E59-AC48-79C87765630A' ORDER BY id

--4/2/2016, cancelled, 53 steps.
SELECT * FROM dbo.sysssislog WHERE executionid = 'B7D209DD-EE2F-42B0-B35B-ABD27BF67377' ORDER BY id

--9/10/2015, cancelled, 324 steps.
SELECT * FROM dbo.sysssislog WHERE executionid = '5339ACD8-6B73-46FD-85AF-6EE7203F3512' ORDER BY id

--1/10/2015, cancelled, 314 steps.
SELECT * FROM dbo.sysssislog WHERE executionid = '1946D057-6DB9-4D15-92B9-6F0AA48D49D3' ORDER BY id

--5/27/2016 (successful run started at 8:50 AM, here for comparison), 338 steps.
SELECT * FROM dbo.sysssislog WHERE executionid = 'CA1F928D-84E0-43BE-8865-9436586766C7' ORDER BY id

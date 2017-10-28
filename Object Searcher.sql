/*********************************
	Name: Text Searcher
	Author: Dustin Marzolf
	Created: 1/16/2015

	Purpose: To enable one to more easily search for objects by an indicated string.

	Usage: 
		- Update the "Where To Search" section to turn on or off various sections.
		- Craft an insert statement to populate "@ObjectsToSearchFor" with the text you
			want to look for.  
		- Execute.


	This is useful when you are trying to find out what is using a linked server.  So you get the name of the 
	linked server (and it's host name) and run a search on that.  It tells you a handful of objects.  You then run
	it again, but this time looking for those objects (say, in other stored procedures or in SSIS/Jobs).  

	CAUTION: If you want to use the recursive functionality, you will need to save off the results FIRST.  

		DROP TABLE #SearchResults

Example Linked Server Query:
	

		INSERT INTO @ObjectsToSearchFor
		(TextString)
		SELECT srvname FROM sys.sysservers WHERE srvname <> @@SERVERNAME 
		UNION
		SELECT datasource FROM sys.sysservers WHERE srvname <> @@SERVERNAME
		UNION
		SELECT srvnetname FROM sys.sysservers WHERE srvnetname <> @@SERVERNAME
		UNION
		SELECT 'OPENROWSET'
		UNION
		SELECT 'OPENQUERY'
		UNION 
		SELECT 'OPENDATASOURCE'
		

**********************************/

--To hide row counts and make the print statements easier to see.
SET NOCOUNT ON

/** Where To Search **/
DECLARE @SearchSSIS BIT = 1
DECLARE @SearchObjectNames BIT = 1
DECLARE @SearchObjectDefinition BIT = 1
DECLARE @SearchAgentJobs BIT = 1

/** What are you looking for? **/
DECLARE @ObjectsToSearchFor TABLE
	(
	TextString VARCHAR(200) NULL
	)

INSERT INTO @ObjectsToSearchFor
(TextString)
SELECT srvname FROM sys.sysservers WHERE srvname <> @@SERVERNAME 
UNION
SELECT datasource FROM sys.sysservers WHERE srvname <> @@SERVERNAME
UNION
SELECT srvnetname FROM sys.sysservers WHERE srvnetname <> @@SERVERNAME
UNION
SELECT 'OPENROWSET'
UNION
SELECT 'OPENQUERY'
UNION 
SELECT 'OPENDATASOURCE'

/*************************************************************************************************************************
Don't chane anyting  below this line unless you know what you are doing
**************************************************************************************************************************/

/** Handle Recursion on #SearchResults.
	Remember to save your data first!
	
	If you don't want recursion, explitly drop #SearchResults between executions.
	**/
IF OBJECT_ID('tempdb..#SearchResults') IS NOT NULL
BEGIN

	DELETE FROM @ObjectsToSearchFor 

	--This allows for successive iterations to search for objects which reference objects which reference....
	INSERT INTO @ObjectsToSearchFor
	(TextString)
	SELECT DISTINCT ObjectName
	FROM #SearchResults 
	WHERE LocationFound IN ('sys.sql_modules')
		AND ObjectName IS NOT NULL 

	SET @SearchObjectNames = 0
	
	DROP TABLE #SearchResults 

END

CREATE TABLE #SearchResults
	(
	DatabaseName SYSNAME NULL
	, ObjectName SYSNAME NULL
	, LocationFound VARCHAR(100) NULL
	, MatchedOn VARCHAR(200) NULL
	, Misc VARCHAR(100) NULL
	)

/** Various declarations to hold results. **/
DECLARE @SearchTerm VARCHAR(200)
DECLARE @DatabaseName SYSNAME
DECLARE @Query NVARCHAR(4000)

-- Loop through search terms.
DECLARE curSearch CURSOR LOCAL STATIC FORWARD_ONLY
FOR	SELECT O.TextString
	FROM @ObjectsToSearchFor O
	 
OPEN curSearch

FETCH NEXT FROM curSearch
INTO @SearchTerm

WHILE @@FETCH_STATUS = 0
BEGIN

	--Begin Searching.
	PRINT ('Looking for: ' + @SearchTerm)

	/** This will loop over every database, only do it if you need it. **/
	IF(@SearchObjectDefinition = 1 OR @SearchObjectNames = 1)
	BEGIN

		DECLARE curDatabases CURSOR LOCAL STATIC FORWARD_ONLY
		FOR	SELECT D.name
			FROM sys.sysdatabases D
			ORDER BY D.name 

		OPEN curDatabases

		FETCH NEXT FROM curDatabases 
		INTO @DatabaseName 

		WHILE @@FETCH_STATUS = 0
		BEGIN

			--Look for object name matching...
			IF(@SearchObjectNames = 1)
			BEGIN

				SET @Query = 'USE ' + QUOTENAME(@DatabaseName) + ';'
					+ 'INSERT INTO #SearchResults'
					+ ' SELECT DB_NAME()'
					+ ', O.name'
					+ ', ' + QUOTENAME('sys.objects', '''')
					+ ', ' + QUOTENAME(@SearchTerm, '''')
					+ ', O.type_desc'
					+ ' FROM sys.objects O (NOLOCK)'
					+ ' WHERE LOWER(O.name) LIKE ' + QUOTENAME('%' + LOWER(@SearchTerm) + '%', '''')

				EXEC sp_executesql @Query 

				SET @Query = 'USE ' + QUOTENAME(@DatabaseName) + ';'
					+ 'INSERT INTO #SearchResults'
					+ ' SELECT DB_NAME()'
					+ ', C.name'
					+ ', ' + QUOTENAME('sys.columns', '''')
					+ ', ' + QUOTENAME(@SearchTerm, '''')
					+ ', O.name + O.type_desc'
					+ ' FROM sys.columns C (NOLOCK) INNER JOIN sys.objects O ON O.[object_id] = C.[object_id]'
					+ ' WHERE LOWER(C.name) LIKE ' + QUOTENAME('%' + LOWER(@SearchTerm) + '%', '''')

				EXEC sp_executesql @Query 

			END --Looking for object names.

			--Look for definitions.
			--Find objects that have the string in question listed, but ignore where the name is what is being searched for.
			IF(@SearchObjectDefinition = 1)
			BEGIN

				SET @Query = 'USE ' + QUOTENAME(@DatabaseName) + ';'
					+ 'INSERT INTO #SearchResults'
					+ ' SELECT DB_NAME()'
					+ ', O.name'
					+ ', ' + QUOTENAME('sys.sql_modules', '''')
					+ ', ' + QUOTENAME(@SearchTerm, '''')
					+ ', O.type_desc'
					+ ' FROM sys.sql_modules M (NOLOCK) INNER JOIN sys.objects O ON O.[object_id] = M.[object_id]'
					+ ' WHERE LOWER(M.[definition]) LIKE ' + QUOTENAME('%' + LOWER(@SearchTerm) + '%', '''')
					+ ' AND NOT(LOWER(O.name) = LOWER(' + QUOTENAME(@SearchTerm, '''') + '))'

				EXEC sp_executesql @Query 

			END --Looking for object definitions.
				
			--Get next database
			FETCH NEXT FROM curDatabases
			INTO @DatabaseName

		END

		CLOSE curDatabases
		DEALLOCATE curDatabases 


	END

	--Look in SSIS packages.
	IF(@SearchSSIS = 1)
	BEGIN

		;WITH SSISFolders AS
		(
		SELECT pf.folderid
			, pf.parentfolderid
			, CAST(pf.foldername AS VARCHAR(MAX)) AS foldername
		FROM msdb.dbo.sysssispackagefolders pf (NOLOCK)
		WHERE pf.parentfolderid IS NULL 
		UNION ALL
		SELECT pf.folderid
			, pf.parentfolderid
			, Parent.foldername + '\' + ISNULL(CAST(pf.foldername AS VARCHAR(MAX)), '') AS foldername
		FROM msdb.dbo.sysssispackagefolders pf (NOLOCK)
			INNER JOIN SSISFolders Parent ON Parent.folderid = pf.parentfolderid 
		)
		INSERT INTO #SearchResults
		SELECT NULL
			, ISNULL(F.foldername, '') + '\' + CAST(ISNULL(S.name, '') AS VARCHAR(MAX))
			, 'msdb.dbo.syssispackages'
			, @SearchTerm
			, NULL 
		FROM msdb.dbo.sysssispackages S (NOLOCK)
			LEFT OUTER JOIN SSISFolders F (NOLOCK) ON F.folderid = S.folderid 
		WHERE LOWER(CAST(CAST(CAST(CAST(packagedata AS VARBINARY(MAX)) AS VARCHAR(MAX)) AS XML) AS VARCHAR(MAX))) LIKE ('%' + @SearchTerm + '%')

	END

	--Look in SQL Agent Jobs
	IF(@SearchAgentJobs = 1)
	BEGIN

		--Job Name
		INSERT INTO #SearchResults
		SELECT NULL
			, J.name
			, 'msdb.dbo.sysjobs'
			, @SearchTerm
			, 'Job Name'
		FROM msdb.dbo.sysjobs J (NOLOCK)
		WHERE LOWER(J.name) LIKE ('%' + @SearchTerm + '%')

		--Job Description
		INSERT INTO #SearchResults
		SELECT NULL
			, J.name
			, 'msdb.dbo.sysjobs'
			, @SearchTerm
			, 'Job Description'
		FROM msdb.dbo.sysjobs J (NOLOCK)
		WHERE LOWER(J.[description]) LIKE ('%' + @SearchTerm + '%')

		--Step Name.
		INSERT INTO #SearchResults
		SELECT NULL
			, (ISNULL(J.name, '') + ' - ' + ISNULL(S.step_name, '') + ' (' + CAST(S.step_id AS VARCHAR(10)) + ')')
			, 'msdb.dbo.sysjobsteps'
			, @SearchTerm 
			, 'Step Name'
		FROM msdb.dbo.sysjobsteps S (NOLOCK)
			INNER JOIN msdb.dbo.sysjobs J (NOLOCK) ON J.job_id = S.job_id
		WHERE LOWER(S.step_name) LIKE ('%' + @SearchTerm + '%')

		--Step Code.

		INSERT INTO #SearchResults
		SELECT NULL
			, (ISNULL(J.name, '') + ' - ' + ISNULL(S.step_name, '') + ' (' + CAST(S.step_id AS VARCHAR(10)) + ')')
			, 'msdb.dbo.sysjobsteps'
			, @SearchTerm 
			, 'Step Code'
		FROM msdb.dbo.sysjobsteps S (NOLOCK)
			INNER JOIN msdb.dbo.sysjobs J (NOLOCK) ON J.job_id = S.job_id
		WHERE LOWER(S.command) LIKE ('%' + @SearchTerm + '%')

	END --End Looking at Jobs.

	--Get next search term.
	FETCH NEXT FROM curSearch
	INTO @SearchTerm

END

--Cleanup.
CLOSE curSearch
DEALLOCATE curSearch 


/***************** Display Output **********************************/

--Display search terms.
SELECT O.TextString
	, COUNT(S.MatchedOn) AS MatchCount 
FROM @ObjectsToSearchFor O
	LEFT OUTER JOIN #SearchResults S ON S.MatchedOn = O.TextString
GROUP BY O.TextString 

--Display search results.
SELECT DISTINCT * FROM #SearchResults 
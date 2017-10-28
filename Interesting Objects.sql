
--This will hold the list of objects.
DECLARE @Objects TABLE
	(
	Name SYSNAME NOT NULL
	, ObjectID INT NOT NULL
	, [RowCount] INT NULL
	, ColumnCount INT NULL
	, ColumnTEXTCount INT NULL
	, ColumnBlobCount INT NULL
	, ColumnLongTextCount INT NULL
	, PrimaryKeyCount INT NULL
	, ForeignKeyCount INT NULL
	, ForeignKeyTargetCount INT NULL
	, DefaultConstraintCount INT NULL
	, ObjectAllCount INT NULL
	, IndexHeapCount INT NULL
	, IndexClusteredCount INT NULL
	, IndexNonClusteredCount INT NULL
	, IndexAllCount INT NULL
	, OldDataTypes INT NULL
	, ComputedColumnCount INT NULL
	, Interesting INT NULL
	, Reason VARCHAR(MAX) NULL
	)
	
--Get the initial list of objects to analyze.
--Use any filtering here if you want.
INSERT INTO @Objects (Name, ObjectID)
SELECT T.name
	, T.[object_id]
FROM sys.tables T

/***********************************************************************************/

/** Begin getting the various statistic information about the tables
	in the below sections.  Broken down more by type of gathering than
	for any real need to do so.  
	**/
	
--Get the row count for the table.
UPDATE @Objects
SET [RowCount] = st.row_count
FROM @Objects O
	INNER JOIN sys.dm_db_partition_stats st ON st.[object_id] = O.ObjectID
	
--ColumnCounts.
UPDATE @Objects
SET ColumnCount = (	SELECT COUNT(C.column_id) 
					FROM sys.columns C 
					WHERE C.[object_id] = O.ObjectID)
	, ColumnTEXTCount = (	SELECT COUNT(C.column_id) 
							FROM sys.columns C 
							WHERE C.[object_id] = O.ObjectID 
								AND C.system_type_id = 35)
	, ColumnBlobCount = (	SELECT COUNT(C.column_id) 
							FROM sys.columns C 
							WHERE C.[object_id] = O.ObjectID 
								AND C.system_type_id IN (173,34, 32))
	, ColumnLongTextCount = (	SELECT COUNT(C.column_id) 
								FROM sys.columns C 
								WHERE C.[object_id] = O.ObjectID 
									AND C.system_type_id IN (231, 167)
									AND (C.max_length >= 1000 OR C.max_length = -1))
	, ComputedColumnCount = (SELECT COUNT(C.column_id) 
							FROM sys.columns C 
							WHERE C.[object_id] = O.ObjectID 
								AND C.is_computed = 1)
FROM @Objects O

--Index Counts.
UPDATE @Objects
SET IndexHeapCount = (	SELECT COUNT(I.index_id)
						FROM sys.indexes I
						WHERE I.[object_id] = O.ObjectID
							AND I.type_desc = 'HEAP')
	, IndexClusteredCount  = (	SELECT COUNT(I.index_id)
								FROM sys.indexes I
								WHERE I.[object_id] = O.ObjectID
									AND I.type_desc = 'CLUSTERED')
	, IndexNonClusteredCount  = (	SELECT COUNT(I.index_id)
									FROM sys.indexes I
									WHERE I.[object_id] = O.ObjectID
										AND I.type_desc = 'NONCLUSTERED')
	, IndexAllCount = (	SELECT COUNT(I.index_id)
							FROM sys.indexes I
							WHERE I.[object_id] = O.ObjectID)
FROM @Objects O

--Keys/Constraint Counts.
UPDATE @Objects
SET PrimaryKeyCount = (	SELECT COUNT(O.[object_id])
						FROM sys.objects O
						WHERE O.parent_object_id = Ob.ObjectID
							AND O.type_desc = 'PRIMARY_KEY_CONSTRAINT')
	, ForeignKeyCount = (	SELECT COUNT(O.[object_id])
							FROM sys.objects O
							WHERE O.parent_object_id = Ob.ObjectID
								AND O.type_desc = 'FOREIGN_KEY_CONSTRAINT')
	, DefaultConstraintCount = (	SELECT COUNT(O.[object_id])
									FROM sys.objects O
									WHERE O.parent_object_id = Ob.ObjectID
										AND O.type_desc = 'DEFAULT_CONSTRAINT')
	, ObjectAllCount = (	SELECT COUNT(O.[object_id])
							FROM sys.objects O
							WHERE O.parent_object_id = Ob.ObjectID)
	, ForeignKeyTargetCount = (	SELECT COUNT(C.constraint_object_id)
								FROM sys.foreign_key_columns C
								WHERE C.referenced_object_id = Ob.ObjectID)
FROM @Objects Ob

--Old Data Types
-- Money type should not be used.
-- datetime type should not be used.
-- Image, text, ntext should not be used.
-- smalldatetime should not be used.

UPDATE @Objects
SET OldDataTypes = (	SELECT COUNT(C.column_id) 
						FROM sys.columns C 
						WHERE C.[object_id] = O.ObjectID 
							AND C.system_type_id IN (60, 61, 58, 35, 99, 34)
						)
FROM @Objects O

/***********************************************************************************/

/** Determine how interesting the table is. 
	The more rules it trips, the more interesting it gets.
	**/
	
UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + ' Lots of Rows (Top 10%);'
FROM @Objects O
WHERE O.ObjectID IN (SELECT TOP 10 PERCENT R.ObjectID FROM @Objects R ORDER BY R.[RowCount] DESC)

UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + ' No Primary Key;'
WHERE PrimaryKeyCount = 0

UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + ' More than 1 foreign key;'
WHERE ForeignKeyCount > 1
	
UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + ' Lots of Indexes (Top 10%);'
WHERE IndexAllCount > 1
	AND ObjectID IN (SELECT TOP 10 PERCENT R.ObjectID FROM @Objects R WHERE R.IndexAllCount > 1 ORDER BY R.IndexAllCount DESC)

UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + ' Lots of objects (TOP 10%);'
FROM @Objects O
WHERE O.ObjectID IN (SELECT TOP 10 PERCENT R.ObjectID FROM @Objects R ORDER BY R.ColumnCount DESC)

UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + ' Has a column with a datatype TEXT;'
WHERE ColumnTEXTCount <> 0

UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + ' Has a column with a BLOB datatype;'
WHERE ColumnBlobCount <> 0

UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + ' Has a column with a large character field;'
WHERE ColumnLongTextCount <> 0

UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + ' Is the target for many foreign key constraints;'
WHERE ForeignKeyTargetCount > 1

UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + ' Contains data types that should not be used anymore (smalldatetime, datetime, money, text, ntext, image, etc.);'
WHERE OldDataTypes > 0

UPDATE @Objects
SET Interesting = ISNULL(Interesting, 0) + 1
	, Reason = ISNULL(Reason, '') + 'Computed Column Detected.'
WHERE ComputedColumnCount > 0

/***********************************************************************************/

/** Return the data back to the user.
	1 - Return the @Objects table, sorted by how interesting the table is.
	2 - Return a list of data types used in the tables and their frequency.
	**/

--First, the list of objects.
SELECT * FROM @Objects ORDER BY Interesting DESC

--Second, a breakdown of all data types used in the related tables and their popularity.
SELECT T.name
	, C.max_length
	, COUNT(C.column_id) AS Occurence
	, [Status] = CASE	WHEN T.system_type_id IN (60, 61, 58, 35, 99, 34) THEN 'Not recommended for new work.' 
						ELSE NULL 
						END
FROM sys.columns C 
	INNER JOIN sys.types T ON T.system_type_id = C.system_type_id 	
WHERE C.object_id IN (SELECT O.ObjectID FROM @Objects O)
GROUP BY T.name, C.max_length, T.system_type_id
ORDER BY 4 DESC, 3 DESC
/*******
	Name: My little Statement Helper
	Author: Dustin Marzolf
	
	Purpose: To help with building various statements regarding existing tables.

	Usage:
		- Given a table/view, will return the column information about it.
		- If the column is part of a clustered index, that is represented with the "IsIndexed" field.
		- You can point this at temporary tables as well, just change the database to "tempdb" and set the tablename to "tempdb..#YourTempTablename"

	Output:
		- various columns describing the specific column for that table (data type name, nullable, precision, etc.)
		- BuildStatement - The column with the data type/null or not
		- BuildIndex - the name of the column if it's part of a clustered index.
		- Statement_Select -selectable columns
		- MergeStatement_XX - Constructs to help with merge statement 




*****/


--May need to include schema if not in dbo.
DECLARE @TableName SYSNAME
SET @TableName = 'tempdb..#InvoiceDetailTemp'

;WITH ColData
AS
(
SELECT O.type_desc AS ObjectType
	, S.name AS SchemaName
	, O.name AS ObjectName
	, C.name AS ColumnName
	, C.column_id AS ColumnID
	, IsIndexed = CASE WHEN IC.index_column_id IS NOT NULL THEN 1 ELSE 0 END
	, C.is_nullable AS IsNullable
	, DataTypeName = UPPER(T.name)
	, DataTypePrecision = C.[precision]
	, DataTypeScale = C.scale
	, DataTypeMaxLength = C.max_length
	, BuildColumn = ', ' + QUOTENAME(C.name) + ' ' + UPPER(T.name) + CASE	WHEN T.user_type_id IN (167,175,231,239)  --CHAR, VARCHAR, NCHAR, NVARCHAR
																				THEN '(' + CAST(C.max_length AS VARCHAR(10)) + ')'
																			WHEN T.user_type_id IN (106) --decimal
																				THEN '(' + CAST(C.[precision] AS VARCHAR(10)) + ', ' + CAST(C.scale AS VARCHAR(10)) + ')'
																		ELSE ''
																		END
																+ CASE WHEN C.is_nullable = 0 THEN ' NULL'
																		ELSE ' NOT NULL'
																		END
	, BuildIndex = CASE WHEN IC.index_column_id IS NOT NULL THEN ', ' + QUOTENAME(C.name) ELSE '' END
FROM sys.columns C
	INNER JOIN sys.objects O ON O.object_id = C.object_id
	INNER JOIN sys.schemas S ON S.schema_id = O.schema_id
	INNER JOIN sys.types T ON T.user_type_id = C.user_type_id
	LEFT OUTER JOIN sys.indexes I ON I.object_id = C.object_id AND I.type = 1
	LEFT OUTER JOIN sys.index_columns IC ON IC.object_id = C.object_id AND IC.index_id = I.index_id AND IC.column_id = C.column_id
WHERE C.object_id = OBJECT_ID(@TableName)
)
SELECT D.*
	, Statement_Select = ', ' + QUOTENAME(D.ColumnName)
	, MergeStatement_Join = CASE WHEN D.IsIndexed = 1
									THEN ' AND S.' + QUOTENAME(D.ColumnName) + ' = T.' + QUOTENAME(D.ColumnName)
								ELSE ''
								END
	, MergeStatement_WhenMatched = CASE WHEN D.IsIndexed = 0 
											THEN ' AND S.' + QUOTENAME(D.ColumnName) + ' <> T.' + QUOTENAME(D.ColumnName)
										ELSE ''
										END
	, MergeStatement_Update = ', T.' + QUOTENAME(D.ColumnName) + ' = S.' + QUOTENAME(D.ColumnName)
	, MergeStatement_Insert_Col = ', ' + QUOTENAME(D.ColumnName)
	, MergeStatement_Insert_Values = ', S.' + QUOTENAME(D.ColumnName)						
FROM ColData D

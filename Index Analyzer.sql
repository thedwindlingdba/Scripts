/**
	Author: Dustin Marzolf 

	Comprehensive index  info



*/

/** Initialize Variables. 

	@DatabaseID - The database we want to examine, defaults to the current database...
	@IndexScanLevel - Chose  one of the levels of detail below.
		- LIMITED -  only looks at the parent level of the index. (Default)
		- SAMPLED - Detailed look at ~1% of the pages in the index. 
		- DETAILED - full scan of all pages( Can cause significant IO pressure do not run in prod)
	@MinFragmentation - If you want to see only indexes fragmented to a certain level.
	@MinPageCount - To limit to indexes that are over a certain page count.  
*/

DECLARE @DatabaseID INT;
SET @DatabaseID = (SELECT DB_ID());

DECLARE @IndexScanLevel NVARCHAR(10);
SET @IndexScanLevel = 'SAMPLED';

DECLARE @MinFragmentation DECIMAL(4,2);
SET @MinFragmentation = 0.0;

DECLARE @MinPageCount INT;
SET @MinPageCount = 100;

/** Begin Work on the Query *********************************************************/

--Get Column List Information
DECLARE @ColumnList AS TABLE
	(
	object_id INT NOT NULL
	, index_id  INT NOT NULL
	, IndexedColumns VARCHAR(8000) NULL
	, IncludedColumns VARCHAR(8000) NULL
	);

WITH CTE_ColumnList AS
(
	SELECT IC.object_id
		, IC.index_id, C.name
		, IC.key_ordinal AS Position
		, DisplayName = C.name + CASE WHEN IC.is_descending_key = 1 THEN ' DESC' ELSE '' END
		, IC.is_included_column
	FROM sys.index_columns IC
		INNER JOIN sys.columns C ON C.object_id = IC.object_id AND IC.column_id = C.column_id
)
INSERT INTO @ColumnList
        ( object_id ,
          index_id ,
          IndexedColumns ,
          IncludedColumns
        )
SELECT DISTINCT 
	C.object_id
	, C.index_id
	, IndexedColumns = STUFF((SELECT ', ' + E.DisplayName FROM CTE_ColumnList E WHERE E.object_id = C.object_id AND E.index_id = C.index_id AND E.is_included_column = 0 ORDER BY E.Position FOR XML PATH('')), 1,1,'')
	, IncludedColumns  = STUFF((SELECT ', ' + E.DisplayName FROM CTE_ColumnList E WHERE E.object_id = C.object_id AND E.index_id = C.index_id AND E.is_included_column = 1 ORDER BY E.Position FOR XML PATH('')), 1,1,'')
FROM CTE_ColumnList C;

SELECT DB_NAME(IPS.database_id) AS DatabaseName
	, SchemaName = S.name
	, ObjectName = O.name
	, O.type_desc AS ObjectType
	, I.name AS IndexName
	, IPS.index_type_desc
	, IPS.alloc_unit_type_desc
	, IPS.avg_fragmentation_in_percent
	, IPS.avg_page_space_used_in_percent 
	, IPS.page_count
	, PageSize_MB = (IPS.page_count/128.0)
	, I.is_unique
	, I.fill_factor
	, I.is_disabled
	, I.has_filter
	, I.filter_definition
	, IUS.user_seeks
	, IUS.user_scans
	, IUS.user_lookups
	, IUS.user_updates
	, UsageActivityTotal = IUS.user_seeks + IUS.user_scans + IUS.user_lookups + IUS.user_updates
	, IOS.leaf_insert_count
	, IOS.leaf_update_count
	, IOS.leaf_delete_count
	, OperationalActivityTotal = IOS.leaf_insert_count + IOS.leaf_update_count + IOS.leaf_delete_count
	, LastAccessed = IUS_LastUsed.LastUsed
	, CL.IndexedColumns
	, CL.IncludedColumns
FROM sys.dm_db_index_physical_stats(@DatabaseID, NULL, NULL, NULL, @IndexScanLevel) AS IPS
	INNER JOIN sys.objects O ON O.object_id = IPS.object_id
	INNER JOIN sys.schemas S ON S.schema_id = O.schema_id
	INNER JOIN sys.indexes I ON I.object_id = IPS.object_id AND I.index_id = IPS.index_id
	LEFT OUTER JOIN @ColumnList CL ON CL.object_id = IPS.object_id AND CL.index_id = IPS.index_id
	LEFT OUTER JOIN sys.dm_db_index_usage_stats IUS ON IUS.database_id = IPS.database_id AND IUS.object_id = IPS.object_id AND IUS.index_id = IPS.index_id
	LEFT OUTER JOIN sys.dm_db_index_operational_stats(@DatabaseID, NULL, NULL, NULL) IOS ON IOS.object_id = IPS.object_id AND IOS.index_id = IPS.index_id
	LEFT OUTER JOIN (
					SELECT S.database_id
						, S.object_id
						, S.index_id
						, MAX(S.lastused) AS LastUsed
					FROM sys.dm_db_index_usage_stats UNPIVOT (lastused FOR nlastused IN (last_user_seek, last_user_scan, last_user_lookup, last_user_update)) AS S
					GROUP BY S.database_id
						, S.object_id
						, S.index_id
					) IUS_LastUsed ON IUS_LastUsed.database_id = IPS.database_id AND IUS_LastUsed.object_id = IPS.object_id AND IUS_LastUsed.index_id = IPS.index_id
WHERE ISNULL(O.is_ms_shipped, 0x0) = 0x0 --Exclude System Generated Objects
	AND ISNULL(I.is_disabled, 0x0) = 0x0 --Exclude Disabled Indexes
	AND ISNULL(IPS.page_count, 0) >= @MinPageCount --Only worry about indexes with worthwhile page counts
	AND ISNULL(IPS.avg_fragmentation_in_percent, 0.0) >= @MinFragmentation --Only display indexes that exceed fragmentation threshold
ORDER BY IPS.avg_fragmentation_in_percent DESC;
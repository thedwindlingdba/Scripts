USE [master]
GO

/****** Object:  StoredProcedure [dbo].[usp_CreateSnapshot]    Script Date: 01-01-1900 5:50:21 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[usp_CreateSnapshot]
(@DatabaseName SYSNAME = NULL,@SnapshotSuffixName VARCHAR(8) = NULL)
AS
--EXEC usp_CreateSnapshot
--EXEC usp_CreateSnapshot test
--EXEC usp_CreateSnapshot test, 'Morning'
SET NOCOUNT ON;
DECLARE @UID VARCHAR(8)
SET @DatabaseName = COALESCE(@DatabaseName,DB_NAME())
SET @UID = COALESCE(@SnapshotSuffixName,CONVERT(VARCHAR(8),GETDATE(),112))
DECLARE @sql NVARCHAR(MAX)
SELECT @sql =N'CREATE DATABASE '+QUOTENAME(@DatabaseName+'_'+@UID)+' ON' +
STUFF((
SELECT
',(NAME='+QUOTENAME(mf.[name])+',FILENAME='''+mf.[physical_name]+'.'+@UID+'.ss'+''')'
FROM sys.master_files AS mf
INNER JOIN sys.databases AS d ON mf.[database_id]=d.[database_id]
WHERE (d.[state_desc]='ONLINE' OR d.[state_desc]='RESTORING')
AND mf.[state_desc]='ONLINE'
AND mf.[type_desc]='ROWS'
AND d.[source_database_id] IS NULL
AND d.[name] = @DatabaseName
FOR XML PATH('')), 1, 1, ' ')+' AS SNAPSHOT OF '+QUOTENAME(@DatabaseName)+';'
BEGIN TRY
 IF (@sql IS NOT NULL)
 BEGIN
 PRINT @sql
 EXECUTE sp_executesql @sql;SELECT [name],[create_date] FROM sys.databases WHERE name = (@DatabaseName+'_'+@UID)
 PRINT 'GO'
 PRINT 'RESTORE DATABASE '+QUOTENAME(@DatabaseName)+' FROM DATABASE_SNAPSHOT = '''+@DatabaseName+'_'+@UID+''';'
 END
 ELSE
 BEGIN
  PRINT 'Script Generation Failed.'
 END
END TRY
BEGIN CATCH
    PRINT ERROR_MESSAGE()
END CATCH

GO



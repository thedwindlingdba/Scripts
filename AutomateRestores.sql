USE dba

IF EXISTS (SELECT 1 FROM dba.sys.objects WHERE name='AutomatedRestore' AND type='P')
DROP PROCEDURE dbo.AutomatedRestore

GO

CREATE PROCEDURE dbo.AutomatedRestore

--By default, running the stored procedure will only output
--a list of the backup files needed (@ListFilesOnly=1)
--When that is set to 0, then the default will be to output
--the TSQL restore statements to the user, not to immediately run the statements.
--They can then be copied into a query window and run. To just construct and
--immediately run the restore, both @ListFilesOnly and @OutputCommandText must be 0.



@RestorePointInTime datetime='1900-01-01-1900:05.000',
@SourceDB varchar(max)='ba',
@DestinationDB varchar(max)='dbatest',
@ListFilesOnly bit=1,
@OutputCommandText bit=1

AS

BEGIN

--The single variable declared within the stored procedure, for holding and constructing the restore TSQL statements

DECLARE @RestoreTSQL varchar(max)=''

--The most straightforward way to construct a restore chain resulted in 10 scans of the backupset table.
--While that is probably acceptable for something one-off like this, I wanted to make it more efficient.
--Fortunately, I did reduce that to 2 scans, which makes sense as a lower limit without indexing, since
--the chain of fulls and differentials is really a different chain than the tlog chain, so there are two
--chains being constructed.
--Unfortunately, that 500% speedup came at the cost of readability, as it's now a pretty complicated
--cross tab query.(2014 provides more elegant solution, but original customer was on 2008)

SELECT physical_device_name, IsLastBackup, backup_set_id,type,backup_start_date,backup_finish_date into #tmp
FROM
(SELECT media_set_id,type,backup_start_date,backup_finish_date,backup_set_id,
IsLastBackup=CASE WHEN backup_finish_date=MostRecentTlog THEN 1 ELSE 0 END
FROM (
SELECT
MostRecentFull=MAX(CASE WHEN backup_finish_date<@RestorePointInTime AND type='d' THEN backup_finish_date ELSE '19000101 00:00' END),
MostRecentDiff=MAX(CASE WHEN backup_finish_date<@RestorePointInTime AND type='i' THEN backup_finish_date ELSE '19000101 00:00' END),
MostRecentTlog=MIN(CASE WHEN backup_finish_date>@RestorePointInTime AND type='l' THEN backup_finish_date ELSE GETDATE() END)
FROM msdb.dbo.backupset
WHERE database_name=@SourceDB) InnerQuery
CROSS JOIN msdb.dbo.backupset
WHERE ((type='d' and backup_finish_date=MostRecentFull) OR (type='i' AND backup_finish_date=MostRecentDiff AND MostRecentDiff>MostRecentFull) OR
(type='l' AND backup_finish_date>MostRecentDiff AND backup_finish_date>MostRecentFull AND backup_finish_date<=MostRecentTlog))
AND database_name=@SourceDB
) BackupChain
INNER JOIN msdb.dbo.backupmediafamily bmf
ON BackupChain.media_set_id=bmf.media_set_id
ORDER BY backup_finish_date asc/

--Having now constructed the restore chain to use, if @ListFilesOnly is 1, we output the list of files and terminate the batch.

IF @ListFilesOnly=1
BEGIN
SELECT backup_start_date,backup_finish_date,physical_device_Name FROM #tmp ORDER BY backup_start_date asc
DROP TABLE #tmp
RETURN
END

--If @ListFilesOnly is not 1, we now begin constructing the TSQL statements for the restore.

SELECT @RestoreTSQL='RESTORE DATABASE '+quotename(@destinationDB)+' FROM DISK='''+physical_device_name+''' WITH NORECOVERY, STATS=10,'+CHAR(13)+CHAR(10)
FROM #tmp WHERE type='d'

--For the restore of the full backup, we use the MOVE clause to make sure we don't step on any files' toes.
--Since there's no guarantee that the file names will be based on the database names, I'm just replacing
--the filenames with the destination database name and a number to guarantee uniqueness.

SELECT @RestoreTSQL=@RestoreTSQL+'MOVE '''+logical_name+''' to '''+LEFT(physical_name,LEN(physical_name)-CHARINDEX('\',REVERSE(physical_name),0)+1)+
@DestinationDB+CAST(ROW_NUMBER() OVER (ORDER BY bf.backup_set_id) as varchar(max))+
RIGHT(physical_name,4)+''''+CASE WHEN ROW_NUMBER() OVER (ORDER BY bf.backup_set_id)!=1 THEN ',' ELSE '' END + CHAR(13)+CHAR(10)
FROM msdb.dbo.backupfile bf
inner join #tmp on #tmp.backup_set_id=bf.backup_set_id
WHERE #tmp.type='d'
ORDER BY ROW_NUMBER() OVER (ORDER BY bf.backup_set_id) desc

--Now we construct the restores of the diff and tlogs, and in case we get to the last log,
--we add the appropriate STOPAT. For maximum flexibility, we do all restores WITH NORECOVERY,
--and then just run a RESTORE <database name> WITH RECOVERY at the end.

SELECT @RestoreTSQL=@RestoreTSQL+'RESTORE DATABASE '+quotename(@destinationDB)+' FROM DISK='''+physical_device_name+''''+
CASE WHEN IsLastBackup=0 THEN ' WITH NORECOVERY, STATS=10' ELSE ' WITH NORECOVERY, STATS=10, STOPAT='''+CONVERT(varchar(max),@RestorePointInTime,126)+'''' END + CHAR(13)+CHAR(10)
FROM #tmp
WHERE type!='d'
order by backup_finish_date asc

SELECT @RestoreTSQL=@RestoreTSQL+'RESTORE DATABASE '+quotename(@destinationDB)+' WITH RECOVERY' + CHAR(13)+CHAR(10)

--Now we either output the command text to the user or execute the command,
--based on @OutputCommandText

IF @OutputCommandText=1
BEGIN
SELECT @RestoreTSQL
END
ELSE
BEGIN
EXECUTE (@RestoreTSQL)
END


DROP TABLE #tmp


END

GO

--A template for running the procedure.
--Note that this will use the default values for @ListFilesOnly
--and @OutputCommandText, so you'll just get the list of backup files
--by default. Change them as explained in the notes in the stored
--procedure to either get a script to run or directly run the restore.

EXEC dbo.AutomatedRestore
@SourceDB='',
@DestinationDB='',
@RestorePointInTime='',
@ListFilesOnly=1,
@OutputCommandText=1





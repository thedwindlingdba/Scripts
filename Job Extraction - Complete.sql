/**
	Get schedule data and create a description of the schedule.
**/
DECLARE @JobSchedules TABLE
	(
	schedule_id INT NOT NULL
	, schedule_uid UNIQUEIDENTIFIER NOT NULL
	, name SYSNAME NOT NULL
	, owner_sid VARBINARY(MAX) NOT NULL
	, [enabled] BIT NOT NULL
	, scheduledescription VARCHAR(200) NULL
	)

INSERT INTO @JobSchedules
(schedule_id, schedule_uid, name, owner_sid, [enabled], scheduledescription)
SELECT msdb.dbo.sysschedules.schedule_id 
	, msdb.dbo.sysschedules.schedule_uid 
	, msdb.dbo.sysschedules.name 
	, msdb.dbo.sysschedules.owner_sid
	, msdb.dbo.sysschedules.[enabled]
	, scheduledescription = CASE  WHEN msdb.dbo.sysschedules.freq_type = 0x1 -- OneTime
           THEN
               'Once on '
             + CONVERT(
                          CHAR(10)
                        , CAST( CAST( msdb.dbo.sysschedules.active_start_date AS VARCHAR ) AS DATETIME )
                        , 102 -- yyyy.mm.dd
                       )
       WHEN msdb.dbo.sysschedules.freq_type = 0x4 -- Daily
           THEN 'Daily'
       WHEN msdb.dbo.sysschedules.freq_type = 0x8 -- weekly
           THEN
               CASE
                   WHEN msdb.dbo.sysschedules.freq_recurrence_factor = 1
                       THEN 'Weekly on '
                   WHEN msdb.dbo.sysschedules.freq_recurrence_factor > 1
                       THEN 'Every '
                          + CAST( msdb.dbo.sysschedules.freq_recurrence_factor AS VARCHAR )
                          + ' weeks on '
               END
             + LEFT(
                         CASE WHEN msdb.dbo.sysschedules.freq_interval &  1 =  1 THEN 'Sunday, '    ELSE '' END
                       + CASE WHEN msdb.dbo.sysschedules.freq_interval &  2 =  2 THEN 'Monday, '    ELSE '' END
                       + CASE WHEN msdb.dbo.sysschedules.freq_interval &  4 =  4 THEN 'Tuesday, '   ELSE '' END
                       + CASE WHEN msdb.dbo.sysschedules.freq_interval &  8 =  8 THEN 'Wednesday, ' ELSE '' END
                       + CASE WHEN msdb.dbo.sysschedules.freq_interval & 16 = 16 THEN 'Thursday, '  ELSE '' END
                       + CASE WHEN msdb.dbo.sysschedules.freq_interval & 32 = 32 THEN 'Friday, '    ELSE '' END
                       + CASE WHEN msdb.dbo.sysschedules.freq_interval & 64 = 64 THEN 'Saturday, '  ELSE '' END
                     , LEN(
                                CASE WHEN msdb.dbo.sysschedules.freq_interval &  1 =  1 THEN 'Sunday, '    ELSE '' END
                              + CASE WHEN msdb.dbo.sysschedules.freq_interval &  2 =  2 THEN 'Monday, '    ELSE '' END
                              + CASE WHEN msdb.dbo.sysschedules.freq_interval &  4 =  4 THEN 'Tuesday, '   ELSE '' END
                              + CASE WHEN msdb.dbo.sysschedules.freq_interval &  8 =  8 THEN 'Wednesday, ' ELSE '' END
                              + CASE WHEN msdb.dbo.sysschedules.freq_interval & 16 = 16 THEN 'Thursday, '  ELSE '' END
                              + CASE WHEN msdb.dbo.sysschedules.freq_interval & 32 = 32 THEN 'Friday, '    ELSE '' END
                              + CASE WHEN msdb.dbo.sysschedules.freq_interval & 64 = 64 THEN 'Saturday, '  ELSE '' END
                           )  - 1  -- LEN() ignores trailing spaces
                   )
       WHEN msdb.dbo.sysschedules.freq_type = 0x10 -- monthly
           THEN
               CASE
                   WHEN msdb.dbo.sysschedules.freq_recurrence_factor = 1
                       THEN 'Monthly on the '
                   WHEN msdb.dbo.sysschedules.freq_recurrence_factor > 1
                       THEN 'Every '
                          + CAST( msdb.dbo.sysschedules.freq_recurrence_factor AS VARCHAR )
                          + ' months on the '
               END
             + CAST( msdb.dbo.sysschedules.freq_interval AS VARCHAR )
             + CASE
                   WHEN msdb.dbo.sysschedules.freq_interval IN ( 1, 21, 31 ) THEN 'st'
                   WHEN msdb.dbo.sysschedules.freq_interval IN ( 2, 22     ) THEN 'nd'
                   WHEN msdb.dbo.sysschedules.freq_interval IN ( 3, 23     ) THEN 'rd'
                   ELSE 'th'
               END
       WHEN msdb.dbo.sysschedules.freq_type = 0x20 -- monthly relative
           THEN
               CASE
                   WHEN msdb.dbo.sysschedules.freq_recurrence_factor = 1
                       THEN 'Monthly on the '
                   WHEN msdb.dbo.sysschedules.freq_recurrence_factor > 1
                       THEN 'Every '
                          + CAST( msdb.dbo.sysschedules.freq_recurrence_factor AS VARCHAR )
                          + ' months on the '
               END
             + CASE msdb.dbo.sysschedules.freq_relative_interval
                   WHEN 0x01 THEN 'first '
                   WHEN 0x02 THEN 'second '
                   WHEN 0x04 THEN 'third '
                   WHEN 0x08 THEN 'fourth '
                   WHEN 0x10 THEN 'last '
               END
             + CASE msdb.dbo.sysschedules.freq_interval
                   WHEN  1 THEN 'Sunday'
                   WHEN  2 THEN 'Monday'
                   WHEN  3 THEN 'Tuesday'
                   WHEN  4 THEN 'Wednesday'
                   WHEN  5 THEN 'Thursday'
                   WHEN  6 THEN 'Friday'
                   WHEN  7 THEN 'Saturday'
                   WHEN  8 THEN 'day'
                   WHEN  9 THEN 'week day'
                   WHEN 10 THEN 'weekend day'
               END
       WHEN msdb.dbo.sysschedules.freq_type = 0x40
           THEN 'Automatically starts when SQLServerAgent starts.'
       WHEN msdb.dbo.sysschedules.freq_type = 0x80
           THEN 'Starts whenever the CPUs become idle'
       ELSE ''
   END
 + CASE
       WHEN msdb.dbo.sysschedules.freq_subday_type = 0x1 OR msdb.dbo.sysschedules.freq_type = 0x1
           THEN ' at '
			+ Case  -- Depends on time being integer to drop right-side digits
				when(msdb.dbo.sysschedules.active_start_time % 1000000)/10000 = 0 then 
						  '12'
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100)))
						+ convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100) 
						+ ' AM'
				when (msdb.dbo.sysschedules.active_start_time % 1000000)/10000< 10 then
						convert(char(1),(msdb.dbo.sysschedules.active_start_time % 1000000)/10000) 
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
						+ convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100) 
						+ ' AM'
				when (msdb.dbo.sysschedules.active_start_time % 1000000)/10000 < 12 then
						convert(char(2),(msdb.dbo.sysschedules.active_start_time % 1000000)/10000) 
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
						+ convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100) 
						+ ' AM'
				when (msdb.dbo.sysschedules.active_start_time % 1000000)/10000< 22 then
						convert(char(1),((msdb.dbo.sysschedules.active_start_time % 1000000)/10000) - 12) 
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
						+ convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100) 
						+ ' PM'
				else	convert(char(2),((msdb.dbo.sysschedules.active_start_time % 1000000)/10000) - 12)
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
						+ convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100) 
						+ ' PM'
			end
       WHEN msdb.dbo.sysschedules.freq_subday_type IN ( 0x2, 0x4, 0x8 )
           THEN ' every '
             + CAST( msdb.dbo.sysschedules.freq_subday_interval AS VARCHAR )
             + CASE freq_subday_type
                   WHEN 0x2 THEN ' second'
                   WHEN 0x4 THEN ' minute'
                   WHEN 0x8 THEN ' hour'
               END
             + CASE
                   WHEN msdb.dbo.sysschedules.freq_subday_interval > 1 THEN 's'
				   ELSE '' -- Added default 3/21/08; John Arnott
               END
       ELSE ''
   END
 + CASE
       WHEN msdb.dbo.sysschedules.freq_subday_type IN ( 0x2, 0x4, 0x8 )
           THEN ' between '
			+ Case  -- Depends on time being integer to drop right-side digits
				when(msdb.dbo.sysschedules.active_start_time % 1000000)/10000 = 0 then 
						  '12'
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100)))
						+ rtrim(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))
						+ ' AM'
				when (msdb.dbo.sysschedules.active_start_time % 1000000)/10000< 10 then
						convert(char(1),(msdb.dbo.sysschedules.active_start_time % 1000000)/10000) 
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
						+ rtrim(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))
						+ ' AM'
				when (msdb.dbo.sysschedules.active_start_time % 1000000)/10000 < 12 then
						convert(char(2),(msdb.dbo.sysschedules.active_start_time % 1000000)/10000) 
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
						+ rtrim(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100)) 
						+ ' AM'
				when (msdb.dbo.sysschedules.active_start_time % 1000000)/10000< 22 then
						convert(char(1),((msdb.dbo.sysschedules.active_start_time % 1000000)/10000) - 12) 
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
						+ rtrim(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100)) 
						+ ' PM'
				else	convert(char(2),((msdb.dbo.sysschedules.active_start_time % 1000000)/10000) - 12)
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
						+ rtrim(convert(char(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))
						+ ' PM'
			end
             + ' and '
			+ Case  -- Depends on time being integer to drop right-side digits
				when(msdb.dbo.sysschedules.active_end_time % 1000000)/10000 = 0 then 
						'12'
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100)))
						+ rtrim(convert(char(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))
						+ ' AM'
				when (msdb.dbo.sysschedules.active_end_time % 1000000)/10000< 10 then
						convert(char(1),(msdb.dbo.sysschedules.active_end_time % 1000000)/10000) 
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))) 
						+ rtrim(convert(char(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))
						+ ' AM'
				when (msdb.dbo.sysschedules.active_end_time % 1000000)/10000 < 12 then
						convert(char(2),(msdb.dbo.sysschedules.active_end_time % 1000000)/10000) 
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))) 
						+ rtrim(convert(char(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))
						+ ' AM'
				when (msdb.dbo.sysschedules.active_end_time % 1000000)/10000< 22 then
						convert(char(1),((msdb.dbo.sysschedules.active_end_time % 1000000)/10000) - 12)
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))) 
						+ rtrim(convert(char(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100)) 
						+ ' PM'
				else	convert(char(2),((msdb.dbo.sysschedules.active_end_time % 1000000)/10000) - 12)
						+ ':'  
						+Replicate('0',2 - len(convert(char(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))) 
						+ rtrim(convert(char(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100)) 
						+ ' PM'
			end
       ELSE ''
   END
FROM msdb.dbo.sysschedules

/**
	Get a list of jobs and their total step count.
**/

DECLARE @JobCounter TABLE
	(
	job_id UNIQUEIDENTIFIER NULL
	, name SYSNAME
	, ScheduleCount INT NULL
	, StepCount INT NULL
	, Step_TSQL INT NULL
	, Step_SSIS INT NULL
	, Step_PSHELL INT NULL
	, Step_CMD INT NULL
	, Step_Other INT NULL
	)

INSERT INTO @JobCounter
(job_id, name, StepCount, ScheduleCount, Step_TSQL, Step_SSIS, Step_CMD, Step_PSHELL, Step_Other)
SELECT J.job_id
	, J.name
	, StepCount = (SELECT COUNT(S.step_id) FROM msdb.dbo.sysjobsteps S WHERE S.job_id = J.job_id)
	, ScheduleCount = (SELECT COUNT(Sched.schedule_id) FROM msdb.dbo.sysjobschedules Sched WHERE Sched.job_id = J.job_id)
	, Step_TSQL =  (SELECT COUNT(S.step_id) FROM msdb.dbo.sysjobsteps S WHERE S.job_id = J.job_id AND S.subsystem = 'TSQL')
	, Step_SSIS =  (SELECT COUNT(S.step_id) FROM msdb.dbo.sysjobsteps S WHERE S.job_id = J.job_id AND S.subsystem = 'SSIS')
	, Step_CMD = (SELECT COUNT(S.step_id) FROM msdb.dbo.sysjobsteps S WHERE S.job_id = J.job_id AND S.subsystem = 'CmdExec')
	, Step_PSHELL = (SELECT COUNT(S.step_id) FROM msdb.dbo.sysjobsteps S WHERE S.job_id = J.job_id AND S.subsystem = 'PowerShell')
	, Step_Other =  (SELECT COUNT(S.step_id) FROM msdb.dbo.sysjobsteps S WHERE S.job_id = J.job_id AND NOT(S.subsystem IN ('TSQL', 'SSIS', 'CmdExec', 'PowerShell')))
FROM msdb.dbo.sysjobs J


/**
	Scheduling Data
		- Only schedules that are used.
**/
SELECT S.name AS ScheduleName
	, S.schedule_id AS ScheduleID
	, S.[enabled] AS [Enabled]
	, P.name AS OwnerName
	, S.scheduledescription AS [Description]
FROM @JobSchedules S 
	LEFT OUTER JOIN sys.server_principals P ON P.[sid] = S.owner_sid
WHERE S.schedule_id IN (SELECT JS.schedule_id FROM msdb.dbo.sysjobschedules JS)

/** 
	Job Level Data
**/
SELECT J.name AS JobName
	, J.job_id AS JobID
	, J.[enabled] AS [Enabled]
	, P.name AS JobOwner
	, C.name AS JobCategory
	, JC.ScheduleCount 	
	, ScheduleDescription = REPLACE((
							SELECT STUFF((SELECT '|' + Schedule.scheduledescription
											FROM @JobSchedules Schedule 
												INNER JOIN msdb.dbo.sysjobschedules SJ ON SJ.schedule_id = Schedule.schedule_id
											WHERE SJ.job_id = J.job_id
												AND Schedule.[enabled] = 1
											FOR XML PATH('')), 1,1,'')
							), '|', ' -AND- ')
	, JC.StepCount AS TotalStepCount
	, JC.Step_TSQL 
	, JC.Step_SSIS 
	, JC.Step_PSHELL 
	, JC.Step_CMD
	, JC.Step_Other 
FROM msdb.dbo.sysjobs J
	INNER JOIN @JobCounter JC ON JC.job_id = J.job_id
	LEFT OUTER JOIN sys.server_principals P ON P.[sid] = J.owner_sid
	LEFT OUTER JOIN msdb.dbo.syscategories C ON C.category_id = J.category_id 


/** 
	Step Level Data
**/
SELECT J.name AS JobName
	, J.job_id AS JobID
	, JS.step_id AS StepID
	, StepNumber = CAST(JS.step_id AS VARCHAR(10)) + ' of ' + CAST(JC.StepCount AS VARCHAR(10))
	, JS.step_name AS StepName
	, JS.database_name AS DefaultDatabaseName
	, JS.database_user_name AS DefaultUserName
	, JP.name AS StepProxyName
	, JobStepServer = CASE WHEN ISNULL(JS.[server], @@SERVERNAME) <> @@SERVERNAME THEN JS.[server] ELSE '' END
	, SuccessAction = CASE JS.on_success_action 
						WHEN 1 THEN 'Quit With Success'
                        WHEN 2 THEN 'Quit With Failure'
                        WHEN 3 THEN 'Goto Next Step'
                        WHEN 4 THEN 'Goto Step'
						END
	, JS.on_success_step_id AS SuccessNextStep
	, FailAction = CASE JS.on_fail_action 
						WHEN 1 THEN 'Quit With Success'
                        WHEN 2 THEN 'Quit With Failure'
                        WHEN 3 THEN 'Goto Next Step'
                        WHEN 4 THEN 'Goto Step'
						END
	, JS.on_fail_step_id AS FailNextStep
	, CommandText = REPLACE(REPLACE(REPLACE(SUBSTRING(JS.command, 0, 250), CHAR(10), ' '), CHAR(13), ' '), CHAR(9), ' ') + CASE WHEN LEN(JS.command) > 250 THEN '...' ELSE '' END
FROM msdb.dbo.sysjobsteps JS
	INNER JOIN msdb.dbo.sysjobs J ON J.job_id = JS.job_id
	LEFT OUTER JOIN msdb.dbo.sysproxies JP ON JP.proxy_id = JS.proxy_id
	INNER JOIN @JobCounter JC ON JC.job_id = JS.job_id 
ORDER BY J.name, JS.step_id 




/** 
	All The Data Together!
**/
SELECT  J.name AS JobName
	, J.job_id AS JobID
	, J.[enabled] AS [Enabled]
	, P.name AS JobOwner
	, C.name AS JobCategory
	, JC.ScheduleCount 	
	, ScheduleDescription = REPLACE((
							SELECT STUFF((SELECT '|' + Schedule.scheduledescription
											FROM @JobSchedules Schedule 
												INNER JOIN msdb.dbo.sysjobschedules SJ ON SJ.schedule_id = Schedule.schedule_id
											WHERE SJ.job_id = J.job_id
												AND Schedule.[enabled] = 1
											FOR XML PATH('')), 1,1,'')
							), '|', ' -AND- ')
	, JC.StepCount AS TotalStepCount
	, JS.step_id AS StepID
	, StepNumber = CAST(JS.step_id AS VARCHAR(10)) + ' of ' + CAST(JC.StepCount AS VARCHAR(10))
	, JS.step_name AS StepName
	, JS.database_name AS DefaultDatabaseName
	, JS.on_success_step_id AS SuccessNextStep
	, JS.on_fail_step_id AS FailNextStep
	, CommandText = REPLACE(REPLACE(REPLACE(SUBSTRING(JS.command, 0, 250), CHAR(10), ' '), CHAR(13), ' '), CHAR(9), ' ') + CASE WHEN LEN(JS.command) > 250 THEN '...' ELSE '' END
FROM msdb.dbo.sysjobsteps JS
	INNER JOIN msdb.dbo.sysjobs J ON J.job_id = JS.job_id
	LEFT OUTER JOIN msdb.dbo.sysproxies JP ON JP.proxy_id = JS.proxy_id
	INNER JOIN @JobCounter JC ON JC.job_id = JS.job_id 
	LEFT OUTER JOIN sys.server_principals P ON P.[sid] = J.owner_sid
	LEFT OUTER JOIN msdb.dbo.syscategories C ON C.category_id = J.category_id 
ORDER BY J.name, JS.step_id 


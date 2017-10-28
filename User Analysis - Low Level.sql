/****************
Name: User Analysis 
Author: Dustin Marzolf 

What it does:
To display the individually set permissions for every user in the current database. 




FIX QUERIES:
There are queries at the bottom that help fix : Orphaned Users, Schema Ownership, etc.  

	Usage for these is recommended to target a specific issue such as orphaned users, fix that issue to your
	satisfaction and then run this script again before targeting a second "issue".  




OUTPUT:
	
	#UserPermissions
	- ServerName - the name of the server.
	- DatabaseName - the name of the database 
	- UserName - the name of the user.
	- SID - the SID of the user in question 
	- RoleName - the name of the role.
	- Usertype - the type of user 
	- UserTypeDescription - the description of the user type.
	- DefaultSchema - the users default schema.
	- create_date - the date the user was created.
	- GrantedThroughName - the name of the role that the access was granted through.
	- SchemaName - the schema of the object in question.  NULL or blank typically means it's a database level permission.
	- ObjectName - the name of the object in question.  NULL or blank typically means it's a database level permission.
	- ObjectType - the type of the object in question.
	- PermissionScope - the scope of the permission 
	- Permission_Type - the type of the permission.
	- Permission_TypeName - the type of the permission (in english).
	- Permission_State - the state of the permission 

	#OwnedSchemas
	- ServerName - the name of the server.
	- DatabaseName - the name of the database.
	- SchemaName - the name of the schema.
	- OwnerName - the name of the owner.
	- OwnerSID - the owner's SID
	- OwnerType - the owner user type.
	- OwnerTypeDesc - the owner's type description.
	- ObjectCount - the number of objects that belong to the schema. 

More Information: https://msdn.microsoft.com/en-us/library/ms191291.aspx

********************/

--Table to hold User Permissions
IF(OBJECT_ID('tempdb..#UserPermissions') IS NOT NULL)
BEGIN
	DROP TABLE #UserPermissions 
END

CREATE TABLE #UserPermissions
	(
	ServerName SYSNAME NULL
	, DatabaseName SYSNAME NULL
	, [SID] VARBINARY(85) NULL
	, ServerUserName SYSNAME NULL
	, DatabaseUserName SYSNAME NULL
	, RoleName SYSNAME NULL
	, RoleOwnerName SYSNAME NULL
	, UserType CHAR(1) NULL
	, UserTypeDesc VARCHAR(50) NULL
	, DefaultSchema SYSNAME NULL
	, DateCreated DATETIME2 NULL
	, RoleGrantedThrough SYSNAME NULL
	, SchemaName SYSNAME NULL
	, ObjectName SYSNAME NULL
	, ObjectType VARCHAR(200) NULL
	, PermissionScope VARCHAR(200) NULL
	, PermissionType VARCHAR(10) NULL
	, PermissionTypeName VARCHAR(200) NULL
	, PermissionState VARCHAR(100) NULL
	)

--Table to hold Schema Information...
IF(OBJECT_ID('tempdb..#OwnedSchemas') IS NOT NULL)
BEGIN
	DROP TABLE #OwnedSchemas 
END

CREATE TABLE #OwnedSchemas
	(
	ServerName SYSNAME NULL
	, DatabaseName SYSNAME NULL
	, SchemaName SYSNAME NULL
	, OwnerName SYSNAME NULL
	, OwnerSID VARBINARY(85) NULL
	, OwnerType CHAR(1) NULL
	, OwnerTypeDesc VARCHAR(50) NULL
	, ObjectCount INT NULL
	)

--Server Level Permissions...
;WITH ServerRoles (member_principal_id, role_principal_id, GrantedThrough)
AS
(
SELECT rm1.member_principal_id
	, rm1.role_principal_id
	, NULL AS GrantedThrough
FROM sys.server_role_members rm1 (NOLOCK)
UNION ALL
SELECT P.principal_id
	, NULL
	, NULL
FROM sys.server_principals P (NOLOCK)
UNION ALL
SELECT d.member_principal_id
	, rm.role_principal_id
	, d.role_principal_id AS GrantedThrough
FROM sys.server_role_members rm (NOLOCK)
	INNER JOIN ServerRoles d ON d.role_principal_id = rm.member_principal_id 
)
--Use distinct to get rid of things like public repeating for each user...
INSERT INTO #UserPermissions
SELECT DISTINCT @@SERVERNAME AS ServerName
	, NULL AS DatabaseName
	, UseRolePrincipalrincipal.[sid]
	, UseRolePrincipalrincipal.name AS ServerUserName
	, NULL AS DatabaseUserName
	, RolePrincipal.name AS RoleName
	, RoleOwner.name AS RoleOwnerName
	, UseRolePrincipalrincipal.[type] AS UserType
	, UseRolePrincipalrincipal.type_desc AS UserTypeDesc
	, NULL AS DefaultSchema
	, UseRolePrincipalrincipal.create_date
	, GrantedViaPrincipal.name AS RoleGrantedThrough
	, NULL AS SchemaName
	, NULL AS ObjectName
	, NULL AS ObjectType
	, DBPerm.class_desc AS Permission_Scope
	, DBPerm.[type] AS Permission_Type
	, DBPerm.[permission_name] AS Permission_TypeName
	, DBPerm.state_desc AS Permission_State
FROM ServerRoles drm
	LEFT OUTER JOIN sys.server_principals RolePrincipal ON RolePrincipal.principal_id = drm.role_principal_id
	LEFT OUTER JOIN sys.server_principals UseRolePrincipalrincipal ON UseRolePrincipalrincipal.principal_id = drm.member_principal_id
	LEFT OUTER JOIN sys.server_principals RoleOwner ON RoleOwner.principal_id = RolePrincipal.owning_principal_id
	LEFT OUTER JOIN sys.server_principals GrantedViaPrincipal on GrantedViaPrincipal.principal_id = drm.GrantedThrough 
	LEFT OUTER JOIN sys.server_permissions DBPerm ON DBPerm.grantee_principal_id = CASE WHEN drm.role_principal_id IS NULL THEN drm.member_principal_id ELSE drm.role_principal_id END

DECLARE @DatabaseName SYSNAME
DECLARE @Query NVARCHAR(4000)

DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY
FOR	SELECT D.name
	FROM sys.sysdatabases D
	ORDER BY D.name 

OPEN curDB

FETCH NEXT FROM curDB
INTO @DatabaseName

WHILE @@FETCH_STATUS = 0
BEGIN

	--Get the User Permission Information.
	SET @Query = 'USE ' + QUOTENAME(@DatabaseName)
		+ ' ;WITH RoleMembers (member_principal_id, role_principal_id, GrantedThrough )
			AS
			(
			SELECT rm1.member_principal_id
				, rm1.role_principal_id
				, NULL AS GrantedThrough 
			FROM sys.database_role_members rm1 (NOLOCK)
			UNION ALL
			SELECT P.principal_id
				, NULL
				, NULL AS GrantedThrough
			FROM sys.database_principals P
			UNION ALL
			SELECT d.member_principal_id
				, rm.role_principal_id
				, d.role_principal_id AS GrantedThrough
			FROM sys.database_role_members rm (NOLOCK)
				INNER JOIN RoleMembers d ON d.role_principal_id = rm.member_principal_id
			) 
			--Use distinct to get rid of things like public repeating for each user...
			INSERT INTO #UserPermissions
			SELECT DISTINCT @@SERVERNAME AS ServerName
				, DB_NAME() AS DatabaseName
				, UserPrincipal.[sid]
				, ServerPrincipal.name AS ServerUserName
				, UserPrincipal.name AS DatabaseUserName
				, RolePrincipal.name AS RoleName
				, RoleOwner.name AS RoleOwnerName
				, UserPrincipal.[type] AS UserType
				, UserPrincipal.type_desc AS UserTypeDesc
				, UserPrincipal.default_schema_name AS DefaultSchema
				, UserPrincipal.create_date
				, GrantedViaPrincipal.name AS RoleGrantedThrough
				, S.name AS SchemaName
				, O.name AS ObjectName
				, O.type_desc AS ObjectType
				, DBPerm.class_desc AS Permission_Scope
				, DBPerm.[type] AS Permission_Type
				, DBPerm.[permission_name] AS Permission_TypeName
				, DBPerm.state_desc AS Permission_State
			FROM RoleMembers drm
				LEFT OUTER JOIN sys.database_principals RolePrincipal ON RolePrincipal.principal_id = drm.role_principal_id
				LEFT OUTER JOIN sys.database_principals UserPrincipal ON UserPrincipal.principal_id = drm.member_principal_id
				LEFT OUTER JOIN sys.database_principals GrantedViaPrincipal on GrantedViaPrincipal.principal_id = drm.GrantedThrough 
				LEFT OUTER JOIN sys.database_principals RoleOwner ON RoleOwner.principal_id = RolePrincipal.owning_principal_id
				LEFT OUTER JOIN sys.database_permissions DBPerm ON DBPerm.grantee_principal_id = CASE WHEN drm.role_principal_id IS NULL THEN drm.member_principal_id ELSE drm.role_principal_id END
				LEFT OUTER JOIN sys.objects O ON O.[object_id] = DBPerm.major_id AND DBPerm.class = 1
				LEFT OUTER JOIN sys.schemas S ON (S.[schema_id] = O.[schema_id] AND DBPerm.class = 1) OR (DBPerm.class = 3 AND S.[schema_id] = DBPerm.major_id)
				LEFT OUTER JOIN sys.server_principals ServerPrincipal ON ServerPrincipal.[SID] = UserPrincipal.[SID]'

		EXEC sp_executesql @Query 

		--Get the Schema Information...
		SET @Query = 'USE ' + QUOTENAME(@DatabaseName)
			+ ' INSERT INTO #OwnedSchemas
				SELECT @@SERVERNAME AS ServerName
				, DB_NAME() AS DatabaseName
				, S.name AS SchemaName
				, P.name AS OwnerName
				, P.[SID]
				, P.[type] AS OwnerType
				, P.type_desc AS OwnerTypeDesc
				, COUNT(O.object_id) AS ObjectCount
			FROM sys.schemas S
				LEFT OUTER JOIN sys.objects O ON O.schema_id = S.schema_id
				LEFT OUTER JOIN sys.database_principals P ON P.principal_id = S.principal_id
			GROUP BY S.name
				, P.name 
				, P.[SID]
				, P.[type]
				, P.type_desc'

		EXEC sp_executesql @Query 

		--Loop to the next database.
		FETCH NEXT FROM curDB
		INTO @DatabaseName

END

CLOSE curDB
DEALLOCATE curDB

SELECT * FROM #UserPermissions

SELECT * FROM #OwnedSchemas

/*** Some Useful Queries


--Distinct Permission Types.
SELECT DISTINCT PermissionType, PermissionTypeName
FROM #UserPermissions
ORDER BY PermissionType


--High Privilege Accounts...
--ALTER objects, Impersonate, Control, Create Tables, Reference Objects, Take Ownership or can GRANT to others.
--or members of db_owner, ddladmin , securityadmin, sysadmin on either database or server levels. 
SELECT * 
FROM #UserPermissions
WHERE PermissionType IN ('IM', 'AL', 'CL', 'CRTB', 'RF', 'TO')
	OR PermissionState = 'GRANT_WITH_GRANT_OPTION'
	OR RoleName IN ('db_owner', 'db_ddladmin', 'db_securityadmin', 'sysadmin', 'securityadmin', 'serveradmin')

**/


/*** Generate Fix Scripts.

	The fix scripts below will generate various fix scripts for certain conditions.  
		I.E. - fix users who can grant permissions.


******************************************************************************************************************
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
******************************************************************************************************************

--Fix Schemas owned by orphaned users.
--If the schema has objects, change the owner to dbo.  
--If the schema does not have objects, drop the schema.
;WITH OwnedSchemaFix
AS
(
SELECT OS.*
	, P.name AS ServerUserName
FROM #OwnedSchemas OS
	LEFT OUTER JOIN sys.server_principals P ON P.[sid] = OS.OwnerSID
WHERE OwnerType = 'U'
	AND P.name IS NULL 		
)
SELECT ServerName	
	, DatabaseName
	, SchemaName
	, OwnerName
	, OwnerType
	, FixStatement = CASE	WHEN ObjectCount = 0
								THEN 'USE ' + QUOTENAME(DatabaseName) + '; DROP SCHEMA ' + QUOTENAME(SchemaName)
							WHEN ObjectCount <> 0
								THEN 'USE ' + QUOTENAME(DatabaseName) + '; ALTER AUTHORIZATION ON SCHEMA:: ' + QUOTENAME(SchemaName) + ' TO [dbo]'
							END
FROM OwnedSchemaFix 

******************************************************************************************************************
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
******************************************************************************************************************

--Fix Orphaned Users
--Change owner of schema or drop schema (if no objects).
--Drop the user.
;WITH OrphanedUserFix
AS
(
SELECT DISTINCT U.ServerName
				, U.DatabaseName
				, U.DatabaseUserName
				, U.ServerUserName
				, U.[SID] 
FROM #UserPermissions U
WHERE U.DatabaseName IS NOT NULL --Only want database level accounts.
	AND U.ServerUserName IS NULL --No entry in sys.server_principals.
	AND U.UserType <> 'R' --Ignore roles.
	AND [SID] <> 0x00 --Ignore system generated users.
)
SELECT E.*
FROM	(
		--Drop Schemas First.
		SELECT F.ServerName
			, F.DatabaseName
			, F.DatabaseUserName
			, F.ServerUserName
			, FixStatement = CASE WHEN S.ObjectCount <> 0 THEN 'USE ' + QUOTENAME(F.DatabaseName) + '; ALTER AUTHORIZATION ON SCHEMA:: ' + QUOTENAME(S.SchemaName) + ' TO [dbo];'
									ELSE 'USE ' + QUOTENAME(DatabaseName) + '; DROP SCHEMA ' + QUOTENAME(SchemaName)
			, FixStatementInt = 1
		FROM OrphanedUserFix F
			INNER JOIN #OwnedSchemas S ON S.OwnerSID = F.[SID]
		UNION ALL
		--Drop Users Second.
		SELECT F.ServerName
			, F.DatabaseName
			, F.DatabaseUserName
			, F.ServerUserName
			, FixStatement = 'USE ' + QUOTENAME(F.DatabaseName) + '; DROP USER ' + QUOTENAME(F.DatabaseUserName)
			, FixStatementInt = 2
		FROM OrphanedUserFix F 
		) E
ORDER BY E.DatabaseName, E.DatabaseUserName, E.FixStatementInt, E.FixStatement

******************************************************************************************************************
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
******************************************************************************************************************

--Generate script to fix GRANT_WITH_GRANT_OPTION
--This will revoke all rights for principals to subsequently pass their permissions onto others.  

;WITH GrantFix
AS
(
SELECT *
FROM #UserPermissions
WHERE PermissionState = 'GRANT_WITH_GRANT_OPTION'
	AND RoleName IS NULL
)
SELECT DatabaseName	
	, ServerUserName
	, DatabaseUserName
	, SchemaName
	, ObjectName
	, PermissionType 
	, PermissionTypeName
	, PermissionState 
	, FixStatements = 'USE ' + QUOTENAME(DatabaseName) + '; REVOKE GRANT OPTION FOR ' + PermissionTypeName + ' ON ' + QUOTENAME(SchemaName) + CASE WHEN ObjectName IS NULL THEN '' ELSE ('.' + QUOTENAME(ObjectName)) END + ' TO ' + QUOTENAME(DatabaseUserName) + ' CASCADE AS [dbo];'
FROM GrantFix
WHERE DatabaseName IS NOT NULL  
ORDER BY DatabaseName, ServerUserName, DatabaseUserName, SchemaName, ObjectName, PermissionTypeName

******************************************************************************************************************
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
******************************************************************************************************************

--Generate script to remove all permissions to use REFERENCE.
--REFERENCE allows users to create objects that have FK references to other tables.
;WITH ReferenceFix
AS
(
SELECT *
FROM #UserPermissions
WHERE PermissionType = 'RF'
	AND PermissionState = 'GRANT'
	AND RoleName IS NULL
)
SELECT DatabaseName	
	, ServerUserName
	, DatabaseUserName
	, SchemaName
	, ObjectName
	, PermissionType 
	, PermissionState 
	, FixStatements = 'USE ' + QUOTENAME(DatabaseName) + '; REVOKE ' + PermissionTypeName + ' ON ' + QUOTENAME(SchemaName) + CASE WHEN ObjectName IS NULL THEN '' ELSE ('.' + QUOTENAME(ObjectName)) END + ' TO ' + QUOTENAME(DatabaseUserName) + ' CASCADE AS [dbo];'
FROM ReferenceFix
WHERE DatabaseName IS NOT NULL
	


******************************************************************************************************************
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
******************************************************************************************************************


****/



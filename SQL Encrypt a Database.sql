/** Author: Dustin Marzolf

	Name: Encyrption Configuration
	
	This script will create a master key, a certificate for the server, backup the certificate
	and then create a database key and finally enable encryption.  For reference, the commands
	to prepare a server to support restoring an encrypted database file are included.

	THINGS TO CHANGE:
	* specify a strong password for the master key and backing up the certificate (they should be different).
	*  a server certificate name and subject
	*  a location to save the certificate and key.
	*  the database to be encrypted, the example below uses AdventureWorks2014
	*  you can change the encryption level, options are AES_128, 192 and 256.  Higher levels have more impact

	NOTE: SAVE THE CERTIFICATE AND KEY THAT YOU BACKUP AND KEEP IT SAFE AND AVAILABLE.
		You will NOT be able to restore an encrypted database without it.
		But keep them separate from the backup files themselves.  

*/


USE [master]

--Create Master Key.
--NOTE: select LONG and COMPLEX password.  This is the 'salt'
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<strong password for Master Key>';
GO

--Create Certificate.
CREATE CERTIFICATE CertificateName WITH SUBJECT = '<Certificate Subject Name>';
GO

--Backup Encryption Key
BACKUP CERTIFICATE CertificateName 
TO FILE = '<Path and Name of .CER>'
WITH PRIVATE KEY 
(
	FILE = '<Path and Name of .KEY>'
    , ENCRYPTION BY PASSWORD = '<strong password for backup key>'
);
GO

/** Create Database Key and enable encryption
	NOTE: TempDB is encrypted automatically as long as any database is encyrpted.
*/

USE [AdventureWorks2014]
GO
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_128 ENCRYPTION BY SERVER CERTIFICATE CertificateName;
GO

USE [master]
GO
ALTER DATABASE [AdventureWorks2014]
SET ENCRYPTION ON;


/** To Restore an encrypted database on another server, run the following commands on it.

	NOTE: They are commented out and included here for reference.

	Other than making sure the certificate is present, there is no difference in restoring a database.

*/

/**
USE [master]

--Create Master Key (password can be different)
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<strong password for Master Key>';
GO

--Create certificate from file.
CREATE CERTIFICATE CertificateName
FROM FILE = '<Path and Name of .CER>'
WITH PRIVATE KEY
(
	FILE = '<Path and Name of .KEY>'
	, DECRYPTION BY PASSWORD = '<strong password for backup key>'
);

--Restore database as you normally would.

*/

/**
This query shows the status of databases that are encrypted, so you can see if it's completed.

select 
  database_id as 'Database ID', name as 'Database Name', 
  CASE encryption_state
  WHEN 0 THEN 'No database encryption key present, no encryption'
  WHEN 1 THEN 'Unencrypted'
  WHEN 2 THEN 'Encryption in progress'
  WHEN 3 THEN 'Encrypted'
  WHEN 4 THEN 'Key change in progress'
  WHEN 5 THEN 'Decryption in progress'
  WHEN 6 THEN 'Protection change in progress'
  END as Status
from 
  sys.dm_database_encryption_keys e
join 
  sys.sysdatabases d 
on 
  e.database_id = d.dbid 

*/
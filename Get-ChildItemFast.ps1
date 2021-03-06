

Function Get-ChildItemFast
{

	Param ([string]$Path 
		, [Int32]$MaxThreads = 0
		, [string]$modifieddate
		)
		
	begin {
	
		If($MaxThreads -eq 0)
		{
			$MaxThreads = [int](Get-WmiObject –class Win32_processor | Select-Object -ExpandProperty NumberOfLogicalProcessors)
		}
	
	}
	Process {
	
		$Folders = @()
		$Folders += $Path 
		
		$AllFiles = @()
	
		$Code = {
				Param($FolderPath, $modifiedate)
				
				Write-Output @(Get-ChildItem -LiteralPath $FolderPath | select Mode, Name, FullName, Extension, LastWriteTime, CreationTime, Length)
				}
				
		While($Folders.Count -ne 0)
		{
		
			$RunspacePool = [RunspaceFactory ]::CreateRunspacePool(1, $MaxThreads)
			$RunspacePool.Open()
			
			$Jobs = @()
			
			ForEach ($Folder In $Folders)
			{
				
				$Job = [powershell ]::Create().AddScript($Code).AddArgument($Folder).AddArgument($modifieddate)
				$Job.RunspacePool = $RunspacePool
				$Jobs += New-Object PSObject -Property @{
				   Pipe = $Job
				   Result = $Job.BeginInvoke()
				   }
			
			}
			
			#Sleep, waiting for jobs to complete.
			while($Jobs.Result.IsCompleted -contains $false)
			{
				Start-Sleep -Milliseconds 1
			}
			
			#Collect the return values.
			$ReturnValue = @()
			ForEach($Job In $Jobs)
			{
				$ReturnValue += $Job.Pipe.EndInvoke($Job.Result)
			}
			
			#Get the new list of folders.
			$Folders = @($ReturnValue | Where-Object -FilterScript {$_.Length -eq $null} | Select -ExpandProperty FullName)
			
			$AllFiles += $ReturnValue
		
		}
	
		Write-Output $AllFiles
	
	}

}
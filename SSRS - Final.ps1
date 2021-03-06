function GetRSConnection([string]$server, [string]$instance)
{

	<# GetRSConnection
		Connects to the ReportExecution2005.asmx web endpoint
		for the indicated server and instance name.
		
		.SERVERNAME - The name of the web server that is running the SSRS service.
		
		.INSTANCE - The name of the instance.  Should be ReportServer or ReportServer.  If you are in doubt,
			chekc the SSRS Configuration manager for the exact path to use.  
			
			NOTE: must be the ReportServer, NOT Reports path.
			
	#>
	
	$reportServerURI = "http://" + $server + "/" + $instance + "/ReportExecution2005.asmx?WSDL"
	
	Write-debug "$(Get-Date) Connecting to $($reportServerURI)"

    $RS = New-WebServiceProxy -Class 'RS' -NameSpace 'RS' -Uri $reportServerURI -UseDefaultCredential
    $RS.Url = $reportServerURI
	
	Write-debug "$(Get-Date) Finished Connectinto $($reportServerURI)"
   
	Write-Output $RS
}

function GetReport($RS, [string]$reportPath)
{
    <# GetReport
	
		Gets the report object from the Report Server.  
		
		.RS - The report server execution end point (GetRSConnection)
		
		.REPORTPATH - The path to the report from root.  so <FOLDERNAME>/<FOLDERNAME>.../<REPORTNAME>
		
	#>    
	
	If([string]$reportPath.StartsWith("/") -eq $false)
	{
		$reportPath = "/" + $reportPath
	}
	
	Write-Debug "$(Get-Date) Getting the report $($reportPath)"
	
    $Report = $RS.GetType().GetMethod("LoadReport").Invoke($RS, @($reportPath, $null))
   
	Write-Output  $Report
}

function AddParameter($params, $name, $val)
{

	<#	AddParameter
	
		This is a little weird, just roll with it.  Helps build up an appropriate parameter array to pass
		in with the report.
		
		.PARAMS - The parameter array that you are constructing.
		
		.NAME - The name of the parameter
		
		.VAL - The value of the parameter
		
		.EXAMPLE 
			$ParameterArray = @()
			$ParameterArray = AddParameters -params $ParameterArray -name "ParameterName" -val "ParameterValue"
			$ParameterArray = AddParameters -params $ParameterArray -name "ParameterName2" -val "ParameterValue2"
			
	#>

    $par = New-Object RS.ParameterValue
    $par.Name = $name
    $par.Value = $val
    $params += $par
    Return ,$params
}

function GetReportInFormat
	($RS
	, $report
	, $params = @()
	, $outputpath
	, $outputname = ""
	, [validateset("CSV","EXCEL","PDF","WORD","XML","MHTML","EXCELOPENXML","WORDOPENXML")]$format
	)
{

	<#	Get-ReportInFormat
	
		Renders the indicated report with the indicated settings to a file.  Useful for getting a report
		to XLS or PDF.
		
		.RS - The Report Server Endpoint (GetRSConnection)
		
		.REPORT - The report object (GetReport)
		
		.PARAMS - The parameters to use (AddParameter)
		
		.OUTPUTPATH - The path to output the file to.
		
		.OUTPUTNAME - The name to output the file to.  (If blank, then uses the name of the report).
		
		.FORMAT - The format of the report, must be one of the indicated values.  
			NOTE: for XLSX then use the format of EXCELOPENXML.  
			NOTE: EXCELOPENXML and WORDOPENXML will only work with SSRS 2008R2 and higher
			
	#>

    #   Set up some variables to hold referenced results from Render
    $deviceInfo = "<DeviceInfo><NoHeader>True</NoHeader></DeviceInfo>"
    $extension = ""
    $mimeType = ""
    $encoding = ""
    $warnings = $null
    $streamIDs = $null

    #   Report parameters are handled by creating an array of ParameterValue objects.
    #   Add the parameter array to the service.  Note that this returns some
    #   information about the report that is about to be executed.
    #   $RS.SetExecutionParameters($parameters, "en-us") > $null
	If($params.Count -ne 0)
	{
    	$RS.SetExecutionParameters($params, "en-us") | Out-Null 
	}
	else {
		Write-Debug "$(Get-Date) No Parameters for report"
	}
	
	#Timeout in miliseconds, 10 minutes * 60 seconds * 1000 miliseconds
	$RS.Timeout = (10*60*1000)

    #    Render the report to a byte array.  The first argument is the report format.
    #    The formats I've tested are: PDF, XML, CSV, WORD (.doc), EXCEL (.xls),
    #    IMAGE (.tif), MHTML (.mhtml).
    $RenderOutput = $RS.Render($format,
        $deviceInfo,
        [ref] $extension,
        [ref] $mimeType,
        [ref] $encoding,
        [ref] $warnings,
        [ref] $streamIDs
    )

    #   Determine file name
    $parts = $report.ReportPath.Split("/")
	
	if($outputname -eq "")
	{
    	$outputname = $parts[-1]
	}
	
    switch($format)
    {
        "EXCEL" { $outputname = $outputname + ".xls" } 
        "WORD" { $outputname = $outputname + ".doc" }
        "IMAGE" { $outputname = $outputname + ".tif" }
		"EXCELOPENXML" {$outputname = $outputname + ".xlsx"}
		"WORDOPENXML" {$outputname = $outputname + ".docx"}
        default { $outputname = $outputname + "." + $format }
    }

    if($outputpath.EndsWith("\\"))
    {
        $filename = $outputpath + $outputname
    } else
    {
        $filename = $outputpath + "\" + $outputname
    }

    write-debug $filename

    # Convert array bytes to file and write
    $Stream = New-Object System.IO.FileStream($filename), Create, Write
    $Stream.Write($RenderOutput, 0, $RenderOutput.Length)
    $Stream.Close()
	
	Write-Debug "$(Get-Date) Report written to $($filename)"
	
	Write-Output $filename 
	
}

Function Get-PrinterPort($PrinterName)
{

	<# Get-PrinterPort
	
		Returns the port for the indicated printer.  When using a Generic Text Printer, this will give you the 
		fixed file path that it used when it output the file.
		
		.PRINTERNAME - The name of the printer.
		
	#>

	Write-Output (Get-WmiObject -Class Win32_Printer | Where-Object -FilterScript {$_.Name -eq $PrinterName} | Select-Object -First 1 -ExpandProperty PortName)

}

Function Out-ExcelPrint([string]$filename, [string]$PrinterName)
{

	<# Out-ExcelPrint
	
		Prints an excel workbook to a specified printer.
		
		.FILENAME - The name of the file to print.
		
		.PRINTERNAME - The name of the printer to use.
		
	#>
	
	Write-Debug "$(Get-Date) Printing Document $($filename) to Printer: $($PrinterName)"

	$Excel = New-Object -ComObject "Excel.Application"
	$Excel.Visible = $false
	$Excel.DisplayAlerts = $false
	
	$WB = $Excel.Workbooks.open($filename)
	
	#Delete the File before printing.
	$PrinterFile = Get-PrinterPort -PrinterName $PrinterName
	If((Test-path -LiteralPath $PrinterFile -PathType leaf) -eq $true)
	{
		Remove-Item -Path $PrinterFile -Force -ErrorAction SilentlyContinue | Out-Null
	}
	
	#.Printout https://msdn.microsoft.com/en-us/library/microsoft.office.tools.excel.workbook.printout(v=vs.120).aspx
	# PageStart, PageEnd, Copies, Preview, ActivePrinter, PrintToFile, Collate, PrToFileName
	$WB.PrintOut(1, [System.Type]::Missing, 1, $false, $PrinterName, $false, $false, [System.Type]::Missing)
	
	#Cleanup...
	$WB.Close($false) | Out-Null 
	$Excel.Quit()
	[System.Runtime.Interopservices.Marshal]::ReleaseComObject($Excel) | Out-Null 
	
	Write-Debug "$(Get-Date) Finished Printing"
	
}

Function Format-PrinterFile([string]$PrinterName, [string]$OutputPathName)
{

	<# Format-PrinterFile
	
		Formats the end result of a printer file.  A little trick is to use the Get-PrinterPort
		cmdlet which will return the name of the file it dumped to.
		
		.PRINTERNAME - The name of the printer you used.
		
		.OUTPUTPATHNAME - The final destination you want the formatted file sent to.
		
	#>

	$SourceFile = Get-PrinterPort -PrinterName $PrinterName
	
	If([string]::IsNullOrEmpty($SourceFile) -eq $true)
	{
		Write-Error "Printer $($PrinterName) file port could not be found."
		return
	}
	
	#Output the file.
	# - Removes leading space.
	# - Replaces Form Feeds with a Return and Line Feed (adjusts #HEADERBEGIN following end of CREW)
	# - Replaces Line Feed followed by a space with just a Line Feed (removes extra leading spaces)
	(Get-Content -LiteralPath $SourceFile -Raw) -replace " #HEADINGBEGIN#", "#HEADINGBEGIN#" -replace "`f", "`r`n" -replace "`n ", "`n" | Set-Content -LiteralPath $OutputPathName

}

<# Generate the SSRS Report #>

#Get RS Report Server Endpoint.
$RS = GetRSConnection -server "STL-L638" -instance "ReportServer_JDF2012"

#Get Report Information...
$report = GetReport -RS $RS -reportPath "TestProject/Columns"

#Build up the parameters...
$params = @()
$params = AddParameter -params $params -name "ParamColumnName" -val "Value"

#Generate the report and save it...
$FileName = GetReportInformat -RS $RS -report $report -params $params -outputpath "c:\temp" -outputname "test" -format "EXCELOPENXML"

#Now Print the document...
$PrinterName = "TextOut"

Out-ExcelPrint -FileName $filename -PrinterName $PrinterName

#Define where the report should actually go...
$OutputFileName = "C:\temp\realoutput.txt"

#Format the generated file and send it onwards.
Format-PrinterFile -PrinterName $PrinterName -OutputPath $OutputFileName




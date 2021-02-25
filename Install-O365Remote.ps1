#Get computers to install office on
#$Computers = (Get-ADComputer -Filter * -SearchBase "OU=Workstations,OU=NCIDemo,DC=prod,DC=ncidemo,DC=com").Name
#$Computers = "A013472"
$Computers = Get-Content "C:\nci\NoConnection-3Jan20.txt"
$SourceDir = "Microsoft.PowerShell.Core\FileSystem::\\tcm422\data\apps\O365"
$365LogDir = "Microsoft.PowerShell.Core\FileSystem::\\tcm422\data\apps\365Logs"
$NoConnection = @()
ForEach ($Computer in $Computers)
{
$DestDir = "Microsoft.PowerShell.Core\FileSystem::\\$computer\c$\TCICT\O365"
	Write-Host "Testing access to $Computer" -ForegroundColor White
	$HostUp = Test-Path -Path (Split-Path (Split-Path $DestDir)) -ErrorAction SilentlyContinue
    #$HostUp = Test-Connection -ComputerName $Computer -BufferSize 12 -Count 1 -ErrorAction SilentlyContinue
	If (!($HostUp))
	{
		Write-Warning -Message "Remote Host: $Computer is not accessible!"
        $NoConnection += $Computer
	}
	Else
	{
		Write-Host "Success!" -ForegroundColor Green
		$items = Get-Item -Path "$SourceDir\*"
        If (!(Test-Path "$DestDir")){
            Write-Host "Creating O365 Source folder on $Computer" -ForegroundColor Yellow
            New-Item -Path "$DestDir" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        }
		foreach ($item in $items)
		{
			If (!(Test-Path ($DestDir + "\" + $item.Name))){
                Write-Host "Copying $Item over to $Computer" -ForegroundColor Yellow
                Copy-Item -Path $item.PsPath -Destination $DestDir -Force -Recurse -Verbose
            }
		}
		If (Test-Path "$DestDir\Setup.exe"){
            Write-Host "Starting setup on $Computer" -ForegroundColor White
            Invoke-Command -ScriptBlock {
                If (!(Test-Path "${ENV:ProgramFiles(x86)}\Microsoft Office\root\Office16\Outlook.EXE")){
                    #Start-Process powershell.exe -ArgumentList ".\Remove-PreviousOfficeInstalls.ps1" -WorkingDirectory "C:\TCICT\O365\RemovePreviousOfficeInstalls" -Wait
                    Set-ExecutionPolicy Unrestricted -Force;
                    #Clean up existing Office Install
                    Set-Location -Path "C:\TCICT\O365\RemovePreviousOfficeInstalls"; .\Remove-PreviousOfficeInstalls.ps1;
                    # Install Office 365
                    Start-Process setup.exe -ArgumentList "/configure TC.xml" -WorkingDirectory "C:\TCICT\O365" -Wait
                    }
                    #Create Outlook Icon
                    $oTargetFile = "${ENV:ProgramFiles(x86)}\Microsoft Office\root\Office16\Outlook.EXE"
                    $oShortcutFile = "$env:Public\Desktop\Outlook 365.lnk"                    
                    If ((Test-Path $oTargetFile) -and (!(Test-Path $oShortcutFile))){
                        $oWScriptShell = New-Object -ComObject WScript.Shell
                        $oShortcut = $oWScriptShell.CreateShortcut($oShortcutFile)
                        $oShortcut.TargetPath = $oTargetFile
                        $oShortcut.Save()
                        }
                    #Create Excel Icon
                    $eTargetFile = "${ENV:ProgramFiles(x86)}\Microsoft Office\root\Office16\Excel.EXE"
                    $eShortcutFile = "$env:Public\Desktop\Excel 365.lnk"                    
                    If ((Test-Path $eTargetFile) -and (!(Test-Path $eShortcutFile))){
                        $eWScriptShell = New-Object -ComObject WScript.Shell
                        $eShortcut = $eWScriptShell.CreateShortcut($eShortcutFile)
                        $eShortcut.TargetPath = $eTargetFile
                        $eShortcut.Save()
                        }
                    #Create Word Icon
                    $wTargetFile = "${ENV:ProgramFiles(x86)}\Microsoft Office\root\Office16\WinWord.EXE"
                    $wShortcutFile = "$env:Public\Desktop\Word 365.lnk"                    
                    If ((Test-Path $wTargetFile) -and (!(Test-Path $wShortcutFile))){
                        $wWScriptShell = New-Object -ComObject WScript.Shell
                        $wShortcut = $wWScriptShell.CreateShortcut($wShortcutFile)
                        $wShortcut.TargetPath = $wTargetFile
                        $wShortcut.Save()
                    }
                } -ComputerName $Computer -AsJob -Verbose
            }
	    }
}
While ((Get-Job).State -eq 'Running'){
    Get-Job | ? {$_.State -ne 'Completed'} | `
    Select Location,Id,State,HasMoreData,PSBeginTime,PSEndTime,@{label='Duration';expression={[INT]((Get-Date).TimeOfDay - $_.PSBeginTime.TimeOfDay).TotalMinutes}} | `
    Format-Table -AutoSize;
    Write-Host "["(Get-date).DateTime"] Jobs Still Running....Checking for status in 3 min" -ForegroundColor Magenta;
    Start-Sleep -Seconds 180;
}
#Export Jobs Report
Get-Job | `
Select Location,Id,State,HasMoreData,PSBeginTime,PSEndTime,@{label='Duration';expression={[INT]($_.PSEndTime.TimeOfDay - $_.PSBeginTime.TimeOfDay).TotalMinutes}} | `
Export-Csv "c:\nci\O365-Install-JobReport-$((Get-Date).ToString("yyyyMMdd_HHmmss")).csv" -NoTypeInformation -Verbose

#Attempt to copy log files
Foreach ($Computer in $Computers){
$DestDir = "Microsoft.PowerShell.Core\FileSystem::\\$computer\c$\TCICT\O365"
    $365LogFiles = gci $DestDir -Filter "*.log"
    If ($365LogFiles) {
        Foreach ($LogFile in $365LogFiles)
        {
            If (!(Test-Path ($365LogDir + "\" + $LogFile.Name))){
            Copy-Item $LogFile.PSPath -Destination $365LogDir -Force -Verbose
            }
        }
    }
}
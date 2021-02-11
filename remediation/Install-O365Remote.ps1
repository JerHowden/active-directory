#Get computers to install office on
#$Computers = (Get-ADComputer -Filter * -SearchBase "OU=Workstations,OU=NCIDemo,DC=prod,DC=ncidemo,DC=com").Name
$Computers = "CL01"
ForEach ($Computer in $Computers)
{
	Write-Host "Working on $Computer" -ForegroundColor White
	
	Write-Host "Testing access to $Computer" -ForegroundColor White
	$HostUp = Test-Connection -ComputerName $Computer -BufferSize 12 -Count 1 -ErrorAction SilentlyContinue
	If (!($HostUp))
	{
		Write-Warning -Message "Remote Host is not accessible!"	}
	Else
	{
		Write-Host "Success!" -ForegroundColor Green
		$items = Get-Item -Path "Microsoft.PowerShell.Core\FileSystem::\\DC01\O365\*"
		Write-Host "Creating O365 Source folder on $Computer" -ForegroundColor Yellow
        If (!(Test-Path "Microsoft.PowerShell.Core\FileSystem::\\$computer\c$\O365")){
            New-Item -Path "Microsoft.PowerShell.Core\FileSystem::\\$computer\c$\O365" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        }
        $I = 0
		foreach ($item in $items)
		{
            Write-Progress -Activity "Copying Office 365 Source Files" -Status "Progress:" -PercentComplete ($i/$items.count*100)
			Write-Host "Copying $Item over to $Computer\c$\O365\" -ForegroundColor Yellow
			Copy-Item -Path "Microsoft.PowerShell.Core\FileSystem::$item" -Destination "Microsoft.PowerShell.Core\FileSystem::\\$computer\c$\O365" -Force -Recurse -Verbose
            $I++
		}
		If (Test-Path "Microsoft.PowerShell.Core\FileSystem::\\$computer\c$\O365\Setup.exe"){
            Write-Host "Starting setup on $Computer" -ForegroundColor White
		    C:\tmp\PsExec64.exe \\$Computer cmd /c "C:\O365\setup.exe /configure C:\O365\Configuration2.xml"
            #Invoke-Command -ScriptBlock { set-location "C:\O365\"; .\setup.exe /configure configuration.xml } -ComputerName $Computer -AsJob
        }
	}
}
#Get-Job | Format-Table
$ErrorActionPreference = "STOP"
iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
choco install git -y
$Env:Path+=";${env:ProgramFiles(x86)}\git\bin"
$psdir = [System.IO.PAth]::GetFullPAth("$PROFILE\..")
$filecount=(gci $psdir -Recurse).Count

if (Test-Path $psdir)
{
  Write-host ""
  Write-host ""
  Write-Warning "this script is about to destory your powershell profile folder."
  Write-warning "This menas that the following location will be deleted: $psdir"
  if ($fileCount -gt 1)
  {
    Write-host "You have $filecount files in this location already, they will all be deleted if you continue!!!" -ForegroundColor red
  }

  Write-host ""
  Write-host "Press enter to continue (ctrl-c to abort)"
  Read-Host
  
  rmdir $psdir -force
}

cd $psdir
git clone https://github.com/lars36s/PowerShell.git WindowsPowerShell
. .\Configure-Choco.ps1
. .\Install-Tools.ps1
. .\Configure-Git.ps1


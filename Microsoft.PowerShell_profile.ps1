function Get-ParentProcessChain ([System.Diagnostics.Process]$Process = [System.Diagnostics.Process]::GetCurrentProcess())
{    
    $ParentProcessId = (gwmi win32_process -Filter "processid='$($Process.Id)'" -ErrorAction SilentlyContinue).parentprocessid
    if ($ParentProcessId)
    {
        $ParentProcess = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
        if ($ParentProcess)
        {
            Write-Output $ParentProcess
            Get-ParentProcessChain $ParentProcess       
        }
    }       
}
function Should-SkipProfile()
{
    $ProcessesNotToLoadInto = @("msbuild", "mstest", "devenv") #wmiprvse.exe
    $Parents = Get-ParentProcessChain
    foreach ($Parent in $Parents)
    {
        if ($Parent.ProcessName.ToLower() -eq "wmiprvse.exe")
        {
            $Parent | fl -Force | Out-File -Append -FilePath C:\profillog.txt             
            [Environment]::FailFast('ohh no you dont!')
        }
        if ($ProcessesNotToLoadInto -contains $Parent.ProcessName.ToLower())
        {
            Write-Host "Found $($Parent.ProcessName) in the Parent Process Chain, Skipping Profile Load!"    
            return $true
        }
    }
    return $false
}
if (Should-SkipProfile)
{
    return
}
function Get-ParentProcessName
{
    $CurrentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $ParentProcessId = (gwmi win32_process -Filter "processid='$($CurrentProcess.Id)'").parentprocessid
    $ParrentProcess = Get-Process -Id $ParentProcessId
    $ParrentProcess.Name
}


Function Invoke-Environment
(
    [Parameter(Mandatory=$true)] [string]
    # Any cmd shell command, normally a configuration batch file.
    $Command
)
{
  cmd /c """$Command"" > nul 2>&1 && set" | .{process{
      if ($_ -match '^([^=]+)=(.*)') {
          [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
      }
  }}
  if ($LASTEXITCODE) {
      throw "Command '$Command': exit code: $LASTEXITCODE"
  }
}
function Connect-RemoteDesktop {
<#   
.SYNOPSIS   
Function to connect an RDP session without the password prompt
.DESCRIPTION 
This function provides the functionality to start an RDP session without having to type in the password
.PARAMETER ComputerName
This can be a single computername or an array of computers to which RDP session will be opened
.PARAMETER User
The user name that will be used to authenticate
.PARAMETER Password
The password that will be used to authenticate
.PARAMETER Credential
The PowerShell credential object that will be used to authenticate against the remote system
.PARAMETER Admin
Sets the /admin switch on the mstsc command: Connects you to the session for administering a server
.PARAMETER MultiMon
Sets the /multimon switch on the mstsc command: Configures the Remote Desktop Services session monitor layout to be identical to the current client-side configuration 
.PARAMETER FullScreen
Sets the /f switch on the mstsc command: Starts Remote Desktop in full-screen mode
.PARAMETER Public
Sets the /public switch on the mstsc command: Runs Remote Desktop in public mode
.PARAMETER Width
Sets the /w:<width> parameter on the mstsc command: Specifies the width of the Remote Desktop window
.PARAMETER Height
Sets the /h:<height> parameter on the mstsc command: Specifies the height of the Remote Desktop window
.EXAMPLE   
Connect-RemoteDesktop -ComputerName server01 -User contoso\jaapbrasser -Password supersecretpw
Description 
-----------     
A remote desktop session to server01 will be created using the credentials of contoso\jaapbrasser
.EXAMPLE   
Connect-RemoteDesktop server01,server02 contoso\jaapbrasser supersecretpw
Description 
-----------     
Two RDP sessions to server01 and server02 will be created using the credentials of contoso\jaapbrasser
.EXAMPLE   
server01,server02 | Connect-RemoteDesktop -User contoso\jaapbrasser -Password supersecretpw -Width 1280 -Height 720
Description 
-----------     
Two RDP sessions to server01 and server02 will be created using the credentials of contoso\jaapbrasser and both session will be at a resolution of 1280x720.
.EXAMPLE   
Connect-RemoteDesktop -ComputerName server01:3389 -User contoso\jaapbrasser -Password supersecretpw -Admin -MultiMon
Description 
-----------     
A RDP session to server01 at port 3389 will be created using the credentials of contoso\jaapbrasser and the /admin and /multimon switches will be set for mstsc
.EXAMPLE   
Connect-RemoteDesktop -ComputerName server01:3389 -User contoso\jaapbrasser -Password supersecretpw -Public
Description 
-----------     
A RDP session to server01 at port 3389 will be created using the credentials of contoso\jaapbrasser and the /public switches will be set for mstsc
.EXAMPLE
Connect-RemoteDesktop -ComputerName 192.168.1.10 -Credential $Cred
Description 
-----------     
A RDP session to the system at 192.168.1.10 will be created using the credentials stored in the $cred variable.
.EXAMPLE   
Get-AzureVM | Get-AzureEndPoint -Name 'Remote Desktop' | ForEach-Object { Connect-RemoteDesktop -ComputerName ($_.Vip,$_.Port -join ':') -User contoso\jaapbrasser -Password supersecretpw }
Description 
-----------     
A RDP session is started for each Azure Virtual Machine with the user contoso\jaapbrasser and password supersecretpw
.EXAMPLE
PowerShell.exe -Command "& {. .\Connect-RemoteDesktop.ps1; Connect-RemoteDesktop server01 contoso\jaapbrasser supersecretpw -Admin}"
Description
-----------
An remote desktop session to server01 will be created using the credentials of contoso\jaapbrasser connecting to the administrative session, this example can be used when scheduling tasks or for batch files.
#>
    [cmdletbinding(SupportsShouldProcess,DefaultParametersetName="UserPassword")]
    param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=0)]
        [Alias("CN")]
            [string[]]$ComputerName,
        [Parameter(ParameterSetName="UserPassword",Mandatory=$true,Position=1)]
        [Alias("U")] 
            [string]$User,
        [Parameter(ParameterSetName="UserPassword",Mandatory=$true,Position=2)]
        [Alias("P")] 
            [string]$Password,
        [Parameter(ParameterSetName="Credential",Mandatory=$true,Position=1)]
        [Alias("C")]
            [PSCredential]$Credential,
        [Alias("A")]
            [switch]$Admin,
        [Alias("MM")]
            [switch]$MultiMon,
        [Alias("F")]
            [switch]$FullScreen,
        [Alias("Pu")]
            [switch]$Public,
        [Alias("W")]
            [int]$Width,
        [Alias("H")]
            [int]$Height
    )
    begin {
        [string]$MstscArguments = ''
        switch ($true) {
            {$Admin} {$MstscArguments += '/admin '}
            {$MultiMon} {$MstscArguments += '/multimon '}
            {$FullScreen} {$MstscArguments += '/f '}
            {$Public} {$MstscArguments += '/public '}
            {$Width} {$MstscArguments += "/w:$Width "}
            {$Height} {$MstscArguments += "/h:$Height "}
        }
        if ($Credential) {
            $User = $Credential.UserName
            $Password = $Credential.GetNetworkCredential().Password
        }
    }
    process {
        foreach ($Computer in $ComputerName) {
            $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
            $Process = New-Object System.Diagnostics.Process
            # Remove the port number for CmdKey otherwise credentials are not entered correctly
            if ($Computer.Contains(':')) {
                $ComputerCmdkey = ($Computer -split ':')[0]
            } else {
                $ComputerCmdkey = $Computer
            }
            $ProcessInfo.FileName = "$($env:SystemRoot)\system32\cmdkey.exe"
            $ProcessInfo.Arguments = "/generic:TERMSRV/$ComputerCmdkey /user:$User /pass:$Password"
            $ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            $Process.StartInfo = $ProcessInfo
            if ($PSCmdlet.ShouldProcess($ComputerCmdkey,'Adding credentials to store')) {
                [void]$Process.Start()
            }
            $ProcessInfo.FileName = "$($env:SystemRoot)\system32\mstsc.exe"
            $ProcessInfo.Arguments = "$MstscArguments /v $Computer"
            $ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
            $Process.StartInfo = $ProcessInfo
            if ($PSCmdlet.ShouldProcess($Computer,'Connecting mstsc')) {
                [void]$Process.Start()
            }
        }
    }
}

function Get-WorkPassword {
    param(
        [Parameter(Mandatory=$true)]        
        $AccountName
    )
    if (!$ENV:SecrectShare)
    {
        throw "The environment varable 'SecrectShare' is not set."
    }

    get-content "$ENV:SecrectShare\$AccountName.txt"
}

function Connect-RemoteDesktopWithWorkAccount {
    param (
        [Parameter(Mandatory=$true,         
            Position=0)]
        [Alias("CN")]
        $ComputerName,
        [Parameter(Mandatory=$true,         
            Position=1)]
        $AccountName,
        [Switch]$MultiMon)    
        Connect-RemoteDesktop -User $AccountName -Password (Get-WorkPassword $AccountName)  -ComputerName $ComputerName -MultiMon:$MultiMon
}

function Connect-RemoteDesktopWithStoredCreds {
    param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=0)]
        [Alias("CN")]
            [string[]]$ComputerName,
        [Switch]$MultiMon)
    BEGIN {
        if (-not $global:GCredentials) {$global:GCredentials = Get-Credential -Message "Please login" -UserName "$env:USERDOMAIN\$env:USERNAME"}
    }
    PROCESS {
        Connect-RemoteDesktop -Credential $global:GCredentials -ComputerName $ComputerName -MultiMon:$MultiMon
    }
    END{
    }
}

$Accounts = 'ntf-serv','MyUser','HelloCanYouHearMe'

function Connect-RemoteDesktopSmart{
        param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=0)]
        [Alias("CN")]
            [string[]]$ComputerName,
        [Switch]$MultiMon,
        [ValidateSet('Bla')]
        $Account)
BEGIN {
    $AccountMap = (Import-Csv $ENV:Home\MachineAccountMap.dat | %{ @{ $_.Name = $_.Value}})
}
PROCESS{
    
    if ($account)
    {
        $UserName = $Account
    }
    else
    {
        $UserName = $AccountMap.$ComputerName
    }
    if (!$UserName)
    {
        Connect-RemoteDesktopWithStoredCreds -ComputerName $ComputerName -MultiMon:$MultiMon
    }
    else {
        Connect-RemoteDesktopWithWorkAccount -ComputerName $ComputerName -AccountName $UserName -MultiMon:$MultiMon
    }
}

}

function Update-ValidateSet {
  [CmdletBinding(SupportsShouldProcess=$true)]
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.FunctionInfo]$Command,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$ParameterName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String[]]$NewSet
  )

  #Find the parameter on the command object
  $Parameter = $Command.Parameters[$ParameterName]
  if($Parameter) {
    #Find all of the ValidateSet attributes on the parameter
    $ValidateSetAttributes = @($Parameter.Attributes | Where-Object {$_ -is [System.Management.Automation.ValidateSetAttribute]})
    if($ValidateSetAttributes) {
      $ValidateSetAttributes | ForEach-Object {
        #Get the validValues private member of the ValidateSetAttribute class
        $ValidValuesField = [System.Management.Automation.ValidateSetAttribute].GetField("validValues", [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
        if($PsCmdlet.ShouldProcess("$Command -$ParameterName", "Set valid set to: $($NewSet -join ', ')")) {
          #Update the validValues array on each instance of ValidateSetAttribute
          $ValidValuesField.SetValue($_, $NewSet)
        }
      }
    } else {
      Write-Error -Message "Parameter $ParameterName in command $Command doesn't use [ValidateSet()]"
    }
  } else {
    Write-Error -Message "Parameter $ParameterName was not found in command $Command"
  }
}

Update-ValidateSet -Command (Get-Command Connect-RemoteDesktopSmart) -ParameterName "Account" -NewSet ((Import-Csv $ENV:Home\MachineAccountMap.dat | %{ @{ $_.Name = $_.Value}}).Values | select -Unique)

function Open-Solution
{
  $solution = gci *.sln -Recurse | Select-Object -First 1
  devenv $solution
}

function Find-InFiles ($pattern, $filter = "*.*")
{
    Get-ChildItem -include $filter  -recurse | Select-String -pattern $pattern | select Path,LineNumber,Line
}

function Configure-Aliases
{
    New-Alias fif Find-InFiles -Option AllScope -ErrorAction SilentlyContinue -Scope "global"
    New-Alias msdev Open-Solution -Option AllScope -ErrorAction SilentlyContinue -Scope "global"
    New-Alias -name SourceTree "C:\Program Files (x86)\Atlassian\SourceTree\SourceTree.exe" -Option AllScope  -Scope "global"
    New-Alias -name RDP Connect-RemoteDesktopSmart -Option AllScope -Scope "global"
}

function Configure-Paths
{
    $Env:Path+=";$Env:ProgramData\chocolatey\lib\sysinternals\tools\"
    $Env:Path+=";${env:ProgramFiles(x86)}\git\bin"
}

function Write-Status ($status)
{
    Write-host " - $status..." -NoNewLine -ForegroundColor Yellow
}

function Complete-LastStatus
{
    Write-host "Done!" -ForegroundColor Green
}

Add-Type -TypeDefinition @"
   public enum Enlistments
   {
      Main,
      Nav8
   }
"@
function Start-Enlistment {
    param ( [Enlistments]$enlistment)
    switch ($enlistment)
    {
        "Main" { goto Main Push-Location; continue } 
        "Nav8" {Push-Location "$profile\.."; continue }         
    }
    . .\eng\Core\Enlistment\start.ps1 -SkipSetup -IncludeOperations
}
Write-host "Starting PowerShell Profile for " -NoNewLine
Write-host "$env:USERNAME" -ForegroundColor Green
Write-Status "Configuring Paths and Aliases"
New-Alias startenlist Start-Enlistment
Import-Module "$PSScriptRoot\goto.psm1"
Configure-Aliases
Configure-Paths
Write-host "Done!" -ForegroundColor Green
Write-host " - Starting VS CMD Environment..." -NoNewLine -ForegroundColor Yellow
$VsEnvironment = gci Env:\VS*ComnTools  | select -First 1

if (!$VsEnvironment)
{
   Write-Warning "Could not find any installed Versions of Visual Studio"  
}
else {
    Invoke-Environment (join-path $VsEnvironment.Value "vsvars32.bat")
    Complete-LastStatus    
}

Write-host " - Starting posh-git..." -NoNewLine -ForegroundColor Yellow

if(Test-Path Function:\Prompt) {Rename-Item Function:\Prompt PrePoshGitPrompt -Force}
. 'C:\tools\poshgit\dahlbyk-posh-git-5ed5c05\profile.example.ps1'
Rename-Item Function:\Prompt PoshGitPrompt -Force

function Prompt() {if(Test-Path Function:\PrePoshGitPrompt){++$global:poshScope; New-Item function:\script:Write-host -value "param([object] `$object, `$backgroundColor, `$foregroundColor, [switch] `$nonewline) " -Force | Out-Null;$private:p = PrePoshGitPrompt; if(--$global:poshScope -eq 0) {Remove-Item function:\Write-Host -Force}}PoshGitPrompt}
Write-host "Done!" -ForegroundColor Green
Write-Host ""
# Chocolatey profile
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}

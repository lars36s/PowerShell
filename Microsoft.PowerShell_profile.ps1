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

New-Alias startenlist Start-Enlistment

Write-host "Starting PowerShell Profile for " -NoNewLine
Write-host "$env:USERNAME" -ForegroundColor Green

Import-Module "$PSScriptRoot\goto.psm1"

Write-Status "Configuring Paths and Aliases"

Configure-Aliases
Configure-Paths
Write-host "Done!" -ForegroundColor Green

Write-host " - Starting VS CMD Environment..." -NoNewLine -ForegroundColor Yellow
Invoke-Environment (join-path $env:VS120COMNTOOLS "vsvars32.bat")
Complete-LastStatus

Write-host " - Starting posh-git..." -NoNewLine -ForegroundColor Yellow


if(Test-Path Function:\Prompt) {Rename-Item Function:\Prompt PrePoshGitPrompt -Force}
. 'C:\tools\poshgit\dahlbyk-posh-git-7acc70b\profile.example.ps1'
Rename-Item Function:\Prompt PoshGitPrompt -Force
function Prompt() {if(Test-Path Function:\PrePoshGitPrompt){++$global:poshScope; New-Item function:\script:Write-host -value "param([object] `$object, `$backgroundColor, `$foregroundColor, [switch] `$nonewline) " -Force | Out-Null;$private:p = PrePoshGitPrompt; if(--$global:poshScope -eq 0) {Remove-Item function:\Write-Host -Force}}PoshGitPrompt}

Write-host "Done!" -ForegroundColor Green
Write-Host ""

cd $env:USERPROFILE

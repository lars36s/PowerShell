. "$Env:INETROOT\Eng\Core\Helpers\TestHarness-NavTest.ps1"
. $Env:INETROOT\Eng\Core\Func\EnlistmentEvent.ps1

function NewTestSuite
(
    [Parameter(Position=0)]
    [string] $SuiteName,
    [string] $GroupName,
    [string] $AssemblyPath = $null,
    [string] $TestSettingsPath = $null,
    [string] $ProjectFilePath = $null,
    [string] $ProjectPlatform,
    [bool] $RestoreDatabase = $false,
    [bool] $UseVsTestConsole = $true,
    [bool] $DeployPlatformUnitTestObjects = $false,
    [bool] $RerunFailures = $true
)
{
    $Suite = new-object PSObject
    $Suite | add-member -type NoteProperty -Name SuiteName -Value $SuiteName
    $Suite | add-member -type NoteProperty -Name GroupName -Value $GroupName
    $Suite | add-member -type NoteProperty -Name AssemblyPath -Value $AssemblyPath
    $Suite | add-member -type NoteProperty -Name TestSettingsPath -Value $TestSettingsPath
    $Suite | add-member -type NoteProperty -Name ProjectFilePath -Value $ProjectFilePath
    $Suite | add-member -type NoteProperty -Name ProjectPlatform -Value $ProjectPlatform
    $Suite | add-member -type NoteProperty -Name RestoreDatabase -Value $RestoreDatabase
    $Suite | add-member -type NoteProperty -Name UseVsTestConsole -Value $UseVsTestConsole
    $Suite | add-member -type NoteProperty -Name DeployPlatformUnitTestObjects -Value $DeployPlatformUnitTestObjects
    $Suite | add-member -type NoteProperty -Name RerunFailures -Value $RerunFailures
    return $Suite
}

function GetTestSuitesFromJson
(
    [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
    [string] $FileName
)
{
    Begin
    {
        $JsonSuites = @() 
    }
    Process
    {
        $MetaDataFile = $_
        $GroupName =  Get-Item $MetaDataFile | select -ExpandProperty BaseName

        (Get-Content $MetaDataFile | Out-String | ConvertFrom-Json) | %{
          $Json = $_
          $AssemblyPath =  $ExecutionContext.InvokeCommand.ExpandString($Json.AssemblyPath).Trim()
          $TestSettingsPath = $ExecutionContext.InvokeCommand.ExpandString($Json.TestSettingsPath).Trim()
          $ProjectFilePath = $ExecutionContext.InvokeCommand.ExpandString($Json.ProjectFilePath).Trim()
          $ProjectPlatform = $Json.ProjectPlatform
          if ($ProjectPlatform -eq $null)
          {
              $ProjectPlatform = "AnyCPU"
          }

          $RestoreDatabase = $Json.RestoreDatabase -eq $true
          $UseVsTestConsole = $Json.UseVsTestConsole -ne $false
          $DeployPlatformUnitTestObjects = $Json.DeployPlatformUnitTestObjects -eq $true
          $RerunFailures = $Json.RerunFailures -ne $false

          $JsonSuites += NewTestSuite -SuiteName $Json.SuiteName -GroupName $GroupName `
                -AssemblyPath $AssemblyPath -TestSettingsPath $TestSettingsPath  -ProjectFilePath $ProjectFilePath -ProjectPlatform $ProjectPlatform `
                -RestoreDatabase $RestoreDatabase -UseVsTestConsole $UseVsTestConsole -DeployPlatformUnitTestObjects $DeployPlatformUnitTestObjects -RerunFailures $RerunFailures
        }
    }
    End
    {
        return $JsonSuites
    }

}

function GetTestSuitesMetaDataFiles
(
  [string] $Group = $null
)
{
  if ($Group)
  {
    $MetaDataFile = "$env:INETROOT\eng\core\lib\testmetadata\$Group.json"
    
    if(!(Test-Path -Path $MetaDataFile))
    {
        throw "$Group is not a known group that has test metadata."
    }

    return $MetaDataFile
  }

  return (gci $env:INETROOT\eng\core\lib\testmetadata\*.json) | Select -ExpandProperty FullName
}

<#
.SYNOPSIS
Gets the list of legacy test suites
.DESCRIPTION
Parses the unittests.txt file into Test Suite objects that can be piped to Run-NavTestSuites
#>
function Get-NavPlatformTestSuites
(
    [string] $Group = $null
)
{
    $MetaDataFiles = GetTestSuitesMetaDataFiles -Group $Group
    return $MetaDataFiles | GetTestSuitesFromJson 
}

<#
.SYNOPSIS
Gets the list of true unit test suites
.DESCRIPTION
Finds all unit test projects that can be executed without building anything
#>
function Get-NavUnitTestSuites()
{
    return (Get-NavPlatformTestSuites -Group "unittests") + (Get-NavPlatformTestSuites -Group "unittests2")
}

<#
.SYNOPSIS
Filters NavTestSuites to group
.DESCRIPTION
Filters a list of NavTestSuite objects to a specific group
#>
function Filter-NavTestSuites
(
    # Specifies which suite(s) to run
    [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
    [PSObject[]] $Suite,
    [string] $Group = $null,
    [string] $SuiteName = $null
)
{
    Process {
          $_ | ? { $_.GroupName -eq $Group -or $_.SuiteName -eq $SuiteName}
    }
}

<#
.SYNOPSIS
Finds a test project file
.DESCRIPTION
Searches for a test project file by the name $SuiteName.csproj or $SuiteName.vcxproj under the specified search paths
#>
function Find-NavTestSuiteProjectFile
(
    [string] $SuiteName,
    [string[]] $SearchPath
)
{
    (gci -Recurse -Path $SearchPath -Include "*$SuiteName.csproj", "*$SuiteName.vcxproj" -File) | select -First 1
}

function BuildNavTestSuite(
  [Parameter(ValueFromPipeline=$true)]
  $TestSuite,
  [string] $Platform,
  [switch] $BuildCop
)
{
Begin
{
    . $env:inetroot\Eng\Core\Func\GenerateNavSolutionFile.ps1
    $AutoSolutionName = "$env:inetroot\Logs\AutoSolution$Platform.sln"

    $projs = @()
}
Process
{
    $projs += $TestSuite.ProjectFilePath
}
End
{
    Write-Log "Building $($projs -join ", ")"
    $slns = $projs | Generate-VsSolutionFile -SolutionFile $AutoSolutionName -Configuration Debug -Platform $Platform
    $slns | Build -Configuration Debug -Platform $Platform -Verbosity quiet -BuildCop:$BuildCop -CustomOptions "/m"
}
}

function GetNavTestSuiteObject
(
    [string] $SuiteName,
    [string] $Root,
    [bool] $DefaultUseVsConsoleValue
)
{
    #Check if it is in a *.json file
    $UnitSuite = Get-NavPlatformTestSuites | ? {$_.SuiteName -eq $SuiteName}
    if ($UnitSuite)
    {
        return $UnitSuite
    }

    #Not a known test suite, build a new test suite object
    $ProjectFile = Find-NavTestSuiteProjectFile -Suite $SuiteName -SearchPath $Root.Split(',')
    if(!$ProjectFile)
    {
        throw "Unable to find test project file for test suite '$SuiteName' in search path '$Root'"
    }
    Write-Log "Test suite: '$SuiteName', found project file: '$ProjectFile'" -Debug

    return NewTestSuite -SuiteName $SuiteName -ProjectFilePath $ProjectFile -UseVsTestConsole $DefaultUseVsConsoleValue
}

<#
.SYNOPSIS
Runs a platform test suite
.DESCRIPTION
Searches for a test project, builds it and runs it. See examples.
.EXAMPLE
Below are some different examples of usage:
"UnitTestSuite.OpenXml" | Run-NavTestSuite
"ManagementTest" | Run-NavTestSuite
Get-NavUnitTestSuites | Run-NavTestSuite
Get-NavLegacyTestSuites -Group Server | Run-NavTestSuite
#>
function Run-NavTestSuite(
    # Specifies which suite(s) to run
    [Parameter(Position=0,ValueFromPipeline=$true)]
    [PSObject] $Suite,
    # Folder where trx file(s) are placed
    [string] $ResultsFolder = "$Env:INETROOT\TestResults",
    # Search paths for location test suites
    [string] $Root = "$Env:INETROOT\test,$Env:INETROOT\ClientFramework,$Env:INETROOT\Platform\test,$Env:INETROOT\NTF,$Env:INETROOT\Build\Tools,$Env:INETROOT\Eng,$Env:INETROOT\SIP\test",
    # Category to run or exclude (using !Category)
    [string] $Category = "!IgnoreInSNAP",
    # Specifies to run in scale mode
    [switch] $Scale,
    # Specifies if vstest.console.exe should be used (instead of mstest). Argument is ignored if the suite is described in a TestSuites*.json file
    [switch] $UseVsTestConsole,
    # Specifies to build using BuildCop
    [switch] $BuildCop,
	[ValidateSet("", "win","core","desktop","phone","tablet")]
	[string] $ClientUnderTestType,
	[ValidateSet("", "safari","InternetExplorer","chrome","firefox","HostedInternetExplorer")]
	[string] $TestPlatformType, 
	[bool] $ShallRunOnDevice = $false,
    [ScriptBlock] $RunAfterBuild = {}
)
{
    Begin {
        if( -not (Test-Path $ResultsFolder))
        {
            Initialize-Directory -Path $ResultsFolder
        }

        $Suites = @()

        New-EnlistmentEvent -Source Run-NavTestSuite -State Test.Starting
		Set-NavClientTestConfig -ClientUnderTestType $ClientUnderTestType -TestPlatformType $TestPlatformType -ShallRunOnDevice $ShallRunOnDevice
    }

    Process {
        $TestSuite = $_

        if ($TestSuite -is [string])
        {
            $TestSuite = GetNavTestSuiteObject $TestSuite -Root $Root -DefaultUseVsConsoleValue $UseVsTestConsole
        }

        # Combine suites and execute in the End block
        $Suites += $TestSuite
    }

    End {
        $Suites | Group -Property ProjectPlatform | % {
            $_.Group | BuildNavTestSuite -Platform $_.Name -BuildCop:$BuildCop
        }
        
        & $RunAfterBuild
        
        $Suites | ? { $_.AssemblyPath } | % {
            #Legacy test suite, cannot be grouped
            $_ | RunNavTestAssembly -ResultsFolder $ResultsFolder -Category $Category | Write-Log
        }

        # group execution based on navtest options
        $Suites | ? { !$_.AssemblyPath } | Group -Property UseVsTestConsole,TestSettingsPath,RerunFailures | %{
        
          New-EnlistmentEvent -Source Run-NavTestSuite -State Test.Start -Message ($Suites.SuiteName -join ";")
        
          $GroupedSuites = $_.Group
          $VsTestConsole = $GroupedSuites[0].UseVsTestConsole
          $TestSetting = $GroupedSuites[0].TestSettingsPath
          $RerunFailures = $GroupedSuites[0].RerunFailures
          $GroupedSuites.SuiteName | Run_TestSuites -ResultsFolder $ResultsFolder -Root $Root -Category $Category -Scale:$Scale -UseVsTestConsole:$VsTestConsole -TestSetting $TestSetting -ReRunFailures $ReRunFailures | Write-Log
        }
    }
}

function RunNavTestAssembly
(
    # Specifies which suite(s) to run
    [Parameter(Position=0,ValueFromPipeline=$true)]
    [PSObject] $TestSuite,
    # Folder where trx file(s) are placed
    [string] $ResultsFolder = "$Env:INETROOT\TestResults",
    [string] $Category
)
{
    Process {
        if($_.RestoreDatabase)
        {
            Restore-NavDatabaseFromCache
            
            Start-NavServer

            if ($_.DeployPlatformUnitTestObjects)
            {
                Initialize-NavDatabaseForPlatformUnitTests
            }
        }

        New-EnlistmentEvent -Source RunNavTestAssembly -State Test.Start -Message ($_.AssemblyPath)

        Run_TestSuites -TestAssembly $_.AssemblyPath -TestSettings $_.TestSettingsPath -ResultsFolder $ResultsFolder -Category $Category -UseVsTestConsole:$_.UseVsTestConsole -ReRunFailures $_.ReRunFailures | Write-Log
    }
}

<#
.SYNOPSIS
Runs PowerShell scriptblocks as a test
.DESCRIPTION
Runs one or more PowerShell scriptblocks in test context, by initializing a test location and cleaning it between tests
#>
function Run-NavPowerShellTest
(
    [Parameter(Position=0,ValueFromPipeline=$true)]
    [ScriptBlock] $Test
)
{
    Begin {
        $TestFolder = "$Env:INETROOT\TestResults\EnlistmentTests"
        Initialize-Directory -Path $TestFolder
    }

    Process {
        try
        {
            Push-Location $TestFolder
            & $Test
        }
        finally
        {
            # Clean up
            Remove-Item -Path "$TestFolder\*" -Recurse -Force
            Pop-Location
        }
    }
}

<#
.SYNOPSIS
Tests enlistment modules
.DESCRIPTION
Searches for tests for each module in the enlistment and runs them
#>
function Run-NavEnlistmentTests()
{    
    gci $Env:INETROOT\Eng\Core,$Env:INETROOT\Eng\Normal -Filter "*.test.ps1" -Recurse | 
        Run-PowerShellTests | 
            Save-PowerShellTestFailures -ResultPath "$Env:INETROOT\Logs" | 
                Format-Table -Property Name,OutCome,Duration,ErrorRecord |
                    Out-String -Stream 
}

<#
.SYNOPSIS
Runs the operations tests in isolation.
.DESCRIPTION
Runs all the Operations tests in a seperate background job. 
#>
function Run-IsolatedOperationTests
{
    $OperationsCode = {
        . $env:INETROOT\Eng\Core\Enlistment\start.ps1 -IncludeOperations -SkipSetup
        Run-OperationsTests
    }
    $TestError = $null

    Start-Job -ScriptBlock $OperationsCode |
        Wait-Job | 
            Receive-Job -Wait -AutoRemoveJob -ErrorVariable TestError -ErrorAction SilentlyContinue | 
                Out-String -Stream

    if ($TestError)
    {
        throw $TestError
    }
}

<#
.SYNOPSIS
Saves test failure logs to a log directory
.DESCRIPTION
Saves failure information from Power Shell tests to a directory
#>
function Save-PowerShellTestFailures
(
    [Parameter(Position=0,ValueFromPipeline=$true)]
    $TestResult,
    $ResultPath
)
{
    Begin {       
        $TestFolder = "$Env:INETROOT\TestResults\EnlistmentTests"
        Initialize-Directory -Path $TestFolder
        Initialize-Directory -Path $ResultPath 
    }

    Process {
        Write-Output $TestResult #put Test back in the pipline so it can be reused by later commandlets.
        
        if ($TestResult.Outcome -eq $null)
        {
            throw new "Testresult object not in the expected format."
        }
        
        if ($TestResult.Outcome -eq "Passed")
        {
            return
        }

        $TestName = $TestResult.Name
        $TestResultFile = "$ResultPath\$TestName.log"
     
        try
        {   
            $TestResult | Format-List -Property * -force | Out-File $testResultFile -Append        
            $TestResult.ErrorRecord | Out-File $testResultFile -Force
            $TestResult.ErrorRecord | Format-List -Property * -force | Out-File $testResultFile -Append
            $TestResult.ErrorRecord.InvocationInfo | Format-List -Property * -force | Out-File $testResultFile -Append
            $TestResult.ErrorRecord.ErrorDetails | Format-List -Property * -force | Out-File $testResultFile -Append      
            
        } catch
        {
        }     
    }
}

<#
.SYNOPSIS
Runs all PowerShell Tests
.DESCRIPTION
Runs all PowerShell tests which are pipped into the command-let
#>
function Run-PowerShellTests
(
    [Parameter(Position=0,ValueFromPipeline=$true)]
    $Test
)
{
    Begin {      
      $Failed = $false
      $originalErrorAction = $ErrorActionPreference
    }

    Process {
        
        if ($Test.Name -eq $null)
        {
            $Test = (gci $Test | Select-Object -First 1)
        }
                        
        $TestResult = New-Object psobject -Property ([ordered]@{
                Name = $test.Name
                Outcome = "Pending"
                ErrorRecord = $null
                Output = ""
                StartTime = Get-Date                
                Duration = [TimeSpan]::Zero
                })
        $Stopwatch = [system.diagnostics.stopwatch]::startNew()

        try
        {
            $ErrorActionPreference = "stop"
            Push-Location $TestFolder            
            
            New-MockedFunction -Name "Write-Host" -Parameters '$Object'

            & $test.FullName | Write-Output -OutVariable TestOutput | Out-Null
          
            $TestResult.Outcome = "Passed"
        } catch
        {
            $Failed = $true            
            $TestResult.Outcome = "Failed"
            $TestResult.ErrorRecord =  $_            
        }
        Finally
        {            
            $Stopwatch.stop()
            Remove-AllMockedFunctions
            $TestResult.Output = $TestOutput
            $TestResult.Duration = $Stopwatch.Elapsed
            Pop-Location
            Write-Output $TestResult
        }
    }
    End 
    {
        $ErrorActionPreference = $originalErrorAction
        if ($Failed)
        {
            throw "One or more tests failed"
        }
    }
}

<#
.SYNOPSIS
Sets the environment variables for Client test Configuration 
.DESCRIPTION
The Script sets the input to enviromental variables which can have the following values:
ClientUnderTestType: Win, Core, Desktop (Web), Phone, Tablet
TestPlatform: Safari, InternetExplorer, Chrome, Firefox, HostedInternetExplorer
ShallRunOnDevice: true | false , ValidateSet("win","core","desktop","phone","tablet")
.EXAMPLE 
Set-NavClientTestConfig -clienttype desktop -testplatform ie
#>
function Set-NavClientTestConfig
(
	[ValidateSet("", "win","core","desktop","phone","tablet")]
	[string] $ClientUnderTestType,
	[ValidateSet("", "safari","InternetExplorer","chrome","firefox","HostedInternetExplorer")]
	[string] $TestPlatformType
)
{
$env:INET_CLIENTUNDERTEST_TYPE = $ClientUnderTestType
$env:INET_TESTPLATFORM_TYPE = $TestPlatformType
$env:INET_SHALLRUNONDEVICE = $ShallRunOnDevice
}

Export-ModuleMember -Function "*-*"
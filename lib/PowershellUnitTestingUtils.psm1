$DefaultTestContextLocation = "$Profile\..\TestResults"

function GetContextLocation()
{   
    if (!Test-Path $DefaultTestContextLocation -PathType Container)
    {
        New-Item $DefaultTestContextLocation -Force | Out-Null
    }

    Write-Output $DefaultTestContextLocation
}

<#
.SYNOPSIS
Asserts that a variable has the value $true
.DESCRIPTION
Throws an exception if $Condition is false
#>
function Assert-IsTrue(
    [Parameter(Mandatory=$True)]
    [bool] $Condition,
    [string] $Message
    )
{
    if (!$Condition)
    {
        throw $Message
    }
}

<#
.SYNOPSIS
Asserts that a variable has the value $false
.DESCRIPTION
Throws an exception if $Condition is $true
#>
function Assert-IsFalse(
    [Parameter(Mandatory=$True)]
    [bool] $Condition,
    [string] $Message
    )
{
$TestContextLocation
    if ($Condition)
    {
        throw $Message
    }
}

<#
.SYNOPSIS
Force failure
.DESCRIPTION
Force failure
#>
function Assert-Fail(
    [string] $Message = "Assertion failed"
    )
{
    throw $Message
}

<#
.SYNOPSIS
Asserts that a file exists
.DESCRIPTION
Throws an exception if a file is not found
#>
function Assert-FileExists(
    [Parameter(Mandatory=$True)]
    [string] $File, 
    [string] $Message = "Expected to find '$file'"
    )
{
    if (!(test-path($File)))
    {
        throw $Message
    }
}

<#
.SYNOPSIS
Asserts that two objects are equal
.DESCRIPTION
Throws an exception if the two objects are not equal. 
#>
function Assert-AreEqual(
    [Parameter(Mandatory=$True)]
    $Expected, 
    [Parameter(Mandatory=$True)]
    $Actual, 
    [String] $Message = "Expected '$Expected' to be equal to '$Actual'" 
    )
{
    if ($Expected -ne $Actual)
    {
        throw $Message
    }
}

<#
.SYNOPSIS
Asserts that a command given as a string raises a specific error message
.DESCRIPTION
Throws an exception if the code executed does not raise the expected error message
#>

function Assert-ErrorMessageRaised(
    [Parameter(Mandatory=$True)]
    [scriptblock] $Command,
    [Parameter(Mandatory=$True)]
    [string] $ErrorMessage
    )
{
    $exception = $null

    try
    {
        Invoke-Command -ScriptBlock $Command
    }
    catch
    {
        $exception = $_.Exception
    }

    if ($exception -eq $null)
    {
        throw "No error was raised!"
    }

    if (-not $exception.Message.Contains($ErrorMessage)) 
    {
        throw "Error message: '$ErrorMessage' was not raised!"
    }
}

<#
.SYNOPSIS
Asserts that a file contains a string
.DESCRIPTION
Throws an exception if the file does not contain the specifed substring. 
#>
function Assert-FileContains(
    [Parameter(Mandatory=$True)]
    [string] $File, 
    [Parameter(Mandatory=$True)]
    [string] $Substring, 
    [string] $Message = "Expected to find '$substring' in '$file'")
{
    $allFileContent = (Get-Content -Path $File | Out-String)
    if (!($allFileContent.Contains($Substring)))
    {
        throw $Message
    }
}

<#
.SYNOPSIS
Asserts that a file contains a string
.DESCRIPTION
Throws an exception if the file does not contain the specifed substring. 
#>
function Assert-FileNotContains(
    [Parameter(Mandatory=$True)]
    [string] $File, 
    [Parameter(Mandatory=$True)]
    [string] $Substring, 
    [string] $Message = "Did not expect to find '$substring' in '$file'")
{
    $allFileContent = (Get-Content -Path $File | Out-String)
    if ($allFileContent.Contains($Substring))
    {
        throw $Message
    }
}

<#
.SYNOPSIS
Mockes a function with new code
.DESCRIPTION
Creates a new mocked function ($Name_Mock) and a alias $Name which points to it.
#>
function New-MockedFunction(
    [Parameter(Mandatory=$True)]
    [string] $Name, 
    [string] $Parameters = "",
    [string] $Code = "",
    [string] $Scope = "2")
{    
    #Alias redirection is needed as only functions can not be created in parent scope (Scope 2)
    $Guid = [guid]::NewGuid().ToString()
    $MockFunctionName = "${Name}_Mock_$guid"

    $mockFunction = "function Global:${MockFunctionName}(${Parameters}) { $Code }"
 
    Invoke-Expression $mockFunction
    Get-item "alias:\$Name" -ErrorAction SilentlyContinue | Remove-item
    New-Alias -Scope $Scope -Name $Name -Value $mockFunctionName -Option AllScope
}

<#
.SYNOPSIS
Removes all mockes created by the New-MockedFunction 
.DESCRIPTION
Removes all mocks (both the alias and the underlying _mock function) which have been created by this module
#>
function Remove-AllMockedFunctions()
{
    $thisModule = $MyInvocation.MyCommand.ModuleName               
    (Get-item "alias:\") | Where-Object { $_.ModuleName -eq $thisModule } | % { Remove-Item "alias:\$_" } 
    (Get-item "function:\*_Mock*") | Where-Object { $_.ModuleName -eq $thisModule} | Remove-Item
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
        $TestFolder = GetContextLocation
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

Export-ModuleMember *-*
#PowerShell Environment

This repro contains random Powershell stuff (its my powershell profile directory), among also have the scripts used to configure my development environment.

It is not meant to be directly reusable by somebody else, but with that said if you can use it for something then you more than welcome.

Bootstrap commands:
iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))

choco install git

$Env:Path+=";${env:ProgramFiles(x86)}\git\bin"

rmdir $PROFILE\.. -force

cd $PROFILE\..\..

git clone https://github.com/lars36s/PowerShell.git WindowsPowerShell

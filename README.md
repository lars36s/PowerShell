#PowerShell Environment

This repro contains my powershell envirnment (its my powershell profile directory), this is basically what I use to configure my development environment.

It is not meant to be directly reusable by somebody else, but with that said if you can use it for something then you more than welcome.

#Bootstrap command

iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/lars36s/PowerShell/master/install.ps1'))

function global:Update-RDMS {
    # Credit https://rcmtech.wordpress.com/2015/08/20/powershell-script-to-update-rdms-server-list/
    Begin{}
    Process{
        Write-Debug "Starting Update-RDMS"
        Write-Debug "Import RDS cmdlets"
        Import-Module RemoteDesktop
        $ConnectionBrokers = Get-RDServer | Where-Object {$_.Roles -contains "RDS-CONNECTION-BROKER"}
        $ServerManagerXML = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\ServerManager\Serverlist.xml"
                Write-Debug "Find active Connection Broker"
        $ActiveManagementServer = $null
        foreach($Broker in $ConnectionBrokers.Server){
            $ActiveManagementServer = (Test-NetConnection -ComputerName $Broker | Where-Object {$_.PingSucceeded -eq 'True'})
            if($ActiveManagementServer -eq $null){
                Write-Host "Unable to contact $Broker" -ForegroundColor Yellow
            } else {
                break
            }
        }
        if($ActiveManagementServer -eq $null){
            Write-Error "Unable to contact any Connection Broker"
        }else{
            if(Get-Process -Name ServerManager -ErrorAction SilentlyContinue){
                Write-Debug "Kill Server Manager"
                # Have to use tskill as stop-process gives an "Access Denied" with ServerManager
                Start-Process -FilePath "$env:systemroot\System32\tskill.exe" -ArgumentList "ServerManager"
            }
            Write-Debug "Get RD servers"
            $RDServers = Get-RDServer -ConnectionBroker $ActiveManagementServer.ComputerName
            Write-Debug "Get Server Manager XML"
            [XML]$SMXML = Get-Content -Path $ServerManagerXML
            foreach($RDServer in $RDServers){
                $Found = $false
                Write-Host ("Checking "+$RDServer.Server+" ") -NoNewline -ForegroundColor Gray
                foreach($Server in $SMXML.ServerList.ServerInfo){
                    if($RDServer.Server -eq $Server.name){
                        $Found = $true
                    }
                }
                if($Found -eq $true){
                    Write-Host "OK" -ForegroundColor Green
                }else{
                    Write-Host "Missing" -ForegroundColor Yellow
                    $NewServer = $SMXML.CreateElement("ServerInfo")
                    $SMXML.ServerList.AppendChild($NewServer) | Out-Null
                    $NewServer.SetAttribute("name",$RDServer.Server)
                    $NewServer.SetAttribute("status","1")
                    $NewServer.SetAttribute("lastUpdateTime",[string](Get-Date -Format s))
                    $NewServer.SetAttribute("locale","en-GB")
                }
            }
            # Remove xmlns attribute on any newly added servers, this is added automatically by PowerShell but causes Server Manager to reject the new server
            $SMXML = $SMXML.OuterXml.Replace(" xmlns=`"`"","")
            Write-Debug "Save XML file"
            $SMXML.Save($ServerManagerXML)
            Write-Debug "Start Server Manager"
            Start-Process -FilePath "$env:systemroot\System32\ServerManager.exe"
        }
    }
    End{}
}

function global:Retry-TestCommand
{
    param (
    [Parameter(Mandatory=$true)][string]$Test,
    [Parameter(Mandatory=$false)][hashtable]$Args = @{},
    [Parameter(Mandatory=$false)][string]$TestProperty,
    [Parameter(Mandatory=$false)][int]$Tries = 5,
    [Parameter(Mandatory=$false)][int]$SecondsDelay = 2,
    [Parameter(Mandatory=$false)][switch]$ExpectNull
    )
    $TryCount = 0
    $Completed = $false
    $MsgFailed = "Command [{0}] failed" -f $Test
    $MsgSucceeded = "Command [{0}] succeeded." -f $Test

    while (-not $Completed)
    {
        try
        {
            $Result = & $Test @Args
            $TestResult = if ($TestProperty) { $Result.$TestProperty } else { $Result }
            if (-not $TestResult -and -not $ExpectNull)
            {
                throw $MsgFailed
            }
            else
            {
                Write-Verbose $MsgSucceeded
                Write-Output $TestResult
                $Completed = $true
            }
        }
        catch
        {
            $TryCount++
            if ($TryCount -ge $Tries)
            {
                $Completed = $true
                Write-Output $null
                Write-Warning ($PSItem | Select -Property * | Out-String)
                Write-Warning ("Command [{0}] failed the maximum number of {1} time(s)." -f $Test, $Tries)
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }
            else
            {
                $Msg = $PSItem.ToString()
                if ($Msg -ne $MsgFailed) { Write-Warning $Msg }
                Write-Warning ("Command [{0}] failed. Retrying in {1} second(s)." -f $Test, $SecondsDelay)
                Start-Sleep $SecondsDelay
            }
        }
    }
}

function global:Download-File
{
    param (
    [Parameter(Mandatory=$true)]
    [string]$Source,

    [Parameter(Mandatory=$true)]
    [string]$Destination,

    [Parameter(Mandatory=$false)]
    [ValidateSet("Ssl3","SystemDefault","Tls","Tls11","Tls12")]
    [string]$SecurityProtocol = "Tls12"
    )
    Write-Verbose "Downloading file --"
    Write-Verbose "    Source = ${Source}"
    Write-Verbose "    Destination = ${Destination}"
    try
    {
        Write-Verbose "Attempting to retrieve file using .NET method..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::$SecurityProtocol
        (New-Object Net.WebClient).DownloadFile("${Source}","${Destination}")
        Write-Output (Get-ChildItem "$Destination")
    }
    catch
    {
        try
        {
            Write-Verbose $PSItem.ToString()
            Write-Verbose ".NET method failed, attempting BITS transfer method..."
            Start-BitsTransfer -Source "${Source}" -Destination "${Destination}"
            Write-Output (Get-ChildItem "$Destination")
        }
        catch
        {
            Write-Verbose $PSItem.ToString()
            $PSCmdlet.ThrowTerminatingError($PSitem)
        }
    }
}

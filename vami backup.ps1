#################################################################################
##
## VAMI Backup and Health Status

## Created by Suriaraj Dhayalan 

## Date : 12 Aug 2021

## Version : 1.0.1

## Email: d.suriaraj23@gmail.com  

## This powershell scripts checks the vCenter server Health Status and Backup Status

## works for single or multiple vcenter's. 

## modification or redistribution is allowed with proper credits to post

## this script is free to use at your own risk

################################################################################

#checking and removing html file

if (get-item "x:\fakepath\result.html" -ErrorAction ignore) {Remove-Item "x:\fakepath\result.html"}

$Result =@()

$Result2 =@()

$Result3 =@()

$snapres = @()

$da=@()

$dAres=@()

cls

##Skipping/Accepting SSL/TLS validation

add-type @"

    using System.Net;

    using System.Security.Cryptography.X509Certificates;

    public class TrustAllCertsPolicy : ICertificatePolicy {

        public bool CheckValidationResult(

            ServicePoint srvPoint, X509Certificate certificate,

            WebRequest request, int certificateProblem) {

            return true;

        }

    }

"@
Import-Module VMware.VimAutomation.Core
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$False

#vc backup validation

foreach ($vcenter in (Get-Content -Path "x:\fakepath\host.txt"))

{

$BaseUri = "https://$vcenter/rest/"

$SessionUri = $BaseUri + "com/vmware/cis/session"

#credentials

$username = "myuser"

$password = "mypassword"

$secst = $password | ConvertTo-SecureString -AsPlainText -Force

$creds=New-Object System.Management.Automation.PSCredential -ArgumentList $username,$secst

$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Creds.UserName+':'+($secst=$Creds.GetNetworkCredential().Password)))

$header = @{

  'Authorization' = "Basic $auth"

}

$authResponse = (Invoke-RestMethod -Method Post -Headers $header -Uri $SessionUri).Value

$sessionHeader = @{"vmware-api-session-id" = $authResponse}

##checking backup job id

$bjlist = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "appliance/recovery/backup/job")

##selecting last recent job id

$bj=$bjlist.value | Select-Object -first 1

##collecting job id status

$bjstat = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "appliance/recovery/backup/job/"+$bj)

##collect backup job size

$bjsize = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "appliance/recovery/backup/job/details?filter.jobs="+$bj)

$bjsize=[math]::Round($bjsize.value.value.size/1GB,2)

##collecting vCenter Overla health and last checked date

$overhealth = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "/appliance/health/system")

$lastcheckdate = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "/appliance/health/system/lastcheck")

$memory = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "/appliance/health/mem")

$dbstat = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "/appliance/health/database-storage")

$CPU = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "/appliance/health/load")

$storage = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "/appliance/health/storage")

$service = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "/appliance/health/applmgmt")

$swap = Invoke-Restmethod -Method Get -Headers $sessionHeader -Uri ($BaseUri + "/appliance/health/swap")

#storing data to array

$Result += New-Object PSObject -Property @{

vCenter_Name = $vcenter

ID = $bjstat.value.id

State = $bjstat.value.state

Start_Time = $bjstat.value.start_time

End_Time = $bjstat.value.end_time

Progress = $bjstat.value.progress

BSize = $bjsize

OverallHealth = $overhealth.value

Lastcheckdate = $lastcheckdate.value

CPU = $cpu.value

Memory = $memory.value

Storage = $storage.value

DatabaseStorage = $dbstat.value

Service=$service.value

Swap=$swap.value

}

}

 

#dastore calculation start

##included multiple loops to obtain single vcenter connection to perform multiple operations

foreach ($vc in (gc "x:\fakepath\host.txt"))

{

Connect-VIServer -server $vc -Username $username -Password $password

#retrieving orphaned VM's

$orphaned_vms = Get-VM * | Where {$_.ExtensionData.Summary.Runtime.ConnectionState -eq "orphaned"}

#calculating Datastore free space

$datastores = Get-Datastore | Sort Name

 

ForEach ($ds in $datastores)

{

        $percentfree = ($ds.FreeSpaceGB / $ds.CapacityGB)*100

        $PercentFree = “{0:N2}” -f $PercentFree

       

        $result2 += New-Object PSObject -Property @{

        vCenter_Name = $vc

        DS_Name = $ds.Name

        Total_Capacity = [math]::Round($ds.CapacityGB)

        Free_Space = [math]::Round($ds.FreeSpaceGB)

        Free_perc = $percentfree

        }

 

    }

 

    #orphaned vm report start

    ForEach ($orp in $Orphaned_vms)

{

        $result3 += New-Object PSObject -Property @{

        vCenter_Name = $vc

        Orphaned_VM = $orp.Name

        }

        }

        #sn report start

        $snap = @()

       $snap=Get-VM -Server $vc | Get-Snapshot | Where {$_.Created -lt (Get-Date).AddDays(-3)}

       Write-Host $snap.count

        foreach ($sn in $snap)

        {

        write-host $sn.name

               $snapres+= New-Object psobject -Property @{

     vCenter=$vc

     VMName=$sn.VM

        Name=$sn.Name

        Created=$sn.created

        Size=[Math]::Round($sn.SizeMB,2)

      

        }

    }

##ESXi host disabled alarm status

 

$dA = Get-VMHost | Where-Object {$_.extensiondata.AlarmActionsEnabled -eq $false} | Select name,connectionstate,powerstate,@{N=”alarmActionsEnabled”; E={$_.Extensiondata.AlarmActionsEnabled}}

foreach($dAlarms in $dA)

{

<#if ($dAlarms.ConnectionState -ne "Maintenance" -and $dAlarms.powerstate -ne "poweredoff" )

{#>

$dAres+= New-Object PSObject -Property @{

vCenter_Name = $vc

Hostname=$dAlarms.Name

CState=$dAlarms.ConnectionState

PState=$dAlarms.powerstate

AState=$dAlarms.alarmActionsEnabled

#}

} }

##end of esxi host alarm

 

#include any addition to report above this line

    Disconnect-VIServer -Server $vc -Confirm:$False

    }

    $Result2 = $result2  | Sort-Object Free_perc | Select-Object -First 20

#dastore calculation end

 

##converting to HTML

if($Result -ne $null)

{

$REPHTML = '<style type="text/css">

#Header{font-family:"Trebuchet MS", Arial, Helvetica, sans-serif;width:100%;border-collapse:collapse;}

#Header td, #Header th {font-size:14px;border:1px solid #3D85C6;padding:3px 7px 2px 7px;}

#Header th {font-size:14px;text-align:left;padding-top:5px;padding-bottom:4px;background-color:#073763;color:#fff;}

#Header tr.alt td {color:#000;background-color:#EAF2D3;}

</Style>'

##start of first table backup status

$REPHTML += "<HTML><BODY>

<b>Backup Status:</b></br>

<Table border=1 cellpadding=0 cellspacing=0 id=Header>

<TR>

<TH><B>vCenter Name</B></TH>

<TH><B>Backup Job ID</B></TD>

<TH><B>Status</B></TD>

<TH><B>Start Time Type</B></TH>

<TH><B>End Time</B></TH>

<TH><B>Progress</B></TH>

<TH><B>BackupSize in GB</B></TH>

</TR>"

Foreach($Entry in $Result)

{

$REPHTML += "<TR>"

$REPHTML += "

<TD>$($Entry.vCenter_name)</TD>

<TD>$($Entry.ID)</TD>

<TD>$($Entry.State)</TD>

<TD>$($Entry.Start_Time)</TD>

<TD>$($Entry.End_Time)</TD>

<TD>$($Entry.Progress)</TD>

<TD>$($Entry.BSize)</TD>

 

</TR>"

 

}

$REPHTML += "</Table></br></br></BODY></HTML>" ##end of first table backup status

 

#start of second table health status

$REPHTML += "<HTML><BODY>

<b>Overall Health Status:</b></br>

<Table border=1 cellpadding=0 cellspacing=0 id=Header>

<TR>

<TH><B>vCenter Name</B></TH>

<TH><B>OverallHealth</B></TH>

<TH><B>Last checked date</B></TD>

<TH><B>CPU Status</B></TD>

<TH><B>Memory Status</B></TH>

<TH><B>Storage Status</B></TH>

<TH><B>DatabaseStorage Status</B></TH>

<TH><B>SWAP Memory Status</B></TH>

<TH><B>Service Status</B></TH>

</TR>"

Foreach($Entry in $Result)

{

$REPHTML += "<TR>"

$REPHTML += "

<TD>$($Entry.vCenter_name)</TD>

<TD>$($Entry.OverallHealth)</TD>

<TD>$($Entry.Lastcheckdate)</TD>

<TD>$($Entry.CPU)</TD>

<TD>$($Entry.Memory)</TD>

<TD>$($Entry.Storage)</TD>

<TD>$($Entry.DatabaseStorage)</TD>

<TD>$($Entry.Service)</TD>

<TD>$($Entry.Swap)</TD>

</TR>"

 

}

$REPHTML += "</Table></br></br></BODY></HTML>" #end of second table health status

#start of third table Datastore Report

$REPHTML += "<HTML><BODY>

<b>Datastore-Top 20 DS Lowest in Free Space:</b></br>

<Table border=1 cellpadding=0 cellspacing=0 id=Header>

<TR>

<TH><B>vCenter Name</B></TH>

<TH><B>Datastore Name</B></TH>

<TH><B>Total Space in GB</B></TH>

<TH><B>Free Space in GB</B></TD>

<TH><B>Free Percentage</B></TD>

</TR>"

Foreach($Entry2 in $Result2)

{

$REPHTML += "<TR>"

$REPHTML += "

<TD>$($Entry2.vCenter_Name)</TD>

<TD>$($Entry2.DS_Name)</TD>

<TD>$($Entry2.Total_Capacity)</TD>

<TD>$($Entry2.Free_Space)</TD>

<TD>$($Entry2.Free_perc)</TD>

 

</TR>"

 

}

$REPHTML += "</Table></br></br></BODY></HTML>" #end of third table datastore status

 

#start of fourth table - orphaned vm

$REPHTML += "<HTML><BODY>

<b>Orphaned VM's:</b></br>

<Table border=1 cellpadding=0 cellspacing=0 id=Header>

<TR>

<TH><B>vCenter Name</B></TH>

<TH><B>Orphaned VM Name</B></TH>

</TR>"

Foreach($Entry3 in $Result3)

{

$REPHTML += "<TR>"

$REPHTML += "

<TD>$($Entry3.vCenter_Name)</TD>

<TD>$($Entry3.Orphaned_VM)</TD>

 

</TR>"

 

}

$REPHTML += "</Table></br></br></BODY></HTML>" #end of fourth table - orphaned vm

 

##start of fourth table sn report

$REPHTML += "<HTML><BODY>

<b>Snapshot Report:</b></br>

<Table border=1 cellpadding=0 cellspacing=0 id=Header>

<TR>

<TH><B>vCenter Name</B></TH>

<TH><B>VM Name</B></TD>

<TH><B>Snapshot Name</B></TD>

<TH><B>Created Date</B></TH>

<TH><B>Size of Sn in MB</B></TH>

</TR>"

Foreach($Entry4 in $snapres)

{

$REPHTML += "<TR>"

$REPHTML += "

<TD>$($Entry4.vCenter)</TD>

<TD>$($Entry4.VMName)</TD>

<TD>$($Entry4.Name)</TD>

<TD>$($Entry4.Created)</TD>

<TD>$($Entry4.Size)</TD>

</TR>"

 

}

$REPHTML += "</Table></br></br></BODY></HTML>"

##end of fourth table snapshot report

 

##start of fifth table esxi alarm report

$REPHTML += "<HTML><BODY>

<b>ESXi Host Alarm Status Report:</b></br>

<Table border=1 cellpadding=0 cellspacing=0 id=Header>

<TR>

<TH><B>vCenter Name</B></TH>

<TH><B>Host Name</B></TD>

<TH><B>Connection State</B></TD>

<TH><B>Power State</B></TH>

<TH><B>ESXi Host Alarm Status</B></TH>

</TR>"

Foreach($Entry5 in $dAres)

{

$REPHTML += "<TR>"

$REPHTML += "

<TD>$($Entry5.vCenter_Name)</TD>

<TD>$($Entry5.HostName)</TD>

<TD>$($Entry5.Cstate)</TD>

<TD>$($Entry5.Pstate)</TD>

<TD>$($Entry5.Astate)</TD>

</TR>"

 

}

$REPHTML += "</Table></br></br></BODY></HTML>"

##end of fifth table alarm report

 

 

#convert to html file

$REPHTML | Out-File "x:\fakepath\result.html"

}

#date variable to add report generated  date and time in email

$date =Get-Date

#moving the html data as raw content to append in email

$HTML_Report = get-content "x:\fakepath\result.html" -raw

#body of the email

 

$Body = @"

Hi Team,</br></br>Please find the vCenter Daily Backup Report for $date </br></br> <b>vCenter Reports: </b>$HTML_Report

</br>

 

<b>Regards,</br>

VMware Support Team.</b>

"@

#email function uses smtp

Send-MailMessage -From me@myserver.com -to me@myserver.com -SmtpServer smtp.myserver.com -Body $body -BodyAsHtml -Subject "vCenter Daily Health & Backup Report"

 

 

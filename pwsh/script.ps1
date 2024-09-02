# requirement 1 - must enable "System assigned" Identity
# requirement 2 - Assign a scope of System-Managed Identity for subscritpion
# Version: PS 5.1
Param(
    [parameter (Mandatory = $true)]
    [String] $vmname,
    [parameter (Mandatory = $true)]
    [String] $sizeToScale,
    [parameter (Mandatory = $true)]
    [String] $resourceGroupName
)

Import-Module Az.Accounts
Import-Module Az.Automation
Import-Module Az.Compute

Write-Output "Connecting to azure via Connect-AzAccount -Identity"
Connect-AzAccount -Identity 
Write-Output "Successfully connected with Automation account's Managed Identity"

################################################################################### SCRIPT
$list = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmname


# Validate - SqlVirtualMachine
foreach ($a in $list) {
    $sqlvm = Get-AzSqlVM -Name $a.Name  -ResourceGroupName $a.ResourceGroupName -ErrorAction SilentlyContinue
    $sqlvm.SqlManagementType
    if ($sqlvm) {
        write-output "Tango down"
        $scriptCode = 'hostname ; Get-service | Where-Object { ($_.name -like "MSSQL$*" -or $_.name -like "MSSQLSERVER" -or $_.name -like "SQL Server (*") -or $_.name -like "MSSQLServerOLAPService"} | stop-service -force -confirm:$false'
        $Command = Invoke-AzVMRunCommand -Name $a.Name -ResourceGroupName $a.ResourceGroupName -CommandId 'RunPowerShellScript' -ScriptString $scriptCode -ErrorAction SilentlyContinue
        $Status = $Command.status
        $message = $Command.Value.Message
        write-output "Command Executed: $($Status)" -ErrorAction SilentlyContinue
        write-output "Command Output:" -ErrorAction SilentlyContinue
        write-output "$($message)" -ErrorAction SilentlyContinue
    }
    else {
        write-output "VM Without SQL" 
    }
}

foreach ($a in $List) {
    $status = (Get-AzVM -ResourceGroupName $a.ResourceGroupName -Name $a.Name -Status).Statuses[1].Code
    
    if ($status -ne "PowerState/deallocated") {
        Stop-AzVM -Name $a.Name -ResourceGroupName $a.ResourceGroupName -confirm:$false -Force
        Write-Output "Stopping VM: $($a.name)"
    }
    else {
        Write-Output "VM already Stopped: $($a.name)"
    }
	
    $a.HardwareProfile.VmSize = $sizetoscale
    Update-AzVM -VM $a -ResourceGroupName $a.ResourceGroupName
}

# Wait before continue
start-sleep -Seconds 30

$list = @()
$list = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmname
foreach ($a in $List) {
    $status = (Get-AzVM -ResourceGroupName $a.ResourceGroupName -Name $a.Name -Status).Statuses[1].Code
    if ($status -ne "PowerState/running") {
        Start-AzVM -Name $a.Name -ResourceGroupName $a.ResourceGroupName -AsJob
        Write-Output "Starting VM: $($a.name)"
    }
    else {
        Write-Output "VM already UP: $($a.name)"
    }
    
    if ($sqlvm) {
        start-sleep -Seconds 120 #wait the VM become UP
        write-output "Starting MS SQL"
        $scriptCode = 'powershell -file c:\azure\SQL-startup.ps1'
        $Command = Invoke-AzVMRunCommand -Name $a.Name -ResourceGroupName $a.ResourceGroupName -CommandId 'RunPowerShellScript' -ScriptString $scriptCode -ErrorAction SilentlyContinue
        $Status = $Command.status
        $message = $Command.Value.Message
        write-output "Command Executed: $($Status)" -ErrorAction SilentlyContinue
        write-output "Command Output:" -ErrorAction SilentlyContinue
        write-output "$($message)" -ErrorAction SilentlyContinue
    }
    else {
        write-output "VM Without SQL" 
    }

}
get-job * | receive-job -wait

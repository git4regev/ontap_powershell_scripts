# 2020-04-06 yaron@netapp.com
# netapp_inode_remediation_script.ps1
#
# Purpose: Script to remediate high inode utilization across all the
#          volumes in a ONTAP cluster.
#
# (c) 2020 NetApp Inc., All Rights Reserved
#
# NetApp disclaims all warranties, excepting NetApp shall provide support
# of unmodified software pursuant to a valid, separate, purchased support
# agreement.  No distribution or modification of this software is permitted
# by NetApp, except under separate written agreement, which may be withheld
# at NetApp's sole discretion.
#
# THIS SOFTWARE IS PROVIDED BY NETAPP "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
# NO EVENT SHALL NETAPP BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#


#######################################
# Custom variables - CHANGE AS NEEDED #
#######################################
$ontap_cluster_name     = "cluster1"  # ONTAP cluster information
$ontap_cluster_username = "admin"     # ONTAP cluster information
$ontap_cluster_password = "Netapp1!" # ONTAP cluster information

# The script will take action if the current inode usage percentage (for each volume) is equal or higher than the value of $non_healthy_inode_utilization
# In case an action is necessary, the new inode count will represent a usage percentage of $healthy_inode_utilization
# For example, if a given volume has 100 inodes and 83 of them are used (a usage percentage of 0.83), and assuming default values of variables were not changed,
#    then the script will increase the number of inodes for the volume from 100 to 166, driving the usage percentage down to 0.5
$healthy_inode_utilization     = 0.5   # Inode details. Should be in the range of 0 to 1
$non_healthy_inode_utilization = 0.8   # Inode details. Should be in the range of 0 to 1

$output_file_name = "C:\inde_remediation_output.txt" # File location for storage script output (append)

$email_from_address  = "inode_script@demo.netapp.com"            # Email information
$email_to_address    = "admin@demo.netapp.com"                   # Email information
$email_subject       = "NetApp I-node Remediation Script Output" # Email information
$email_smtp_server   = "mail.demo.netapp.com"                    # Email information
$email_smtp_username = "admin"                                   # Email information
$email_smtp_password = "Netapp1!"                                # Email information
$email_smtp_port     = 25                                        # Email information

$send_email    = $true # $true if you want email to be sent out. $false if not.
$store_to_file = $true # $true if you want output to be stored in a local file. $false if not.


##########################################################
# -------- DO NOT CHANGE CODE BEYOND THIS POINT -------- #
##########################################################

# The Send-InodeOutput function will write the script output to file and send it as email if configured to do so
# Usage: Send-InodeOutput <String: output>
function Send-InodeOutput {
    $output_to_send = $args[0]

    # Email output to recipient
    if ($send_email -eq $true){
        $email_creds_exist = $false
        Write-Host -NoNewline "Creating secured email credentials... "
        try {
            $secured_password = ConvertTo-SecureString $email_smtp_password -AsPlainText -Force
            $email_credential = New-Object System.Management.Automation.PSCredential -ArgumentList $email_smtp_password,$secured_password
            $email_creds_exist = $true
        } catch {
            $text = "FAILED. Error: $_"
            Write-Host "$text"
            $output_to_send += "Creating secured email credentials... $text`r`n"
        }
        if ($email_creds_exist -eq $true) {
            Write-Host "OK."
            $output_to_send += "Creating secured email credentials... OK.`r`n"
            Write-Host -NoNewline "Sending email... "
            try {
                Send-MailMessage -To $email_to_address -From $email_from_address  -Subject $email_subject -Body $output_to_send -Credential $email_credential -SmtpServer $email_smtp_server -Port $email_smtp_port
                Write-Host "OK."
                $output_to_send += "Sending email... OK.`r`n"
            } catch {
                $text = "FAILED. Error: $_"
                Write-Host "$text"
                $output_to_send += "Sending email... $text`r`n"
            }
        }
    }

    # Store output to file
    if ($store_to_file -eq $true){
        Add-Content $output_file_name $output_to_send
    }

}

$text_output = "" # This variable will contain output that will be stored in a file/email at the end of the run
$text_output = "========================================================`r`n"
$date = (Get-Date).ToString()
$text_output += "Date/time: $date`r`n`r`n"

# Disable interactive prompt
$ErrorActionPreference = "stop"
$ConfirmPreference = 'None'

# Load DataONTAP PowerShell module
Write-Host -NoNewline "Loading DataONTAP PowerShell module... "
try {
    Import-Module DataONTAP
} catch {
    $text = "FAILED. Error: $_"
    Write-Host "$text"
    $text_output += "Loading DataONTAP PowerShell module... $text`r`n"
    Send-InodeOutput $text_output
    return
}
Write-Host "OK."
$text_output += "Loading DataONTAP PowerShell module... OK.`r`n"

# Creating ONTAP secured credential object
Write-Host -NoNewline "Creating ONTAP secured credential object... "
try {
    $secured_password = ConvertTo-SecureString $ontap_cluster_password -AsPlainText -Force
    $ontap_credential = New-Object System.Management.Automation.PSCredential -ArgumentList $ontap_cluster_username,$secured_password
} catch {
    $text = "FAILED. Error: $_"
    Write-Host "$text"
    $text_output += "Creating ONTAP secured credential object... $text`r`n"
    Send-InodeOutput $text_output
    return
}
Write-Host "OK."
$text_output += "Creating ONTAP secured credential object... OK.`r`n"

# Connect to ONTAP cluster
Write-Host -NoNewline "Connecting to ONTAP cluster $ontap_cluster_name... "
try {
    Connect-NcController -Name $ontap_cluster_name -Credential $ontap_credential | Out-Null
} catch {
    $text = "FAILED. Error: $_"
    Write-Host "$text"
    $text_output += "Connecting to ONTAP cluster $ontap_cluster_name... $text`r`n"
    Send-InodeOutput $text_output
    return
}
Write-Host "OK."

# Get list of all FlexVol volumes in the cluster (FlexGroup volumes' constituents are FlexVol volumes)
Write-Host -NoNewline "Getting non-root volume inventory for cluster... "
try {
    $ontap_volumes = Get-NcVol | where {$_.VolumeStateAttributes.IsNodeRoot -eq $false -and $_.VolumeStateAttributes.IsVserverRoot -eq $false}
} catch {
    $text = "FAILED. Error: $_"
    Write-Host "$text"
    $text_output += "Getting non-root volume inventory for cluster... $text`r`n"
    Send-InodeOutput $text_output
    return
}
Write-Host "OK."
$text_output += "Getting non-root volume inventory for cluster... OK.`r`n"

# Iterarte through all volumes and fix inode issues if exists
foreach ($ontap_volume in $ontap_volumes){
    # Ignore FlexVol volumes that are FlexGroup but not constituents
    if (-Not ($ontap_volume.VolumeStateAttributes.IsFlexgroup -eq $true -and $ontap_volume.VolumeStateAttributes.IsConstituent -eq $false)) {
        # Get inode information for volume
        $volume_name = $ontap_volume.Name
        $volume_svm_name = $ontap_volume.Vserver
        $volume_total_inodes = $ontap_volume.FilesTotal
        $volume_used_inodes = $ontap_volume.FilesUsed

        # Fix issue if exists
        if (($volume_used_inodes / $volume_total_inodes) -ge $non_healthy_inode_utilization){
        
            # Calculate new inode count
            $volume_new_total_inodes = $volume_used_inodes / $healthy_inode_utilization

            # Apply new inode count to volume
            Write-Host -NoNewline "- $volume_name - "
            try {
                Set-NcVolTotalFiles -Name $volume_name -VserverContext $volume_svm_name -TotalFiles $volume_new_total_inodes | Out-Null
                $volume_updated_total_inodes = (Get-NcVol -Name $volume_name -VserverContext $volume_svm_name).FilesTotal
            } catch {
                $text = "FAILED to increase inode count. Error: $_"
                Write-Host "$text"
                $text_output += "- $volume_name - $text`r`n"
                continue # Even though the operation failed, we want to try and see if it works for the other volumes
            }
            Write-Host "Increased inode count from $volume_total_inodes to $volume_updated_total_inodes."
            $text_output += "- $volume_name - Increased inode count from $volume_total_inodes to $volume_updated_total_inodes.`r`n"

        } else {
            # Notify the volume was healthy
            Write-Host "- $volume_name - Healthy. No increase in inodes necessary."
            $text_output += "- $volume_name - Healthy. No increase in inodes necessary.`r`n"
        }
    }
}

# Send output to file/email
Send-InodeOutput $text_output

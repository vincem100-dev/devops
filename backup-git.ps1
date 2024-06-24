param (
    [parameter(HelpMessage = "Enter Subscription Name.")] $SubscriptionName = 'az-np-usr-555-SpainDepot_dev',
    [parameter(HelpMessage = "Enter Organization Name.")] [String] $OrganizationName = 'costcocloudops',
    [parameter(HelpMessage = "Enter Project Name.")] [String]  $ProjectName = 'International%20IT%20Depot',
    [parameter(HelpMessage = "Enter Resource Group Name.")] [String]  $ResourceGroupName = 'depot-shared',
    [parameter(HelpMessage = "Enter Storage Account Name (Optional)")] [String]  $StorageAccountName = '',
    [parameter(HelpMessage = "Enter Container Name.")] [String]  $ContainerName = 'repository',
    [parameter(HelpMessage = "Enter Weekly Backup Retention (days).")]
    [ValidateRange(90, [int]::MaxValue)] 
    [int] $WeeklyBackupRetention = 90,
    [parameter(HelpMessage = "Enter Access Token (Skip if use local credential)")] [String] $AccessToken = '',
    [parameter(HelpMessage = "Enter List of repo name")] 
    [String[]] $RepoNames = @()
)

# GLOBAL VARIABLES
$CURRENT_PATH = $(Get-Location)
$BackupFolder = "$CURRENT_PATH/Backup"
$ReposFolder = "$BackupFolder/Repos"
$ZIPFolder = "$BackupFolder/ZIP"

# Check if today is end of week
function Is-WeekEndDate {
    $Today = (Get-Date).ToUniversalTime().Date
    $IsWeekEndDate = $Today.DayOfWeek.value__ -eq 0

    return $IsWeekEndDate
}

function Remove-LocalFolder {    
    Write-Host "Removing Local Folder"
    #  Delete old local BackupFolder if exist
    if (Test-Path $BackupFolder) {
        Remove-Item $backupFolder -recurse -force -ErrorAction SilentlyContinue | Out-Null
    }
    
    if (Test-Path $BackupFolder) {            
        Write-Host "Fail to remove $BackupFolder"
    }
    Else {             
        Write-Host "Removed $BackupFolder"        
    }
}

function Setup-LocalFolder {    
    Remove-LocalFolder

    # Create local $BackupFolder 
    New-Item -Path $BackupFolder -ItemType Directory

    # Create local Repos folder
    New-Item -Path $ReposFolder -ItemType Directory

    # Create local ZIP folder 
    New-Item -Path $ZIPFolder -ItemType Directory
}

function Is-ExistAZBlob {
    [cmdletbinding()]
    param(
        $AZBlobName,
        $AZStorageContext
    )
    $blob = Get-AzStorageBlob -Blob $AZBlobName -Container $ContainerName -Context $AZStorageContext -ErrorAction Ignore

    if ($blob) {
        Write-Host "Exist AZBlob $AZBlobName" 
        return $True
    }
    Else {
        Write-Host "Can not find blob $AZBlobName"       
        return $False
    }
}

function Remove-PreviousBlobs {
    [cmdletbinding()]
    param(
        $ContainerName,
        $Pattern,
        $BlobName,
        $AZStorageContext
    )
    Write-Host "Removing previous Blobs"

    Write-Host $(Get-AzStorageBlob -Container $ContainerName -Blob $Pattern -Context $AZStorageContext | Where-Object { $_.Name -ne $BlobName } ).Name

    Get-AzStorageBlob -Container $ContainerName -Blob $Pattern -Context $AZStorageContext | Where-Object { $_.Name -ne $BlobName } | Remove-AzStorageBlob
}

function Remove-OldWeeklyBlobs {
    [cmdletbinding()]
    param(
        $ContainerName,
        $Pattern,
        $BlobName,
        $AZStorageContext
    )
    $RemoveBeforeDate = (Get-Date).Date.AddDays(-$WeeklyBackupRetention)
    Write-Host "Removing old Weekly Blobs, last modified Date < $RemoveBeforeDate"

    Write-Host $(Get-AzStorageBlob -Container $ContainerName -Blob $Pattern -Context $AZStorageContext | Where-Object { $_.LastModified.DateTime -lt $RemoveBeforeDate } ).Name

    Get-AzStorageBlob -Container $ContainerName -Blob $Pattern -Context $AZStorageContext | Where-Object { $_.LastModified.DateTime -lt $RemoveBeforeDate } | Remove-AzStorageBlob
}


function Backup {
    Write-Host "Backup"

    Write-Host "Select AzSubscription"
    Select-AzSubscription -SubscriptionName  $SubscriptionName

    $StorageAccountName = Get-StorageAccountName

    Write-Host "Get AZ Storage Context"
    $AZStorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

    if (Is-WeekEndDate) {
        $backupType = "Weekly"

    }
    Else {
        $backupType = "Daily"
    }
    
    Write-Host "Backup type: $backupType"
    

    # Set the date and time for the backup
    $BackupDate = Get-Date -Format "yyyy_MMM_dd-HH_mm_ss"
    
    $AccessToken = Get-AccessToken

    Write-Host "Get-RepoNames"
    $RepoNames = Get-RepoNames -OrganizationName $OrganizationName -ProjectName $ProjectName -AccessToken $AccessToken
    $totalRepo = $RepoNames.Count
    Write-Host "Total repos: $totalRepo"

    Write-Host "Looping through repository names..."
    $desiredBackupRepos = @(
        "intl-depot",
        "intl-bartender",
        "intl-satellite"
    )
    ForEach ($RepoName in $RepoNames) {
        If (-not ($desiredBackupRepos -contains $RepoName)) {
            continue
        }
        Else {
            Write-Host "================================"
            Write-Host "Starting backup repos $RepoName"
    
            $repoPath = "$ReposFolder/$RepoName.git"
            
            Write-Host "Clone the Git repository to retrieve all branches"
            git clone --mirror "https://$AccessToken@dev.azure.com/$OrganizationName/$ProjectName/_git/$RepoName" $repoPath
    
            Write-Host "Archive the Git repository to create a comprehensive backup"
            $archivePath = "$ZIPFolder/$RepoName-$BackupDate.zip"
            Compress-Archive -Path $repoPath -DestinationPath $archivePath
    
            $FileName = Split-Path $archivePath -leaf
            $AZBlobName = $backupType + "/" + $FileName.Replace("\", "/")
    
            Write-Host "Uploading file to az storage"
            
            Set-AzStorageBlobContent -File $archivePath -Container $ContainerName -Blob $AZBlobName -Context $AZStorageContext -Force | Out-Null
    
            $IsExistBlob = Is-ExistAZBlob -AZBlobName $AZBlobName -AZStorageContext $AZStorageContext
            
            if ($IsExistBlob) {
                Write-Host "Uploading Successfully"
    
                if ($backupType -eq "Daily") {
                    Remove-PreviousBlobs -ContainerName $ContainerName -Pattern "*Daily/$RepoName-20*.zip" -BlobName $AZBlobName -AZStorageContext $AZStorageContext       
                }
    
                if ($backupType -eq "Weekly") {
                    Remove-OldWeeklyBlobs -ContainerName $ContainerName -Pattern "*Weekly/$RepoName-20*.zip" -BlobName $AZBlobName -AZStorageContext $AZStorageContext
                }
                
            }
            Else {
                Write-Host "NOT Exist-AZBlob $AZBlobName"
            }
        }
    }
}

function Get-AccessToken {
    Write-Host "Get-AccessToken"

    $_accessToken = $AccessToken

    if ([string]::IsNullOrEmpty($_accessToken)) { 
        Write-Host "Parameter AccessToken is null or empty"
        Write-Host "Get AccessToken"
        
        $_accessToken = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query "accessToken" --output tsv
        
        if ([string]::IsNullOrEmpty($_accessToken)) {
            Write-Host "accessToken is null or empty"
        }
        else {        
            Write-Host "Successfully get access token"
        }    

    }
    Else {        
        Write-Host "Using Parameter AccessToken"
    }    

    return $_accessToken
}
function  Get-RepoNames {
    [cmdletbinding()]
    param(
        $OrganizationName,
        $ProjectName,
        $AccessToken
    )    
    
    $uri = "https://dev.azure.com/$OrganizationName/$ProjectName/_apis/git/repositories?api-version=7.1-preview.1" 

    $headers = @{
        Authorization = ("Bearer " + $AccessToken)
    }

    Write-Host $uri
    $Repo = (Invoke-RestMethod -Uri $uri -Method Get -UseDefaultCredential -Headers $headers -ContentType "application/json")

    return $Repo.value.name
}

function  Get-StorageAccountName {
    Write-Host "Get-StorageAccountName"
    $storageAccountName = $StorageAccountName
    if ([string]::IsNullOrEmpty($storageAccountName)) { 
        Write-Host "Parameter storageAccountName is null or empty"
        $Names = $(Get-AzStorageAccount -ResourceGroupName $ResourceGroupName).StorageAccountName
        ForEach ($name in $Names) {    
            if ($name -Match 'depotbackup') {
                $storageAccountName = $name
                Write-Host "Get-StorageAccountName successfull"
                break
            }
        }
    }
    Else {        
        Write-Host "Using Parameter StorageAccountName"
    }
    return $storageAccountName
}
function Login() {  
    Write-Host "Az Login"
    $context = Get-AzContext  
  
    if (!$context) {  
        Write-Host "Connect AzAccount" 
        Connect-AzAccount -UseDeviceAuthentication
    }   
    Else {  
        Write-Host " Already connected"  
    }  
}

function Main-Function { 
    Login
    
    Setup-LocalFolder   
    
    Backup

    Remove-LocalFolder
}

Main-Function
param (
    [parameter(HelpMessage="Enter Service Principal Origin ID.")] $SPBackupObjectID
)

function Grant-Git-Permission {
    $projectID = az devops project show --project "International IT Depot" --query "id" --output tsv

    $token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query "accessToken" --output tsv         

    $gitNamespaceId = az devops security permission namespace list --query "[?displayName=='Git Repositories'].{namespaceId:namespaceId}" -o tsv

    # Read Git Repositories permisson
    $allowMask = 2
    $denyMask = 0

    $headers = @{
        Authorization = ("Bearer " + $token)
    }

    Add-SP-To-Security-Group-Using-Rest-API    
    $tenantID = az account tenant list --query "[0].{tenantId:tenantId}" --output tsv
    $descriptor = "Microsoft.VisualStudio.Services.Claims.AadServicePrincipal;$tenantID\\$SPBackupObjectID"

    $bodyInfo = 
    @"
    {
        "token": "repoV2/$projectID", 
        "merge": true, 
        "accessControlEntries": [ 
            { 
                "descriptor": "$descriptor", 
                "allow": "$AllowMask", 
                "deny": "$DenyMask", 
                "extendedinfo": {} 
            } 
        ] 
    }
"@

    $uri = "https://dev.azure.com/costcocloudops/_apis/accesscontrolentries/" + $gitNamespaceId + "?api-version=7.1-preview.1"

    $result = $(Invoke-RestMethod -Method Post -Uri $uri -Body $bodyInfo -Headers $headers -ContentType "application/json").value
    Write-Host $result
}

function Add-SP-To-Security-Group-Using-Rest-API {
    
    $token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query "accessToken" --output tsv

    $headers = @{
        Authorization = ("Bearer " + $token)
    }

    $bodyInfo = 
    @"
    {
        "originId": "$SPBackupObjectID"
    }
"@
    
    $readersGroupDescriptor = az devops security group list --query "graphGroups[?contains(domain, '$projectID') && displayName=='Readers'].{descriptor:descriptor}" -o tsv
    $uri = "https://vssps.dev.azure.com/costcocloudops/_apis/graph/serviceprincipals?groupDescriptors=" + $readersGroupDescriptor + "&api-version=7.1-preview.1"

    $descriptor = $(Invoke-RestMethod -Method Post -Uri $uri -Body $bodyInfo -Headers $headers -ContentType "application/json").descriptor
    return $descriptor
}

function Main-Function {
    az devops configure --defaults organization=https://dev.azure.com/costcocloudops/ project="International IT Depot"
    az devops configure --defaults 
    Grant-Git-Permission
}

Main-Function
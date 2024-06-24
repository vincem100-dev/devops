#!/usr/bin/env pwsh
param(
    $version
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

Write-Information "Version is $version."

if ($version.Contains("-"))
{
    $tagName = "prerelease/$version"
}
else
{
    $tagName = "releasecandidate/$version"
}
Write-Information "Tag name is $tagName."

if ($null -ne $env:BUILD_REQUESTEDFOR) {
    Write-Information "GIT user.name set to $($env:BUILD_REQUESTEDFOR)."
    git config --global user.name "$($env:BUILD_REQUESTEDFOR)"
}
if ($null -ne $env:BUILD_REQUESTEDFOREMAIL) {
    Write-Information "GIT user.email set to $($env:BUILD_REQUESTEDFOREMAIL)."
    git config --global user.email "$($env:BUILD_REQUESTEDFOREMAIL)"
}
git tag -a "$tagName" -m "Built by pipeline $($env:BUILD_DEFINITIONNAME) from branch $($env:BUILD_SOURCEBRANCH)."
git push origin "$tagName"

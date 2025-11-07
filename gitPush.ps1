# === GIT WORKFLOW POWERSHELL CLEAN VERSION ===
# Routine Git interactive : status → add → commit → rebase → push

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Vérification de l'état du dépôt ==="
git status

Write-Host ""
$files = Read-Host "Quels fichiers veux-tu ajouter ? ('.' pour tout ajouter)"
if (-not $files) {
    Write-Host "Aucun fichier sélectionné, arrêt du script."
    exit
}

git add $files

Write-Host ""
Write-Host "Entre ton message de commit (multiligne). Termine par une ligne vide puis Ctrl+Z + Entrée :"
$commitMsg = ""
while ($true) {
    $line = Read-Host
    if ([string]::IsNullOrWhiteSpace($line)) { break }
    $commitMsg += "$line`n"
}

if (-not $commitMsg) {
    Write-Host "Aucun message de commit, arrêt."
    exit
}

git commit -m $commitMsg

$currentBranch = git rev-parse --abbrev-ref HEAD
$upstreamBranch = git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null

if (-not $upstreamBranch) {
    Write-Host ""
    Write-Host "Aucune branche distante liée détectée pour '$currentBranch'."
    Write-Host "Exemple : git branch --set-upstream-to=origin/develop $currentBranch"
    exit
}

$remoteName, $parentBranch = $upstreamBranch -split "/", 2
Write-Host ""
Write-Host "Branche actuelle : $currentBranch"
Write-Host "Branche d'origine détectée : $upstreamBranch"

$doRebase = Read-Host "Souhaites-tu rebase ta branche sur $upstreamBranch ? (y/n)"
if ($doRebase -match '^[yY]$') {
    Write-Host ""
    Write-Host "Rebase sur $upstreamBranch..."
    git fetch $remoteName
    git rebase $upstreamBranch
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Des conflits sont apparus !"
        Write-Host "Résous-les puis exécute la commande suivante :"
        Write-Host 'git add "fichiers_resolus" ; git rebase --continue'
        exit
    }
    Write-Host "Rebase terminé avec succès."
}
else {
    Write-Host "Rebase ignoré."
}

$doPush = Read-Host "Souhaites-tu pousser tes changements ? (y/n)"
if ($doPush -match '^[yY]$') {
    Write-Host ""
    Write-Host "Push sécurisé en cours..."
    git push --force-with-lease
    Write-Host "Push effectué."
}
else {
    Write-Host "Push ignoré."
}

Write-Host ""
Write-Host "=== Routine Git terminée avec succès ==="

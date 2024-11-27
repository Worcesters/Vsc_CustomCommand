# Chemin vers votre fichier settings.json de VSCode
$settingsPath = "$env:APPDATA\Code\User\settings.json"

# Chargement du contenu du fichier settings.json
$jsonContent = Get-Content $settingsPath -Raw

# Conversion du contenu JSON en objet
$settings = $jsonContent | ConvertFrom-Json

# Affichage du message avec mise en forme simple
$borderLine = "-" * 50
Write-Host "+$borderLine+"
Write-Host "| Souhaitez-vous activer la suppression des caractères d'espaces orphelins ? (Y/N) |".PadRight(50) "|"
Write-Host "+$borderLine+"

$response = Read-Host "Votre choix"
if ($response -eq 'Y') {
    $settings.'files.trimTrailingWhitespace' = $true
    Write-Host "La suppression des espaces orphelins a été activée."
} else {
    $settings.'files.trimTrailingWhitespace' = $false
    Write-Host "Aucune modification - la suppression des espaces reste désactivée."
}

# Convertit l'objet modifié en JSON et sauvegarde les modifications dans le fichier settings.json
$settings | ConvertTo-Json -Depth 100 | Out-String | Set-Content $settingsPath -Force -Encoding UTF8

Write-Host "Le fichier settings.json a été mis à jour."

# Boucle pour la restauration des paramètres par défaut
do {
    Write-Host "+$borderLine+"
    Write-Host "| Souhaitez-vous restaurer le paramètre par défaut ? (Y/N) |".PadRight(50) "|"
    Write-Host "+$borderLine+"

    $restoreDefault = Read-Host "Votre choix"
    if ($restoreDefault -eq 'Y') {
        $settings.'files.trimTrailingWhitespace' = $false
        Write-Host "La valeur a été restaurée à false par défaut."
        
        # Convertit l'objet modifié en JSON et sauvegarde les modifications dans le fichier settings.json
        $settings | ConvertTo-Json -Depth 100 | Out-String | Set-Content $settingsPath -Force -Encoding UTF8

        Write-Host "Le fichier settings.json a été mis à jour."
        break
    } else {
        Write-Host "Veuillez répondre 'Y' pour confirmer la restauration aux valeurs par défaut."
    }
} while ($restoreDefault -ne 'Y')

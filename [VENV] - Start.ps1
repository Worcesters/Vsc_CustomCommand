# Demander le nom de l'environnement virtuel
$venvName = Read-Host "Entrez le nom de votre environnement virtuel"
Write-Host "Nom de l'environnement virtuel entré : $venvName"

# Récupérer le chemin du répertoire actuel
$currentDir = Get-Location
Write-Host "Répertoire actuel : $currentDir"

# Construire le chemin vers l'activate script
$venvPath = "$currentDir\$venvName\Scripts\Activate.ps1"
Write-Host "Chemin vers le venv : $venvPath"

# Vérifier si l'environnement est déjà activé
if ($env:VIRTUAL_ENV) {
    Write-Host "L'environnement '$venvName' est déjà actif. Fermeture..."
    exit
} else {
    Write-Host "L'environnement virtuel n'est pas encore actif."
}

# Vérifier si le chemin vers Activate.ps1 existe
if (Test-Path $venvPath) {
    Write-Host "Le chemin '$venvPath' existe. Activation de l'environnement..."

    # Vérifier si PowerShell permet l'exécution de scripts
    $executionPolicy = Get-ExecutionPolicy
    if ($executionPolicy -eq "Restricted" -or $executionPolicy -eq "AllSigned" -or $executionPolicy -eq "RemoteSigned") {
        Write-Host "Changement de la politique d'exécution pour permettre l'activation..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
    }

    # Exécuter l'activation
    & $venvPath

} else {
    Write-Host "Erreur : Le chemin '$venvPath' n'existe pas !"
    Write-Host "Vérifie si le dossier '$venvName' et le fichier 'Activate.ps1' existent."
}

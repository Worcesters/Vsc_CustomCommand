# Exécuter git fetch pour mettre à jour les informations sur les branches distantes

git config --global --add safe.directory '%(prefix)///wsl.localhost/Debian/home/jdidier/dev/itisanoo'

git fetch
git branch -a

# Récupérer le nom de la branche actuelle
$currentBranch = git rev-parse --abbrev-ref HEAD

# Demander à l'utilisateur s'il souhaite voir le graphique pour une branche unique ou entre parent-enfant
$graphOption = Read-Host "Voulez-vous voir le graphique entre parent-enfant (P) ou seulement pour la branche actuelle (B) ?"

if ($graphOption -eq "P") {
    # Demander à l'utilisateur d'entrer le nom de la branche parent (branche "mère")
    $parentBranch = Read-Host "Entrez le nom de la branche parente : "
    
    # Vérifier que la branche parent existe
    if (git show-ref --verify --quiet "refs/heads/$parentBranch") {
        # Exécuter git log avec les options pour afficher le graphique entre les deux branches
        Write-Output "Graphique des commits entre $parentBranch et $currentBranch"
        Write-Output "-----------------------------------------------"
        git log --graph --oneline $parentBranch..$currentBranch
    }
    else {
        Write-Output "La branche parent '$parentBranch' n'existe pas. Assurez-vous d'entrer un nom de branche valide."
    }
}
elseif ($graphOption -eq "B") {
    # Exécuter git log avec les options pour afficher le graphique de la branche actuelle uniquement
    Write-Output "Graphique des commits pour la branche $currentBranch"
    Write-Output "-----------------------------------------------"
    git log --graph --oneline $currentBranch
}
else {
    Write-Output "Option invalide. Veuillez entrer 'P' pour parent-enfant ou 'B' pour branche unique."
}

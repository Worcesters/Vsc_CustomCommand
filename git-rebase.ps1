# Récupérer le nom de la branche actuelle
$currentBranch = git rev-parse --abbrev-ref HEAD

# Exécuter le rebase avec la branche de référence récupérée
git rebase $currentBranch@{u}

$aGit = @{
    ". git pull" = "    Met a jour le referentiel local avec les modifications du referentiel distant."
    ". git fetch" = "    Recupere les references des branches distantes sans fusionner avec le repertoire de travail."
    ". git push" = "    Envoie les modifications locales vers le referentiel distant."
    ". git add" = "    Ajoute des modifications au prochain commit (index/staging area)."
    ". git commit (-m)" = "    Cree un nouveau commit avec les modifications ajoutees a l'index, et ajoute un message de commit."
    ". git status" = "    Affiche l'etat actuel du repertoire de travail (fichiers modifies, ajoutes, supprimes, etc.)."
    ". git checkout ( . , -b )" = "    Change de branche ou restaure les fichiers du repertoire de travail a leur etat precedent. Utilisez '-b' pour creer une nouvelle branche."
    ". git rebase <nom-de-votre-branche>" = "    Reapplique les commits d'une branche sur une autre branche."
    ". git log --graph --oneline <nom-de-votre-branche>" = "    Affiche l'historique des commits de la branche specifiee avec une representation graphique."
}

foreach ($key in $aGit.Keys) {
    Write-Host $key -ForegroundColor "Blue"
    Write-Host $aGit[$key] -ForegroundColor "Yellow"
    Write-Host "" # Ajoute un espace à la fin de chaque boucle
}

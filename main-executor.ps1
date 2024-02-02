# Demande à l'utilisateur si le fichier main.py est dans l'emplacement actuel
$response = Read-Host "Le fichier main.py se trouve-t-il dans l'emplacement actuel ? (y/n)"

# Vérifie la réponse de l'utilisateur
if ($response -eq 'y') {
    # Si oui, exécute main.py depuis l'emplacement actuel
    python .\main.py
} else {
    # Si non, demande le chemin complet vers main.py
    $path = Read-Host "Veuillez entrer le chemin complet vers main.py"
    python $path
}

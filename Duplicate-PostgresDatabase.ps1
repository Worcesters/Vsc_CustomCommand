# Duplicate-PostgresDatabase.ps1
# Script pour dupliquer une base de données PostgreSQL dans un conteneur Docker

# Fonction pour afficher du texte en couleur
function Write-ColorText {
    param (
        [string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )

    Write-Host $Text -ForegroundColor $Color
}

# Fonction pour lister les conteneurs Docker
function Get-DockerContainers {
    Write-ColorText "Recherche des conteneurs Docker en cours d'exécution..." Cyan

    try {
        # Exécuter docker ps et stocker les informations dans une variable
        $containersInfo = docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Image}}"

        # Afficher directement le résultat pour vérification
        Write-ColorText "`nSortie brute de docker ps:" Yellow
        $containersInfo | ForEach-Object { Write-Host $_ }

        # Si aucun conteneur n'est en cours d'exécution
        if ($containersInfo.Count -le 1) {
            Write-ColorText "Aucun conteneur Docker en cours d'exécution!" Red
            exit
        }

        # Créer une liste d'objets conteneur
        $containerList = @()
        $index = 1

        # Ignorer la ligne d'en-tête
        for ($i = 1; $i -lt $containersInfo.Count; $i++) {
            $line = $containersInfo[$i]
            if ($line.Trim()) {
                $columns = $line -split '\s+'

                # Les 12 premiers caractères sont généralement l'ID
                $id = $columns[0]

                # Le nom est généralement le deuxième élément après la division
                $name = $columns[1]

                # L'image est le troisième élément
                $image = $columns[2]

                $containerObj = [PSCustomObject]@{
                    Index = $index
                    ID    = $id
                    Name  = $name
                    Image = $image
                }

                $containerList += $containerObj
                $index++
            }
        }

        # Afficher les conteneurs dans un format tabulaire
        Write-ColorText "`nConteneurs Docker disponibles:" Green
        $containerList | Format-Table -Property Index, ID, Name, Image

        return $containerList
    }
    catch {
        Write-ColorText "Erreur lors de la récupération des conteneurs Docker: $_" Red
        # Afficher l'erreur détaillée pour le débogage
        Write-ColorText $_.Exception.Message Red
        exit
    }
}

# Fonction pour sélectionner un conteneur
function Select-Container {
    param (
        [array]$ContainerList
    )

    $selectedContainer = $null
    while ($null -eq $selectedContainer) {
        try {
            $containerInput = Read-Host "Entrez l'ID ou l'index du conteneur de base de données"

            # Vérifier si l'entrée est un nombre (index)
            if ($containerInput -match '^\d+$' -and [int]$containerInput -ge 1 -and [int]$containerInput -le $ContainerList.Count) {
                $selectedContainer = $ContainerList[[int]$containerInput - 1]
            }
            # Sinon, chercher par ID
            else {
                $selectedContainer = $ContainerList | Where-Object { $_.ID -like "$containerInput*" } | Select-Object -First 1

                if ($null -eq $selectedContainer) {
                    Write-ColorText "Aucun conteneur trouvé avec cet ID. Veuillez entrer un ID valide ou un index (1-$($ContainerList.Count))" Yellow
                }
            }
        }
        catch {
            Write-ColorText "Entrée invalide. Veuillez entrer un ID de conteneur valide ou un index (1-$($ContainerList.Count))" Yellow
        }
    }

    return $selectedContainer
}

# Fonction pour lister les bases de données dans un conteneur
function Get-Databases {
    param (
        [string]$ContainerID,
        [string]$CustomUser = ""
    )

    Write-ColorText "`nRecherche des bases de données PostgreSQL..." Cyan

    try {
        # Utiliser l'utilisateur personnalisé ou demander à l'utilisateur
        if ([string]::IsNullOrEmpty($CustomUser)) {
            $pgUser = Read-Host "Entrez le nom d'utilisateur PostgreSQL (par défaut: itisanoo)"
            if ([string]::IsNullOrEmpty($pgUser)) {
                $pgUser = "itisanoo"
            }
        }
        else {
            $pgUser = $CustomUser
        }

        Write-ColorText "Utilisation de l'utilisateur PostgreSQL: $pgUser" Yellow

        # Afficher toutes les bases de données, y compris les templates
        Write-ColorText "Récupération de la liste complète des bases de données..." Yellow

        # Exécuter une commande pour afficher toutes les bases de données (sauf les templates)
        $output = docker exec $ContainerID psql -U $pgUser -c '\l' postgres

        # Afficher la sortie brute pour diagnostic
        Write-ColorText "Liste des bases de données (sortie brute):" Yellow
        $output | ForEach-Object { Write-Host $_ }

        # Maintenant, récupérer les noms des bases de données dans un format plus facile à traiter
        $query = "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;"
        $databaseOutput = docker exec $ContainerID psql -U $pgUser -t -c "$query" postgres

        $databaseList = @()
        $index = 1

        foreach ($line in $databaseOutput) {
            $dbName = $line.Trim()
            if (-not [string]::IsNullOrEmpty($dbName)) {
                $databaseObj = [PSCustomObject]@{
                    Index = $index
                    Name  = $dbName
                }
                $databaseList += $databaseObj
                $index++
            }
        }

        # Ne pas afficher ici, car Select-Database le fera
        return $databaseList
    }
    catch {
        Write-ColorText "Erreur lors de la récupération des bases de données: $_" Red
        exit
    }
}
# Fonction pour sélectionner une base de données
function Select-Database {
    param (
        [array]$DatabaseList
    )

    $selectedDatabase = $null

    while ($null -eq $selectedDatabase) {
        $dbInput = Read-Host "Entrez le nom ou l'index de la base de données à dupliquer"

        # Vérifier si l'entrée est un nombre (index)
        if ($dbInput -match '^\d+$' -and [int]$dbInput -ge 1 -and [int]$dbInput -le $DatabaseList.Count) {
            $selectedDatabase = $DatabaseList[[int]$dbInput - 1]
        }
        # Recherche exacte par nom
        else {
            $exactMatch = $DatabaseList | Where-Object { $_.Name -eq $dbInput }
            if ($exactMatch) {
                $selectedDatabase = $exactMatch
            }
            else {
                # Recherche partielle
                $partialMatch = $DatabaseList | Where-Object { $_.Name -like "*$dbInput*" }
                if ($partialMatch.Count -gt 0) {
                    $selectedDatabase = $partialMatch[0]
                }
                else {
                    Write-ColorText "Aucune base de données trouvée avec ce nom. Veuillez entrer un nom exact ou un index (1-$($DatabaseList.Count))" Yellow
                }
            }
        }
    }

    return $selectedDatabase
}

# Fonction pour dupliquer la base de données
function Duplicate-Database {
    param (
        [string]$ContainerID,
        [string]$SourceDB,
        [string]$PgUser = "itisanoo"
    )

    $targetDB = Read-Host "Entrez le nom de la nouvelle base de données"

    if (-not $targetDB) {
        Write-ColorText "Le nom de la base de données ne peut pas être vide!" Red
        exit
    }

    # Demander l'utilisateur PostgreSQL si nécessaire
    if ([string]::IsNullOrEmpty($PgUser)) {
        $PgUser = Read-Host "Entrez le nom d'utilisateur PostgreSQL (par défaut: itisanoo)"
        if ([string]::IsNullOrEmpty($PgUser)) {
            $PgUser = "itisanoo"
        }
    }

    Write-ColorText "`nDéconnexion des utilisateurs de la base $targetDB..." Cyan
    docker exec $ContainerID psql -U $PgUser postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$targetDB' AND pid <> pg_backend_pid();"

    Write-ColorText "Suppression de la base $targetDB si elle existe..." Cyan
    docker exec $ContainerID psql -U $PgUser postgres -c "DROP DATABASE IF EXISTS $targetDB;"

    Write-ColorText "Création de la base $targetDB à partir de $SourceDB..." Cyan
    $result = docker exec $ContainerID psql -U $PgUser postgres -c "CREATE DATABASE $targetDB WITH TEMPLATE $SourceDB;"

    if ($LASTEXITCODE -eq 0) {
        Write-ColorText "`nLa base de données $targetDB a été créée avec succès!" Green
    }
    else {
        Write-ColorText "`nErreur lors de la création de la base de données!" Red
        Write-ColorText $result Red
    }
}

# Programme principal
try {
    Write-ColorText "=== Script de duplication de base de données PostgreSQL ===" Magenta

    # Étape 1: Lister les conteneurs Docker
    $containers = Get-DockerContainers

    # Étape 2: Sélectionner un conteneur
    $selectedContainer = Select-Container -ContainerList $containers
    Write-ColorText "`nConteneur sélectionné: $($selectedContainer.Name)" Green

    # Étape 3: Demander le nom d'utilisateur PostgreSQL
    $pgUser = Read-Host "Entrez le nom d'utilisateur PostgreSQL (par défaut: itisanoo)"
    if ([string]::IsNullOrEmpty($pgUser)) {
        $pgUser = "itisanoo"
    }

    # Étape 4: Lister les bases de données
    $databases = Get-Databases -ContainerID $selectedContainer.ID -CustomUser $pgUser

    # Étape 5: Sélectionner une base de données
    $selectedDatabase = Select-Database -DatabaseList $databases
    Write-ColorText "`nBase de données sélectionnée: $($selectedDatabase.Name)" Green

    # Étape 6: Dupliquer la base de données
    Duplicate-Database -ContainerID $selectedContainer.ID -SourceDB $selectedDatabase.Name -PgUser $pgUser

}
catch {
    Write-ColorText "Une erreur est survenue: $_" Red
}
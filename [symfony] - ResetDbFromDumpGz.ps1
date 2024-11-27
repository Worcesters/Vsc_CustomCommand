# Demande le nom ou l'identifiant du conteneur Docker
$containerName = Read-Host "Entrez le nom ou l'identifiant du conteneur Docker"

# Exécute le conteneur Docker
docker start $containerName

# Exécute les commandes PHP
docker exec -it $containerName php bin/console d:d:d --force
docker exec -it $containerName php bin/console d:d:c

# Demande le chemin du dump
$dumpPath = Read-Host "Entrez le chemin de votre dump"

# Demande si le dump est compressé
$compressed = Read-Host "Est-ce que le dump est compressé ? (o/n)"
if ($compressed -eq "o") {
    # Demande le format de compression
    $compressionFormat = Read-Host "Quel est le format de compression ? (zip, gzip, etc.)"

    # Décompresse le dump
    switch ($compressionFormat) {
        "zip" {
            docker exec -it $containerName unzip $dumpPath -d /tmp
            $dumpPath = "/tmp/" + (Get-Item $dumpPath).BaseName
        }
        "gzip" {
            docker exec -it $containerName gzip -d $dumpPath
            $dumpPath = $dumpPath -replace "\.gz$"
        }
        default {
            Write-Host "Format de compression non pris en charge"
            exit
        }
    }
}

# Exécute la commande pour importer le dump
docker exec -it $containerName php bin/console doctrine:database:import $dumpPath


#POUR ITISANOO
#gunzip < ../itisanoo_re7_20231124.sql.gz | docker exec -i itisanoodb64 psql -U itisanoo itisanoo
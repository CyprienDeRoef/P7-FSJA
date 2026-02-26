# Plan CI/CD – MicroCRM

## 1. Plan de testing périodique

### Types de tests

**Backend (Spring Boot / Gradle)**

- `MicroCRMApplicationTests` : test de démarrage du contexte Spring (smoke test).
- `PersonRepositoryIntegrationTest` : test d'intégration de la couche JPA, vérifie que la recherche par e-mail retourne bien la bonne entité.
- Exécutés via JUnit 5 avec `./gradlew test`.

**Frontend (Angular / Karma + Jasmine)**

- Tests unitaires des composants et services Angular (`*.spec.ts`).
- Exécutés via `ng test --watch=false --browsers=ChromeHeadlessNoSandbox`.

### Déclencheurs

| Événement                         | Action                                                      |
| --------------------------------- | ----------------------------------------------------------- |
| Push sur n'importe quelle branche | Compilation + exécution de tous les tests                   |
| Pull Request vers `main`          | Compilation + tests + analyse de qualité (SonarQube)        |
| Merge sur `main`                  | Compilation + tests + build Docker + publication de l'image |

### Objectifs

- **Validation fonctionnelle** : s'assurer que les fonctionnalités principales (persistance, API REST, affichage Angular) fonctionnent correctement.
- **Non-régression** : détecter immédiatement si un nouveau commit casse un comportement existant.
- **Qualité de code** : mesurer la couverture de tests et identifier les mauvaises pratiques.

---

## 2. Plan de sécurité

### Rôle de SonarQube Cloud

SonarQube Cloud est intégré dans le pipeline CI pour analyser statiquement le code source backend (Java) et frontend (TypeScript). Il est déclenché à chaque pull request et à chaque push sur `main`.

### Types de problèmes surveillés

| Catégorie          | Exemples                                                                       |
| ------------------ | ------------------------------------------------------------------------------ |
| **Vulnérabilités** | Injections SQL, exposition de données sensibles, désérialisation non sécurisée |
| **Bugs**           | NullPointerException potentielle, mauvaise gestion des exceptions              |
| **Code smells**    | Méthodes trop longues, code dupliqué, nommage peu clair                        |
| **Couverture**     | Pourcentage du code couvert par les tests unitaires                            |

### Bonnes pratiques CI

- **Secrets** : les credentials (tokens SonarQube, identifiants Docker Hub) sont stockés dans les variables secrètes du pipeline CI (ex. GitHub Actions Secrets), jamais en clair dans le code.
- **Dépendances** : utilisation de `npm ci` (lockfile strict) côté frontend et de Gradle avec versions fixées côté backend pour garantir des builds reproductibles.
- **Branches protégées** : les merges vers `main` nécessitent que le pipeline CI passe entièrement.

---

## 3. Principes de conteneurisation et de déploiement

### Rôle du Dockerfile

Le `Dockerfile` à la racine du projet utilise un **build multi-étapes** :

| Étape         | Rôle                                                                 | Image de base                   |
| ------------- | -------------------------------------------------------------------- | ------------------------------- |
| `front-build` | Compile l'application Angular (`npm ci` + `ng build --optimization`) | `node:20-alpine`                |
| `back-build`  | Compile l'application Spring Boot (`gradle build`)                   | `gradle:8.7-jdk17`              |
| `front`       | Sert les fichiers statiques Angular via Caddy                        | `caddy:2-alpine`                |
| `back`        | Exécute le JAR Spring Boot                                           | `eclipse-temurin:17-jre-alpine` |
| `standalone`  | Lance les deux services dans un seul conteneur via Supervisord       | `alpine:3.20`                   |

**Justification des images de base :**

| Image                           | Raison du choix                                                                                                                                        |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `node:20-alpine`                | Version LTS pinned, base Alpine minimale, distribution officielle Node.js                                                                              |
| `gradle:8.7-jdk17`              | Image officielle Gradle, JDK 17 = version cible du projet                                                                                              |
| `caddy:2-alpine`                | Distribution officielle Caddy, plus légère qu'Alpine + apk, pas d'outil inutile                                                                        |
| `eclipse-temurin:17-jre-alpine` | Distribution OpenJDK officielle (Adoptium/Eclipse Foundation), JRE uniquement (pas JDK complet), Alpine minimal, cohérent avec JDK 17 utilisé en build |

L'approche multi-étapes évite d'embarquer les outils de build (Node, Gradle, JDK complet) dans l'image finale, réduisant ainsi sa taille et sa surface d'attaque.

### Rôle de docker-compose

Le fichier `docker-compose.yml` à la racine du projet permet de :

- Démarrer les services `front` (port 80) et `back` (port 8080) séparément avec un seul `docker-compose up`.
- Chaque service est construit à partir d'une étape cible (`target`) du Dockerfile multi-étapes.
- L'application Angular communique avec le backend via `http://localhost:8080` — cela fonctionne naturellement car le code Angular s'exécute dans le navigateur du client, qui accède directement au port 8080 exposé sur la machine hôte.

### Stratégie de déploiement

À chaque merge sur `main`, un job CD (`publish`) se déclenche **uniquement après la réussite des deux jobs de tests**. Il construit les images Docker `front` et `back` et les publie sur **GitHub Container Registry (ghcr.io)**.

Chaque image est taguée avec :

- `latest` — pour récupérer facilement la dernière version stable.
- le SHA du commit (`github.sha`) — pour garantir la traçabilité et permettre un rollback précis.

Les images publiées sont ensuite disponibles à :

- `ghcr.io/<owner>/microcrm-back:latest`
- `ghcr.io/<owner>/microcrm-front:latest`

---

## 4. Implémentation GitHub Actions

### Fichier de workflow

Le pipeline est défini dans `.github/workflows/ci.yml` et contient deux jobs indépendants qui s'exécutent en parallèle.

### Choix techniques

| Choix                                        | Justification                                                                                                    |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `actions/checkout@v4` avec `fetch-depth: 0`  | La profondeur complète de l'historique Git est requise par SonarQube pour calculer les métriques de code nouveau |
| `actions/setup-java@v4` avec `cache: gradle` | Met en cache le cache Gradle entre les runs pour accélérer les builds                                            |
| `actions/setup-node@v4` avec `cache: npm`    | Met en cache `node_modules` via `package-lock.json` pour éviter de retélécharger les dépendances                 |
| `npm ci` plutôt que `npm install`            | Installe exactement les versions du lockfile, garantissant un build reproductible                                |
| `ChromeHeadlessNoSandbox`                    | Permet d'exécuter Karma dans un environnement CI sans interface graphique ni droits root                         |
| Plugin `jacoco` (Gradle)                     | Génère un rapport de couverture XML exploité par SonarQube pour afficher la couverture dans le dashboard         |
| `SONAR_TOKEN` en secret GitHub               | Le token SonarCloud n'est jamais exposé dans le code source                                                      |
| `actions/upload-artifact@v4`                 | Publie les rapports de tests dans l'onglet "Artifacts" du run GitHub Actions pour consultation                   |

### Configuration SonarQube requise

Avant d'utiliser le pipeline, deux valeurs doivent être renseignées :

1. Dans `back/build.gradle`, remplacer `YOUR_SONAR_PROJECT_KEY` et `YOUR_SONAR_ORGANIZATION` par les valeurs de votre projet sur [sonarcloud.io](https://sonarcloud.io).
2. Dans les **Secrets** du dépôt GitHub (`Settings > Secrets and variables > Actions`), créer un secret `SONAR_TOKEN` avec le token généré depuis SonarCloud.

---

## 5. Commandes clés du projet

| Commande                                                       | Objectif                                                            | Définie dans                                  | Exécutée à                      |
| -------------------------------------------------------------- | ------------------------------------------------------------------- | --------------------------------------------- | ------------------------------- |
| `./gradlew test`                                               | Lance tous les tests JUnit du backend                               | `back/build.gradle` (bloc `test`)             | CI (`test-back`), local         |
| `./gradlew jacocoTestReport`                                   | Génère le rapport de couverture XML pour SonarQube                  | `back/build.gradle` (bloc `jacocoTestReport`) | CI (`test-back`)                |
| `./gradlew sonar`                                              | Envoie l'analyse statique vers SonarCloud                           | `back/build.gradle` (bloc `sonar`)            | CI (`test-back`)                |
| `npx ng test --watch=false --browsers=ChromeHeadlessNoSandbox` | Lance les tests Karma/Jasmine du frontend sans navigateur graphique | `front/package.json` (script `test`)          | CI (`test-front`), local        |
| `npm ci`                                                       | Installe les dépendances Node.js depuis le lockfile (reproductible) | `front/package-lock.json`                     | CI (`test-front`), build Docker |
| `docker build --target back`                                   | Construit uniquement l'image du backend                             | `Dockerfile` (étape `back`)                   | CI/CD (`publish`), local        |
| `docker build --target front`                                  | Construit uniquement l'image du frontend                            | `Dockerfile` (étape `front`)                  | CI/CD (`publish`), local        |
| `docker compose up`                                            | Lance les services `front` et `back` localement                     | `docker-compose.yml`                          | Local uniquement                |

---

## 6. Plan de déploiement

### Prérequis techniques

| Prérequis | Détail |
| --------- | ------ |
| Docker Engine ≥ 24 | Nécessaire pour construire et exécuter les images |
| Docker Compose v2 | Orchestration des services `front` et `back` |
| Accès à GHCR | Token GitHub avec scope `read:packages` pour `docker pull` |
| Port 80 disponible | Servi par Caddy (frontend Angular) |
| Port 8080 disponible | Servi par Spring Boot (backend REST) |
| JVM non requise sur l'hôte | Le JRE est embarqué dans l'image `back` (`eclipse-temurin:17-jre-alpine`) |

### Ordre de déploiement

Le déploiement suit une séquence stricte car le frontend dépend du backend pour les appels API :

```
1. (CI/CD) Tests back + tests front  ─┐
                                       ├─ en parallèle
2. (CI/CD) Analyse SonarCloud        ─┘
3. (CI/CD) Build & push images Docker (front + back) vers GHCR
4. (Serveur cible) docker compose pull   ← récupère les nouvelles images
5. (Serveur cible) docker compose up -d  ← redémarre les conteneurs
```

Le fichier `docker-compose.yml` définit `depends_on: back` pour le service `front`, garantissant que le conteneur backend est démarré avant le frontend.

### Procédure de déploiement manuel (opérateur)

```bash
# 1. Se connecter au registry si non encore authentifié
echo $GHCR_PAT | docker login ghcr.io -u <github-user> --password-stdin

# 2. Récupérer les dernières images publiées par le pipeline CI/CD
docker compose pull

# 3. Redémarrer les services en arrière-plan
docker compose up -d

# 4. Vérifier que les conteneurs sont bien démarrés
docker compose ps
docker compose logs --tail=50
```

### Procédure de rollback

En cas de régression détectée après déploiement, le rollback consiste à pointer sur le tag SHA du dernier déploiement stable :

```bash
# Identifier le SHA du dernier déploiement stable dans l'historique GHCR ou GitHub Actions
STABLE_SHA=<commit-sha-stable>

# Récupérer les images taguées avec ce SHA
docker pull ghcr.io/<owner>/microcrm-back:${STABLE_SHA}
docker pull ghcr.io/<owner>/microcrm-front:${STABLE_SHA}

# Redémarrer avec les images stables (surcharger les tags dans docker-compose.yml ou via env vars)
BACK_TAG=${STABLE_SHA} FRONT_TAG=${STABLE_SHA} docker compose up -d
```

**Justification :** chaque image est taguée avec le SHA du commit (`github.sha`) en plus de `latest`, ce qui permet un rollback précis sans reconstruire. Ce mécanisme adresse directement le point d'amélioration *Time to Restore* identifié dans les KPI DORA (actuellement niveau Medium, ~15–30 min).

---

## 7. Plan de sauvegarde

### Données et configurations à sauvegarder

| Élément | Emplacement | Criticité | Raison |
| ------- | ----------- | --------- | ------ |
| Base de données H2 (fichier, si persistée) | Volume Docker ou `./data/` | Haute | Données métier (personnes, organisations) |
| `application.properties` | `back/src/main/resources/` | Haute | Paramètres runtime (logs, profil Spring) |
| `docker-compose.yml` | Racine du projet | Haute | Définition de l'infrastructure locale |
| `Dockerfile` | Racine du projet | Haute | Reproducibilité des images |
| `misc/docker/Caddyfile` | `misc/docker/` | Moyenne | Configuration du reverse proxy frontend |
| `elk/logstash/pipeline/logstash.conf` | `elk/logstash/pipeline/` | Moyenne | Pipeline d'ingestion des logs ELK |
| `elk/logstash/config/logstash.yml` | `elk/logstash/config/` | Moyenne | Configuration de l'agent Logstash |
| Secrets CI (GitHub Secrets) | GitHub > Settings > Secrets | Haute | `SONAR_TOKEN`, `GHCR_PAT` — à documenter dans un gestionnaire de secrets hors code |

> **Note sur la base de données :** dans l'état actuel, H2 fonctionne en mémoire — les données sont perdues à chaque redémarrage et aucune sauvegarde de données n'est nécessaire. Si `spring.datasource.url=jdbc:h2:file:./data/microcrm` est ajouté à `application.properties`, les données sont persistées dans un fichier et la procédure ci-dessous s'applique.

### Fréquence de sauvegarde

| Type | Fréquence | Déclencheur |
| ---- | --------- | ----------- |
| Fichier H2 (si persisté) | Quotidienne | Tâche cron (hors heures de pointe) |
| Fichiers de configuration | À chaque modification | Commit Git (versioning natif) |
| Secrets CI | À chaque rotation | Documentation manuelle dans un coffre (ex. Bitwarden, HashiCorp Vault) |

### Méthode

**Configuration et code source** : la sauvegarde est assurée nativement par **Git** (dépôt GitHub). Tout fichier versionné est sauvegardé à chaque push — aucune procédure supplémentaire n'est nécessaire pour ces fichiers.

**Fichier de base de données H2 (si activé)** :

```bash
# Exemple de script de sauvegarde quotidienne du fichier H2
cp ./data/microcrm.mv.db ./backups/microcrm-$(date +%Y%m%d).mv.db

# Conservation sur 7 jours glissants
find ./backups/ -name "microcrm-*.mv.db" -mtime +7 -delete
```

**Justification des choix :**
- Git couvre l'essentiel des sauvegardes (code + config), sans surcharge opérationnelle.
- La base H2 en mémoire ne requiert pas de sauvegarde dans l'état actuel du projet ; la stratégie évolue si l'application migre vers PostgreSQL.
- Les secrets sont gérés hors dépôt (GitHub Secrets), conformément à la politique de sécurité définie en section 2.

---

## 8. Plan de mise à jour

### Mise à jour de l'application

La mise à jour suit le même flux que le déploiement initial, piloté par le pipeline CI/CD :

```
1. Développeur crée une branche feature/* ou fix/*
2. Commit + push → pipeline CI déclenché (tests + SonarCloud)
3. Pull Request vers main → revue de code + validation CI
4. Merge sur main → job publish déclenché → nouvelles images taguées et poussées sur GHCR
5. Sur le serveur : docker compose pull && docker compose up -d
```

Aucune intervention manuelle n'est requise entre l'étape 1 et l'étape 4 : le pipeline garantit qu'aucune régression n'atteint `main`.

### Gestion des dépendances

#### Backend (Gradle / Java)

| Pratique | Détail |
| -------- | ------ |
| Versions fixées | Toutes les dépendances déclarées avec une version explicite dans `build.gradle` |
| Détection des mises à jour | `./gradlew dependencyUpdates` (plugin Gradle Versions) liste les nouvelles versions disponibles |
| Processus | Mise à jour dans une branche dédiée → PR → pipeline CI valide → merge |
| JDK | Version fixée dans `build.gradle` (`sourceCompatibility = '17'`) et dans l'image Docker (`gradle:8.7-jdk17`) ; migrer les deux ensemble |

#### Frontend (npm / Angular)

| Pratique | Détail |
| -------- | ------ |
| Lockfile strict | `package-lock.json` versionné ; `npm ci` utilisé en CI pour une installation reproductible |
| Mise à jour mineure | `npm update` + commit du `package-lock.json` mis à jour |
| Mise à jour majeure Angular | `ng update @angular/core @angular/cli` en suivant le guide de migration Angular |
| Audit de sécurité | `npm audit` à chaque mise à jour ; bloquer en CI si vulnérabilité critique (`npm audit --audit-level=critical`) |

#### Images Docker de base

| Image | Stratégie de mise à jour |
| ----- | ------------------------ |
| `node:20-alpine` | Suivre les releases LTS Node.js ; migrer vers `node:22-alpine` lors de la prochaine LTS |
| `gradle:8.7-jdk17` | Mettre à jour en cohérence avec `sourceCompatibility` dans `build.gradle` |
| `caddy:2-alpine` | Mettre à jour à chaque release de sécurité Caddy |
| `eclipse-temurin:17-jre-alpine` | Synchroniser avec la version JDK du build ; patcher lors des releases de sécurité JDK |
| `alpine:3.20` | Mettre à jour à chaque release Alpine LTS |

### Bonnes pratiques

1. **Ne jamais utiliser le tag `latest`** dans le `Dockerfile` : utiliser des tags de version explicites pour garantir la reproductibilité des builds.
2. **Mettre à jour les dépendances dans une branche dédiée** : le pipeline CI valide la compatibilité avant le merge.
3. **Activer Dependabot** sur le dépôt GitHub pour recevoir automatiquement des PR de mise à jour de sécurité.
4. **SonarCloud comme filet de sécurité** : après chaque mise à jour majeure, l'analyse statique détecte les nouveaux problèmes de qualité éventuellement introduits.
5. **Conserver le tag SHA** des images en production : permet un rollback immédiat vers la version précédente sans reconstruire (cf. section 6 — Plan de déploiement).

### Lien avec les KPI DORA

| KPI | Impact de la mise à jour |
| --- | ------------------------ |
| **Change Failure Rate** | Une mise à jour de dépendance non testée peut introduire une régression → toujours passer par le pipeline CI |
| **Time to Restore** | Si une mise à jour casse la production, le tag SHA permet un rollback en < 5 min |
| **Lead Time** | Les mises à jour mineures n'allongent pas le pipeline (cache Gradle/npm actif) |

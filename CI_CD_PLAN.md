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

| Commande | Objectif | Définie dans | Exécutée à |
|----------|----------|--------------|------------|
| `./gradlew test` | Lance tous les tests JUnit du backend | `back/build.gradle` (bloc `test`) | CI (`test-back`), local |
| `./gradlew jacocoTestReport` | Génère le rapport de couverture XML pour SonarQube | `back/build.gradle` (bloc `jacocoTestReport`) | CI (`test-back`) |
| `./gradlew sonar` | Envoie l'analyse statique vers SonarCloud | `back/build.gradle` (bloc `sonar`) | CI (`test-back`) |
| `npx ng test --watch=false --browsers=ChromeHeadlessNoSandbox` | Lance les tests Karma/Jasmine du frontend sans navigateur graphique | `front/package.json` (script `test`) | CI (`test-front`), local |
| `npm ci` | Installe les dépendances Node.js depuis le lockfile (reproductible) | `front/package-lock.json` | CI (`test-front`), build Docker |
| `docker build --target back` | Construit uniquement l'image du backend | `Dockerfile` (étape `back`) | CI/CD (`publish`), local |
| `docker build --target front` | Construit uniquement l'image du frontend | `Dockerfile` (étape `front`) | CI/CD (`publish`), local |
| `docker compose up` | Lance les services `front` et `back` localement | `docker-compose.yml` | Local uniquement |

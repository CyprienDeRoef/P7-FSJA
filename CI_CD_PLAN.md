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

| Étape         | Rôle                                                                                                     |
| ------------- | -------------------------------------------------------------------------------------------------------- |
| `front-build` | Compile l'application Angular (`npm ci` + `ng build --optimization`)                                     |
| `back-build`  | Compile l'application Spring Boot (`gradle build`)                                                       |
| `front`       | Image Alpine légère avec Caddy pour servir les fichiers statiques Angular                                |
| `back`        | Image Alpine légère avec OpenJDK 21 pour exécuter le JAR Spring Boot                                     |
| `standalone`  | Image combinée utilisant Supervisord pour lancer les deux services (front + back) dans un seul conteneur |

L'approche multi-étapes évite d'embarquer les outils de build (Node, Gradle, JDK complet) dans l'image finale, réduisant ainsi sa taille et sa surface d'attaque.

### Rôle de docker-compose

Un fichier `docker-compose.yml` (à créer) permettrait de :

- Démarrer les services `front` et `back` séparément avec un seul `docker-compose up`.
- Configurer facilement le réseau entre les conteneurs et les variables d'environnement.
- Simplifier les tests locaux de l'image conteneurisée.

### Stratégie de déploiement

1. **Publication d'images** : à chaque merge sur `main`, le pipeline CI/CD construit les images Docker (`front`, `back`, `standalone`) et les publie sur un registre (ex. Docker Hub ou GitHub Container Registry) avec le tag `latest` et un tag versionné.
2. **Déploiement automatisé** : une étape de déploiement (CD) peut ensuite pousser la nouvelle image vers l'environnement cible (serveur VPS, cloud) en exécutant un `docker pull` + `docker run` ou en déclenchant un webhook.

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

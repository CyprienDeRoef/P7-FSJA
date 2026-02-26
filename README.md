<p align="center">
   <img src="./front/src/favicon.png" width="192px" />
</p>

# MicroCRM — P7 CI/CD Full-Stack

Application de démonstration CRM (gestion de contacts et d''organisations) servant de socle au module **P7 — Intégration et déploiement continu d''une application Full-Stack**.

![Page d''accueil](./misc/screenshots/screenshot_1.png)
![Édition d''un individu](./misc/screenshots/screenshot_2.png)

---

## Stack technique

| Composant         | Technologie                                       |
| ----------------- | ------------------------------------------------- |
| Backend           | Java 17 · Spring Boot 3 · Gradle · H2 (in-memory) |
| Frontend          | Angular 17 · TypeScript · Jest                    |
| Conteneurisation  | Docker (multi-stage) · Docker Compose             |
| Reverse proxy     | Caddy 2                                           |
| CI/CD             | GitHub Actions                                    |
| Qualité de code   | SonarCloud · JaCoCo                               |
| Monitoring / Logs | ELK Stack (Elasticsearch · Logstash · Kibana)     |

---

## Démarrage rapide (Docker Compose)

> Prérequis : Docker Engine ≥ 24 et Docker Compose v2.

```bash
docker compose up --build
```

| Service                      | URL                   |
| ---------------------------- | --------------------- |
| Frontend (Angular via Caddy) | http://localhost:80   |
| Backend (Spring Boot REST)   | http://localhost:8080 |

---

## Démarrage sans Docker

### Backend

```bash
cd back
./gradlew build
java -jar build/libs/microcrm-0.0.1-SNAPSHOT.jar
```

### Frontend

```bash
cd front
npm install
npx @angular/cli serve
```

Ouvrir http://localhost:4200.

---

## Tests

### Backend (JUnit 5 + JaCoCo)

```bash
cd back
./gradlew test             # exécute les tests
./gradlew jacocoTestReport # génère le rapport de couverture
```

### Frontend (Jest)

```bash
cd front
npx ng test --watch=false --browsers=ChromeHeadlessNoSandbox
```

---

## Images Docker

Le `Dockerfile` utilise un **build multi-étapes** produisant trois cibles indépendantes :

| Cible                    | Commande                                                    | Port      |
| ------------------------ | ----------------------------------------------------------- | --------- |
| Frontend seul            | `docker build --target front -t microcrm-front .`           | 80        |
| Backend seul             | `docker build --target back -t microcrm-back .`             | 8080      |
| Tout-en-un (Supervisord) | `docker build --target standalone -t microcrm-standalone .` | 80 + 8080 |

---

## Pipeline CI/CD (GitHub Actions)

Le pipeline est défini dans `.github/workflows/ci.yml` et s''exécute en trois étapes :

```
test-back  ─┐
             ├─ (en parallèle) → publish (images Docker → GHCR)
test-front ─┘
```

| Job          | Déclencheur                 | Actions                               |
| ------------ | --------------------------- | ------------------------------------- |
| `test-back`  | Tout push / PR              | `gradle test` + JaCoCo + SonarCloud   |
| `test-front` | Tout push / PR              | `npm ci` + `ng test` (ChromeHeadless) |
| `publish`    | Merge sur `main` uniquement | Build Docker + push sur `ghcr.io`     |

Les images publiées sont taguées `latest` **et** avec le SHA du commit pour permettre un rollback précis.

### Secrets requis

| Secret GitHub  | Utilisation                                                      |
| -------------- | ---------------------------------------------------------------- |
| `SONAR_TOKEN`  | Authentification SonarCloud                                      |
| `GITHUB_TOKEN` | Publication sur GHCR (fourni automatiquement par GitHub Actions) |

---

## Stack ELK (monitoring logs)

```bash
docker compose -f docker-compose.elk.yml up
```

Kibana est accessible sur http://localhost:5601. Les logs Spring Boot sont envoyés via Logstash vers l''index `microcrm-logs-*`.

---

## Documentation technique

- [`CI_CD_PLAN.md`](CI_CD_PLAN.md) — plan de testing, sécurité, conteneurisation, déploiement, sauvegarde et mise à jour
- [`DORA_KPI.md`](DORA_KPI.md) — métriques DORA mesurées et KPI opérationnels

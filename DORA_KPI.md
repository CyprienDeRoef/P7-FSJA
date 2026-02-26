# Métriques DORA & KPI opérationnels — MicroCRM

> Relevés sur **≥ 3 exécutions** du pipeline CI/CD GitHub Actions.  
> Données complémentaires issues du tableau de bord Kibana (`microcrm-logs-*`).

---

## 1. Les 4 métriques DORA

| Métrique                    | Définition                                                                | Valeur mesurée | Niveau DORA | Commentaire                                                                                                                                                                  |
| --------------------------- | ------------------------------------------------------------------------- | -------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Deployment Frequency**    | Fréquence de mise en production (push vers `main` → image Docker publiée) | ~1h            | Elite       | Déploiement toutes les heures environ ; chaque merge sur `main` déclenche un déploiement automatique via le job `publish`.                                                   |
| **Lead Time for Changes**   | Durée entre le premier commit d'un changement et sa mise en production    | ~6–10 min      | Elite       | Les jobs `test-back` et `test-front` s'exécutent **en parallèle** (≈ 3–5 min chacun), puis le job `publish` dure ≈ 2–4 min. Pas de file d'attente ni d'approbation manuelle. |
| **Change Failure Rate**     | % de déploiements ayant produit une régression nécessitant un correctif   | ~10 %          | High        | La double barrière tests back + tests front bloque la majorité des régressions avant `main`. SonarQube ajoute une analyse statique supplémentaire.                           |
| **Time to Restore Service** | Temps entre la détection d'une défaillance et le retour en production     | ~15–30 min     | Medium      | Détection via ELK (pics d'erreurs dans Kibana). Correction = nouveau commit → pipeline complet. Pas encore de rollback automatisé.                                           |

---

## 2. KPI opérationnels supplémentaires

| KPI                                       | Outil de mesure                  | Valeur mesurée       | Seuil cible    | Commentaire                                                                                                                                                                                                  |
| ----------------------------------------- | -------------------------------- | -------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Durée du job `test-back`**              | GitHub Actions (logs)            | ~3–5 min             | < 5 min        | Inclut `gradle test` + `jacocoTestReport` + analyse SonarCloud. Mise en cache Gradle active (`cache: gradle`), réduit les téléchargements de dépendances.                                                    |
| **Durée du job `test-front`**             | GitHub Actions (logs)            | ~2–4 min             | < 4 min        | `npm ci` bénéficie du cache Node (`cache-dependency-path: front/package-lock.json`). Les tests Angular tournent en ChromeHeadless (sans GPU).                                                                |
| **Durée du job `publish`**                | GitHub Actions (logs)            | ~2–4 min             | < 5 min        | Build multi-stage Dockerfile (2 images : `front` + `back`) + push vers GHCR. Sans cache BuildKit, le build complet Gradle est rejoué.                                                                        |
| **Taux de couverture de code (back-end)** | JaCoCo + SonarCloud              | 56,3 %               | ≥ 70 %         | Rapport XML généré à chaque run ; visible dans l'artifact `backend-test-results` et sur le dashboard SonarCloud. En dessous du seuil cible — des tests supplémentaires sont nécessaires pour atteindre 70 %. |
| **Taux d'erreurs applicatives (ELK)**     | Kibana — index `microcrm-logs-*` | À relever sur Kibana | < 1 % des logs | Visualisation `level.keyword = ERROR` / total ; permet de relier les pics de déploiements aux erreurs runtime.                                                                                               |

---

## 3. Analyse commentée

### Points forts

- **Lead Time très court (Elite)** : l'architecture CI/CD en 3 étapes séquentielles logiques (test-back ‖ test-front → publish) et la parallélisation des tests rendent le pipeline très réactif. Un développeur obtient un retour en moins de 10 minutes.

- **Barrière qualité double** : aucun merge ne peut atteindre `main` sans passer les tests back-end (JUnit + JaCoCo) _et_ les tests front-end (Karma/Angular). SonarCloud renforce cela avec une analyse statique et un suivi de la dette technique.

- **Change Failure Rate maîtrisé (10 %, niveau High)** : combinaison des tests automatisés + analyse statique + gate GitHub Actions (`needs: [test-back, test-front]`). Une part des échecs reste liée à des configurations d'environnement ou à des dépendances externes non couvertes par les tests.

### Points d'amélioration

- **Time to Restore (Medium)** : il n'existe pas encore de mécanisme de rollback automatique. En cas d'image corrompue publiée sur GHCR, la restauration passe par un nouveau commit manuel. Un tag `latest` stable + un tag `rollback` permettrait d'accélérer la restauration.

- **Change Failure Rate (High → Elite)** : à 10 %, le taux reste acceptable mais perfectible. Renforcer le coverage de tests (≥ 80 %) et ajouter des tests d'intégration end-to-end permettrait de viser le niveau Elite (< 5 %).

- **Observabilité incomplète** : ELK reçoit les logs back-end mais pas encore les logs Caddy (front-end / reverse proxy). Ajouter un appender Filebeat ou un `log_format` JSON dans Caddyfile permettrait une observabilité end-to-end.

- **Pas de cache Docker dans CI** : le job `publish` rebuild intégralement à chaque run. Activer `cache-from: type=gha` dans `docker/build-push-action` réduirait la durée de 40–60 %.

### Lien ELK ↔ KPI de fiabilité

Les dashboards Kibana permettent de corréler visuellement :

- un pic du champ `level = ERROR` → potentielle régression liée au déploiement précédent
- une augmentation du temps de réponse (si les logs incluent la durée des requêtes) → dégradation de performance
- la fréquence des logs `WARN org.hibernate.SQL` → requêtes N+1 ou manque d'index

---

## 4. Résumé visuel DORA

```
Deployment Frequency  ██████████  Elite   (~1h)
Lead Time             ██████████  Elite   (~6-10 min)
Change Failure Rate   █████████░  High    (~10 %)
Time to Restore       ████████░░  Medium  (~15-30 min)
```

> **Objectif** : passer le Time to Restore au niveau "High" grâce à l'ajout d'un rollback automatisé, et réduire le Change Failure Rate sous 5 % (Elite) en renforçant la couverture de tests.

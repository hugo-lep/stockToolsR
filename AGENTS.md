# stockToolsR

Package R pour collecter, stocker et analyser des données financières boursières (S&P 500).

## Mode de travail

- **Branche git : travailler sur la branche `dev`.** Ne jamais committer sur `master` ni créer de commit sans demande explicite.
- **Un fichier à la fois.** Ne jamais créer ou modifier plus d'un fichier par échange.
- Toujours proposer et attendre la validation avant de passer au fichier suivant.
- **Ne jamais modifier un fichier sans que l'utilisateur en fasse la demande explicite.**
- Les scripts du cron actuel (`inst/script/`) restent **intacts** pendant la révision : l'utilisateur continue de les utiliser quotidiennement.
- La version révisée est construite **un fichier à la fois** dans `inst/script2/`. On ne passe au script suivant que lorsque l'utilisateur l'a clairement énoncé.
- **Répondre de manière concise**, sans préambule, sans résumé inutile, sans explications superflues. Aller droit au but.

## Gestion des améliorations

- Les améliorations identifiées durant le développement sont consignées dans **`inst/opencode/ROADMAP.md`**.
- Ce fichier sert de backlog : performance, robustesse, idées à évaluer.
- Ne pas encombrer `AGENTS.md` avec ces items — le garder court et opérationnel.

## Architecture générale

- **Données** : Financial Modeling Prep (FMP) + Yahoo Finance (via `tidyquant`)
- **Base de données** : PostgreSQL sur VPS, schéma `stocktools`
  - En local : tunnel SSH pour accéder au VPS
  - Tables `_orig` = données brutes API ; tables `_build` = données transformées/utilisables
- **Stockage objet** : S3 OVH via le package personnel `s3db`
  - Connexion : `s3db::s3_connection_HL()` (aucune config supplémentaire)
  - S3 pour les petits fichiers de suivi du cron et les logs détaillés (pas de filtrage SQL nécessaire)
  - **Convention S3** : bucket `avnumbers`, main_folder = projet (ex: `finance`), puis un sous-dossier par package (ex: `stockToolsR`)
  - Le bucket et le main_folder sont fournis par protegR2 (via `config_global.rds` lu sur S3) — le package ne les gère pas
  - Le package fournit seulement le chemin relatif (ex: `logs/YYYY-MM-DD.rds`), `s3db` préfixe automatiquement le main_folder
- **Logs du cron** : stockés de deux façons, consultables depuis l'app Shiny
  - **Résumé** en table PostgreSQL `cron_log` (interrogeable par `SELECT`)
  - **Détail** en fichiers journels sur S3 (historique long, diagnostic)
- **Cible finale** : module Shiny dans un projet séparé qui utilisera ce package

## Sécurité

- **La clé API FMP ne doit jamais être écrite en dur** dans le code. Toujours via `Sys.getenv("key_fmp_api")`.
- Passer la clé API par **header HTTP**, pas dans l'URL, pour éviter la fuite dans les logs.
- La clé actuellement en dur dans `inst/script/0-plan.R` est une fuite à corriger (à traiter en révision).

## Contrainte API FMP

**Limite : 300 appels/min.** Toujours ajouter `Sys.sleep()` dans les boucles d'appels FMP.
Règle : `Sys.sleep(0.2)` minimum entre chaque appel (= max ~5 tickers/sec).

## Conventions de code

- Langue : commentaires et messages en français.
- Style : `tidyverse`, pipes `|>`, indentation 4 espaces.
- Préférer le code R au SQL (le SQL doit rester simple : SELECT, INSERT, DELETE).
- Paramètre de connexion toujours nommé `con`.
- Scripts numérotés `0-plan.R`, `00_api.R`, `01-*.R`, `02-*.R` … dans `inst/script2/`.
- Quand les scripts seront stables → encapsuler en fonctions dans `R/`.
- **Nouveaux fichiers/fonctions dans `R/`** : ne pas écraser un fichier existant utilisé par les scripts actuels (`inst/script/`). Si une fonction `R/` existe mais ne convient pas, créer un nouveau fichier ET une nouvelle fonction avec un nom légèrement différent (ex: `fmp_get_stmts_cie` vs `fmp_get_stmts_new_cie`).
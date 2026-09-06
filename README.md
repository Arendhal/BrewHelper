# BrewHelper 🍺⚙️
*L'expérience native, intelligente et sécurisée pour gérer Homebrew sur macOS.*

![macOS](https://img.shields.io/badge/macOS-14.0+-black?style=for-the-badge&logo=apple) ![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift) ![SwiftUI](https://img.shields.io/badge/SwiftUI-100%25-blue?style=for-the-badge&logo=apple) ![Homebrew](https://img.shields.io/badge/Homebrew-Compatible-yellow?style=for-the-badge&logo=homebrew) ![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**BrewHelper** est une application macOS native développée en **SwiftUI** qui révolutionne la gestion de votre écosystème **Homebrew**. Fini les lignes de commande répétitives et opaques : pilotez vos installations, maintenez la santé de votre système et auditez la sécurité de vos logiciels dans une interface moderne et fluide.

---

## ✨ Fonctionnalités Principales

### 1. 📦 Gestion Universelle (Formulae & Casks)
* **Vue d'ensemble intuitive** : Visualisez en temps réel l'ensemble de vos paquets en ligne de commande (*Formulae*) et de vos applications graphiques macOS (*Casks*).
* **Fiches techniques détaillées** : Accédez au détail de chaque logiciel en un clic — versions locales et distantes, arborescence des dépendances, licences officielles, description et liens directs vers la documentation de l'éditeur.
* **Détection fine des versions** : Un algorithme scrute localement tous vos répertoires de version (via *Cellar* et *Caskroom*) pour éliminer tout faux positif et vous indiquer avec précision si vous êtes à jour.

### 2. 🛡️ Audit de Sécurité à la Demande (NVD/NIST · EUVD/ENISA · CISA KEV · EPSS)
* **Déclenché quand vous le décidez** : le lancement de l'application se contente d'un `brew update` — l'état « mises à jour disponibles » est donc toujours exact. L'audit de vulnérabilités, lui, interroge une base distante paquet par paquet : il se lance depuis l'onglet *Audit de Sécurité* et son résultat est conservé d'une session à l'autre.
* **Deux bases au choix** : **NVD** (NIST) par recoupement CPE — le nom du produit et la version installée sont envoyés à NIST, qui fait lui-même le calcul de plage — ou **EUVD** (ENISA) par produit déclaré. Le nom Homebrew est réconcilié avec le dictionnaire CPE quand il diffère (`node` → `nodejs`).
* **Verdict par version installée** : chaque avis est recroisé avec la version présente sur le disque. Ce que votre version corrige déjà n'apparaît pas ; les plages exprimées dans un autre schéma (dates d'instantané, empreintes de commit) sont écartées au lieu d'être prises pour des numéros de version.
* **Priorisation par le risque réel** : les failles inscrites au catalogue **CISA KEV** (exploitation avérée sur le terrain) passent devant tout le reste, et le score **EPSS** donne la probabilité d'exploitation à trente jours. Un score CVSS élevé que personne n'exploite ne masque plus une faille moyenne activement utilisée.
* **Trois états distincts, jamais confondus** : *sain*, *produit non répertorié par la base* et *interrogation échouée*. Un quota d'API dépassé ne s'affiche plus comme un badge vert.
* **Analyse parallèle** : les paquets sont interrogés de front dans la limite du quota de la base ; une clé d'API NVD (gratuite) fait passer la limite de 5 à 50 requêtes par 30 secondes.

### 3. 🔧 Plan de Remédiation par Paquet
Savoir qu'une faille est ouverte ne dit pas quoi en faire. Pour chaque paquet vulnérable, BrewHelper construit la marche à suivre, avec les commandes `brew` exécutables d'un clic :
* **Mise à jour simple** quand le catalogue porte déjà le correctif.
* **Migration de branche majeure** (`openssl@1.1` → `openssl@3`) quand le correctif n'existe que dans une branche suivante — avec la question qui bloque en pratique : **quels paquets installés réclament encore l'ancienne version**. `brew uses --installed` les liste, et chacun est classé selon que sa version à jour s'en passe (le mettre à jour libère l'ancienne branche) ou qu'il la réclame toujours (l'ancienne branche doit rester, et reste exposée).
* **Remplacement** d'une formule dépréciée ou désactivée, en lisant le motif annoncé par Homebrew et la formule remplaçante.
* **Absence de correctif** : le plan le dit franchement et propose les mesures de contournement, plutôt que de conseiller une mise à jour qui n'existe pas.
* **Casks à mise à jour automatique** : signalés comme tels, la version connue de Homebrew n'étant plus celle qui tourne.

### 4. 🛍️ Catalogue & App Store Homebrew Intégré
* **Onglet Découvrir** : Parcourez des sélections sélectionnées par catégorie (Utilitaires de développement, Terminaux Modernes, Sécurité, Éditeurs de texte).
* **Recherche Mondiale Instantanée** : Tapez n'importe quel mot-clé dans la barre de recherche. L'application interroge la base globale Homebrew et vous propose l'installation en 1-clic des nouveaux outils sans quitter l'interface !

### 5. ⚙️ Maintenance & Mode Silencieux
* **Zéro interruption visuelle** : Lancez un nettoyage complet (`brew cleanup`), un diagnostic système (`brew doctor`) ou une mise à niveau générale (`brew update & upgrade`). Tout s'exécute silencieusement en arrière-plan via un bandeau de progression animé au sommet de la fenêtre.
* **Console d'audit à la demande** : Besoin d'inspecter les détails techniques d'une installation ? Ouvrez d'un clic la console de logs en direct au format terminal macOS.

---

## 🔒 Sécurité & Hardening du Code

* **Protection Anti-MITM (Man-in-the-Middle)** : Toutes les exécutions sous-jacentes d'Homebrew intègrent la directive `HOMEBREW_NO_INSECURE_REDIRECT=1`, interdisant toute redite HTTP non chiffrée lors du téléchargement de binaires.
* **Concurrence Strict (@MainActor)** : Conçu selon l'architecture moderne d'Apple, évitant les collisions et assurant un rendu 120Hz sans ralentissement.
* **Validation des Requêtes** : Encodage strict et temporisations (timeouts 8s) pour garantir qu'aucune requête dégradée sur le réseau ne bloque votre ordinateur.

---

## 🚀 Installation & Utilisation

### Option 1 : Via l'Installateur macOS (DMG)
Un fichier d'installation clé en main est généré et prêt à l'emploi :
1. Téléchargez ou ouvrez `BrewHelper-1.3-Installer.dmg`.
2. Glissez simplement l'icône **BrewHelper** dans votre dossier *Applications*.
3. Lancez l'application ! *(Note : nécessite Homebrew accessible sur le Mac sous `/opt/homebrew` ou `/usr/local`)*

### Option 2 : Compilation depuis Apple Xcode
1. Ouvrez `BrewHelper.xcodeproj` dans **Xcode 15+**.
2. Sélectionnez la cible `Mac` (ARM64 / Apple Silicon ou Intel x86_64).
3. Appuyez sur **⌘ R** pour lancer l'application.

---

## 🏗️ Architecture Technique

* **`AppState.swift`** : Chef d'orchestre de l'interface graphique et gestionnaire asynchrone des tâches d'arrière-plan.
* **`BrewCommandService.swift`** : Pont de communication sécurisé exécutant les processus natifs macOS (`Process`, `Pipe`) avec lecture de flux d'entrées/sorties en continu.
* **`BrewCatalogService.swift`** : Catalogue de recommandations et moteur de recherche global connectant l'App Store Homebrew en JSON v2.
* **`CVESecurityService.swift`** : Orchestration de l'audit — interrogation parallèle, temporisation par quota, reprises sur échec, cache disque et distinction sain / non répertorié / échec.
* **`VulnerabilityMatcher.swift`** : Comparaison de versions et interprétation des plages affectées (CPE structuré côté NVD, texte libre côté EUVD).
* **`ThreatIntelService.swift`** : Catalogue CISA KEV et scores EPSS, qui déterminent l'ordre de traitement des failles.
* **`RemediationService.swift`** : Construction du plan de remédiation à partir de `versioned_formulae`, `deprecated`/`disabled` et `brew uses --installed`.
* **`Views/`** : Interface 100 % SwiftUI modulable avec effets d'animation *macOS Sonoma / Sequoia*.

## 📋 Journal des versions

Les évolutions de chaque version sont détaillées dans [`CHANGELOG.md`](CHANGELOG.md).

---
*Conçu avec passion et rigueur pour les administrateurs systèmes, ingénieurs et amoureux de macOS.* 🍻👨‍💻

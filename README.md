# BrewHelper 🍺⚙️
*L'expérience native, intelligente et sécurisée pour gérer Homebrew sur macOS.*

![macOS](https://img.shields.io/badge/macOS-14.0+-black?style=for-the-badge&logo=apple) ![Universal](https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-lightgrey?style=for-the-badge&logo=apple) ![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift) ![SwiftUI](https://img.shields.io/badge/SwiftUI-100%25-blue?style=for-the-badge&logo=apple) ![Homebrew](https://img.shields.io/badge/Homebrew-Compatible-yellow?style=for-the-badge&logo=homebrew) ![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**BrewHelper** est une application macOS native développée en **SwiftUI** qui révolutionne la gestion de votre écosystème **Homebrew**. Fini les lignes de commande répétitives et opaques : pilotez vos installations, maintenez la santé de votre système et auditez la sécurité de vos logiciels dans une interface moderne et fluide.

---

## ✨ Fonctionnalités Principales

### 1. 📦 Accueil & Bibliothèque
* **Quatre espaces** : *Accueil*, *Bibliothèque*, *Découvrir* et *Sécurité*, plus l'*Activité* ; palette de commandes **⌘K** pour ouvrir un paquet ou lancer une action, **⌘1 à ⌘5** pour passer d'un espace à l'autre.
* **Thème clair ou sombre** : réglage *Auto* (suit macOS), *Clair* ou *Sombre* dans la barre d'outils.
* **Accueil** : l'état du Mac en quatre cartes (sécurité, couverture de l'audit, mises à jour, activité) et une liste **« À faire »** classée par risque réel — faille confirmée avec ou sans correctif, avis à trancher, angle mort de l'audit, tap tiers, dépendances devenues inutiles (`brew autoremove`).
* **Bibliothèque** : une seule liste de vos *Formulae* et *Casks*, filtrable (demandés, dépendances, apps, à mettre à jour, vulnérables, non concluants, non suivis, non maintenus), avec pour chaque paquet **pourquoi il est là** (installé à votre demande, dépendance de tel paquet, ou plus requis par rien).
* **Fiches techniques détaillées** : Accédez au détail de chaque logiciel en un clic — versions locales et distantes, arborescence des dépendances, licences officielles, description et liens directs vers la documentation de l'éditeur.
* **Détection fine des versions** : Un algorithme scrute localement tous vos répertoires de version (via *Cellar* et *Caskroom*) pour éliminer tout faux positif et vous indiquer avec précision si vous êtes à jour.

### 2. 🛡️ Audit de Sécurité à la Demande (EUVD/ENISA + NVD/NIST · CISA KEV · EPSS)
* **Déclenché quand vous le décidez** : le lancement de l'application se contente d'un `brew update` — l'état « mises à jour disponibles » est donc toujours exact. L'audit de vulnérabilités, lui, interroge une base distante paquet par paquet : il se lance depuis l'espace *Sécurité* et son résultat est conservé d'une session à l'autre.
* **Audit hybride EUVD + NVD** : **EUVD** (ENISA, par produit déclaré) porte l'audit et la **NVD** (NIST, par recoupement CPE — le nom du produit et la version installée sont envoyés à NIST, qui fait lui-même le calcul de plage) le complète en parallèle, sur sa propre file, sans jamais le ralentir. Chaque faille indique la base qui l'a relevée, avec un lien cliquable vers sa page officielle. Les modes EUVD seul et NVD seul restent disponibles. Le nom Homebrew est réconcilié avec le dictionnaire CPE quand il diffère (`node` → `nodejs`).
* **Verdict par version installée** : chaque avis est recroisé avec la version présente sur le disque. Ce que votre version corrige déjà n'apparaît pas ; les plages exprimées dans un autre schéma (dates d'instantané, empreintes de commit) sont écartées au lieu d'être prises pour des numéros de version.
* **Priorisation par le risque réel** : les failles inscrites au catalogue **CISA KEV** (exploitation avérée sur le terrain) passent devant tout le reste, et le score **EPSS** donne la probabilité d'exploitation à trente jours. Un score CVSS élevé que personne n'exploite ne masque plus une faille moyenne activement utilisée.
* **États distincts, jamais confondus** : *faille confirmée*, *avis à trancher*, *non concluant* (des avis sans plage de versions n'ont pas pu être tranchés), *non suivi*, *interrogation échouée* et *sain*. Une barre de couverture montre d'un coup d'œil ce que l'audit a réellement pu vérifier ; un quota d'API dépassé ne s'affiche jamais comme un badge vert.
* **Moins d'angles morts** : un paquet dont le nom Homebrew diffère de celui des bases est aussi cherché sous son nom amont (`webp` → `libwebp`). Pour ce qui reste non suivi, la fiche signale un paquet déprécié, désactivé ou issu d'un tap tiers, et propose des liens de vérification manuelle (NVD, EUVD, OSV, avis du dépôt GitHub).
* **Analyse parallèle** : les paquets sont interrogés de front dans la limite du quota de la base ; une clé d'API NVD (gratuite) fait passer la limite de 5 à 50 requêtes par 30 secondes.

### 3. 🔧 Plan de Remédiation par Paquet
Savoir qu'une faille est ouverte ne dit pas quoi en faire. Pour chaque paquet vulnérable, BrewHelper construit la marche à suivre, avec les commandes `brew` exécutables d'un clic :
* **Mise à jour simple** quand le catalogue porte déjà le correctif.
* **Migration de branche majeure** (`openssl@1.1` → `openssl@3`) quand le correctif n'existe que dans une branche suivante — avec la question qui bloque en pratique : **quels paquets installés réclament encore l'ancienne version**. `brew uses --installed` les liste, et chacun est classé selon que sa version à jour s'en passe (le mettre à jour libère l'ancienne branche) ou qu'il la réclame toujours (l'ancienne branche doit rester, et reste exposée).
* **Remplacement** d'une formule dépréciée ou désactivée, en lisant le motif annoncé par Homebrew et la formule remplaçante.
* **Absence de correctif** : le plan le dit franchement et propose les mesures de contournement, plutôt que de conseiller une mise à jour qui n'existe pas.
* **Casks à mise à jour automatique** : signalés comme tels, la version connue de Homebrew n'étant plus celle qui tourne.

### 4. 🛍️ Catalogue & App Store Homebrew Intégré
* **Découvrir** : des recommandations tirées des statistiques publiques d'installation de Homebrew, actualisées chaque jour — ce qui monte en ce moment, les outils et applications les plus installés, un tirage du jour parmi des paquets moins connus — sans ce qui est déjà installé. Installation en un clic, mise en file d'attente.
* **Recherche Mondiale Instantanée** : Tapez n'importe quel mot-clé dans la barre de recherche. L'application interroge la base globale Homebrew et vous propose l'installation en 1-clic des nouveaux outils sans quitter l'interface !

### 5. ⚙️ Activité & Maintenance
* **File d'attente** : chaque commande Homebrew — installation, mise à jour, nettoyage (`brew cleanup`), diagnostic (`brew doctor`) — devient une tâche qui attend son tour, sans bloquer l'interface ni entrer en concurrence avec une autre.
* **Journal par tâche** : vue résumée étape par étape ou sortie brute du terminal, consultable après coup dans l'espace *Activité*.

---

## 🔒 Sécurité & Hardening du Code

* **Protection Anti-MITM (Man-in-the-Middle)** : Toutes les exécutions sous-jacentes d'Homebrew intègrent la directive `HOMEBREW_NO_INSECURE_REDIRECT=1`, interdisant toute redite HTTP non chiffrée lors du téléchargement de binaires.
* **Concurrence Strict (@MainActor)** : Conçu selon l'architecture moderne d'Apple, évitant les collisions et assurant un rendu 120Hz sans ralentissement.
* **Validation des Requêtes** : Encodage strict et temporisations (timeouts 8s) pour garantir qu'aucune requête dégradée sur le réseau ne bloque votre ordinateur.

---

## 🚀 Installation & Utilisation

**Prérequis** : macOS 14 (Sonoma) ou ultérieur, et Homebrew installé sous `/opt/homebrew`
(Apple Silicon) ou `/usr/local` (Intel).

### Option 1 : Via l'Installateur macOS (DMG)
L'installateur publié avec chaque version contient un **binaire universel**, exécutable
nativement sur Apple Silicon comme sur Intel :
1. Téléchargez `BrewHelper-1.5-Installer.dmg` depuis la [dernière version publiée](https://github.com/Arendhal/BrewHelper/releases/latest).
2. Ouvrez-le et glissez l'icône **BrewHelper** dans votre dossier *Applications*.
3. Lancez l'application.

*L'application est signée localement (signature ad hoc) et non notarisée : au premier
lancement, macOS demande une confirmation via **Réglages Système → Confidentialité et
sécurité → Ouvrir quand même**.*

### Option 2 : Compilation depuis Apple Xcode
1. Ouvrez `BrewHelper.xcodeproj` dans **Xcode 15+**.
2. Appuyez sur **⌘ R** pour lancer l'application.

La configuration *Release* compile pour les deux architectures (`ARCHS = arm64 x86_64`).
Pour produire l'installateur universel en ligne de commande, la destination générique est
nécessaire — sans elle, `xcodebuild` ne compile que l'architecture de la machine hôte :

```sh
xcodebuild -project BrewHelper.xcodeproj -scheme BrewHelper \
           -configuration Release -destination 'generic/platform=macOS' \
           -derivedDataPath build clean build
lipo -archs build/Build/Products/Release/BrewHelper.app/Contents/MacOS/BrewHelper
# → x86_64 arm64
```

---

## 🏗️ Architecture Technique

* **`AppState.swift`** : Chef d'orchestre de l'interface graphique et gestionnaire asynchrone des tâches d'arrière-plan.
* **`ActivityCenter.swift`** : File sérielle des commandes Homebrew et journal de chaque tâche.
* **`BrewCommandService.swift`** : Pont de communication sécurisé exécutant les processus natifs macOS (`Process`, `Pipe`) avec lecture de flux d'entrées/sorties en continu.
* **`BrewCatalogService.swift`** : Recommandations calculées à partir des statistiques d'installation de Homebrew (`formulae.brew.sh/api/analytics`) et moteur de recherche global.
* **`CVESecurityService.swift`** : Orchestration de l'audit — une file par base (EUVD en première ligne, NVD en renfort), recoupement des verdicts, temporisation par quota, reprises sur échec, cache disque et distinction sain / non répertorié / échec.
* **`ProductIdentity.swift`** : Vérification d'identité des avis — nom, éditeur, plateforme visée, schéma de version et références, avec un score et des raisons affichables. `Tools/check-identity.sh` en rejoue les cas de régression hors ligne.
* **`VulnerabilityMatcher.swift`** : Comparaison de versions et interprétation des plages affectées (CPE structuré côté NVD, texte libre côté EUVD), correspondance produit/paquet.
* **`ThreatIntelService.swift`** : Catalogue CISA KEV et scores EPSS, qui déterminent l'ordre de traitement des failles.
* **`RemediationService.swift`** : Construction du plan de remédiation à partir de `versioned_formulae`, `deprecated`/`disabled` et `brew uses --installed`.
* **`Views/`** : Interface 100 % SwiftUI modulable avec effets d'animation *macOS Sonoma / Sequoia*.

## 📋 Journal des versions

Les évolutions de chaque version sont détaillées dans [`CHANGELOG.md`](CHANGELOG.md).

---
*Conçu avec passion et rigueur pour les administrateurs systèmes, ingénieurs et amoureux de macOS.* 🍻👨‍💻

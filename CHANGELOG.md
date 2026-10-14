# Journal des versions

## 1.4.1 — Rattachement des avis au bon logiciel, et clé NVD vérifiée

Un avis n'est plus retenu parce que son nom ressemble à celui du paquet : chaque
rapprochement est confronté à plusieurs indices, et ce qui est écarté se justifie.

### Vérification d'identité des avis

- **Déclencheur : `python@3.14` remontait des failles « 2020.5.0 ».** C'étaient celles de
  l'extension Python de Visual Studio Code, que la NVD publie sous le produit `python`
  (éditeur Microsoft, numérotation par année). Comparée à `3.14.8`, une borne `< 2020.5.0`
  paraît toujours supérieure : le paquet semblait vulnérable.
- **Chaque produit déclaré par un avis est confronté au paquet** (`ProductIdentity.swift`) :
  nom (identique, voisin, adresse du dépôt, ou lu dans une phrase), éditeur (cohérent avec
  le nom du paquet ou le site du projet), site officiel cité dans les références de l'avis,
  plateforme visée (`target_sw` d'un CPE : Windows, Android, extension d'une application
  hôte), schéma de version (numérotation par année contre numérotation classique).
  L'adresse source de l'archive (`urls.stable.url`) s'ajoute à la page d'accueil pour
  reconnaître le projet amont.
- **Un score et des raisons lisibles** : sur chaque faille, un badge « Produit de l'avis :
  python (éditeur python) — correspondance forte », dont le survol détaille les indices.
- **Les avis écartés sont listés avec leur motif**, dans une section repliable de la fiche du
  paquet : extension de Visual Studio Code, faille propre à Windows, homonyme sans version.
- **Contrôle hors ligne** : `Tools/check-identity.sh` rejoue 21 cas réels (Python et son
  extension, `gettext.js`, `NGINX Plus`, `Zoom Node`, un avis propre à Windows...).

### Autres fausses détections corrigées

- `gettext` remontait une faille de `gettext.js`, un portage JavaScript : le suffixe « .js »
  ne vaut plus que pour Node.js.
- `bitwarden-cli 2026.9.1` : une version calendaire était prise pour une date et jugée
  incomparable avec `2026.4.0`. Une date s'écrit avec des tirets ou un mois sur deux chiffres.
- `deno` : une faille propre à Windows s'affichait sur macOS.
- **NVD : « non suivi » à tort.** Quand le dictionnaire de NIST connaît le produit mais
  qu'aucune faille ne vise la version installée, l'audit répondait « non suivi » au lieu de
  « sain » (`xz`, `c-ares`, `libidn2`, `opus`...). Les paquets « non suivis » passent de 47 à
  31 sur une installation type. Une requête de repli refusée est maintenant un échec visible.

### Clé d'API NVD

- La clé est **nettoyée** avant envoi : un espace ou un retour à la ligne collé avec elle
  la faisait refuser comme une clé fausse.
- Une clé refusée affiche **« Clé d'API NVD refusée par NIST »** au lieu de « code 404 », sans
  nouvelle tentative inutile.
- Bouton **« Tester la clé »** : interroge réellement la NVD et répond *acceptée*, *refusée*
  ou *injoignable*.

### Limites connues

- Les paquets dont le nom Homebrew diffère de celui des bases (`webp` pour `libwebp`,
  `icu4c`, `tcl-tk`, `sdl3`) restent « non suivis » : une table d'alias est à l'étude.
- Les avis identifiés seulement par un commit restent « non vérifiables ».

## 1.4 — Audit hybride EUVD + NVD, et un moteur de verdicts corrigé

Le principe reste celui de la 1.3 : **ne jamais afficher en vert ce qui n'a pas été
vérifié**. Cette version l'applique à ce qui restait faux dans la lecture d'EUVD, et
ajoute la NVD en renfort plutôt qu'en alternative.

### Audit hybride : EUVD porte l'audit, la NVD le complète

- **Nouvelle base par défaut, « EUVD + NVD »** (les modes EUVD seul et NVD seul restent
  au choix, et un réglage déjà enregistré est conservé).
- **Deux files indépendantes.** EUVD, rapide, avance à son rythme ; la NVD, bridée à
  5 requêtes par 30 s sans clé, travaille en parallèle sur sa propre file, avec sa propre
  cadence. Une base lente ne ralentit jamais l'autre.
- **La NVD commence par les paquets qu'EUVD ne connaît pas** (ou n'a pas pu lire) : c'est
  là qu'elle apporte le plus. `xz 5.6.1` est « non suivi » côté EUVD, alors que la NVD lui
  relève des failles ouvertes.
- **Chaque faille indique la base qui l'a relevée**, avec une étiquette cliquable par base
  (EUVD, NVD) qui ouvre la page officielle. Une faille vue par les deux n'apparaît qu'une
  fois, avec les deux références.
- **Recoupement des verdicts** : quand les bases divergent, la plage structurée de la NVD
  l'emporte sur une plage lue dans le texte libre d'EUVD, qui l'emporte sur « non
  vérifiable ». Une base en panne ne masque pas ce que l'autre a trouvé.
- **Progression séparée** pour le complément (« Complément NVD en arrière-plan : x / y »),
  sablier sur les paquets dont le verdict peut encore s'étoffer, et bouton *Interrompre le
  complément* une fois la phase EUVD terminée.

### Lecture d'EUVD corrigée

Constaté sur l'API réelle, en rejouant le moteur de verdicts sur des paquets installés :

- **EUVD pagine par 100 et ne trie pas** : seule la première page était lue. curl : 50
  avis sur 163 ; OpenSSL 3.0.1 : 0 faille détectée sur les 67 réelles ; nginx 1.20 : 0 sur
  2. Toutes les pages sont maintenant lues, et une lecture interrompue passe en erreur au
  lieu de se faire passer pour un paquet sain.
- **« Aucun avis rattachable » n'est plus « sain »** : `product=` est une recherche
  floue (`xz` ramène 3 avis, tous sur `xzs-mysql`). Un paquet dont aucun avis ne le
  concerne est désormais *non suivi*, pas vert.
- **Correspondance des noms de produit** : `https://github.com/curl/curl` (51 avis curl)
  et `NGINX Open Source` (30 avis) étaient ignorés ; `Zoom Node`, `OpenClaw Windows Node`
  ou `Kubernetes ingress-nginx` étaient pris pour Node.js et nginx (6 fausses failles
  sur Node 26). La règle « dernier mot du nom » exige maintenant un éditeur connu devant.
- **Plages de versions lues de travers** : `from 7.59.0 to 7.61.1` perdait sa borne haute
  (curl 8.x paraissait touché par des failles de 2018) ; `Fixed in 7.83.1` était lu comme
  une version affectée ; `10.0 <10.*` donnait une plage vide ; `All versions prior to X`
  devenait « toutes versions » ; les suffixes lettres d'OpenSSL (`1.1.1zh`) étaient perdus
  et `1.1.1w` passait pour antérieure à `1.1.1`.
- **EUVD fournit son propre indicateur d'exploitation et son EPSS** : ils sont conservés,
  KEV et FIRST.org les complètent sans les écraser.
- **Le cache d'audit porte une version du moteur** : les résultats calculés par un moteur
  antérieur ne survivent plus à sa correction (le cache est donc recalculé au premier audit
  de cette version).

### Recherche dans « Découvrir & Installer »

- **Un cask d'un tap tiers est retrouvé** (`macspace` → `1architect/macspace/macspace`). La
  recherche interroge formules et casks séparément et classe (nom exact, préfixe, reste)
  *avant* de tronquer ; elle tronquait auparavant les 15 premiers noms de la sortie brute,
  où les casks venaient après les formules.
- **Un nom que `brew info` refuse ne vide plus la liste** : la recherche réessaie nom par
  nom.
- Les erreurs de recherche sont affichées, et une nouvelle frappe annule la recherche
  précédente.

### Limites connues

- EUVD ne rattache aucun produit à certains avis (la porte dérobée xz, par exemple) : la
  recherche par produit ne peut pas les trouver, d'où l'intérêt de la NVD en renfort.
- Sans clé d'API, la NVD reste lente (plusieurs minutes pour quelques dizaines de paquets).
  La clé est gratuite.
- Les numéros de build (`2026.7.1-3`) sont lus sans leur suffixe.

## 1.3 — Audit de sécurité à la demande, fiable, et suivi d'un plan d'action

Cette version réécrit l'audit de vulnérabilités de bout en bout. Le principe qui la guide :
**ne jamais afficher en vert ce qui n'a pas été vérifié**, et **ne jamais s'arrêter au
constat d'une faille sans dire quoi en faire**.

### L'audit ne part plus tout seul

Jusqu'ici, ouvrir l'application déclenchait une analyse de chaque paquet installé contre
une base de vulnérabilités distante. C'est long, cela consomme du quota d'API, et cela
n'a d'intérêt qu'au moment où on se pose la question.

- **Au lancement**, l'application se contente désormais d'un `brew update`. C'est cette
  actualisation qui rend exact l'état « mises à jour disponibles », et elle est rapide et
  locale. Un bandeau de progression distinct la signale sans verrouiller l'interface.
- **L'audit** se lance depuis un bouton, dans un onglet *Audit de Sécurité* dédié. Il peut
  être interrompu, relancé intégralement, ou complété — auquel cas seuls les paquets sans
  verdict pour leur version actuelle sont réexaminés.
- **Le résultat est conservé sur disque** et retrouvé au démarrage suivant : un audit
  devenu explicite ne pouvait pas se perdre à chaque fermeture.
- Ouvrir la fiche d'un paquet ne déclenche plus non plus d'interrogation réseau. La fiche
  montre le verdict mémorisé, et l'analyse d'un paquet isolé reste une action volontaire.

### Ce que l'audit trouve vraiment

- **NVD est interrogé par recoupement CPE** avec la version installée injectée dans la
  requête (`virtualMatchString`) : NIST effectue lui-même le calcul de plage et ne renvoie
  que ce qui vise ce produit dans cette version. Pour curl 8.1.0, 35 entrées ciblées, là
  où la recherche par mot-clé en renvoyait des milliers, triées de la plus ancienne à la
  plus récente — au point que les premières pages ne contenaient que des failles des
  années 1990.
- **Le nom Homebrew est réconcilié avec le dictionnaire CPE** quand il en diffère. Node.js
  y est publié sous `nodejs` : la formule `node` était auparavant déclarée introuvable,
  elle reçoit maintenant un vrai verdict.
- **Trois états sont distingués, jamais confondus** : *sain*, *produit absent de la base
  interrogée*, et *interrogation échouée*. C'est la correction la plus importante de cette
  version : un quota NVD dépassé renvoyait une liste vide, que l'interface affichait
  exactement comme un paquet sain. Un badge vert pouvait donc signifier « rien à
  signaler » aussi bien que « on n'a rien pu vérifier ».
- **Interrogation parallèle** dans la limite du quota de la base, avec temporisation
  calculée et reprises sur échec au lieu d'un abandon silencieux.
- **Clé d'API NVD** (gratuite) prise en charge : la limite passe de 5 à 50 requêtes par
  30 secondes, et l'audit interroge 4 paquets de front au lieu d'un seul.

### Deux fausses détections corrigées

Toutes deux observées sur des paquets réellement installés, toutes deux dues à une borne
de version lue de travers :

- **EUVD publie parfois l'empreinte du commit correctif** à la place d'un numéro de
  version (`0 <983dae9c19f46c87d597598c0fd2f2fcee0ad2f8`). Le préfixe chiffré de
  l'empreinte était lu comme une version : FFmpeg 9.0.1 était déclaré « vulnérable,
  corrigé en 983 ».
- **NVD référence certains projets suivis en continu par des dates d'instantané**
  (`< 2025-01-13` pour FFmpeg). Comparée à une version sémantique, la date l'emporte
  toujours : toute version installée paraissait vulnérable.

Une borne exprimée dans un autre schéma que la version installée est désormais écartée.
L'avis correspondant est présenté comme *non vérifiable* plutôt que faussement confirmé —
ce qui rend l'audit un peu plus bavard, mais exact.

### Hiérarchisation par le risque réel

Un score CVSS dit la gravité théorique d'une faille, pas si quelqu'un s'en sert.

- **Catalogue CISA KEV** : les failles dont l'exploitation en conditions réelles est
  documentée sont signalées et passent devant toutes les autres, quel que soit leur score.
  L'emploi avéré par des rançongiciels est indiqué à part.
- **Score EPSS** (FIRST.org) : probabilité d'exploitation à trente jours, qui départage
  les dizaines de failles « élevées » qui ne le seront jamais de la poignée qui compte.
- Le classement des paquets et des failles suit ce risque composite, pas le seul CVSS.

### Plan de remédiation

Savoir qu'une faille est ouverte ne dit pas quoi en faire. Chaque paquet vulnérable reçoit
une marche à suivre numérotée, dont chaque étape porte sa commande `brew` exécutable d'un
clic :

- **Mise à jour simple** quand le catalogue Homebrew porte déjà le correctif.
- **Migration de branche majeure** (`openssl@1.1` → `openssl@3`) quand le correctif
  n'existe que dans une branche suivante — avec la question qui bloque en pratique :
  *quels paquets installés réclament encore l'ancienne version ?* `brew uses --installed`
  les liste, et chacun est classé selon que sa version à jour s'en passe (le mettre à jour
  libère l'ancienne branche) ou qu'il la réclame toujours. Dans ce second cas, l'ancienne
  branche doit rester et demeure exposée : le plan le dit, au lieu de conseiller une
  désinstallation qui casserait ces paquets.
- **Remplacement** d'une formule dépréciée ou désactivée, en lisant le motif annoncé par
  Homebrew et la formule remplaçante qu'il désigne.
- **Absence de correctif** : le plan l'énonce franchement et propose les mesures de
  contournement, plutôt que de suggérer une mise à jour qui n'existe pas.
- **Casks à mise à jour automatique** signalés comme tels : la version connue de Homebrew
  n'est alors plus celle qui tourne, et l'audit la compare à un numéro périmé.

### Icône

Le squircle était posé sur un fond blanc, avec son ombre portée fixée dans l'image. Le
fond est retiré et la silhouette redécoupée par une superellipse — la courbe du squircle
dessiné — ce qui élimine aussi le voile d'ombre qui débordait à droite et sous la forme.
L'illustration occupe désormais 824 px sur une toile de 1024, la géométrie des icônes
système, au lieu des 61 % d'origine qui la faisaient paraître plus petite que les autres
icônes du Dock.

### Notes techniques

- Nouveaux composants : `RemediationService`, `ThreatIntelService`, `RemediationPlan`,
  `Views/Security/SecurityAuditView`.
- `CVESecurityService` est réécrit autour de l'orchestration (parallélisme, quotas,
  reprises, cache disque) ; l'interrogation des bases est isolée dans un
  `VulnerabilityFetcher` détaché de l'acteur principal.
- L'installateur livre un **binaire universel** (`arm64` + `x86_64`). macOS 14 ou
  ultérieur. La configuration *Release* visait déjà les deux architectures, mais
  l'empaquetage en ligne de commande ne produisait que celle de la machine hôte faute de
  destination générique — les installateurs 1.0 à 1.2 étaient `arm64` seul, alors que le
  projet annonçait la compatibilité Intel.

---

## 1.2

- Croisement de chaque avis CVE avec la version installée : seules les failles encore
  ouvertes sont affichées, celles que la version corrige déjà sont écartées.
- Le bouton d'actualisation lance `brew update` au lieu d'un simple rechargement local.
- `.gitignore` renforcé (secrets, certificats) et retrait de l'état Xcode local du suivi.

## 1.1

- Détection des versions installées revue via *Cellar* et *Caskroom*.

## 1.0

- Première version publiée : gestion des formulae et des casks, catalogue de découverte,
  utilitaires de maintenance et console de logs.

# Journal des versions

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
- Le binaire livré est `arm64` (identique à la 1.2). macOS 14 ou ultérieur.

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

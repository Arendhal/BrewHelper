import Foundation

// Contrôle hors ligne de la vérification d'identité (ProductIdentityEvaluator) : chaque cas
// est un homonyme ou un avis réellement rencontré. Lancer `Tools/check-identity.sh`.

func pkg(_ name: String, _ version: String, home: String, source: String? = nil, desc: String = "", full: String? = nil) -> BrewPackage {
    BrewPackage(id: name, name: name, fullName: full ?? name, type: .formula, description: desc, homepage: home,
                license: "", installedVersion: version, latestVersion: version, sourceURL: source)
}

enum Expect { case strong, probable, accepted, rejected, notThis }

struct Case {
    let label: String
    let package: BrewPackage
    let product: String
    let vendor: String?
    let target: String?
    let versions: String?
    let description: String
    let references: [String]
    let expect: Expect
}

let python = pkg("python@3.14", "3.14.8_2", home: "https://www.python.org/", source: "https://www.python.org/ftp/python/3.14.8/Python-3.14.8.tgz")
let gettext = pkg("gettext", "1.0", home: "https://www.gnu.org/software/gettext/")
let curl = pkg("curl", "8.19.0", home: "https://curl.se", source: "https://github.com/curl/curl/releases/download/curl-8_19_0/curl-8.19.0.tar.bz2")
let nginx = pkg("nginx", "1.28.0", home: "https://nginx.org/")
let node = pkg("node", "26.11.1", home: "https://nodejs.org/")
let deno = pkg("deno", "2.9.7", home: "https://deno.com/", source: "https://github.com/denoland/deno/releases/download/v2.9.7/deno_src.tar.gz")
let bitwarden = pkg("bitwarden-cli", "2026.9.1", home: "https://bitwarden.com/")
let wpcli = pkg("wp-cli", "2.12.0", home: "https://wp-cli.org/", desc: "Command-line interface for WordPress")
let openssl = pkg("openssl@3", "3.5.9", home: "https://openssl-library.org/")
let ytdlp = pkg("yt-dlp", "2026.8.19_2", home: "https://github.com/yt-dlp/yt-dlp", source: "https://github.com/yt-dlp/yt-dlp/archive/2026.08.19.tar.gz")
let xz = pkg("xz", "5.6.1", home: "https://tukaani.org/xz/")

let cases: [Case] = [
    // Python et l'extension Python de Visual Studio Code (éditeur Microsoft, numérotée par année).
    Case(label: "python / extension VS Code (CPE target_sw)", package: python, product: "python", vendor: "microsoft",
         target: "visual_studio_code", versions: "0 <2025.8.1", description: "Trust boundary violation in Visual Studio Code - Python extension", references: [], expect: .rejected),
    Case(label: "python / extension VS Code (numérotation par année)", package: python, product: "python", vendor: "microsoft",
         target: nil, versions: "0 <2024.18.2", description: "Visual Studio Code Python Extension Remote Code Execution Vulnerability", references: [], expect: .rejected),
    Case(label: "python / homonyme sans version ni éditeur crédible", package: python, product: "python", vendor: "microsoft",
         target: nil, versions: nil, description: "Some issue in a tool", references: [], expect: .rejected),
    Case(label: "python / vrai Python", package: python, product: "Python", vendor: "python",
         target: nil, versions: "<3.14.9", description: "Buffer overflow in the interpreter", references: ["https://www.python.org/dev/security/"], expect: .strong),
    // Portages et homonymes
    Case(label: "gettext / gettext.js (portage JavaScript)", package: gettext, product: "gettext.js", vendor: "guillaumepotier",
         target: nil, versions: "< 2.0.3", description: "gettext.js is a GNU gettext port for node and the browser", references: [], expect: .notThis),
    Case(label: "gettext / GNU gettext", package: gettext, product: "gettext", vendor: "gnu",
         target: nil, versions: "<0.22", description: "Flaw in msgfmt", references: ["https://www.gnu.org/software/gettext/"], expect: .strong),
    Case(label: "curl / dépôt amont désigné par son adresse", package: curl, product: "https://github.com/curl/curl", vendor: "n/a",
         target: nil, versions: "Fixed in 7.83.1", description: "HSTS bypass in curl", references: ["https://curl.se/docs/CVE-2022-30115.html"], expect: .strong),
    Case(label: "nginx / NGINX Open Source", package: nginx, product: "NGINX Open Source", vendor: "F5",
         target: nil, versions: "1.0.0 <1.29.1", description: "Memory disclosure in ngx_http_mp4_module", references: ["https://nginx.org/en/security_advisories.html"], expect: .accepted),
    Case(label: "nginx / NGINX Plus (produit commercial)", package: nginx, product: "NGINX Plus", vendor: "F5",
         target: nil, versions: "R30", description: "Flaw", references: [], expect: .notThis),
    Case(label: "nginx / Kubernetes ingress-nginx", package: nginx, product: "Kubernetes ingress-nginx", vendor: "kubernetes",
         target: nil, versions: "<1.9.0", description: "Annotation injection", references: [], expect: .notThis),
    Case(label: "node / Zoom Node", package: node, product: "Zoom Node", vendor: "zoom",
         target: nil, versions: "<5.0", description: "Flaw in Zoom Node", references: [], expect: .notThis),
    Case(label: "node / Advantech WebAccess Node", package: node, product: "Advantech WebAccess Node", vendor: "advantech",
         target: nil, versions: "<9.0", description: "Flaw", references: [], expect: .notThis),
    Case(label: "node / Node.js", package: node, product: "Node.js", vendor: "nodejs",
         target: nil, versions: "<26.12.0", description: "HTTP/2 flaw", references: ["https://nodejs.org/en/blog/vulnerability/"], expect: .strong),
    // Plateformes
    Case(label: "deno / faille propre à Windows", package: deno, product: "deno", vendor: "deno",
         target: nil, versions: "2.7.0 <=2.9.7", description: "Deno versions 2.7.0 through 2.9.7 on Windows contain a command injection vulnerability", references: ["https://github.com/denoland/deno/security/advisories/1"], expect: .rejected),
    Case(label: "deno / Windows ET macOS", package: deno, product: "deno", vendor: "deno",
         target: nil, versions: "2.7.0 <=2.9.7", description: "Flaw on Windows and macOS", references: ["https://github.com/denoland/deno/security/advisories/1"], expect: .strong),
    Case(label: "openssl / CPE target_sw=windows", package: openssl, product: "openssl", vendor: "openssl",
         target: "windows", versions: "<3.6.0", description: "Register corruption", references: [], expect: .rejected),
    Case(label: "yt-dlp / bibliothèque Python (target_sw=python)", package: ytdlp, product: "yt-dlp", vendor: "yt-dlp_project",
         target: "python", versions: "<2026.9.1", description: "Command injection", references: ["https://github.com/yt-dlp/yt-dlp/security/advisories/1"], expect: .strong),
    // Numérotation calendaire légitime
    Case(label: "bitwarden-cli / même schéma calendaire", package: bitwarden, product: "Bitwarden CLI", vendor: "Bitwarden",
         target: nil, versions: "2026.4.0", description: "Compromised npm build", references: ["https://bitwarden.com/"], expect: .accepted),
    // Un paquet lié à l'hôte n'est pas une « extension de l'hôte »
    Case(label: "wp-cli / mention de WordPress légitime", package: wpcli, product: "wp-cli", vendor: "wp-cli",
         target: nil, versions: "<2.12.1", description: "Flaw in the WordPress plugin installer of wp-cli", references: ["https://wp-cli.org/"], expect: .strong),
    // Produit étranger
    Case(label: "xz / xzs-mysql", package: xz, product: "xzs-mysql 学之思开源考试系统", vendor: "mindskip",
         target: nil, versions: "3.9.0", description: "Exam system", references: [], expect: .notThis)
]

var failures = 0
for c in cases {
    let range = c.versions.map { VersionConstraintParser.parse($0) }
    let claim = AdvisoryProductClaim(name: c.product, vendor: c.vendor, targetSoftware: c.target,
                                     range: (range?.carriesVersionInformation ?? false) ? range : nil)
    let verdict = ProductIdentityEvaluator.evaluate(claim, description: c.description, references: c.references, package: c.package)
    var got = "", ok = false
    switch verdict {
    case .accepted(let identity):
        got = "accepté (\(identity.confidence.localizedLabel), score \(identity.score))"
        switch c.expect {
        case .strong: ok = identity.confidence == .strong
        case .probable: ok = identity.confidence >= .probable
        case .accepted: ok = true
        default: ok = false
        }
    case .rejected(let reason):
        got = "écarté : \(reason)"; ok = c.expect == .rejected
    case .notThisProduct:
        got = "autre produit"; ok = c.expect == .notThis
    }
    if !ok { failures += 1 }
    print("\(ok ? "✓" : "✗") \(c.label)\n    → \(got)")
}

// Verdict de correctif : la même base, lue deux fois, ne doit pas se contredire.
let patched = PatchVerdict.assess(ranges: [VersionConstraintParser.parse("2026.4.0")], installed: "2026.9.1").verdict
if case .patched = patched { print("✓ bitwarden-cli 2026.9.1 est déclaré corrigé face à 2026.4.0") }
else { failures += 1; print("✗ bitwarden-cli 2026.9.1 devrait être corrigé face à 2026.4.0 (\(patched))") }

print(failures == 0 ? "\nTous les contrôles passent (\(cases.count + 1))." : "\n\(failures) contrôle(s) en échec.")
exit(failures == 0 ? 0 : 1)

#!/usr/bin/env bash
# Test-Suite für ccacct. Läuft komplett in einer Sandbox (CCACCT_PRIMARY/CCACCT_ROOT),
# fasst also niemals das echte ~/.claude an.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCACCT="$HERE/../bin/ccacct"

PASS=0
FAIL=0
CURRENT=""

t() { CURRENT="$1"; }
ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$CURRENT${1:+ — $1}"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n    %s\n' "$CURRENT" "$1"; }

assert_eq()      { [ "$1" = "$2" ] && ok || bad "erwartet '$2', bekommen '$1'"; }
assert_ok()      { if "$@" >/dev/null 2>&1; then ok; else bad "Kommando fehlgeschlagen: $*"; fi; }
assert_fails()   { if "$@" >/dev/null 2>&1; then bad "Kommando hätte fehlschlagen müssen: $*"; else ok; fi; }
assert_file()    { [ -f "$1" ] && ok || bad "Datei fehlt: $1"; }
assert_symlink() { [ -L "$1" ] && ok || bad "kein Symlink: $1"; }
assert_absent()  { [ ! -e "$1" ] && ok || bad "sollte nicht existieren: $1"; }
assert_match()   { case "$1" in *"$2"*) ok ;; *) bad "'$2' nicht gefunden in: $1" ;; esac; }
assert_nomatch() { case "$1" in *"$2"*) bad "'$2' unerwartet gefunden in: $1" ;; *) ok ;; esac; }

# ---------------------------------------------------------------- Sandbox ----
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export CCACCT_PRIMARY="$SANDBOX/.claude"
export CCACCT_ROOT="$SANDBOX/.claude-accounts"
export CCACCT_CLAUDE_BIN="$SANDBOX/fake-claude"

# Ein realistisch bestücktes Primär-Configdir aufbauen.
mkdir -p "$CCACCT_PRIMARY"/{rules,skills/demo,hooks,plugins,projects/proj-a,sessions}
echo "# global instructions" > "$CCACCT_PRIMARY/CLAUDE.md"
echo "# rules"               > "$CCACCT_PRIMARY/rules/sicherheit.md"
echo "name: demo"            > "$CCACCT_PRIMARY/skills/demo/SKILL.md"
echo '{"model":"opus"}'      > "$CCACCT_PRIMARY/settings.json"
echo '{"claudeAiOauth":{"accessToken":"sk-ant-oat-PRIMARY","subscriptionType":"pro","expiresAt":4102444800000}}' \
                             > "$CCACCT_PRIMARY/.credentials.json"
echo "transcript"            > "$CCACCT_PRIMARY/projects/proj-a/log.jsonl"
echo "prompt"                > "$CCACCT_PRIMARY/history.jsonl"
echo "session"               > "$CCACCT_PRIMARY/sessions/s1.json"
mkdir -p "$CCACCT_PRIMARY"/{.git,cache,plans,memory}
echo "gitdata"               > "$CCACCT_PRIMARY/.git/HEAD"
echo "cached"                > "$CCACCT_PRIMARY/cache/x.json"
echo "plan"                  > "$CCACCT_PRIMARY/plans/p1.md"
echo "note"                  > "$CCACCT_PRIMARY/memory/m.md"
echo "log"                   > "$CCACCT_PRIMARY/daemon.log"
cat > "$SANDBOX/.claude.json" <<'EOF'
{
  "oauthAccount": {"emailAddress": "primary@example.com", "organizationUuid": "org-1"},
  "userID": "primary-user-id",
  "machineID": "primary-machine",
  "numStartups": 42,
  "cachedGrowthBookFeatures": {"junk": true},
  "mcpServers": {"diary": {"command": "diary-mcp"}},
  "projects": {"/home/tom/x": {"hasTrustDialogAccepted": true, "allowedTools": ["Bash(ls)"]}},
  "hasCompletedOnboarding": true,
  "skillUsage": {"senior-dev": 7}
}
EOF

# Fake-claude, das nur seine Umgebung protokolliert.
cat > "$CCACCT_CLAUDE_BIN" <<'EOF'
#!/usr/bin/env bash
echo "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-unset}"
echo "ARGS=$*"
EOF
chmod +x "$CCACCT_CLAUDE_BIN"

printf '\n\033[1mccacct — Testsuite\033[0m\n\n'

# ------------------------------------------------------------------ Tests ----
printf '\033[1mGrundlagen\033[0m\n'

t "ccacct existiert und ist ausführbar"
[ -x "$CCACCT" ] && ok || bad "nicht ausführbar: $CCACCT"

t "list ohne Profile zeigt nur das Primärprofil"
out="$("$CCACCT" list 2>&1)"
assert_match "$out" "default"

t "list zeigt die E-Mail des Primäraccounts"
assert_match "$out" "primary@example.com"

printf '\n\033[1mProfil anlegen\033[0m\n'

t "add legt das Profilverzeichnis an"
"$CCACCT" add work >/dev/null 2>&1
assert_eq "$([ -d "$CCACCT_ROOT/work" ] && echo yes || echo no)" "yes"

t "add verlinkt CLAUDE.md geteilt"
assert_symlink "$CCACCT_ROOT/work/CLAUDE.md"

t "geteilter Symlink zeigt auf das Primärprofil"
assert_eq "$(readlink "$CCACCT_ROOT/work/CLAUDE.md")" "$CCACCT_PRIMARY/CLAUDE.md"

t "geteilte Inhalte sind über den Link lesbar"
assert_eq "$(cat "$CCACCT_ROOT/work/rules/sicherheit.md")" "# rules"

t "skills werden geteilt"
assert_symlink "$CCACCT_ROOT/work/skills"

t "settings.json wird geteilt"
assert_symlink "$CCACCT_ROOT/work/settings.json"

t "projects werden standardmäßig geteilt (Kontext bleibt erhalten)"
assert_symlink "$CCACCT_ROOT/work/projects"

t "Credentials werden NICHT geteilt"
assert_absent "$CCACCT_ROOT/work/.credentials.json"

t "kein .config.json angelegt (würde Claude Codes Pfadauflösung kapern)"
assert_absent "$CCACCT_ROOT/work/.config.json"

t "history.jsonl wird nicht geteilt"
assert_absent "$CCACCT_ROOT/work/history.jsonl"

t "add mit --isolate-projects teilt projects nicht"
"$CCACCT" add solo --isolate-projects >/dev/null 2>&1
[ -L "$CCACCT_ROOT/solo/projects" ] && bad "projects sollte isoliert sein" || ok

t "add lehnt einen bereits existierenden Namen ab"
assert_fails "$CCACCT" add work

t "add lehnt ungültige Namen ab"
assert_fails "$CCACCT" add "../evil"

t "add lehnt den reservierten Namen 'default' ab"
assert_fails "$CCACCT" add default

printf '\n\033[1mAuflisten & Status\033[0m\n'

t "list führt neue Profile auf"
out="$("$CCACCT" list 2>&1)"
assert_match "$out" "work"

t "list markiert nicht eingeloggte Profile"
assert_match "$out" "nicht eingeloggt"

t "path liefert das Configdir des Profils"
assert_eq "$("$CCACCT" path work)" "$CCACCT_ROOT/work"

t "path für default liefert das Primärverzeichnis"
assert_eq "$("$CCACCT" path default)" "$CCACCT_PRIMARY"

t "path für unbekanntes Profil schlägt fehl"
assert_fails "$CCACCT" path gibtsnicht

t "which meldet ohne gesetztes CLAUDE_CONFIG_DIR 'default'"
assert_eq "$(env -u CLAUDE_CONFIG_DIR "$CCACCT" which)" "default"

t "which erkennt ein aktives Profil an CLAUDE_CONFIG_DIR"
assert_eq "$(CLAUDE_CONFIG_DIR="$CCACCT_ROOT/work" "$CCACCT" which)" "work"

t "list markiert das aktive Profil"
out="$(CLAUDE_CONFIG_DIR="$CCACCT_ROOT/work" "$CCACCT" list 2>&1)"
assert_match "$out" "*"

t "list richtet Spalten trotz Nicht-ASCII-Platzhaltern aus"
cat > "$SANDBOX/check_align.py" <<'PY2'
import re, sys
lines = [re.sub(r"\x1b\[[0-9;]*m", "", l) for l in sys.stdin.read().splitlines() if l.strip()]
start = lines[0].index("ABO")
misaligned = [l for l in lines[1:] if len(l) > start and l[start] == " "]
sys.exit(1 if misaligned else 0)
PY2
if "$CCACCT" list 2>&1 | python3 "$SANDBOX/check_align.py"; then ok; else bad "Spalten nicht buendig:\n$("$CCACCT" list 2>&1)"; fi

printf '\n\033[1mIsolation der Anmeldung\033[0m\n'

# Login in Profil "work" simulieren
cat > "$CCACCT_ROOT/work/.credentials.json" <<'EOF'
{"claudeAiOauth":{"accessToken":"sk-ant-oat-WORK","subscriptionType":"max","expiresAt":4102444800000}}
EOF
cat > "$CCACCT_ROOT/work/.claude.json" <<'EOF'
{"oauthAccount":{"emailAddress":"work@example.com","organizationUuid":"org-2"}}
EOF

t "Profil-Credentials überschreiben die des Primärprofils nicht"
assert_match "$(cat "$CCACCT_PRIMARY/.credentials.json")" "sk-ant-oat-PRIMARY"

t "list zeigt die E-Mail je Profil getrennt"
out="$("$CCACCT" list 2>&1)"
assert_match "$out" "work@example.com"

t "list zeigt den Abo-Typ je Profil"
assert_match "$out" "max"

t "list zeigt abgelaufene Tokens als solche"
cat > "$CCACCT_ROOT/solo/.credentials.json" <<'EOF'
{"claudeAiOauth":{"accessToken":"sk-ant-oat-OLD","subscriptionType":"pro","expiresAt":1000000000000}}
EOF
cat > "$CCACCT_ROOT/solo/.claude.json" <<'EOF'
{"oauthAccount":{"emailAddress":"old@example.com"}}
EOF
out="$("$CCACCT" list 2>&1)"
assert_match "$out" "abgelaufen"

printf '\n\033[1mAusführen\033[0m\n'

t "run startet claude mit dem Configdir des Profils"
out="$("$CCACCT" run work 2>&1)"
assert_match "$out" "CLAUDE_CONFIG_DIR=$CCACCT_ROOT/work"

t "run reicht zusätzliche Argumente durch"
out="$("$CCACCT" run work --model opus 2>&1)"
assert_match "$out" "ARGS=--model opus"

t "run für default setzt CLAUDE_CONFIG_DIR nicht"
out="$(env -u CLAUDE_CONFIG_DIR "$CCACCT" run default 2>&1)"
assert_match "$out" "CLAUDE_CONFIG_DIR=unset"

t "run für unbekanntes Profil schlägt fehl"
assert_fails "$CCACCT" run gibtsnicht

t "exec führt ein beliebiges Kommando im Profilkontext aus"
out="$("$CCACCT" exec work -- sh -c 'echo $CLAUDE_CONFIG_DIR' 2>&1)"
assert_eq "$out" "$CCACCT_ROOT/work"

printf '\n\033[1mSync / Reparatur\033[0m\n'

t "sync repariert einen gelöschten Symlink"
rm "$CCACCT_ROOT/work/CLAUDE.md"
"$CCACCT" sync work >/dev/null 2>&1
assert_symlink "$CCACCT_ROOT/work/CLAUDE.md"

t "sync ersetzt einen Symlink, den Claude Code durch eine Datei ersetzt hat"
rm "$CCACCT_ROOT/work/settings.json"
echo '{"model":"stale"}' > "$CCACCT_ROOT/work/settings.json"
"$CCACCT" sync work >/dev/null 2>&1
assert_symlink "$CCACCT_ROOT/work/settings.json"

t "sync verlinkt neu im Primärprofil aufgetauchte Shares"
mkdir -p "$CCACCT_PRIMARY/agents"
echo "agent" > "$CCACCT_PRIMARY/agents/a.md"
"$CCACCT" sync --all >/dev/null 2>&1
assert_symlink "$CCACCT_ROOT/work/agents"

t "sync fasst Credentials nicht an"
assert_match "$(cat "$CCACCT_ROOT/work/.credentials.json")" "sk-ant-oat-WORK"

printf '\n\033[1mLöschen\033[0m\n'

t "rm verweigert das Primärprofil"
assert_fails "$CCACCT" rm default --force

t "rm ohne --force fragt nach statt zu löschen"
assert_fails "$CCACCT" rm solo

t "solo existiert nach dem verweigerten rm weiterhin"
assert_eq "$([ -d "$CCACCT_ROOT/solo" ] && echo yes || echo no)" "yes"

t "rm --force entfernt das Profil"
"$CCACCT" rm solo --force >/dev/null 2>&1
assert_absent "$CCACCT_ROOT/solo"

t "rm eines Profils lässt geteilte Primärdateien unangetastet"
assert_file "$CCACCT_PRIMARY/CLAUDE.md"

t "rm eines Profils lässt geteilte projects unangetastet"
assert_file "$CCACCT_PRIMARY/projects/proj-a/log.jsonl"

printf '\n\033[1mIdentisches Setup (Denylist statt Allowlist)\033[0m\n'

t "beliebige neue Datei im Primaerprofil wird automatisch geteilt"
echo "neu" > "$CCACCT_PRIMARY/website-spielregeln.md"
"$CCACCT" add fresh >/dev/null 2>&1
assert_symlink "$CCACCT_ROOT/fresh/website-spielregeln.md"

t "beliebiges neues Verzeichnis im Primaerprofil wird automatisch geteilt"
assert_symlink "$CCACCT_ROOT/fresh/plans"

t "memory/ wird geteilt"
assert_symlink "$CCACCT_ROOT/fresh/memory"

t ".git wird NICHT verlinkt (wuerde das Profil zum Worktree machen)"
assert_absent "$CCACCT_ROOT/fresh/.git"

t "sessions werden nicht geteilt"
assert_absent "$CCACCT_ROOT/fresh/sessions"

t "cache wird nicht geteilt"
assert_absent "$CCACCT_ROOT/fresh/cache"

t "daemon.log wird nicht geteilt"
assert_absent "$CCACCT_ROOT/fresh/daemon.log"

t "add erzeugt eine .claude.json im Profil"
assert_file "$CCACCT_ROOT/fresh/.claude.json"

t "Profil-.claude.json uebernimmt mcpServers aus dem Primaerprofil"
assert_match "$(cat "$CCACCT_ROOT/fresh/.claude.json")" '"diary"'

t "Profil-.claude.json uebernimmt projects inkl. Trust und Permissions"
assert_match "$(cat "$CCACCT_ROOT/fresh/.claude.json")" "hasTrustDialogAccepted"

t "Profil-.claude.json uebernimmt hasCompletedOnboarding"
assert_match "$(cat "$CCACCT_ROOT/fresh/.claude.json")" "hasCompletedOnboarding"

t "Profil-.claude.json uebernimmt NICHT den oauthAccount des Primaerprofils"
assert_nomatch "$(cat "$CCACCT_ROOT/fresh/.claude.json")" "primary@example.com"

t "Profil-.claude.json uebernimmt NICHT die userID des Primaerprofils"
assert_nomatch "$(cat "$CCACCT_ROOT/fresh/.claude.json")" "primary-user-id"

t "Profil-.claude.json uebernimmt keine accountgebundenen Caches"
assert_nomatch "$(cat "$CCACCT_ROOT/fresh/.claude.json")" "cachedGrowthBookFeatures"

t "sync zieht einen neu angelegten MCP-Server ins Profil nach"
python3 - "$SANDBOX/.claude.json" <<'PY3'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["mcpServers"]["neu"] = {"command": "neu-mcp"}
json.dump(d, open(p, "w"))
PY3
touch -d '2020-01-01' "$CCACCT_ROOT/fresh/.claude.json"
"$CCACCT" sync fresh >/dev/null 2>&1
assert_match "$(cat "$CCACCT_ROOT/fresh/.claude.json")" '"neu-mcp"'

t "sync laesst die Anmeldung des Profils unangetastet"
python3 - "$CCACCT_ROOT/fresh/.claude.json" <<'PY3'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["oauthAccount"] = {"emailAddress": "fresh@example.com"}
json.dump(d, open(p, "w"))
PY3
touch -d '2020-01-01' "$CCACCT_ROOT/fresh/.claude.json"
"$CCACCT" sync fresh >/dev/null 2>&1
assert_match "$(cat "$CCACCT_ROOT/fresh/.claude.json")" "fresh@example.com"

t "sync erhaelt profil-eigene projects-Eintraege"
python3 - "$CCACCT_ROOT/fresh/.claude.json" <<'PY3'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["projects"]["/nur/hier"] = {"hasTrustDialogAccepted": True}
json.dump(d, open(p, "w"))
PY3
touch -d '2020-01-01' "$CCACCT_ROOT/fresh/.claude.json"
"$CCACCT" sync fresh >/dev/null 2>&1
assert_match "$(cat "$CCACCT_ROOT/fresh/.claude.json")" "/nur/hier"

t "sync ueberspringt die .claude.json einer laufenden Session"
touch "$CCACCT_ROOT/fresh/.claude.json"
out="$("$CCACCT" sync fresh 2>&1)"
assert_match "$out" "uebersprungen"

t "sync --force schreibt auch bei laufender Session"
touch "$CCACCT_ROOT/fresh/.claude.json"
out="$("$CCACCT" sync fresh --force 2>&1)"
assert_nomatch "$out" "uebersprungen"

t "sync --links-only fasst .claude.json nicht an"
python3 - "$CCACCT_ROOT/fresh/.claude.json" <<'PY3'
import json, sys
json.dump({"marker": "unberuehrt"}, open(sys.argv[1], "w"))
PY3
touch -d '2020-01-01' "$CCACCT_ROOT/fresh/.claude.json"
"$CCACCT" sync fresh --links-only >/dev/null 2>&1
assert_match "$(cat "$CCACCT_ROOT/fresh/.claude.json")" "unberuehrt"

printf '\n\033[1mdoctor — Drift-Erkennung\033[0m\n'

t "doctor meldet ein sauberes Profil als in Ordnung"
"$CCACCT" sync fresh --force >/dev/null 2>&1
assert_ok "$CCACCT" doctor fresh

t "doctor erkennt einen fehlenden Symlink"
rm "$CCACCT_ROOT/fresh/CLAUDE.md"
assert_fails "$CCACCT" doctor fresh

t "doctor benennt den fehlenden Eintrag"
out="$("$CCACCT" doctor fresh 2>&1)"
assert_match "$out" "CLAUDE.md"

t "doctor erkennt einen fehlenden .claude.json-Schluessel"
"$CCACCT" sync fresh --force >/dev/null 2>&1
python3 - "$CCACCT_ROOT/fresh/.claude.json" <<'PY3'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.pop("mcpServers", None)
json.dump(d, open(p, "w"))
PY3
assert_fails "$CCACCT" doctor fresh

t "doctor repariert nichts von selbst"
assert_nomatch "$("$CCACCT" doctor fresh 2>&1)" "repariert"

t "doctor --fix behebt die Drift"
"$CCACCT" doctor fresh --fix >/dev/null 2>&1
assert_ok "$CCACCT" doctor fresh

t "doctor --all prueft alle Profile"
out="$("$CCACCT" doctor --all 2>&1)"
assert_match "$out" "fresh"

printf '\n\033[1mautosync — Hook in der geteilten settings.json\033[0m\n'

t "autosync status meldet zunaechst 'nicht installiert'"
assert_eq "$("$CCACCT" autosync status 2>&1)" "autosync ist nicht installiert"

t "autosync install traegt einen SessionStart-Hook ein"
"$CCACCT" autosync install >/dev/null 2>&1
assert_match "$(cat "$CCACCT_PRIMARY/settings.json")" "SessionStart"

t "autosync install laesst bestehende Settings intakt"
assert_match "$(cat "$CCACCT_PRIMARY/settings.json")" '"opus"'

t "autosync install ist idempotent"
"$CCACCT" autosync install >/dev/null 2>&1
assert_eq "$(grep -c 'CCACCT_AUTOSYNC' "$CCACCT_PRIMARY/settings.json")" "1"

t "autosync status meldet danach 'installiert'"
assert_eq "$("$CCACCT" autosync status 2>&1)" "autosync ist installiert"

t "autosync uninstall entfernt den Hook wieder"
"$CCACCT" autosync uninstall >/dev/null 2>&1
assert_nomatch "$(cat "$CCACCT_PRIMARY/settings.json")" "CCACCT_AUTOSYNC"

t "autosync uninstall laesst andere Settings intakt"
assert_match "$(cat "$CCACCT_PRIMARY/settings.json")" '"opus"'

printf '\n\033[1mShell-Integration\033[0m\n'

t "shell-init fish gibt eine fish-Funktion aus"
out="$("$CCACCT" shell-init fish 2>&1)"
assert_match "$out" "function ccacct"

t "shell-init fish setzt CLAUDE_CONFIG_DIR global"
assert_match "$out" "set -gx CLAUDE_CONFIG_DIR"

t "shell-init fish behandelt 'use default' als unset"
assert_match "$out" "set -e CLAUDE_CONFIG_DIR"

t "shell-init bash gibt eine bash-Funktion aus"
out="$("$CCACCT" shell-init bash 2>&1)"
assert_match "$out" "ccacct()"

t "shell-init lehnt unbekannte Shells ab"
assert_fails "$CCACCT" shell-init tcsh

t "help zeigt die Kommandos"
out="$("$CCACCT" help 2>&1)"
assert_match "$out" "login"

t "unbekanntes Kommando schlägt fehl"
assert_fails "$CCACCT" quatsch

# ----------------------------------------------------------------- Bilanz ----
printf '\n\033[1mErgebnis:\033[0m %d bestanden, %d fehlgeschlagen\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

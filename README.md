# ccacct — mehrere Claude-Code-Accounts, ein einziges Setup

Claude Code kennt keinen eingebauten Account-Switcher: pro Configdir gibt es genau
eine Anmeldung. `ccacct` nutzt das aus — ein `CLAUDE_CONFIG_DIR` pro Account.

**Das Setup existiert dabei genau einmal, in `~/.claude`.** Profile enthalten keine
Kopien, sondern Symlinks auf genau diese Dateien. Alles liegt weiterhin am selben Ort;
wer eine Datei über ein Profil bearbeitet, bearbeitet das Original.

**Das Einzige, was sich zwischen Profilen unterscheidet, ist der eingeloggte Account.**

## Installation

```fish
ln -sf ~/Projekte/SEProjects/claude-accounts/bin/ccacct ~/.local/bin/ccacct
# einmalig in ~/.config/fish/config.fish:
#   if type -q ccacct
#       ccacct shell-init fish | source
#   end
ccacct autosync install    # hält alle Profile bei jedem Sessionstart identisch
```

Für bash/zsh: `eval "$(ccacct shell-init bash)"` in `.bashrc`/`.zshrc`.

## Benutzung

```fish
ccacct add work            # Profil anlegen (verlinkt auf ~/.claude)
ccacct login work          # Claude Code startet, dort /login → zweiter Account
ccacct list                # wer ist wo eingeloggt, welches Abo, Token-Status
ccacct use work            # aktuelle Shell auf "work" umstellen
claude                     # läuft jetzt unter dem work-Account
ccacct use default         # zurück
ccacct run work -p "…"     # einmalig, ohne die Shell umzustellen
ccacct doctor --all        # prüft, ob jedes Profil identisch zu default ist
ccacct doctor work --fix   # behebt Abweichungen
```

Jedes Terminal kann ein anderes Profil aktiv haben — zwei Accounts arbeiten parallel.

## Was geteilt wird

**Alles** aus `~/.claude` — Denylist statt Allowlist. Neue Dateien, die du oder Claude
Code künftig dort anlegen, tauchen automatisch in jedem Profil auf (`ccacct autosync`
zieht sie beim Sessionstart nach). Geteilt sind damit u.a. `CLAUDE.md`, `settings.json`,
`settings.local.json`, `rules/`, `skills/`, `hooks/`, `plugins/`, `mcp-servers/`,
`.mcp.json`, `memory/`, `plans/`, `servers/`, `projects/` (Transkripte, `--continue`,
Auto-Memory).

Nicht geteilt wird nur, was den Account oder die laufende Session ausmacht:
`.credentials.json` (die OAuth-Tokens — genau hier steckt der Unterschied),
`history.jsonl`, `sessions/`, `tasks/`, `jobs/`, `queue/`, `file-history/`,
`session-env/`, `shell-snapshots/`, Caches und Daemon-Dateien. Ebenfalls nicht
verlinkt: `.git` (`~/.claude` ist ein Repo — ein Link machte das Profil zum Worktree).

### Die eine Ausnahme: `.claude.json`

Claude Code mischt in dieser Datei Setup und Identität: `mcpServers` und `projects`
(inkl. Trust-Status und Permissions) stehen dort direkt neben `oauthAccount`. Sie kann
deshalb nicht verlinkt werden, ohne die Account-Trennung aufzugeben. `ccacct` spiegelt
stattdessen **alle** Schlüssel aus dem Primärprofil hinein — außer den Identitäts- und
Cache-Schlüsseln (`oauthAccount`, `userID`, `machineID`, Abo-Caches …). Ergebnis:
dieselben MCP-Server, dieselben freigegebenen Projekte, derselbe Trust-Status — nur
eben ein anderer Account. Das ist die einzige echte Datei in einem Profilverzeichnis.

Läuft in einem Profil gerade eine Session (`.claude.json` jünger als 120 s), überspringt
`sync` diese Datei, um der laufenden Session nicht dazwischenzuschreiben — `--force`
erzwingt es.

## Tests

```fish
./tests/test_ccacct.sh
```

86 Tests, laufen komplett in einer Sandbox (`CCACCT_PRIMARY`/`CCACCT_ROOT`/
`CCACCT_CLAUDE_BIN`) und fassen das echte `~/.claude` nie an.

## Hinweis

Mehrere eigene Abos zu besitzen ist erlaubt; verboten sind Account-Sharing,
Weiterverkauf und Limit-Umgehung. `ccacct` rotiert deshalb bewusst **nicht**
automatisch bei Rate-Limits — der Wechsel ist immer explizit.

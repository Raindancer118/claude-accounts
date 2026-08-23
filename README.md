# ccacct — mehrere Claude-Code-Accounts, nahtlos gewechselt

Claude Code kennt keinen eingebauten Account-Switcher: pro Configdir gibt es genau
eine Anmeldung. `ccacct` nutzt das aus — ein Configdir pro Account, aber alles
Accountneutrale (CLAUDE.md, Rules, Skills, Hooks, Plugins, Settings, Projekte/
Transkripte) per Symlink aus dem Primärprofil geteilt. Ergebnis: getrennte Accounts,
ein Setup.

## Installation

```fish
ln -sf ~/Projekte/SEProjects/claude-accounts/bin/ccacct ~/.local/bin/ccacct
# einmalig in ~/.config/fish/config.fish:
#   if type -q ccacct
#       ccacct shell-init fish | source
#   end
```

Für bash/zsh: `eval "$(ccacct shell-init bash)"` in `.bashrc`/`.zshrc`.

## Benutzung

```fish
ccacct add work            # Profil anlegen (teilt Config mit "default")
ccacct login work          # Claude Code startet, dort /login → zweiter Account
ccacct list                # wer ist wo eingeloggt, welches Abo, Token-Status
ccacct use work            # aktuelle Shell auf "work" umstellen
claude                     # läuft jetzt unter dem work-Account
ccacct use default         # zurück
ccacct run work -p "…"     # einmalig, ohne die Shell umzustellen
```

Jedes Terminal kann ein anderes Profil aktiv haben — zwei Accounts können also
parallel arbeiten.

## Was geteilt wird, was nicht

| geteilt (Symlink → `~/.claude/…`)                                                | getrennt je Profil                                              |
|----------------------------------------------------------------------------------|-----------------------------------------------------------------|
| `CLAUDE.md`, `settings.json`, `rules/`, `skills/`, `hooks/`, `agents/`, `commands/`, `output-styles/`, `plugins/`, `scripts/`, `mcp-servers/`, `.mcp.json`, `servers.md`, `projects/` | `.credentials.json`, `.claude.json` (oauthAccount), `history.jsonl`, `sessions/`, `tasks/`, `file-history/`, Caches |

`projects/` (Transkripte, `--continue`/`--resume`, Auto-Memory) wird bewusst geteilt,
damit der Kontext beim Accountwechsel nicht verloren geht. Mit
`ccacct add <name> --isolate-projects` bleibt auch das getrennt.

Ersetzt Claude Code einen geteilten Symlink beim Schreiben durch eine echte Datei
(atomares `rename`), stellt `ccacct sync --all` die Verlinkung wieder her.

## Tests

```fish
./tests/test_ccacct.sh
```

52 Tests, laufen komplett in einer Sandbox (`CCACCT_PRIMARY`/`CCACCT_ROOT`/
`CCACCT_CLAUDE_BIN`) und fassen das echte `~/.claude` nie an.

## Hinweis

Mehrere eigene Abos zu besitzen ist erlaubt; verboten sind Account-Sharing,
Weiterverkauf und Limit-Umgehung. `ccacct` rotiert deshalb bewusst **nicht**
automatisch bei Rate-Limits — der Wechsel ist immer explizit.

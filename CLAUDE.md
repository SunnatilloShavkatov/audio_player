# CLAUDE.md

@AGENTS.md

## Claude Code notes

- `AGENTS.md` above is the source of truth for layout, commands, conventions and the native lifecycle rules. Edit it
  there, not here, so other agents stay in sync.
- Never run `git commit` in this repository (also set in the user's global config). Show the diff and stop.
- For Swift changes, `flutter build ios --simulator --no-codesign` from `example/` is the quickest compile check.
  It does not exercise runtime behavior such as engine teardown; say so when reporting results.

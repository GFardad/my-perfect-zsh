# Zsh UX and startup audit — 2026-11-22

## Scope and status

The previous interactive configuration was inspected without modifying the live
shell during the audit phase. Exact configuration copies, syscall traces, and
prototypes were archived locally under `audit/2026-11-22/`; that directory is
ignored because it contains machine-specific data.

The modular implementation now exists in this repository and passes isolated
smoke, PTY, privacy, and performance checks. The live migration is performed
only after those checks succeed and retains rollback files.

## Root cause of the original delay

The first executable command in the old `~/.zshrc` was:

```zsh
fetch
```

`fetch` is an animated ASCII system-information program. Its default is 2,000
frames at 50 ms per frame, so it blocked for approximately 100 seconds.

Measured interactive startup:

```text
zsh -i -c exit
100.503 s
```

A temporary copy with only that command removed started in:

```text
0.405 s  (first/cold)
0.056 s  (warm)
0.060 s  (warm)
```

The archived syscall trace confirms repeated frame rendering and 50 ms sleeps;
this was not a network hang.

## Important findings

1. Powerlevel10k's instant-prompt cache snippet was at the bottom of `.zshrc`;
   it belongs near the top.
2. Atuin, thefuck, and fzf were initialized in a background subshell. Their
   functions and bindings never reached the parent shell.
3. Atuin and fzf both claimed `Ctrl-R`. Atuin also claimed Up and `?`.
4. `thefuck --alias` cost about 100 ms and belonged behind a lazy wrapper.
5. History limits were 50,000,000 in-memory and 2,000,000,000 saved entries.
6. `APPEND_HISTORY` and `SHARE_HISTORY` were both enabled.
7. Leading-space commands were recorded by Zsh and Atuin; a later isolated PTY
   run also exposed a tab-prefixed Atuin gap that the accept-line privacy wrapper
   closes.
8. The distribution's `/etc/zsh/zshrc` also ran `compinit`; this duplicated the
   user completion setup and contributed about 70 ms before user startup.
9. `GOPROXY=direct` and `GOSUMDB=off` were global.
10. `PYTHONPATH` used a leading colon when previously unset, adding the current
    directory to Python's import path.
11. Machine-specific paths and aliases made the old file unsuitable for
    publication.
12. zsh-autocomplete, fzf-tab, fast-syntax-highlighting, zsh-autopair, and
    zsh-opencode-tab were installed but mostly unused.
13. The local Powerlevel10k checkout was updated to v1.21.0
    (`50a35cc8d9f1488d18fb8aea6cddcfc31189cc9f`) during the audit.
14. fast-syntax-highlighting contains a first-use network fallback for an
    optional theme. The implementation now seeds that file locally so the
    fallback cannot run during startup.
15. Powerlevel10k's gitstatus integration can auto-install a platform-specific
    daemon during startup. The daemon and its installer are disabled so VCS
    status uses Zsh's local `vcs_info` fallback without network access.

## Original module costs

| Operation | Approximate cost |
|---|---:|
| `zoxide init zsh` | 3 ms |
| `atuin init zsh` | 12 ms |
| `fzf --zsh` | 5 ms |
| `thefuck --alias` | 100 ms |
| Oh My Zsh source | 45 ms warm / 335 ms cold |
| Powerlevel10k config | 4 ms |
| opam init | 2 ms |
| Bun completion source | 16 ms |

## Implemented architecture

```text
.zshenv                       global-RC gate
.zshrc                        ordered module interface
modules/bootstrap.zsh         paths and dependency seam
modules/options.zsh           curated Zsh options
modules/local.zsh             machine-local configuration seam
modules/history.zsh           bounded private history
modules/completion.zsh        audited compinit, fzf-tab, deferred Bun
modules/navigation.zsh        zoxide and fzf widgets
modules/history-ui.zsh        Atuin and autosuggestions
modules/prompt.zsh            Powerlevel10k
modules/lazy-tools.zsh        one-shot wrappers
modules/keys.zsh              final reserved-key enforcement
modules/syntax.zsh            fast-syntax-highlighting, sourced last
config/p10k.zsh               compact prompt policy
config/atuin/config.toml      privacy-safe defaults
deps.lock                     exact source and tool versions
scripts/                      install, rollback, history import, benchmark
tests/                        smoke, PTY, and performance checks
```

The explicit source list is the interface. Each module owns one concern,
optional dependencies fail closed, and the final keymap is the single
enforcement point.

## Explicit key ownership

| Key | Owner | Fallback/behavior |
|---|---|---|
| `Tab` | fzf-tab | Native Zsh completion if fzf-tab is unavailable |
| `Ctrl-R` | Atuin fuzzy history | FZF history, then unbound |
| `Ctrl-T` | FZF file picker | Unbound without fzf |
| `Alt-C` | FZF directory picker | Unbound without fzf |
| `Up` | Native Zsh history | Always available |
| `?` | Literal text insertion | Atuin AI disabled |
| `/` in vi command mode | Native vi history search | Always available |
| `z` / `zi` | zoxide | Unavailable without zoxide |

## Deliberate exclusions

- **Starship:** Powerlevel10k already owns the prompt.
- **zsh-autocomplete:** overlaps with fzf-tab and changes the completion UX.
- **zsh-syntax-highlighting:** fast-syntax-highlighting is the sole highlighter.
- **Oh My Zsh:** avoid framework magic, broad aliases, duplicate compinit, and
  ambiguous plugin ordering.
- **Eager thefuck, fetch, conda, opam, or tool completion:** load only on
  demand or keep them in local configuration.
- **Global `GOSUMDB=off`:** never part of the published core.

## Security and privacy decisions

- Keep completion's `compaudit` enabled and run one real `compinit`.
- Disable automatic Atuin sync and update checks by default.
- Enable Atuin secret filtering and exclude leading-whitespace commands with
  the exact `^\s+` filter. The runtime additionally guards Atuin's preexec path
  because Zsh strips leading whitespace before Atuin receives the command.
- Validate Atuin changes in an isolated candidate before atomic replacement;
  preserve the active configuration byte-for-byte when validation fails.
- Parse legacy multiline history into logical records before applying the
  leading-whitespace privacy rule.
- Evaluate only trusted output from locally installed binaries.
- Never evaluate downloaded shell code during startup.
- Disable Powerlevel10k's gitstatus daemon and auto-installer; use local
  `vcs_info` status instead.
- Remove global `GOSUMDB=off` and `GOPROXY=direct`.
- Do not create an empty leading component in `PYTHONPATH`.
- Keep VPN, paste-service, IDE, CUDA, and personal tool policy in local files.
- Suppress local-file stdout so it cannot corrupt the instant prompt.

## Performance result

Measured in an isolated HOME/XDG environment with real login-interactive Zsh:

| Measurement | Original | Implemented | Budget |
|---|---:|---:|---:|
| Cold startup | 100.503 s | 223 ms | 300 ms |
| Warm p50 | 100.503 s | 49 ms | 60 ms |
| Warm p95 | 100.503 s | 53 ms | 80 ms |
| Warm max | 100.503 s | 56 ms across 30 samples | 80 ms |

The cold sample includes completion cache creation. Warm samples use the cache.
The test suite also proves that fetch, fastfetch, Bun, Python, fzf, thefuck,
curl, and wget are not executed during startup.

## Acceptance criteria

1. [x] No startup animation or multi-second blocker.
2. [x] No startup stdout/stderr in the isolated interactive shell.
3. [x] No startup network access or forbidden child process.
4. [x] Key ownership matches the table above in emacs, vi-insert, and vi-command
   modes.
5. [x] History is bounded, append-only, duplicate-resistant, and excludes
   leading-whitespace commands in Zsh and Atuin, including tab-prefixed
   commands; multiline legacy records are filtered as complete logical commands.
6. [x] The runtime contains no personal path, VPN, paste-service, IDE, CUDA, or
   conda policy.
7. [x] Machine-specific behavior lives under
   `~/.config/my-perfect-zsh/`.
8. [x] Missing optional tools degrade without diagnostics.
9. [x] The sole syntax highlighter is sourced after all custom widgets.
10. [x] Smoke, installer, PTY, privacy, and performance checks reproduce the
    claims.
11. [x] Installation and rollback preserve previous startup files, including
    repeated-install and dangling-backup edge cases.

## Residual risks

- fzf-tab, autosuggestions, and syntax highlighting remain order-sensitive;
  the binding and PTY tests are mandatory.
- Exact dependency locks delay upstream fixes and require deliberate updates.
- The pinned fzf shell code must track the installed fzf binary.
- Atuin remains eager because deferring it changes observable history behavior.
- Native `vcs_info` status can be slower than Powerlevel10k's daemon in very
  large repositories, but it remains deterministic and network-free.
- Lazy wrappers move latency to first use.
- Skipping global RC files intentionally removes distribution-wide aliases and
  helpers; this configuration owns completion, prompt, and key behavior.

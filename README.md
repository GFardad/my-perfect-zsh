# My Perfect ZSH

A fast, coherent, publishable Zsh configuration built from pinned modules rather
than a plugin framework.

The configuration has one owner for completion, prompt, history, and reserved
keys. It starts without animation, network access, or background shell-mutating
initialization, and it keeps machine-specific policy outside the published core.

## Highlights

- Powerlevel10k as the sole prompt; no Starship or Oh My Zsh runtime.
- Local `vcs_info` status with no background gitstatus daemon or runtime download.
- Atuin for fuzzy history, fzf for file/directory search, fzf-tab for completion.
- zoxide for directory navigation and autosuggestions from local Zsh history.
- Lazy, retryable `thefuck`, archive extraction, Bun completion, and system information.
- Bounded history with leading-whitespace suppression in Zsh (spaces and tabs)
  and the same policy in Atuin, including Atuin's preexec capture path.
- Exact source commits in `deps.lock`; optional binaries are version-checked.
- Machine-local configuration under `~/.config/my-perfect-zsh/`.

## Quick start

```sh
git clone <repository-url> my-perfect-zsh
cd my-perfect-zsh
./scripts/install
exec zsh
```

The installer:

1. installs the exact dependency commits into ignored `vendor/`;
2. verifies the tested Atuin, zoxide, and fzf versions;
3. validates and atomically applies privacy-safe Atuin settings;
4. backs up and links `~/.zshrc` and `~/.zshenv` to this repository.

Atuin changes are first written to an isolated candidate and parsed by the
installed Atuin binary. The active configuration is replaced only after every
privacy key and the exact `^\s+` history filter validate. The installer honors
`ATUIN_CONFIG_DIR` when it is set explicitly. Startup-file backups use
collision-proof names, including when a preferred backup path is a dangling
symlink.

Use `./scripts/install --no-link` to install dependencies without changing
startup files. Use `./scripts/install --allow-version-drift` when using newer
system packages.

## Requirements

- Zsh 5.8 or newer
- Git
- Atuin, zoxide, and fzf for the complete interface
- Bun and thefuck are optional and load only when first used

The published source never downloads or evaluates shell code during startup.
Only the installer contacts GitHub, and only to fetch pinned checkouts.

## Key ownership

| Key | Action | Fallback |
|---|---|---|
| `Ctrl-R` | Atuin fuzzy history | fzf history, then unbound |
| `Ctrl-T` | fzf file picker | unbound |
| `Alt-C` | fzf directory picker | unbound |
| `Tab` | fzf-tab completion | native Zsh completion |
| `Up` | native Zsh history | always available |
| `?` | literal text insertion | no Atuin AI binding |
| `/` in vi command mode | native vi history search | always available |
| `z` / `zi` | zoxide navigation | unavailable without zoxide |

The final keymap is enforced in `modules/keys.zsh`, after every widget exists.

## Architecture

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

The explicit source list is the interface. Each module owns one concern and
keeps implementation details out of the entry point.

## Local configuration

The published core contains no personal aliases, paths, IDE launchers, VPN
configuration, paste services, or tool initialization. Put those in either:

- `~/.config/my-perfect-zsh/local.zsh`, or
- `~/.config/my-perfect-zsh/local.d/*.zsh`.

Repository-local `config/local.d/` is also supported and ignored by Git. Local
files are sourced in lexical order with stdout suppressed, so they cannot
corrupt Powerlevel10k's instant prompt. The final reserved keymap is applied
after local files, preventing them from stealing owned keys.

See `config/local.zsh.example` for the interface.

## Privacy and security

- `compaudit` remains enabled; completion runs exactly once.
- Atuin defaults to no automatic sync, no update checks, secret filtering, and
  fuzzy search. Commands whose first character is whitespace, including a tab,
  are excluded from Atuin history; Zsh history uses `HIST_IGNORE_SPACE` plus a
  `zshaddhistory` hook. An accept-line wrapper flags the raw leading-whitespace
  command before Zsh strips it, and the Atuin preexec hook honors that flag,
  because Atuin otherwise captures the stripped command.
- `GOSUMDB=off`, `GOPROXY=direct`, and unsafe leading-colon `PYTHONPATH` values
  are not part of the core.
- Shell code is evaluated only from locally installed, trusted binaries.
- Fast Syntax Highlighting's optional theme is seeded from the pinned checkout,
  preventing its built-in network fallback from running.
- Powerlevel10k's gitstatus daemon and auto-installer are disabled; prompt VCS
  status uses Zsh's local `vcs_info` implementation.
- `~/.zsh_history` can be imported once with `./scripts/import-history`.
  The importer treats backslash-continued lines as one logical command and
  excludes the entire record when its first character is whitespace.

Leading-whitespace suppression is a convenience, not a guarantee that secrets
cannot appear in output, process arguments, logs, prompts, or transcripts.

## Performance

The benchmark uses isolated XDG directories and a real login-interactive Zsh:

```sh
./scripts/benchmark.sh 30
```

Measured on 2026-11-22 in the audit environment:

```text
cold:     246 ms   (budget 300 ms)
warm p50:  37 ms   (budget  60 ms)
warm p95:  40 ms   (budget  80 ms)
```

Results vary by machine. The benchmark fails when a budget is exceeded.

## Development

```sh
./tests/run                 # syntax, lint, smoke, PTY, and performance checks
./tests/run --no-perf       # skip the benchmark
./scripts/check-syntax.sh   # zsh -n for every runtime file
./scripts/install --check   # verify vendor commits and tool versions
```

The test suite proves startup silence, no forbidden startup processes, reserved
key ownership in all supported keymaps, optional-tool fallback, retryable lazy
parent-shell initialization, leading-whitespace and multiline history privacy,
installer validation and rollback, and PTY-backed ZLE dispatch behavior.

## Rollback

```sh
./scripts/uninstall
```

Rollback restores the most recent backup of `~/.zshrc` and `~/.zshenv`,
preserving vendor checkouts, local configuration, Atuin data, and imported
history. Backup paths are recorded separately, so repeated installations do not
overwrite earlier rollback points. The audit also kept a timestamped copy of the
original live configuration.

## License

MIT. Vendored dependencies are installed separately and retain their own
licenses.

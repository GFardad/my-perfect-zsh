# Design

## Goals

My Perfect ZSH optimizes for four properties in this order:

1. **Fast and quiet startup** — no animation, network request, or unbounded
   initializer during shell startup.
2. **Coherent interaction** — exactly one owner for completion, prompt, history,
   and every reserved key.
3. **Locality** — behavior and verification live in one module instead of being
   spread across a framework and arbitrary plugin order.
4. **Publishability** — the core contains portable policy; machine-specific
   behavior lives in ignored local configuration.

Starship, Oh My Zsh, zsh-autocomplete, and a second syntax highlighter are
intentionally absent. They overlap with interfaces this configuration already
owns.

## Deep modules

A module is useful here when its interface is small and its implementation
absorbs complexity. The explicit source list in `.zshrc` is the only startup
interface callers need to know.

| Module | Interface | Implementation hidden behind it |
|---|---|---|
| Bootstrap | Repository and XDG paths become available | PATH idempotence, secure directory creation, Atuin config selection |
| Options | Curated interactive behavior | Option conflicts and defaults |
| Local | Machine policy is loaded | Ordered files, quiet stdout, override capture and re-application |
| History | `HISTFILE`, bounded size, private policy | Duplicate and leading-space handling |
| Completion | Completion is initialized once | Styles, cache, fzf-tab order, deferred Bun |
| Navigation | `z`, `zi`, `Ctrl-T`, `Alt-C` | zoxide initialization, fzf fallback widgets |
| History UI | Atuin search and autosuggestions exist | Atuin flags, parent-shell hooks, local-history strategy |
| Prompt | One Powerlevel10k prompt exists | Theme ordering and network-free VCS fallback |
| Lazy tools | `fuck`, `extract`, `sysinfo` exist | Retryable parent-shell initialization |
| Keys | Reserved bindings are final | Widget detection and mode-specific fallback |
| Syntax | Highlighting is active last | Network-free theme cache preparation |

Each module fails closed when its optional dependency is absent. Missing tools
produce no startup diagnostics and do not leave partially initialized widgets.

## Startup sequence

### 1. Global RC gate

The user `.zshenv` disables Zsh's `GLOBAL_RCS` option for interactive shells.
This skips distribution-wide startup files such as `/etc/zsh/zshrc`, which in
the audit environment duplicated `compinit` and added roughly 70 ms.

User RC files remain enabled. Normal Zsh startup order and history persistence
remain intact. Noninteractive shells are unaffected.

### 2. Powerlevel10k instant prompt

The official P10k-generated snippet is the first executable block in `.zshrc`.
It sources only a local cache file and performs no network access.

### 3. Ordered modules

```text
bootstrap → options → local → history → completion → navigation
          → history UI → prompt → lazy tools → keys → syntax
```

Important ordering constraints:

- local configuration runs before integrations so it can adjust PATH and the
  Atuin configuration directory;
- core modules reset the parameters they own and then re-apply the machine-local
  declaration, so a local file wins over a core default without being sourced
  twice;
- `compinit` runs before fzf-tab and deferred Bun completion;
- fzf-tab runs before autosuggestions and highlighting;
- Atuin initializes in the parent shell before autosuggestions;
- the final keymap runs after every widget exists;
- fast-syntax-highlighting is sourced last.

## Completion

The repository owns one real `compinit` invocation. `ZSH_DISABLE_COMPFIX` is not
used, and `compaudit` remains active. The completion cache lives at
`$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION`.

Bun completion uses a deferred `_bun` function. The first request replaces the
stub in the parent shell with Bun's generated completion. A distribution's
autoload marker named `_bun` is replaced, while a real user-defined function is
preserved. If Bun is temporarily unavailable or fails to generate completion,
the stub remains installed so a later request can retry.

The `thefuck` wrapper follows the same rule: a failed first-use initialization
does not discard the wrapper, and a later invocation can retry in the parent
shell.

FZF's completion script is never sourced. Only its pinned `key-bindings.zsh` is
loaded, with `FZF_CTRL_R_COMMAND` empty so it cannot claim `Ctrl-R`.

## Key ownership

| Key | Owner | Enforcement |
|---|---|---|
| `Ctrl-R` | Atuin | Final emacs/vi-insert/vi-command binding; fzf fallback only without Atuin |
| `Ctrl-T` | fzf | Final file-widget binding; `undefined-key` without fzf |
| `Alt-C` | fzf | Final directory-widget binding; `undefined-key` without fzf |
| `Tab` | fzf-tab | Final binding; native `expand-or-complete` fallback |
| `Up` | Native Zsh | `up-line-or-history` in all three keymaps |
| `?` | Native insertion | `self-insert` in insert modes; no Atuin AI widget |
| `/` in vi command mode | Native vi search | `vi-history-search-backward` |
| `z` / `zi` | zoxide | No competing core alias |

The keys module is the enforcement point, not a convenience. Plugins may define
functions, but the final table decides which function a key invokes.

## History and privacy

Zsh history is bounded to 50,000 entries, appended safely, duplicate-resistant,
and saved in `$XDG_STATE_HOME/zsh/history`. `HIST_IGNORE_SPACE` excludes
commands beginning with a space, and a `zshaddhistory` hook excludes every
logical entry whose first character is whitespace, including a tab. The hook
function is intentionally left defined after registration because Zsh invokes
hook functions by name.

Atuin uses the same policy through `history_filter = ["^\\s+"]`. Its preexec
hook receives the command only after Zsh strips leading whitespace, so this
runtime wraps the accept-line widget to record the raw privacy state and wraps
Atuin's preexec hook to skip a flagged command. The wrapper preserves the
original widget chain and resets after the command. Atuin defaults also disable
automatic sync and update checks while enabling secret filtering. Sync remains
an explicit user opt-in because command history is sensitive.

The legacy importer parses Zsh's backslash-continued physical lines as logical
records before applying the privacy rule. If the first character of a logical
record is whitespace, the complete record is excluded; otherwise all of its
continuation lines remain intact. The parser runs byte-oriented so malformed
legacy bytes are preserved without locale diagnostics. A state-directory marker
makes the import idempotent.

Leading-whitespace suppression does not prevent secrets from appearing in command
output, process arguments, logs, prompts, or transcripts.

## Security decisions

- Evaluate output only from locally installed binaries.
- Never evaluate downloaded shell code during startup.
- Keep completion's security audit enabled.
- Do not weaken Go checksum verification or force a global direct proxy.
- Do not create an empty leading component in `PYTHONPATH`.
- Keep personal paths and tool initialization out of the runtime.
- Seed fast-syntax-highlighting's optional theme locally so its network
  fallback is unreachable.
- Disable Powerlevel10k's gitstatus daemon and auto-installer. Its native
  `vcs_info` fallback supplies VCS status without a runtime download.

## Failure modes

| Failure | Behavior |
|---|---|
| Vendor checkout missing | The related integration is skipped without diagnostics |
| Atuin missing | `Ctrl-R` uses fzf history, or is unbound if fzf is absent |
| fzf missing | `Ctrl-T` and `Alt-C` are unbound |
| fzf-tab missing | Native Zsh completion owns `Tab` |
| Bun missing | Deferred completion stays absent; a transient failure remains retryable |
| thefuck missing | `fuck` returns 127 and remains retryable |
| P10k missing | No custom prompt is installed; the shell still starts |
| Local file writes stdout | stdout is suppressed; stderr remains visible |

## Performance method

`tests/perf.zsh` creates isolated HOME and XDG directories, removes only the
completion cache for the cold sample, then measures warm login-interactive
shells with `EPOCHREALTIME`. It reports cold, p50, p95, and maximum values and
fails against these budgets:

| Measurement | Budget |
|---|---:|
| Cold startup | 300 ms |
| Warm p50 | 60 ms |
| Warm p95 | 80 ms |

A startup shim suite additionally proves that fetch, fastfetch, Bun, Python,
fzf, thefuck, curl, and wget are not executed during startup.

## Migration and rollback

The installer backs up both startup files before atomically replacing them with
symlinks. Backup paths are collision-proof and recorded separately, so repeated
installations preserve distinct rollback points. `scripts/uninstall` restores
the most recent recorded backup. Vendor data, Atuin's database, local policy,
and imported history are never deleted by rollback.

Atuin privacy settings are rewritten in an isolated directory and parsed by the
installed Atuin binary before an atomic replacement. A failed candidate leaves
the active configuration byte-for-byte unchanged. Existing filter arrays and
configuration comments are preserved while the exact `^\s+` filter is enforced.

Legacy Zsh history is appended once. A marker in the state directory prevents
repeated concatenation.

## Configuration wizard

`scripts/wizard` edits machine-local policy only. It writes one managed file,
`<config dir>/local.d/50-wizard.zsh`, and never changes published core files or
startup files. Preview is the default; `--apply` is required before anything is
written, so every change is reviewed before it lands.

Four settings are managed: history size (`HISTSIZE`), the autosuggestion
highlight style (`ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE`), and the left and right
Powerlevel10k prompt element lists. Values are validated before any write: a
history size must be a positive integer inside a fixed bound, a highlight style
must be a literal that stays safe inside the generated double quotes, and prompt
elements must be Powerlevel10k names.

The proposed file is staged and validated in an isolated Zsh before publication.
Sourcing must be silent, and the real runtime must start from an isolated HOME
and XDG tree with every managed value still in place. A candidate that fails
either check leaves the active file untouched. An existing managed file is
copied to a timestamped backup before replacement, and the write itself is
atomic, so an interrupted run cannot leave a partial file.

The generated file is deterministic: fixed header, fixed field order, no
timestamps. Applying the same settings twice writes nothing the second time, so
a preview is a byte-exact statement of what `--apply` will do.

`--tui` opens an interactive menu over the same settings. It reads one keypress
at a time on a terminal and one key per line when piped, so a scripted session
and the automated tests drive the same interface. Nothing in the wizard runs at
startup.

## Evolution rules

1. Add behavior to the module that owns it, not to `.zshrc`.
2. Keep one implementation behind each interface; avoid wrappers that only
   forward calls.
3. Add or update the exact commit in `deps.lock` deliberately.
4. Add a smoke assertion through the same interface users cross.
5. Preserve key ownership and the no-network startup guarantee.
6. Measure before and after with `scripts/benchmark.sh`.

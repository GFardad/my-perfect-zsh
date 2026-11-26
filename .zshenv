# The distribution-wide /etc/zsh/zshrc duplicates completion setup and adds
# substantial startup latency. Skip only global RC files for interactive
# shells; user startup files, history persistence, and noninteractive shells
# keep their normal behavior.
if [[ -o interactive ]]; then
  unsetopt GLOBAL_RCS
fi
# browse: ensure ~/.local/bin is on PATH in zsh.
# .zshenv runs for every shell, including nested non-interactive ones, so the
# prepend must be idempotent or PATH grows once per nesting level.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

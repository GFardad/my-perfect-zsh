# The distribution-wide /etc/zsh/zshrc duplicates completion setup and adds
# substantial startup latency. Skip only global RC files for interactive
# shells; user startup files, history persistence, and noninteractive shells
# keep their normal behavior.
if [[ -o interactive ]]; then
  unsetopt GLOBAL_RCS
fi

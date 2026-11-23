# Enable Powerlevel10k instant prompt. Should stay close to the top of .zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

[[ -o interactive ]] || return 0

typeset -g MPZ_ROOT="${${(%):-%N}:A:h}"

source "$MPZ_ROOT/modules/bootstrap.zsh"
source "$MPZ_ROOT/modules/options.zsh"
source "$MPZ_ROOT/modules/local.zsh"
source "$MPZ_ROOT/modules/history.zsh"
source "$MPZ_ROOT/modules/completion.zsh"
source "$MPZ_ROOT/modules/navigation.zsh"
source "$MPZ_ROOT/modules/history-ui.zsh"
source "$MPZ_ROOT/modules/prompt.zsh"
source "$MPZ_ROOT/modules/lazy-tools.zsh"
source "$MPZ_ROOT/modules/keys.zsh"
source "$MPZ_ROOT/modules/syntax.zsh"

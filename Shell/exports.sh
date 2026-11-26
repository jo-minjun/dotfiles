# PATH additions
export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
# pnpm 12는 global 명령을 $PNPM_HOME/bin 에 두고, 이 폴더가 PATH에 없으면 `pnpm add -g`가 실패한다
# $PNPM_HOME 은 pnpm 10 이하가 global 명령을 둔 위치라 남겨 둔다
export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH"

# Claude Code configuration
export CLAUDE_BIN_PATH="$HOME/.local/bin/claude"
export OPENCODE_EXPERIMENTAL_LSP_TOOL=true
export ENABLE_LSP_TOOL=1

# 업무 설정은 private 저장소(dotfiles-work)를 별도 chezmoi 소스로 적용한다
export CHEZMOI_WORK_SOURCE="$HOME/.local/share/chezmoi-work"
export CHEZMOI_WORK_STATE="$HOME/.config/chezmoi/chezmoistate-work.boltdb"
[ -f "$HOME/Shell/work.sh" ] && source "$HOME/Shell/work.sh"

# 기기별 설정은 chezmoi 관리 밖의 local.sh에 둔다
[ -f "$HOME/Shell/local.sh" ] && source "$HOME/Shell/local.sh"

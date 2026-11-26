# 다른 chezmoi 소스가 *.tables 에 적은 표인지 가른다. dot_codex/modify_private_config.toml.tmpl 과 chezmoi-sync 의 capture-modify-files.sh 가 같이 쓴다.
# 표 이름은 OWNED_TABLES 환경 변수(한 줄에 표 머리글 하나)로 받는다. BSD awk 는 -v 값에 줄바꿈을 받지 않는다.
# Codex 가 표를 다시 쓰며 따옴표 종류를 바꿀 수 있어 따옴표와 공백을 지우고 비교하고, 하위 표도 그 소스의 표로 본다.
function norm(t) { gsub(/["\047 \t]/, "", t); return t }
function load_owned(   k, i, names) {
  k = split(ENVIRON["OWNED_TABLES"], names, "\n")
  for (i = 1; i <= k; i++) if (names[i] ~ /^\[/) owned[norm(names[i])] = 1
}
function is_owned(t,   n, o) {
  n = norm(t)
  if (n in owned) return 1
  for (o in owned) if (index(n, substr(o, 1, length(o) - 1) ".") == 1) return 1
  return 0
}

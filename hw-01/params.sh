# shellcheck shell=bash

PARAMS=(PREFIX ZONE_A ZONE_B CIDR_A CIDR_B APP_PORT WORD WEB_COUNT ENV_NAME)

declare -A DEFAULTS=(
  [PREFIX]=vetrov-09
  [ZONE_A]=ru-central1-d
  [ZONE_B]=ru-central1-a
  [CIDR_A]=10.19.1.0/24
  [CIDR_B]=10.19.2.0/24
  [APP_PORT]=8027
  [WORD]=cloudlab
  [WEB_COUNT]=2
  [ENV_NAME]=lab
)

declare -A OPTIONS=(
  [--prefix]=PREFIX
  [--zone-a]=ZONE_A
  [--zone-b]=ZONE_B
  [--cidr-a]=CIDR_A
  [--cidr-b]=CIDR_B
  [--port]=APP_PORT
  [--word]=WORD
  [--web-count]=WEB_COUNT
  [--env]=ENV_NAME
)

declare -A SOURCE=()
PRINT_PARAMS=0

die() { echo "ошибка: $*" >&2; exit 1; }

usage() {
  cat <<USAGE
Использование: $(basename "$0") [параметры]

  --prefix NAME     префикс имён ресурсов        (PREFIX,    по умолчанию ${DEFAULTS[PREFIX]})
  --zone-a ZONE     зона A                       (ZONE_A,    ${DEFAULTS[ZONE_A]})
  --zone-b ZONE     зона B                       (ZONE_B,    ${DEFAULTS[ZONE_B]})
  --cidr-a CIDR     подсеть в зоне A             (CIDR_A,    ${DEFAULTS[CIDR_A]})
  --cidr-b CIDR     подсеть в зоне B             (CIDR_B,    ${DEFAULTS[CIDR_B]})
  --port PORT       порт сервиса                 (APP_PORT,  ${DEFAULTS[APP_PORT]})
  --word WORD       слово на странице            (WORD,      ${DEFAULTS[WORD]})
  --web-count N     число веб-серверов           (WEB_COUNT, ${DEFAULTS[WEB_COUNT]})
  --env NAME        имя окружения для меток      (ENV_NAME,  ${DEFAULTS[ENV_NAME]})
  --print-params    показать итоговые значения и откуда они взялись, ничего не делать
  -h, --help        эта справка

Приоритет: аргумент > переменная окружения > умолчание.
USAGE
}

load_params() {
  local p key val var
  for p in "${PARAMS[@]}"; do
    if [ -n "${!p:-}" ]; then
      SOURCE[$p]="окружение"
    else
      printf -v "$p" '%s' "${DEFAULTS[$p]}"
      SOURCE[$p]="умолчание"
    fi
  done
  # 3. аргументы перекрывают всё
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --print-params) PRINT_PARAMS=1; shift; continue ;;
      --*=*) key="${1%%=*}"; val="${1#*=}"; shift ;;
      --*) key="$1"; [ $# -ge 2 ] || die "у параметра $1 нет значения"; val="$2"; shift 2 ;;
      *) die "непонятный аргумент: $1 (см. --help)" ;;
    esac
    var="${OPTIONS[$key]:-}"
    [ -n "$var" ] || die "неизвестный параметр $key (см. --help)"
    printf -v "$var" '%s' "$val"
    SOURCE[$var]="аргумент"
  done
  validate_params
  export "${PARAMS[@]}"
  if [ "$PRINT_PARAMS" -eq 1 ]; then show_params; exit 0; fi
}

validate_params() {
  [[ "$PREFIX" =~ ^[a-z][a-z0-9-]{1,40}$ ]] || die "префикс: строчные латинские буквы, цифры и дефис, получено: $PREFIX"
  [[ "$WEB_COUNT" =~ ^[1-9][0-9]*$ ]] || die "число веб-серверов должно быть целым больше нуля, получено: $WEB_COUNT"
  [[ "$APP_PORT" =~ ^[0-9]+$ ]] && [ "$APP_PORT" -ge 1 ] && [ "$APP_PORT" -le 65535 ] \
    || die "порт должен быть числом от 1 до 65535, получено: $APP_PORT"
  [[ "$CIDR_A" =~ ^[0-9.]+/[0-9]+$ && "$CIDR_B" =~ ^[0-9.]+/[0-9]+$ ]] || die "подсети задаются как 10.19.1.0/24"
  [ "$ZONE_A" != "$ZONE_B" ] || die "зоны A и B совпадают ($ZONE_A): стенд не переживёт отказ зоны"
  [[ "$WORD" =~ ^[A-Za-z0-9_-]+$ ]] || die "слово на странице: латиница, цифры, _ и -, получено: $WORD"
  if [ "$WEB_COUNT" -lt 2 ]; then
    echo "внимание: веб-сервер один, отказ машины стенд не переживёт" >&2
  fi
}

show_params() {
  local p
  echo "==> параметры стенда"
  for p in "${PARAMS[@]}"; do
    printf '    %-10s = %-15s (%s)\n' "$p" "${!p}" "${SOURCE[$p]}"
  done
}

need() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "не найдена утилита $cmd"
  done
}

# shellcheck disable=SC2016,SC2034 # $p — переменная jq; MINE_JQ используют check.sh и destroy.sh
MINE_JQ='.[] | select(((.labels.owner // "") == $p) or ((.name // "") | startswith($p + "-")))'

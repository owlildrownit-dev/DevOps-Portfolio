#!/usr/bin/env bash
# Собирает образ "до" и "после" из одного и того же кода и сравнивает размеры.
# Результат: results/sizes.md (числа берутся из docker image inspect).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HERE/../../app"
OUT="$HERE/results"
mkdir -p "$OUT"

build() {
  local tag=$1 dockerfile=$2 start end
  start=$(date +%s)
  # --no-cache: честное время сборки с нуля для обоих вариантов
  DOCKER_BUILDKIT=1 docker build --no-cache -q -t "$tag" -f "$dockerfile" "$APP_DIR" >/dev/null
  end=$(date +%s)
  echo $((end - start))
}

echo "Сборка orders-api:before ..."
t_before=$(build orders-api:before "$HERE/Dockerfile.single-stage")
echo "Сборка orders-api:after ..."
t_after=$(build orders-api:after "$APP_DIR/Dockerfile")

# Size: размер образа в байтах по данным Docker
s_before=$(docker image inspect --format '{{.Size}}' orders-api:before)
s_after=$(docker image inspect --format '{{.Size}}' orders-api:after)

mb() { awk -v b="$1" 'BEGIN{printf "%.1f", b/1024/1024}'; }
pct=$(awk -v b="$s_before" -v a="$s_after" 'BEGIN{printf "%.1f", (b-a)/b*100}')

# Проверка, что "после" не сломалось: компилятора в образе нет, приложение импортируется
gcc_after=$(docker run --rm --entrypoint sh orders-api:after -c 'command -v gcc || echo "нет"')
import_ok=$(docker run --rm --entrypoint python orders-api:after -c 'import app, psycopg2; print("ok")')

{
  echo "# Размер образов orders-api"
  echo
  echo "Замер: $(date '+%Y-%m-%d %H:%M'), $(docker version --format 'Docker {{.Server.Version}}')"
  echo
  echo "| Образ | Размер, байт | Размер, МБ | Сборка с нуля, с |"
  echo "| --- | --- | --- | --- |"
  echo "| orders-api:before | $s_before | $(mb "$s_before") | $t_before |"
  echo "| orders-api:after | $s_after | $(mb "$s_after") | $t_after |"
  echo
  echo "Уменьшение: ($s_before - $s_after) / $s_before × 100 = **$pct%**"
  echo
  echo "Проверки образа after: gcc в образе: $gcc_after; импорт приложения: $import_ok"
  echo
  echo "## Слои before (docker history)"
  echo '```'
  docker history --format 'table {{.Size}}\t{{.CreatedBy}}' --no-trunc orders-api:before | cut -c1-140
  echo '```'
  echo
  echo "## Слои after (docker history)"
  echo '```'
  docker history --format 'table {{.Size}}\t{{.CreatedBy}}' --no-trunc orders-api:after | cut -c1-140
  echo '```'
} > "$OUT/sizes.md"

cat "$OUT/sizes.md" | head -12
echo "Полный отчет: $OUT/sizes.md"

#!/usr/bin/env bash
# Builds the "before" and "after" images from the same code and compares their sizes.
# Output: results/sizes.md (sizes come from docker image inspect).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HERE/../../app"
OUT="$HERE/results"
mkdir -p "$OUT"

build() {
  local tag=$1 dockerfile=$2 start end
  start=$(date +%s)
  # --no-cache: a fair from-scratch build time for both variants
  DOCKER_BUILDKIT=1 docker build --no-cache -q -t "$tag" -f "$dockerfile" "$APP_DIR" >/dev/null
  end=$(date +%s)
  echo $((end - start))
}

echo "Building orders-api:before ..."
t_before=$(build orders-api:before "$HERE/Dockerfile.single-stage")
echo "Building orders-api:after ..."
t_after=$(build orders-api:after "$APP_DIR/Dockerfile")

# Size: image size in bytes as reported by Docker
s_before=$(docker image inspect --format '{{.Size}}' orders-api:before)
s_after=$(docker image inspect --format '{{.Size}}' orders-api:after)

mb() { awk -v b="$1" 'BEGIN{printf "%.1f", b/1024/1024}'; }
pct=$(awk -v b="$s_before" -v a="$s_after" 'BEGIN{printf "%.1f", (b-a)/b*100}')

# Check that "after" still works: no compiler in the image, the app imports cleanly
gcc_after=$(docker run --rm --entrypoint sh orders-api:after -c 'command -v gcc || echo "none"')
import_ok=$(docker run --rm --entrypoint python orders-api:after -c 'import app, psycopg2; print("ok")')

{
  echo "# orders-api image sizes"
  echo
  echo "Measured: $(date '+%Y-%m-%d %H:%M'), $(docker version --format 'Docker {{.Server.Version}}')"
  echo
  echo "| Image | Size, bytes | Size, MiB | Clean build, s |"
  echo "| --- | --- | --- | --- |"
  echo "| orders-api:before | $s_before | $(mb "$s_before") | $t_before |"
  echo "| orders-api:after | $s_after | $(mb "$s_after") | $t_after |"
  echo
  echo "Reduction: ($s_before - $s_after) / $s_before × 100 = **$pct%**"
  echo
  echo "Checks for the after image: gcc in image: $gcc_after; app import: $import_ok"
  echo
  echo "## before layers (docker history)"
  echo '```'
  docker history --format 'table {{.Size}}\t{{.CreatedBy}}' --no-trunc orders-api:before | cut -c1-140
  echo '```'
  echo
  echo "## after layers (docker history)"
  echo '```'
  docker history --format 'table {{.Size}}\t{{.CreatedBy}}' --no-trunc orders-api:after | cut -c1-140
  echo '```'
} > "$OUT/sizes.md"

cat "$OUT/sizes.md" | head -12
echo "Full report: $OUT/sizes.md"

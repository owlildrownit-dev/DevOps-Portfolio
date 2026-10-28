#!/usr/bin/env bash
# Ставит все, что нужно стенду, на Ubuntu/Debian (GitHub Codespaces, WSL2, облачная ВМ).
# Устанавливает только то, чего нет. Запуск: bash scripts/setup-tools.sh
set -euo pipefail

KIND_VERSION="${KIND_VERSION:-v0.33.0}"
ARCH=$(dpkg --print-architecture)       # amd64 / arm64
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
SUDO=""; if [[ $(id -u) -ne 0 ]]; then SUDO="sudo"; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

have() { command -v "$1" >/dev/null 2>&1; }
step() { printf '\n==== %s ====\n' "$*"; }

# После распаковки zip через браузер права на запуск могут потеряться
find "$ROOT" -name '*.sh' -exec chmod +x {} +
chmod +x "$ROOT/benchmarks/postgres-cpu/report.py"

step "Базовые пакеты"
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq curl wget gnupg ca-certificates unzip openssl python3-pip >/dev/null

step "Docker"
if have docker && docker info >/dev/null 2>&1; then
  docker version --format 'Docker {{.Server.Version}}: уже работает'
else
  echo "Docker не найден или не запущен."
  echo "В Codespaces он есть по умолчанию. На своей ВМ: https://docs.docker.com/engine/install/ubuntu/"
  exit 1
fi

step "PostgreSQL (сервер + pgbench, для раздела 3)"
if ls /usr/lib/postgresql/*/bin/pgbench >/dev/null 2>&1; then
  echo "уже установлен: $(ls -d /usr/lib/postgresql/*/bin | head -1)"
else
  $SUDO apt-get install -y -qq postgresql postgresql-contrib >/dev/null
  # системный сервис не нужен: benchmarks/postgres-cpu/run.sh поднимает свой кластер
  $SUDO service postgresql stop >/dev/null 2>&1 || true
fi

step "Terraform"
if have terraform; then terraform version | head -1; else
  wget -qO- https://apt.releases.hashicorp.com/gpg | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $CODENAME main" \
    | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  $SUDO apt-get update -qq && $SUDO apt-get install -y -qq terraform >/dev/null
  terraform version | head -1
fi

step "Ansible + коллекция community.docker"
if ! have ansible-playbook; then
  python3 -m pip install --user -q ansible-core docker 2>/dev/null \
    || python3 -m pip install --user -q --break-system-packages ansible-core docker
fi
export PATH="$HOME/.local/bin:$PATH"
python3 -c "import docker" 2>/dev/null \
  || python3 -m pip install --user -q docker 2>/dev/null \
  || python3 -m pip install --user -q --break-system-packages docker
ansible-galaxy collection install community.docker
ansible --version | head -1

step "kubectl"
if have kubectl; then kubectl version --client | head -1; else
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/$ARCH/kubectl"
  $SUDO install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
fi

step "Helm"
if have helm; then helm version --short; else
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
fi

step "kind"
if have kind; then kind version; else
  curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/$KIND_VERSION/kind-linux-$ARCH"
  $SUDO install -m 0755 /tmp/kind /usr/local/bin/kind
  kind version
fi

step "Сеть Docker: трафик между контейнерами"
bash "$HERE/fix-docker-network.sh"

step "Готово"
echo "Если ansible не находится в новом терминале, выполните: export PATH=\"\$HOME/.local/bin:\$PATH\""

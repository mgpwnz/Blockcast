#!/bin/bash

set -euo pipefail

SERVICE_NAME="blockcast-check"
SCRIPT_DIR="$HOME/blockcast"
SCRIPT_PATH="$SCRIPT_DIR/restart_if_needed.sh"
LOG_PATH="$SCRIPT_DIR/docker-compose.yml"

# === 1. Створити скрипт перевірки ===
mkdir -p "$SCRIPT_DIR"

cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash

COMPOSE_DIR="$HOME/blockcast"
LOG_FILE="$COMPOSE_DIR/docker-compose.yml"
MAX_ERRORS=3

# Масив рядків, за якими шукаємо помилки
ERROR_PATTERNS=(
  "unexpected HTTP status code received from server: 400"
  "error creating cloud connection"
  "failed to connect to state reporting service"
  "gateway mconfig streaming error"
  "error querying service 'beacond' state"
  "Cannot load configs from"
)

cd "$COMPOSE_DIR" || exit 1

# Підтягуємо логи лише один раз
logs=$(docker compose logs --since 5m 2>/dev/null)

# Рахуємо сумарну кількість знайдених рядків для всіх патернів
errors=0
for pattern in "${ERROR_PATTERNS[@]}"; do
  count=$(grep -cF "$pattern" <<< "$logs")
  errors=$((errors + count))
done

if [ "$errors" -ge "$MAX_ERRORS" ]; then
  echo "$(date): Too many errors ($errors). Restarting..." >> ~/blockcast_restart.log
  docker compose down
  sleep 2
  docker compose up -d
else
  echo "$(date): Errors OK ($errors)" >> ~/blockcast_restart.log
fi

EOF

chmod +x "$SCRIPT_PATH"

# === 2. Створити systemd service ===
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Check Blockcast logs and restart if needed

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
EOF

# === 3. Створити systemd timer ===
sudo tee /etc/systemd/system/${SERVICE_NAME}.timer > /dev/null <<EOF
[Unit]
Description=Run Blockcast healthcheck every 5 min

[Timer]
OnBootSec=3min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

# === 4. Активувати таймер ===
sudo systemctl daemon-reload
sudo systemctl enable --now ${SERVICE_NAME}.timer

echo -e "\n✅ Готово! Таймер активовано. Перевірка буде кожні 5 хвилин."

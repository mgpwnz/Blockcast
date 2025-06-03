#!/bin/bash
# Default variables
function="install"
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
        -up|--update)
            function="update"
            shift
            ;;
        -un|--uninstall)
            function="uninstall"
            shift
            ;;
        *|--)
    break
	;;
	esac
done
install() {
#docker install
cd $HOME
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
#create dir and config
if [ ! -d $HOME/blockcast ]; then
  mkdir $HOME/blockcast
fi
read -r -p "Enter port for watchtower [8080]: " port
port=${port:-8080}
# Create script 
tee $HOME/blockcast/docker-compose.yml > /dev/null <<EOF
x-service: &service
  image: blockcast/cdn_gateway_go:${IMAGE_VERSION:-stable}
  restart: unless-stopped
  network_mode: "service:blockcastd"
  volumes:
    - ${HOME}/.blockcast/certs:/var/opt/magma/certs
    - ${HOME}/.blockcast/snowflake:/etc/snowflake
  labels:
    - "com.centurylinklabs.watchtower.enable=true"

services:
  control_proxy:
    <<: *service
    container_name: control_proxy
    command: /usr/bin/control_proxy

  blockcastd:
    <<: *service
    container_name: blockcastd
    command: /usr/bin/blockcastd -logtostderr=true -v=0
    network_mode: bridge

  beacond:
    <<: *service
    container_name: beacond
    command: /usr/bin/beacond -logtostderr=true -v=0

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: unless-stopped
    environment:
      - WATCHTOWER_LABEL_ENABLE=true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "${port}:8080"

EOF

#Run nnode
docker compose -f $HOME/blockcast/docker-compose.yml up -d
}
update() {
docker compose -f $HOME/blockcast/docker-compose.yml down
docker compose -f $HOME/blockcast/docker-compose.yml pull
docker compose -f $HOME/blockcast/docker-compose.yml up -d
echo "Blockcast updated"

}
uninstall() {
if [ ! -d "$HOME/blockcast" ]; then
    echo "Directory not found"
    break
fi

read -r -p "Wipe all DATA? [y/N] " response
case "$response" in
    [yY][eE][sS]|[yY]) 
        docker-compose -f "$HOME/blockcast/docker-compose.yml" down -v
        rm -rf "$HOME/blockcast"
        echo "Data wiped"
        ;;
    *)
        echo "Canceled"
        break
        ;;
esac
}
# Actions
sudo apt install wget -y &>/dev/null
cd
$function
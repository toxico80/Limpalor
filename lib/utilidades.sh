#!/usr/bin/env bash
# utilidades.sh — funciones comunes del Limpiador Mint
# (colores, diálogos zenity, cálculo de espacio, protección de paquetes)

COL_RESET='\033[0m'
COL_VERDE='\033[0;32m'
COL_AMAR='\033[1;33m'
COL_ROJO='\033[0;31m'
COL_AZUL='\033[0;34m'

log()  { echo -e "${COL_VERDE}[OK]${COL_RESET} $*"; }
warn() { echo -e "${COL_AMAR}[!!]${COL_RESET} $*"; }
err()  { echo -e "${COL_ROJO}[ERR]${COL_RESET} $*" >&2; }
info() { echo -e "${COL_AZUL}[i]${COL_RESET} $*"; }

banner() {
  echo -e "${COL_VERDE}"
  cat <<'EOF'
 _     _                       _
| |   (_)_ __ ___  _ __   __ _| | ___  _ __
| |   | | '_ ` _ \| '_ \ / _` | |/ _ \| '__|
| |___| | | | | | | |_) | (_| | | (_) | |
|_____|_|_| |_| |_| .__/ \__,_|_|\___/|_|
                  |_|
        🧹 Limpiador Mint v1.0
EOF
  echo -e "${COL_RESET}"
}

# Formatea bytes a texto legible. Uso: human 1234567
human() {
  local b=${1:-0}
  if (( b >= 1073741824 )); then
    awk "BEGIN{printf \"%.2f GB\", $b/1073741824}"
  elif (( b >= 1048576 )); then
    awk "BEGIN{printf \"%.1f MB\", $b/1048576}"
  elif (( b >= 1024 )); then
    awk "BEGIN{printf \"%.1f KB\", $b/1024}"
  else
    echo "${b} B"
  fi
}

# Convierte una cantidad tipo "255 MB" o "1.5G" a bytes
a_bytes() {
  local n=$1 u=$2
  awk "BEGIN{
    n=$n; u=toupper(\"$u\");
    if (u ~ /^G/)      printf \"%d\", n*1073741824;
    else if (u ~ /^M/) printf \"%d\", n*1048576;
    else if (u ~ /^K/) printf \"%d\", n*1024;
    else if (u ~ /^T/) printf \"%d\", n*1099511627776;
    else               printf \"%d\", n;
  }"
}

# Bytes ocupados por directorios/archivos (ignora los que no existen)
dir_bytes() {
  local total=0 d b
  for d in "$@"; do
    [[ -e $d ]] || continue
    b=$(du -sb "$d" 2>/dev/null | cut -f1)
    total=$(( total + ${b:-0} ))
  done
  echo "$total"
}

# Espacio disponible en la partición raíz (bytes)
espacio_libre() { df -B1 --output=avail / 2>/dev/null | tail -1 | tr -d ' '; }

# Diálogos zenity comunes
confirmar() {
  zenity --question --title="Limpiador Mint" --text="$1" \
    --width=560 --ok-label="Sí, continuar" --cancel-label="Cancelar" 2>/dev/null
}

aviso() {
  zenity --info --title="Limpiador Mint" --text="$1" --width=480 2>/dev/null
}

error_gui() {
  zenity --error --title="Limpiador Mint" --text="$1" --width=480 2>/dev/null
}

# Caché de paquetes esenciales/requeridos (se construye una sola vez)
_ESCENCIALES_CARGADOS=0
declare -A _ESQ_ESCENCIALES=()
cargar_esenciales() {
  (( _ESCENCIALES_CARGADOS )) && return 0
  local p
  while read -r p; do
    _ESQ_ESCENCIALES[$p]=1
  done < <(dpkg-query -W -f='${Package}|${Essential}|${Priority}\n' 2>/dev/null \
           | awk -F'|' '$2 == "yes" || $3 == "required" || $3 == "critical" {print $1}')
  _ESCENCIALES_CARGADOS=1
}

# ¿El paquete está protegido (esencial del sistema)? Devuelve 0 si SÍ está protegido
paquete_protegido() {
  local p=$1 rel
  rel=$(uname -r)
  case "$p" in
    # kernel en uso y el más reciente
    linux-image-${rel}|linux-headers-${rel}|linux-modules-${rel}|linux-modules-extra-${rel}|linux-tools-${rel})
      return 0 ;;
    linux-image-generic|linux-headers-generic|linux-generic|linux-virtual|linux-firmware|linux-base|linux-libc-dev)
      return 0 ;;
    mint*|ubuntu*|xfce4|xfce4-*|xorg|xserver*|grub*|systemd|systemd-*|bash|coreutils|dpkg|apt|apt-*)
      return 0 ;;
    init|initramfs-tools*|dbus|dbus-*|polkit*|policykit*|lightdm*|slick-greeter*|nemo|cinnamon*)
      return 0 ;;
    network-manager*|NetworkManager*|kernel*|plymouth*|sudo|gnome-keyring*|bluez*|cups*|alsa*|pulseaudio*|pipewire*)
      return 0 ;;
  esac
  # esencial o prioridad requerida según dpkg (con caché)
  cargar_esenciales
  [[ -n ${_ESQ_ESCENCIALES[$p]:-} ]] && return 0
  return 1
}

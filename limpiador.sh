#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  🧹 Limpiador Mint — limpia basura y desinstala aplicaciones
#  Interfaz gráfica con zenity | Linux Mint (XFCE/Cinnamon/MATE)
#
#  Uso:
#    ./limpiador.sh          → menú gráfico
#    ./limpiador.sh --todo   → limpieza completa desde terminal
# ═══════════════════════════════════════════════════════════════
set -u

DIR_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/utilidades.sh
source "$DIR_BASE/lib/utilidades.sh"
# shellcheck source=lib/limpieza.sh
source "$DIR_BASE/lib/limpieza.sh"
# shellcheck source=lib/apps.sh
source "$DIR_BASE/lib/apps.sh"

# ---------------------------------------------------------------------------
# Ver espacio en disco
# ---------------------------------------------------------------------------
gui_espacio() {
  local salida
  salida="═══ ESPACIO EN DISCO ═══\n\n"
  salida+="$(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs -x overlay 2>/dev/null)\n\n"
  salida+="═══ CACHÉS Y BASURA COMÚN ═══\n\n"
  salida+="Caché APT:        $(human "$(dir_bytes /var/cache/apt)")\n"
  salida+="Miniaturas:       $(human "$(dir_bytes "$HOME/.cache/thumbnails")")\n"
  salida+="Papelera:         $(human "$(dir_bytes "$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info")")\n"
  salida+="Caché usuario:    $(human "$(dir_bytes "$HOME/.cache")")\n"
  if command -v flatpak >/dev/null 2>&1; then
    salida+="Apps Flatpak:     $(flatpak list --app 2>/dev/null | wc -l) instaladas\n"
  fi
  salida+="Logs del sistema: $(LANG=C journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]?i?B' | head -1)\n"
  zenity --text-info --title="Limpiador Mint — Espacio en disco" \
    --width=760 --height=480 --font="monospace" \
    <<< "$(echo -e "$salida")" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Crear acceso directo en el menú de XFCE
# ---------------------------------------------------------------------------
crear_atajo() {
  local destino="$HOME/.local/share/applications/limpiador-mint.desktop"
  if ! confirmar "¿Crear un acceso directo «Limpiador Mint» en tu menú de aplicaciones?"; then
    return 0
  fi
  mkdir -p "$HOME/.local/share/applications"
  # Instalamos el icono propio en la estructura de tema hicolor
  # (los iconos sueltos en ~/.local/share/icons/ no los encuentra el sistema)
  local icono="preferences-system"
  if [[ -f "$DIR_BASE/docs/icono.png" ]]; then
    local tam
    for tam in 48 128 512; do
      local src="$DIR_BASE/docs/icono-${tam}.png"
      [[ -f "$src" ]] || src="$DIR_BASE/docs/icono.png"
      mkdir -p "$HOME/.local/share/icons/hicolor/${tam}x${tam}/apps"
      cp "$src" "$HOME/.local/share/icons/hicolor/${tam}x${tam}/apps/limpiador-mint.png"
    done
    # El tema hicolor del usuario necesita un index.theme para que la caché funcione
    if [[ ! -f "$HOME/.local/share/icons/hicolor/index.theme" ]]; then
      cat > "$HOME/.local/share/icons/hicolor/index.theme" <<'IDX'
[Icon Theme]
Name=Hicolor
Comment=Fallback icon theme
Hidden=true
Directories=48x48/apps,128x128/apps,512x512/apps

[48x48/apps]
Size=48
Context=Applications
Type=Threshold

[128x128/apps]
Size=128
Context=Applications
Type=Threshold

[512x512/apps]
Size=512
Context=Applications
Type=Threshold
IDX
    fi
    gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
    icono="limpiador-mint"
  fi
  cat > "$destino" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Limpiador Mint
GenericName=Limpiador del sistema
Comment=Limpia basura del sistema y desinstala aplicaciones
Exec=bash ${DIR_BASE}/limpiador.sh
Icon=${icono}
Terminal=false
Categories=System;Utility;
StartupNotify=true
EOF
  chmod +x "$destino"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  aviso "✅ Acceso directo creado.\n\nBúscalo como «Limpiador Mint» en tu menú de aplicaciones.\n\nArchivo: $destino"
}

# ---------------------------------------------------------------------------
# Comprobaciones iniciales
# ---------------------------------------------------------------------------
comprobar_entorno() {
  if ! command -v zenity >/dev/null 2>&1; then
    err "zenity no está instalado. Instálalo con: sudo apt install zenity"
    err "También puedes usar el modo terminal: $0 --todo"
    exit 1
  fi
  if [[ -z ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then
    err "No se detectó un entorno gráfico. Usa el modo terminal: $0 --todo"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Modo CLI
# ---------------------------------------------------------------------------
if [[ ${1:-} == "--todo" ]]; then
  banner
  cli_limpiar_todo
  exit $?
fi

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  banner
  echo "Uso: $0 [--todo|--help]"
  echo "  (sin opciones)  Abre el menú gráfico"
  echo "  --todo          Limpia todas las categorías desde terminal (usa sudo)"
  echo "  --help          Muestra esta ayuda"
  exit 0
fi

comprobar_entorno
banner

# ---------------------------------------------------------------------------
# Menú principal
# ---------------------------------------------------------------------------
while true; do
  opcion=$(zenity --list \
    --title="🧹 Limpiador Mint" \
    --text="¿Qué quieres hacer?" \
    --width=620 --height=420 \
    --column="Acción" --column="Descripción" \
    "limpiar" "🧹 Limpiar basura (cachés, kernels viejos, papelera, logs...)" \
    "apps"    "🗑️  Borrar aplicaciones (APT y Flatpak)" \
    "espacio" "💾 Ver espacio en disco" \
    "atajo"   "🖥️  Crear acceso directo en el menú de aplicaciones" \
    "salir"   "🚪 Salir" \
    2>/dev/null)

  case "$opcion" in
    limpiar) gui_limpiar ;;
    apps)    gui_borrar_apps ;;
    espacio) gui_espacio ;;
    atajo)   crear_atajo ;;
    salir|"") break ;;
    *)       continue ;;
  esac
done

exit 0

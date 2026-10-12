#!/usr/bin/env bash
# limpieza.sh — tareas de limpieza del Limpiador Mint
# Cada tarea tiene: clave, descripción, función de estimación y función de ejecución.
# Las funciones tarea_* se ejecutan DENTRO del script con permisos de root (reciben $1 = home del usuario).

# Claves de tareas en orden de ejecución
TAREAS_CLAVES=(apt_cache huerfanos kernels flatpaks miniaturas temporales papelera logs rc)

# Descripciones legibles
declare -A TAREA_DESC=(
  [apt_cache]="Caché de APT (paquetes .deb descargados)"
  [huerfanos]="Paquetes huérfanos (dependencias sin usar)"
  [kernels]="Kernels antiguos (conserva el actual y el más nuevo)"
  [flatpaks]="Flatpaks sin usar y su caché"
  [miniaturas]="Caché de miniaturas de imágenes"
  [temporales]="Archivos temporales (/tmp con más de 1 día)"
  [papelera]="Vaciar la papelera de reciclaje"
  [logs]="Logs antiguos del sistema (más de 7 días)"
  [rc]="Configuraciones residuales de programas desinstalados"
)

# ---------------------------------------------------------------------------
# Listas auxiliares
# ---------------------------------------------------------------------------

# Paquetes de kernels viejos (excluye el kernel en uso y el más nuevo instalado)
kernels_viejos_paquetes() {
  local rel actual newest p v
  rel=$(uname -r)
  actual="linux-image-${rel}"
  mapfile -t imgs < <(dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*' 2>/dev/null | sort -V)
  (( ${#imgs[@]} <= 1 )) && return 0
  newest="${imgs[-1]}"
  for p in "${imgs[@]}"; do
    [[ "$p" == "$actual" || "$p" == "$newest" ]] && continue
    v="${p#linux-image-}"
    for extra in "linux-image-$v" "linux-headers-$v" "linux-modules-$v" "linux-modules-extra-$v" "linux-tools-$v"; do
      dpkg-query -W "$extra" >/dev/null 2>&1 && echo "$extra"
    done
  done
}

# Paquetes con configuraciones residuales (estado 'rc')
paquetes_rc() {
  dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' 2>/dev/null \
    | awk -F'|' '$1 ~ /^rc/ {print $2}'
}

# ---------------------------------------------------------------------------
# Estimaciones (bytes) — se ejecutan como usuario normal
# ---------------------------------------------------------------------------

estimar_bytes() {
  local clave=$1 out n
  case "$clave" in
    apt_cache)
      dir_bytes /var/cache/apt/archives /var/cache/apt/pkgcache.bin /var/cache/apt/srcpkgcache.bin ;;
    huerfanos)
      out=$(LANG=C apt-get -s autoremove --purge 2>/dev/null | awk '/will be freed/{print $4, $5}')
      [[ -n $out ]] && a_bytes $out || echo 0 ;;
    kernels)
      local total=0 kb
      while read -r p; do
        kb=$(dpkg-query -W -f='${Installed-Size}' "$p" 2>/dev/null)
        total=$(( total + ${kb:-0} ))
      done < <(kernels_viejos_paquetes)
      echo $(( total * 1024 )) ;;
    flatpaks)
      # No hay forma fiable de estimarlo sin ejecutar; devolvemos 0 (se muestra "—")
      echo 0 ;;
    miniaturas)
      dir_bytes "${HOME}/.cache/thumbnails" ;;
    temporales)
      # solo archivos de /tmp con más de 1 día de antigüedad
      local t=0
      while read -r f; do
        n=$(du -sb "$f" 2>/dev/null | cut -f1)
        t=$(( t + ${n:-0} ))
      done < <(find /tmp -mindepth 1 -maxdepth 1 -mtime +0 2>/dev/null)
      echo "$t" ;;
    papelera)
      dir_bytes "${HOME}/.local/share/Trash/files" "${HOME}/.local/share/Trash/info" ;;
    logs)
      out=$(LANG=C journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]?' | head -1)
      if [[ -n $out ]]; then
        n="${out%[!0-9.]*}"; local u="${out##*[0-9.]}"
        a_bytes "$n" "$u"
      else echo 0; fi ;;
    rc)
      echo 0 ;;  # las configuraciones residuales ocupan muy poco
    *) echo 0 ;;
  esac
}

# Texto auxiliar para la lista (conteos, etc.)
estimar_texto_extra() {
  local clave=$1 c
  case "$clave" in
    rc)   c=$(paquetes_rc | wc -l); echo "${c} paquetes con configuración residual" ;;
    kernels) c=$(kernels_viejos_paquetes | wc -l); echo "${c} paquetes de kernels viejos" ;;
    *) echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# Funciones de ejecución (corren como root dentro del script generado)
# $1 = home del usuario
# ---------------------------------------------------------------------------

tarea_apt_cache() {
  apt-get clean
  apt-get autoclean -y
}

tarea_huerfanos() {
  DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
}

tarea_kernels() {
  local rel newest p v pkgs=()
  rel=$(uname -r)
  mapfile -t imgs < <(dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*' 2>/dev/null | sort -V)
  (( ${#imgs[@]} <= 1 )) && return 0
  newest="${imgs[-1]}"
  for p in "${imgs[@]}"; do
    [[ "$p" == "linux-image-${rel}" || "$p" == "$newest" ]] && continue
    v="${p#linux-image-}"
    for extra in "linux-image-$v" "linux-headers-$v" "linux-modules-$v" "linux-modules-extra-$v" "linux-tools-$v"; do
      dpkg-query -W "$extra" >/dev/null 2>&1 && pkgs+=("$extra")
    done
  done
  (( ${#pkgs[@]} > 0 )) && DEBIAN_FRONTEND=noninteractive apt-get purge -y "${pkgs[@]}"
  return 0
}

tarea_flatpaks() {
  if command -v flatpak >/dev/null 2>&1; then
    flatpak uninstall --unused -y
    rm -rf /var/tmp/flatpak-cache-*
    rm -rf /var/lib/flatpak/cache/* 2>/dev/null
  fi
  return 0
}

tarea_miniaturas() {
  local uhome=$1
  rm -rf "${uhome}/.cache/thumbnails/"*
  return 0
}

tarea_temporales() {
  find /tmp -mindepth 1 -maxdepth 1 -mtime +0 -exec rm -rf {} + 2>/dev/null
  return 0
}

tarea_papelera() {
  local uhome=$1
  rm -rf "${uhome}/.local/share/Trash/files/"* "${uhome}/.local/share/Trash/info/"*
  return 0
}

tarea_logs() {
  journalctl --vacuum-time=7d
  journalctl --rotate
  journalctl --vacuum-time=7d
}

tarea_rc() {
  local pkgs
  pkgs=$(dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' 2>/dev/null | awk -F'|' '$1 ~ /^rc/ {print $2}')
  if [[ -n $pkgs ]]; then
    # shellcheck disable=SC2086
    DEBIAN_FRONTEND=noninteractive apt-get purge -y $pkgs
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Generación del script de limpieza (se ejecuta con pkexec o sudo)
# ---------------------------------------------------------------------------

# generar_script_limpieza <archivo_salida> <modo: gui|cli> <clave1> [clave2 ...]
generar_script_limpieza() {
  local out=$1 modo=$2; shift 2
  local tareas=("$@")
  local n=${#tareas[@]} i=1 clave fn pct pct_prev

  {
    echo '#!/bin/bash'
    echo "# Script generado por Limpiador Mint — $(date)"
    echo "set -u"
    echo "UHOME='${HOME}'"
    echo
    # incluimos las funciones de tarea
    declare -f tarea_apt_cache tarea_huerfanos tarea_kernels tarea_flatpaks \
               tarea_miniaturas tarea_temporales tarea_papelera tarea_logs tarea_rc
    echo
    if [[ $modo == gui ]]; then
      echo "progreso() { echo \"\$1\"; echo \"#\$2\"; sleep 0.2; }"
    else
      echo "progreso() { echo; echo \"===> \$2\"; }"
    fi
    echo

    for clave in "${tareas[@]}"; do
      fn="tarea_${clave}"
      pct_prev=$(( (i - 1) * 100 / n ))
      pct=$(( i * 100 / n ))
      local desc="${TAREA_DESC[$clave]:-$clave}"
      echo "progreso ${pct_prev} 'Limpiando: ${desc}'"
      if [[ $modo == gui ]]; then
        echo "${fn} \"\$UHOME\" >/dev/null 2>&1 || true"
      else
        echo "${fn} \"\$UHOME\" || echo '[!!] Falló: ${desc}'"
      fi
      echo "progreso ${pct} 'Listo: ${desc}'"
      echo
      (( i++ ))
    done
    echo "progreso 100 'Limpieza completada'"
  } > "$out"
  chmod +x "$out"
}

# ---------------------------------------------------------------------------
# Flujo gráfico de limpieza
# ---------------------------------------------------------------------------

gui_limpiar() {
  local filas=() clave b size_txt extra total_est=0
  declare -A est_bytes

  # Construimos la lista con estimaciones (puede tardar unos segundos)
  for clave in "${TAREAS_CLAVES[@]}"; do
    b=$(estimar_bytes "$clave")
    est_bytes[$clave]=$b
    total_est=$(( total_est + b ))
    if (( b > 0 )); then
      size_txt=$(human "$b")
    else
      size_txt="—"
    fi
    extra=$(estimar_texto_extra "$clave")
    [[ -n $extra ]] && size_txt="${size_txt} (${extra})"
    filas+=(FALSE "$clave" "${TAREA_DESC[$clave]}" "$size_txt")
  done

  local seleccion
  seleccion=$(zenity --list --checklist --multiple \
    --title="Limpiador Mint — Limpiar basura" \
    --text="Marca lo que quieras limpiar:" \
    --width=720 --height=520 \
    --column="Sel" --column="Clave" --column="Tarea" --column="Espacio aprox." \
    --hide-column=2 --print-column=2 \
    "${filas[@]}" 2>/dev/null) || return 0

  [[ -z $seleccion ]] && { aviso "No seleccionaste nada. 😊"; return 0; }

  IFS='|' read -ra elegidas <<< "$seleccion"

  # Resumen de confirmación
  local resumen="Se limpiarán:\n\n" sel tb=0
  for sel in "${elegidas[@]}"; do
    b=${est_bytes[$sel]:-0}
    tb=$(( tb + b ))
    if (( b > 0 )); then
      resumen+="• ${TAREA_DESC[$sel]} — $(human "$b")\n"
    else
      resumen+="• ${TAREA_DESC[$sel]}\n"
    fi
  done
  if (( tb > 0 )); then
    resumen+="\n<b>Space estimado a liberar: $(human "$tb")</b>\n\n¿Continuar?"
  else
    resumen+="\n¿Continuar?"
  fi
  confirmar "$(echo -e "$resumen")" || return 0

  # Verificamos herramientas de autenticación
  local RUNAS="" script_tmp log_tmp
  script_tmp=$(mktemp /tmp/limpiador-XXXXXX.sh)
  log_tmp=$(mktemp /tmp/limpiador-log-XXXXXX.txt)
  generar_script_limpieza "$script_tmp" gui "${elegidas[@]}"

  if command -v pkexec >/dev/null 2>&1; then
    RUNAS=(pkexec /bin/bash "$script_tmp")
  else
    RUNAS=(sudo /bin/bash "$script_tmp")
  fi

  local libre_antes libre_despues
  libre_antes=$(espacio_libre)

  ( "${RUNAS[@]}" >"$log_tmp" 2>&1; echo 100 ) \
    | zenity --progress --auto-close --no-cancel \
             --title="Limpiador Mint" --text="Iniciando limpieza..." \
             --width=520 --percentage=0 2>/dev/null
  local rc_pk=${PIPESTATUS[0]}

  libre_despues=$(espacio_libre)
  local liberado=$(( libre_despues - libre_antes ))
  (( liberado < 0 )) && liberado=0

  rm -f "$script_tmp"

  if (( rc_pk != 0 )); then
    error_gui "La limpieza no se completó (se canceló la autenticación o hubo un error).\n\nRegistro guardado en:\n$log_tmp"
    return 1
  fi

  aviso "✅ <b>Limpieza completada</b>\n\nEspacio liberado en disco: <b>$(human "$liberado")</b>\n\nRegistro detallado:\n$log_tmp"
}

# ---------------------------------------------------------------------------
# Modo CLI: limpia todo de una vez (--todo)
# ---------------------------------------------------------------------------

cli_limpiar_todo() {
  info "Modo CLI: se limpiarán TODAS las categorías."
  local script_tmp
  script_tmp=$(mktemp /tmp/limpiador-XXXXXX.sh)
  generar_script_limpieza "$script_tmp" cli "${TAREAS_CLAVES[@]}"

  local libre_antes libre_despues
  libre_antes=$(espacio_libre)

  echo "Se requieren permisos de administrador (sudo)..."
  if sudo /bin/bash "$script_tmp"; then
    libre_despues=$(espacio_libre)
    local liberado=$(( libre_despues - libre_antes ))
    (( liberado < 0 )) && liberado=0
    log "Limpieza completada. Espacio liberado: $(human "$liberado")"
  else
    err "La limpieza falló o se canceló."
  fi
  rm -f "$script_tmp"
}

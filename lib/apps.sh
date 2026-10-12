#!/usr/bin/env bash
# apps.sh — borrar aplicaciones (APT y Flatpak) del Limpiador Mint
# Formato de fila del inventario: id<TAB>nombre<TAB>fuente<TAB>tamaño_bytes<TAB>extra
#   fuente: "APT", "Flatpak (system)" o "Flatpak (user)"

# Construye el inventario de aplicaciones instaladas (excluye paquetes protegidos)
inventario_apps() {
  local p size desc
  # --- APT: una sola consulta por lote (rápido) ---
  local manuales
  manuales=$(apt-mark showmanual 2>/dev/null | sort)
  declare -A apt_size apt_desc
  while IFS=$'\t' read -r p size desc; do
    apt_size[$p]=${size:-0}
    apt_desc[$p]=${desc:-}
  done < <(dpkg-query -W -f='${Package}\t${Installed-Size}\t${binary:Summary}\n' 2>/dev/null)

  while read -r p; do
    [[ -z $p ]] && continue
    paquete_protegido "$p" && continue
    size=${apt_size[$p]:-0}
    printf '%s\t%s\t%s\t%s\t%s\n' "$p" "$p" "APT" "$(( size * 1024 ))" "${apt_desc[$p]:-}"
  done <<< "$manuales"
  unset apt_size apt_desc

  # --- Flatpak: solo aplicaciones (no runtimes) ---
  if command -v flatpak >/dev/null 2>&1; then
    local app nombre tam inst tam_bytes
    while IFS=$'\t' read -r app nombre tam inst; do
      [[ -z $app ]] && continue
      tam=${tam:-}
      # flatpak puede usar espacio duro (U+00A0) entre número y unidad; lo normalizamos
      tam=${tam//$'\xc2\xa0'/ }
      tam=${tam//[$'\t\r\n ']/ }
      if [[ $tam =~ ^[0-9]+$ ]]; then
        tam_bytes=$tam                       # bytes crudos (flatpak >= 1.16)
      elif [[ $tam =~ ^([0-9.]+)[[:space:]]*([KMGT]?i?B?)$ ]]; then
        tam_bytes=$(a_bytes "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")  # "671.9 MB"
      else
        tam_bytes=0
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "$app" "${nombre:-$app}" "Flatpak (${inst})" "$tam_bytes" ""
    done < <(flatpak list --app --columns=application,name,size,installation 2>/dev/null)
  fi
}

# Muestra la lista en zenity y devuelve los IDs seleccionados (separados por |)
# $1 = contenido filtrado del inventario, $2 = título
seleccionar_de_lista() {
  local inventario=$1 titulo=$2
  local filas=() id nombre fuente tam desc tam_txt

  while IFS=$'\t' read -r id nombre fuente tam desc; do
    [[ -z $id ]] && continue
    if (( tam > 0 )); then tam_txt=$(human "$tam"); else tam_txt="—"; fi
    filas+=(FALSE "$id" "$nombre" "$fuente" "$tam_txt")
  done <<< "$inventario"

  if (( ${#filas[@]} == 0 )); then
    aviso "No se encontraron aplicaciones para mostrar."
    return 1
  fi

  zenity --list --checklist --multiple \
    --title="$titulo" \
    --text="Marca las aplicaciones que quieras desinstalar:" \
    --width=860 --height=560 \
    --column="Sel" --column="ID" --column="Nombre" --column="Origen" --column="Tamaño" \
    --hide-column=2 --print-column=2 \
    "${filas[@]}" 2>/dev/null
}

# Desinstala los IDs seleccionados. $1 = inventario completo, resto = IDs (array por referencia en $@)
desinstalar_apps() {
  local inventario=$1; shift
  local ids=("$@")
  local id nombre fuente tam total=0 resumen="" cmd_root="" cmd_user="" apt_pkgs=()

  for id in "${ids[@]}"; do
    local linea
    linea=$(awk -F'\t' -v id="$id" '$1 == id {print; exit}' <<< "$inventario")
    [[ -z $linea ]] && continue
    IFS=$'\t' read -r id nombre fuente tam _ <<< "$linea"
    (( tam > 0 )) && total=$(( total + tam ))
    resumen+="• ${nombre} <i>(${fuente})</i> — $(human "${tam:-0}")\n"

    case "$fuente" in
      APT)
        paquete_protegido "$id" && { warn "Omitido paquete protegido: $id"; continue; }
        apt_pkgs+=("$id") ;;
      "Flatpak (system)")
        cmd_root+="flatpak uninstall -y --system '$id'; " ;;
      "Flatpak (user)")
        cmd_user+="flatpak uninstall -y --user '$id'; " ;;
    esac
  done

  if (( ${#apt_pkgs[@]} > 0 )); then
    resumen+="\n<i>Los paquetes APT se purgarán (se borran también sus configuraciones).</i>\n"
    cmd_root+="DEBIAN_FRONTEND=noninteractive apt-get purge -y ${apt_pkgs[*]}; "
  fi

  [[ -z $resumen ]] && { aviso "No hay nada que desinstalar."; return 0; }

  local texto="Se van a desinstalar:\n\n${resumen}"
  if (( total > 0 )); then
    texto+="\n<b>Espacio que se liberará: $(human "$total")</b>\n\n¿Estás seguro?"
  else
    texto+="\n¿Estás seguro?"
  fi
  confirmar "$(echo -e "$texto")" || return 0

  local log_tmp
  log_tmp=$(mktemp /tmp/limpiador-desinstala-XXXXXX.txt)

  # Flatpaks del usuario (sin root)
  if [[ -n $cmd_user ]]; then
    ( bash -c "$cmd_user" >"$log_tmp" 2>&1; echo 100 ) \
      | zenity --progress --pulsate --auto-close --no-cancel \
               --title="Limpiador Mint" --text="Desinstalando flatpaks del usuario..." 2>/dev/null
  fi

  # Lo que requiere root: una sola autenticación
  if [[ -n $cmd_root ]]; then
    local RUNAS=()
    if command -v pkexec >/dev/null 2>&1; then
      RUNAS=(pkexec /bin/bash -c "$cmd_root")
    else
      RUNAS=(sudo /bin/bash -c "$cmd_root")
    fi
    ( "${RUNAS[@]}" >>"$log_tmp" 2>&1; echo 100 ) \
      | zenity --progress --pulsate --auto-close --no-cancel \
               --title="Limpiador Mint" --text="Desinstalando (autenticación requerida)..." 2>/dev/null
    local rc=${PIPESTATUS[0]}
    if (( rc != 0 )); then
      error_gui "Hubo un error o se canceló la autenticación.\n\nRegistro: $log_tmp"
      return 1
    fi
  fi

  # ¿Limpiar huérfanos que hayan quedado?
  if (( ${#apt_pkgs[@]} > 0 )); then
    if confirmar "$(echo -e "✅ Desinstalación completada.\n\n¿Quieres eliminar también las dependencias huérfanas que hayan quedado?")"; then
      local RUNAS2=()
      if command -v pkexec >/dev/null 2>&1; then
        RUNAS2=(pkexec /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y")
      else
        RUNAS2=(sudo /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y")
      fi
      ( "${RUNAS2[@]}" >>"$log_tmp" 2>&1; echo 100 ) \
        | zenity --progress --pulsate --auto-close --no-cancel \
                 --title="Limpiador Mint" --text="Eliminando dependencias huérfanas..." 2>/dev/null
    fi
  fi

  aviso "✅ <b>Desinstalación completada</b>\n\nRegistro detallado:\n$log_tmp"
}

# Flujo principal: elegir modo y desinstalar
gui_borrar_apps() {
  local modo
  modo=$(zenity --list \
    --title="Limpiador Mint — Borrar aplicaciones" \
    --text="¿Cómo quieres buscar la aplicación a borrar?" \
    --width=560 --height=300 \
    --column="Modo" --column="Descripción" \
    "lista"   "📋 Lista interactiva: ver todas las apps instaladas con su tamaño" \
    "busqueda" "🔍 Búsqueda por nombre: escribir parte del nombre (ej. gimp)" \
    2>/dev/null) || return 0

  # Construir inventario (puede tardar unos segundos)
  zenity --progress --pulsate --auto-close --no-cancel \
    --title="Limpiador Mint" --text="Cargando lista de aplicaciones instaladas..." \
    --width=440 2>/dev/null &
  local pid_zen=$!
  local inventario
  inventario=$(inventario_apps)
  kill "$pid_zen" 2>/dev/null
  wait "$pid_zen" 2>/dev/null

  if [[ -z $inventario ]]; then
    error_gui "No se pudo leer la lista de aplicaciones instaladas."
    return 1
  fi

  local ids
  case "$modo" in
    lista)
      ids=$(seleccionar_de_lista "$inventario" "Aplicaciones instaladas") || return 0 ;;
    busqueda)
      local patron
      patron=$(zenity --entry \
        --title="Limpiador Mint — Buscar aplicación" \
        --text="Escribe parte del nombre de la aplicación:" \
        --width=440 2>/dev/null) || return 0
      [[ -z $patron ]] && return 0
      local filtrado
      filtrado=$(grep -i -- "$patron" <<< "$inventario")
      if [[ -z $filtrado ]]; then
        aviso "No se encontró ninguna aplicación que coincida con «$patron»."
        return 0
      fi
      ids=$(seleccionar_de_lista "$filtrado" "Resultados para «$patron»") || return 0 ;;
    *) return 0 ;;
  esac

  [[ -z $ids ]] && { aviso "No seleccionaste ninguna aplicación. 😊"; return 0; }

  IFS='|' read -ra seleccion <<< "$ids"
  desinstalar_apps "$inventario" "${seleccion[@]}"
}

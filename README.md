# 🧹 Limpiador Mint

Herramienta gráfica para **Linux Mint** que automatiza la limpieza de basura
del sistema y la desinstalación de aplicaciones (APT y Flatpak), usando
ventanas de [zenity](https://help.gnome.org/users/zenity/stable/) y `pkexec`
para pedir permisos de administrador con el diálogo nativo del sistema.

## Requisitos

- Linux Mint (probado en Mint 22.3 XFCE)
- `zenity` (ya viene instalado en Mint)
- `pkexec` (polkit, ya viene instalado en Mint)

## Uso

```bash
cd ~/Documentos/herramienta_Linux
./limpiador.sh
```

Se abre el menú gráfico principal:

| Opción | Descripción |
|---|---|
| 🧹 Limpiar basura | Elige con casillas qué limpiar, con tamaño estimado |
| 🗑️ Borrar aplicaciones | Lista interactiva o búsqueda por nombre (APT + Flatpak) |
| 💾 Ver espacio en disco | Resumen de uso de disco y cachés |
| 🖥️ Crear acceso directo | Añade «Limpiador Mint» al menú de XFCE |

### Modo terminal (sin ventanas)

```bash
./limpiador.sh --todo    # limpia TODAS las categorías (pide sudo)
./limpiador.sh --help    # ayuda
```

## Qué limpia

| Categoría | Comandos equivalentes |
|---|---|
| Caché de APT | `sudo apt clean && sudo apt autoclean` |
| Paquetes huérfanos | `sudo apt autoremove --purge` |
| Kernels antiguos | `sudo apt purge linux-image-X.Y.Z...` (conserva el kernel en uso y el más nuevo) |
| Flatpaks sin usar | `flatpak uninstall --unused` + borrado de cachés de flatpak |
| Miniaturas | borra `~/.cache/thumbnails` |
| Temporales | borra entradas de `/tmp` con más de 1 día |
| Papelera | vacía `~/.local/share/Trash` |
| Logs antiguos | `sudo journalctl --vacuum-time=7d` |
| Configuraciones residuales | `sudo apt purge $(dpkg -l \| awk '/^rc/{print $2}')` |

## Seguridad

- **Confirmación antes de cada acción destructiva**, con resumen y espacio
  estimado a liberar.
- **Lista de paquetes protegidos**: nunca se ofrece borrar el kernel en uso,
  paquetes esenciales (`Essential: yes`, prioridad `required`) ni componentes
  clave de Mint/XFCE (`mint*`, `xfce4*`, `grub*`, `systemd`, `lightdm`...).
- Al purgar apps APT, ofrece después eliminar las dependencias huérfanas.
- Se guarda un **registro en `/tmp`** de cada operación para poder revisarla.
- Los permisos de root se piden con el diálogo gráfico de polkit (`pkexec`);
  nunca se escribe la contraseña en una ventana de texto.

## Estructura

```
herramienta_Linux/
├── limpiador.sh        # Script principal (menú zenity)
├── lib/
│   ├── utilidades.sh   # Colores, diálogos, cálculo de espacio, protecciones
│   ├── limpieza.sh     # Tareas de limpieza + generación de script root
│   └── apps.sh         # Inventario y desinstalación de apps (APT/Flatpak)
└── README.md
```

## Automatización con cron (opcional)

Para limpiar todo automáticamente cada domingo a las 10:00:

```bash
sudo crontab -e
# añadir:
0 10 * * 0 /home/goscj1/Documentos/herramienta_Linux/limpiador.sh --todo
```

> Nota: en modo cron usa `sudo crontab` para que tenga permisos de root
> directamente (así no necesita pedir contraseña).

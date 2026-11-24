# AUR Toolkit · yay / paru
# Cargar únicamente en sesiones interactivas, sin consultas al iniciar Fish.
# Las consultas de AUR necesitan red; no sincronizan las bases de pacman.

if not status is-interactive
    return
end

function __aur_helper --description 'Imprimir el helper de AUR disponible'
    # Igual que sysupdate: yay primero, paru después.
    for helper in yay paru
        if command -q $helper
            echo $helper
            return 0
        end
    end
    return 1
end

function __aur_run --description 'Ejecutar yay o, si no está instalado, paru'
    # Elegir al ejecutar, no al cargar Fish.
    set -l helper (__aur_helper)
    or begin
        printf '%s\n' 'Falta un helper de AUR: instala yay o paru para usar estos atajos.' >&2
        return 127
    end

    # Conservar los menús de revisión de sysupdate para instalar/actualizar.
    # Paru tiene su propio flujo de revisión y no acepta estas opciones de yay.
    set -l review_args
    if test "$helper" = yay; and contains -- "$argv[1]" -Sa -Sua
        set review_args --diffmenu --editmenu
    end

    # El helper gestiona los privilegios; nunca ejecutarlo entero como root.
    command $helper $argv[1] $review_args $argv[2..-1]
end

# ─────────────────────────────────────────────
# AUR · Instalación y consultas
# ─────────────────────────────────────────────

# -a limita los objetivos a AUR; las dependencias pueden venir de repositorios.
alias auri='__aur_run -Sa'
alias aurs='__aur_run -Ssa'
alias aurinfo='__aur_run -Sia'

# Consultar actualizaciones disponibles en AUR, sin instalar nada.
alias aurcheck='__aur_run -Qua'

# ─────────────────────────────────────────────
# ACTUALIZACIÓN Y PKGBUILD
# ─────────────────────────────────────────────

# Solo AUR; para actualizar repositorios + AUR con verificaciones: sysupdate.
alias aurup='__aur_run -Sua'

# Descargar PKGBUILD y archivos relacionados en el directorio actual.
alias aurget='__aur_run -Ga'

# Tab: completar __aur_run (y con él auri, aurs, aurinfo...) como el helper.
# Sin esto la cadena de --wraps se cortaba en __aur_run y no sugería nada.
# Los paquetes de AUR salen de la caché de yay (yay -Pc); yay solo la
# descarga de nuevo cuando caduca (completionrefreshtime, 7 días por defecto).
if set -l helper (__aur_helper)
    complete -c __aur_run -w $helper
end

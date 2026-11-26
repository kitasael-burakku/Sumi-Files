# Pacman Toolkit
# Cargar únicamente en sesiones interactivas
# pkgsize/pkgtotal usan expac; deps/rdeps/cleanpkg y pkgaudit usan pacman-contrib.
# Las consultas son locales: no sincronizan bases de datos ni piden privilegios.

if not status is-interactive
    return
end

# ─────────────────────────────────────────────
# PACMAN · Gestión de paquetes
# ─────────────────────────────────────────────

# Uso de sudo
function S --wraps=sudo --description 'alias S sudo'
    sudo $argv
end

# Actualización de repositorios (para repositorios + AUR: sysupdate)
alias Syu='pkexec pacman -Syu'
alias qu='pacman -Qu'

# Instalación y búsqueda
alias i='pkexec pacman -S'
alias s='pacman -Ss'
alias si='pacman -Si'

# Eliminación: rns también quita dependencias que ya nadie usa (-s)
# y no guarda copias .pacsave de la configuración modificada (-n)
alias r='pkexec pacman -R'
alias rs='pkexec pacman -Rs'
alias rns='pkexec pacman -Rns'

# Paquetes instalados
alias q='pacman -Q'
alias qe='pacman -Qe'
alias qm='pacman -Qm'
alias qi='pacman -Qi'
alias ql='pacman -Ql'

# ─────────────────────────────────────────────
# AUDITORÍA · Solo lectura
# ─────────────────────────────────────────────

# Buscar entre los paquetes instalados
alias qss='pacman -Qs'

# Mostrar paquetes huérfanos
alias qdt='pacman -Qdt'

# Listar paquetes explícitos sin versiones
alias qeq='pacman -Qeq'

# Listar paquetes extranjeros sin versiones (no necesariamente del AUR)
alias qmq='pacman -Qmq'

# Mostrar dependencias de un paquete
alias deps='pactree'

# Mostrar qué paquetes dependen de otro
alias rdeps='pactree -r'

# Identificar el paquete dueño de un archivo
alias owns='pacman -Qo'

# Buscar qué paquete proporciona un archivo
alias provides='pacman -F'

# Simular una eliminación con dependencias
alias dryrs="pacman -Rs --print --print-format '%n %v'"

# Verificar archivos instalados de un paquete
alias checkpkg='pacman -Qk'

# ─────────────────────────────────────────────
# MANTENIMIENTO
# ─────────────────────────────────────────────

# Limpiar caché conservando tres versiones
alias cleanpkg='pkexec paccache -r'

# Actualizar la base de datos de archivos
alias syncfiles='pkexec pacman -Fy'

# Marcar como explícitos 
alias explicits='pkexec pacman -D --asexplicit'

# Marcar como dependencias
alias asdeps='pkexec pacman -D --asdeps'

function __pacman_sizes --description 'Consultar tamaño instalado en bytes y nombre'
    if not command -q expac
        printf '%s\n' 'Falta expac: pkgsize y pkgtotal lo necesitan para consultar tamaños en bytes.' >&2
        return 127
    end

    # %m consulta el tamaño registrado en ALPM, no el espacio físico ocupado.
    LC_ALL=C command expac -Q -H B '%m\t%n'
end

function pkgsize --description 'Mostrar los paquetes instalados más pesados'
    if test (count $argv) -eq 1; and contains -- "$argv[1]" -h --help
        printf '%s\n' 'Uso: pkgsize [cantidad]' 'Muestra 15 paquetes por defecto, ordenados por tamaño instalado.'
        return 0
    end

    if test (count $argv) -gt 1
        printf '%s\n' 'Uso: pkgsize [cantidad]' >&2
        return 2
    end

    set -l limit 15
    if set -q argv[1]
        set limit $argv[1]
    end
    if not string match -qr '^[1-9][0-9]*$' -- "$limit"
        printf '%s\n' 'Uso: pkgsize [cantidad entera positiva]' >&2
        return 2
    end

    # Capturar primero evita mostrar resultados parciales si falla la consulta.
    set -l sizes (__pacman_sizes)
    or return $status

    set -lx LC_ALL C
    printf '%s\n' $sizes | command sort -k1,1nr -k2,2 |
        command awk -F '\t' -v limit="$limit" 'NF == 2 && NR <= limit {printf "%9.2f MiB  %s\n", $1/1048576, $2}'
    # awk consume toda la entrada: no se corta sort con head/SIGPIPE.
    for rc in $pipestatus
        test $rc -eq 0; or return $rc
    end
    return 0
end

function pkgtotal --description 'Tamaño total registrado por pacman'
    if test (count $argv) -eq 1; and contains -- "$argv[1]" -h --help
        printf '%s\n' 'Uso: pkgtotal' 'Suma los tamaños registrados por pacman; no mide el espacio físico en disco.'
        return 0
    end
    if test (count $argv) -ne 0
        printf '%s\n' 'Uso: pkgtotal' >&2
        return 2
    end

    set -l sizes (__pacman_sizes)
    or return $status

    set -lx LC_ALL C
    printf '%s\n' $sizes | command awk -F '\t' '
        NF == 2 { total += $1; count++ }
        END {
            printf "Paquetes: %d\n", count
            printf "Tamaño instalado: %.2f GiB\n", total/1073741824
        }
    '
    for rc in $pipestatus
        test $rc -eq 0; or return $rc
    end
    return 0
end

function pkgaudit --description 'Auditoría básica de un paquete'
    if test (count $argv) -eq 1; and contains -- "$argv[1]" -h --help
        printf '%s\n' 'Uso: pkgaudit <paquete>' 'Consulta información, dependencias inversas y simula su eliminación.' 'Devuelve un estado distinto de cero si alguna consulta falla o queda incompleta.'
        return 0
    end
    if test (count $argv) -ne 1; or test -z "$argv[1]"; or string match -q -- '-*' "$argv[1]"
        printf '%s\n' 'Uso: pkgaudit <paquete>' >&2
        return 2
    end

    set -l pkg $argv[1]

    echo "=== INFORMACIÓN ==="
    # Una sola consulta; conservar el diagnóstico y el código de pacman.
    command pacman -Qi -- "$pkg"
    or return $status

    echo
    echo "=== DEPENDENCIAS INVERSAS ==="
    set -l tree_rc 0
    if command -q pactree
        command pactree -r -- "$pkg"
        set tree_rc $status
    else
        printf '%s\n' 'Auditoría incompleta: falta pactree (pacman-contrib).' >&2
        set tree_rc 127
    end

    echo
    echo "=== SIMULACIÓN DE ELIMINACIÓN ==="
    command pacman -Rs --print --print-format '%n %v' -- "$pkg"
    or return $status
    return $tree_rc
end

complete -c pkgsize -f -s h -l help -d 'Mostrar ayuda'
complete -c pkgtotal -f -s h -l help -d 'Mostrar ayuda'
complete -c pkgaudit -f -s h -l help -d 'Mostrar ayuda'
complete -c pkgaudit -f -n __fish_is_first_arg -a '(command pacman -Qq)' -d 'Paquete instalado'

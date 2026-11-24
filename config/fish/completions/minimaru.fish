
# Completions para Minimaru · Sumi Shell
# Sin efectos secundarios ni consultas IPC.

set -l subs health clean update theme wall mode doctor dashboard diskbackup menu

# Desactivar completions de archivos por defecto.
complete -c minimaru -f

# Opciones globales
complete -c minimaru \
    -n "not __fish_seen_subcommand_from $subs" \
    -s h -l help -d 'Show help'

complete -c minimaru \
    -n "not __fish_seen_subcommand_from $subs" \
    -s V -l version -d 'Sumi Shell version'
    
# Subcomandos
for entry in \
    'health:System health check' \
    'clean:Quick cache cleanup' \
    'update:Full system update (pacman + AUR)' \
    'theme:Visual profile (Matugen)' \
    'wall:Wallpaper picker' \
    'mode:Desktop mode' \
    'doctor:System diagnostics' \
    'dashboard:Open control centre' \
    'diskbackup:Mirror to the backup disk' \
    'menu:Show shell controls'

    set -l parts (string split -m1 ':' -- $entry)

    complete -c minimaru \
        -n "not __fish_seen_subcommand_from $subs" \
        -a "$parts[1]" \
        -d "$parts[2]"
end

# Health
complete -c minimaru \
    -n '__fish_seen_subcommand_from health' \
    -l json -d 'Output diagnostic records as JSON'

# Clean
complete -c minimaru \
    -n '__fish_seen_subcommand_from clean' \
    -l deep -d 'Clean orphans and pacman cache'

# Doctor
complete -c minimaru \
    -n '__fish_seen_subcommand_from doctor' \
    -l json -d 'Output diagnostic records as JSON'

complete -c minimaru \
    -n '__fish_seen_subcommand_from doctor' \
    -l fresh-clone -d 'Check machine-specific configuration'

# Backup
complete -c minimaru \
    -n '__fish_seen_subcommand_from diskbackup' \
    -l check -d 'Check pending changes without writing'

# Wallpapers
complete -c minimaru \
    -n '__fish_seen_subcommand_from wall' \
    -l fzf -d 'Use terminal wallpaper picker'

# Matugen schemes
set -l schemes \
    tonal-spot vibrant expressive fidelity content \
    neutral rainbow monochrome fruit-salad

for scheme in $schemes
    complete -c minimaru \
        -n '__fish_seen_subcommand_from theme' \
        -a "$scheme"
end

# Desktop modes
complete -c minimaru \
    -n '__fish_seen_subcommand_from mode' \
    -a 'normal focus gaming cinema status'


function move --description "Safe mv wrapper with --mkdir and --dry-run"
    set -l create_dir false
    set -l dry_run false
    set -l literal false
    set -l paths

    # Parsear opciones propias
    for arg in $argv
        if test "$literal" = false
            switch "$arg"
                case --mkdir
                    set create_dir true
                    continue
                case --dry-run
                    set dry_run true
                    continue
                case --
                    set literal true
                    continue
            end

            if string match -q -- '-*' "$arg"
                printf "move: opción desconocida: %s\n" "$arg" >&2
                return 2
            end
        end

        set -a paths "$arg"
    end

    # Validar argumentos
    if test (count $paths) -lt 2
        echo "Uso: move [--mkdir] [--dry-run] ORIGEN... DESTINO" >&2
        return 2
    end

    set -l destination $paths[-1]
    set -l sources $paths[1..-2]

    # Validar todos los orígenes antes de crear nada
    for source in $sources
        if not test -e "$source"; and not test -L "$source"
            printf "move: origen inexistente: %s\n" "$source" >&2
            return 1
        end
    end

    if test "$create_dir" = true
        # No convertir un archivo existente en directorio
        if test -e "$destination"; or test -L "$destination"
            if not test -d "$destination"
                printf "move: el destino no es un directorio: %s\n" "$destination" >&2
                return 1
            end
        else
            # Un origen + destino nuevo sin / es ambiguo
            if test (count $sources) -eq 1
                if not string match -q '*/' -- "$destination"
                    if test "$dry_run" = false
                        if not status is-interactive
                            echo "move: destino ambiguo; añade / al final" >&2
                            return 2
                        end

                        read --line --prompt-str \
                            "¿Crear directorio '$destination'? [s/N] " answer
                        or return 1

                        switch (string lower -- "$answer")
                            case s si sí y yes
                                # Confirmado
                            case '*'
                                echo "move: operación cancelada"
                                return 1
                        end
                    end
                end
            end
        end
    end

    # Modo simulación
    if test "$dry_run" = true
        if test "$create_dir" = true
            if not test -d "$destination"
                printf '[DRY-RUN] mkdir -p -- %s\n' \
                    (string escape -- "$destination")
            end
        end

        set -l shown (string join ' ' -- (string escape -- $paths))
        printf '[DRY-RUN] mv -iv -- %s\n' "$shown"
        return 0
    end

    # Crear destino únicamente después de validar
    if test "$create_dir" = true
        command mkdir -p -- "$destination"
        or return $status
    end

    # Ejecutar mv original con protección interactiva
    command mv -iv -- $paths
end

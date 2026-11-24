# jerrors — errores del journal (prioridad ≤ 3) con el ruido cosmético conocido
# plegado en un resumen, en vez de escondido.
#
# Por qué existe: `journalctl -p 3` mezcla dos cosas que no se parecen en nada.
# Por un lado fallos reales — una unidad que no arranca, un proceso que vuelca
# core. Por otro, mensajes que ciertos programas registran con LOG_ERR cuando
# en realidad solo reportan una capacidad ausente o una carrera inofensiva de
# arranque. Leer la lista cruda enseña a desconfiar de todo por igual, que es
# justo lo contrario de lo que sirve.
#
# LA REGLA DE ORO: nada se oculta en silencio. Lo plegado se cuenta siempre al
# final, con el nombre de la regla que lo plegó, y `--all` / `--why` lo
# devuelven a la vista. Un filtro que no se anuncia es peor que no filtrar:
# convierte "no vi nada" en "no había nada", que es el mismo falso positivo de
# limpieza que _rui_pacfiles existe para evitar.
#
# Lo que NUNCA se pliega, por diseño: coredumps (systemd-coredump), unidades
# que fallan al arrancar, y cualquier cosa que no esté en la tabla de reglas.
# Ante la duda, la línea se muestra.

# Tabla de reglas: id <TAB> regex <TAB> motivo.
#
# Los regex son deliberadamente largos y específicos: pliegan ESTE mensaje, no
# la categoría entera. El caso de sudo lo ilustra — "sudo" como identificador
# no se pliega jamás, solo el sondeo `sudo -n true`, porque un sudo que falla
# de verdad sí es señal que quieres ver.
function __jerrors_rules --description "Reglas de plegado de jerrors: id<TAB>regex<TAB>motivo"
    printf '%s\t%s\t%s\n' tdx \
        'virt/tdx: TDX not supported by the host platform' \
        'Kernel de CachyOS compilado con CONFIG_INTEL_TDX_HOST=y corriendo en CPU AMD. TDX es exclusivo de Intel: la rutina de init falla siempre y lo reporta con pr_err. 1 vez por arranque, inevitable sin recompilar el kernel.'

    printf '%s\t%s\t%s\n' wifi-mcast \
        'nl80211: kernel reports: multicast RX registrations are not supported' \
        'El driver ath12k (Qualcomm WCN785x Wi-Fi 7) no anuncia MULTICAST_REGISTRATIONS. wpa_supplicant lo loguea como error, pero es solo un "no" a una pregunta de capacidades: sigue registrando frames por interfaz y conecta igual.'

    printf '%s\t%s\t%s\n' gkr-pam \
        'gkr-pam: unable to locate daemon control file' \
        'En la fase auth de PAM el daemon de gnome-keyring aún no existe (arranca en la fase session). PAM guarda la contraseña y desbloquea el llavero en cuanto nace. Solo se pliega si ese mismo arranque registró "unlocked login keyring" — si el desbloqueo falló de verdad, la línea se muestra.'

    printf '%s\t%s\t%s\n' sudo-probe \
        'a password is required ;.*COMMAND=/usr/bin/true$' \
        'Sondeo no interactivo `sudo -n true` de _rui_pacfiles (report-ui.fish), que pregunta "¿tengo token de sudo en caché?" antes de escanear /etc en busca de .pacnew. Si no hay token falla al instante por diseño y cae al escaneo sin privilegios. Un sudo fallido con CUALQUIER otro comando NO se pliega.'

    printf '%s\t%s\t%s\n' nm-dispatcher \
        'Activation request for .org\.freedesktop\.nm_dispatcher. failed' \
        'Carrera entre la activación por D-Bus y systemd, que ya estaba arrancando o parando NetworkManager-dispatcher. El servicio está enabled y corre bien ("Started" / "Deactivated successfully" en el mismo journal).'

    printf '%s\t%s\t%s\n' bt-hid \
        'profiles/input/(device|server)\.c:(control_connect_cb\(\) connect to .*: (Function not implemented|Host is down)|auth_callback\(\) Access denied|hidp_add_connection\(\) Rejected connection from !bonded device)' \
        'Ruido del perfil HID de bluetoothd cuando un mando (tu DualSense) sondea o intenta conectar sin estar emparejado. bluetoothd lo registra como error; es el rechazo esperado.'

    printf '%s\t%s\t%s\n' bt-nomatch \
        'bluetoothd.*No matching connection for device' \
        'bluetoothd buscó una conexión que ya se había cerrado. Contabilidad interna al desconectar, sin efecto.'

    printf '%s\t%s\t%s\n' dualsense-crc \
        'DualSense input CRC.s check failed' \
        'El driver hid-playstation descarta paquetes del mando con CRC inválido (normal por interferencia en Bluetooth) y loguea cada uno. El mando sigue funcionando.'

    printf '%s\t%s\t%s\n' sd-pam-session \
        'Varlink call io\.systemd\.Login\.ReleaseSession failed: io\.systemd\.Login\.NoSuchSession' \
        'Al cerrar sesión, pam_systemd intenta liberar una sesión que logind ya había destruido. Carrera de orden en el apagado de la sesión, inofensiva.'
end

function jerrors --description "Errores del journal (p≤3) sin el ruido cosmético conocido"
    # -i (--ignore-unknown) es lo que deja pasar los argumentos de journalctl:
    # sin él, `jerrors -b -1` moría con "-b: unknown option" en vez de consultar
    # el arranque anterior. El precio es que un flag mal escrito ya no se detecta
    # aquí — lo rechaza journalctl, y el código de salida se propaga igual.
    # Ojo: -a/--all lo captura ESTA función (no filtrar), no journalctl.
    argparse -i -x a,w h/help a/all w/why -- $argv
    or return 2

    if set -q _flag_help
        echo "jerrors — errores del journal (prioridad ≤ 3), sin el ruido cosmético conocido."
        echo ""
        echo "Uso: jerrors [-a|--all] [-w|--why] [args extra de journalctl]"
        echo ""
        echo "  (sin opciones)  Errores del arranque actual, con el ruido conocido plegado"
        echo "                  y contado al final. Nunca oculta nada en silencio."
        echo "  -a, --all       No filtra nada. La salida cruda de journalctl -b -p 3."
        echo "  -w, --why       Explica cada regla de plegado y qué mensaje cubre."
        echo "  -h, --help      Esto."
        echo ""
        echo "Los argumentos extra pasan tal cual a journalctl:"
        echo "  jerrors -b -1            errores del arranque anterior"
        echo "  jerrors --since today    errores de hoy, todos los arranques"
        echo "  jerrors -p 4             baja el umbral a warning"
        echo ""
        echo "Nunca se pliegan: coredumps, unidades que fallan al arrancar, y todo"
        echo "lo que no esté en la tabla de reglas (jerrors --why)."
        return 0
    end

    if set -q _flag_why
        echo ""
        set_color --bold brwhite
        echo "  Reglas de plegado de jerrors"
        set_color normal
        set_color brblack
        echo "  Cada una cubre un mensaje concreto, no una categoría."
        set_color normal
        for r in (__jerrors_rules)
            set -l f (string split \t -- $r)
            echo ""
            set_color --bold yellow
            echo "  ▸ $f[1]"
            set_color brblack
            echo "    patrón: $f[2]"
            set_color normal
            echo "$f[3]" | fold -s -w 72 | sed 's/^/    /'
        end
        echo ""
        return 0
    end

    # journalctl no acepta `-b` dos veces de forma predecible, así que solo lo
    # añadimos cuando quien llama no eligió ya su propio rango. Sin esto,
    # `jerrors -b -1` y `jerrors --since ayer` harían algo distinto de lo que
    # dicen.
    set -l jargs -p 3 --no-pager
    set -l has_range 0
    for a in $argv
        if string match -qr -- '^(-b|--boot|--since|--until)' $a
            set has_range 1
        end
    end
    test $has_range -eq 0; and set -a jargs -b
    set -a jargs $argv

    set -l out (journalctl $jargs)
    set -l rc $status
    if test $rc -ne 0
        set_color red
        echo "jerrors: journalctl falló (código $rc)" >&2
        set_color normal
        return $rc
    end

    # `-- No entries --` es texto, no un error: si es lo único que hay, la
    # lista está vacía.
    if test (count $out) -eq 1; and string match -qr 'No entries' -- $out[1]
        set out
    end

    if set -q _flag_all
        if test (count $out) -eq 0
            set_color green; echo "✓ Sin errores (p≤3) en el rango consultado."; set_color normal
        else
            printf '%s\n' $out
        end
        return 0
    end

    # gkr-pam solo se pliega si el llavero llegó a desbloquearse. La línea
    # "unable to locate daemon control file" es benigna únicamente como primer
    # paso de la secuencia stash → unlock; si el unlock nunca llegó, entonces sí
    # es un fallo real del llavero y debe verse.
    #
    # Limitación consciente: la comprobación mira SIEMPRE el arranque actual
    # (-b), también cuando la consulta abarca varios (--since). Se prefiere así
    # porque el caso que importa es "¿mi llavero funciona ahora?"; un fallo de
    # llavero de hace tres arranques, ya resuelto, no es accionable.
    set -l gkr_unlocked 0
    set -l unlock (journalctl -b -q -g 'unlocked login keyring' -n 1 2>/dev/null)
    test (count $unlock) -gt 0; and set gkr_unlocked 1

    set -l ids
    set -l pats
    set -l whys
    set -l hits
    for r in (__jerrors_rules)
        set -l f (string split \t -- $r)
        set -a ids $f[1]
        set -a pats $f[2]
        set -a whys $f[3]
        set -a hits 0
    end

    set -l kept
    set -l folded 0
    for line in $out
        set -l matched 0
        for i in (seq (count $ids))
            if test $ids[$i] = gkr-pam; and test $gkr_unlocked -eq 0
                continue
            end
            if string match -qr -- $pats[$i] $line
                set hits[$i] (math $hits[$i] + 1)
                set matched 1
                break
            end
        end
        if test $matched -eq 1
            set folded (math $folded + 1)
        else
            set -a kept $line
        end
    end

    if test (count $kept) -eq 0
        set_color green
        echo "✓ Sin errores reales. Todo lo del journal era ruido conocido."
        set_color normal
    else
        printf '%s\n' $kept
    end

    # El resumen va a stderr para que `jerrors | grep algo` siga limpio, pero
    # se vea igual en la terminal.
    if test $folded -gt 0
        set -l labels
        for i in (seq (count $ids))
            test $hits[$i] -gt 0; and set -a labels "$ids[$i]×$hits[$i]"
        end
        set -l dim (set_color brblack)
        set -l off (set_color normal)
        printf '%s\n' "" >&2
        printf '%s  %d línea(s) cosmética(s) plegada(s): %s%s\n' \
            $dim $folded (string join ', ' $labels) $off >&2
        printf '%s  jerrors --all para verlas · jerrors --why para saber por qué%s\n' \
            $dim $off >&2
    end

    return 0
end

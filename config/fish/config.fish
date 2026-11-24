function fastfetch --description "fastfetch with a weighted roulette of configs"
    if not command -q fastfetch
        echo "fastfetch not found"
        return 1
    end

    set -l base "$HOME/.config/fastfetch"

    # With arguments: "fastfetch fox" forces fox.jsonc, anything else
    # (--help, -c foo, ...) goes straight to the real fastfetch.
    if test (count $argv) -gt 0
        if test (count $argv) -eq 1 -a -f "$base/$argv[1].jsonc"
            command fastfetch --config "$base/$argv[1].jsonc"
        else
            command fastfetch $argv
        end
        return
    end

    # Weights = how many times each config shows up per round of the bag.
    # Every *.jsonc in $base joins automatically with $default_weight;
    # weight 0 takes it out of the roulette.
    set -l weights \
        minimaru:4 \
        goldship:4 \
        fox:4 \
        yani:3 \
        Yani-Neko:3 \
        arch:2 \
        microfetch:2 \
        lfs:2 \
        cachyos:2 \
        hyprmc:2 \
        minimaru_ascii:2 \
        duki:1
    set -l default_weight 2

    set -l bag_file "$base/.fastfetch_bag"

    # Current pool as name:weight, from the files that actually exist
    set -l pool
    for file in $base/*.jsonc
        set -l name (path change-extension '' (path basename $file))
        set -l weight $default_weight
        for item in $weights
            set -l kv (string split ":" $item)
            test "$kv[1]" = "$name"; and set weight $kv[2]
        end
        # Some logos aren't distributed (fastfetch/fastfetchlogo/README.md): a
        # preset whose logo file is missing stays out of the pool. Left in the
        # bag it would never be drawn, and once only such presets remained the
        # roulette would fall back to plain fastfetch for good. Adding the file
        # changes the signature below, so the bag is rebuilt with it.
        set -l logo (string match -rg '"source":\s*"(~?/[^"]+)"' < "$file")
        if test -n "$logo[1]"; and not test -f (string replace -r '^~' -- "$HOME" "$logo[1]")
            continue
        end
        test "$weight" -gt 0; and set pool $pool "$name:$weight"
    end
    set -l sig (string join "," $pool)

    # Bag file: "#<sig>" line, "@<last shown>" line, then one name per line.
    # Empty lines are ignored, so an emptied bag (a lone newline) reads as 0.
    set -l saved_sig
    set -l last
    set -l bag
    if test -f "$bag_file"
        for line in (cat "$bag_file")
            switch $line
                case '#*'
                    set saved_sig (string sub -s 2 -- $line)
                case '@*'
                    set last (string sub -s 2 -- $line)
                case ''
                    # fish 4 has no "?" wildcard, so skip blanks explicitly
                case '*'
                    set bag $bag $line
            end
        end
    end

    # Refill when empty, or when configs/weights changed (new config added,
    # one deleted, weight edited) so changes show up right away.
    if test (count $bag) -eq 0 -o "$saved_sig" != "$sig"
        set bag
        for item in $pool
            set -l kv (string split ":" $item)
            for i in (seq $kv[2])
                set bag $bag $kv[1]
            end
        end

        # Shuffle until no config comes twice in a row, not even across the
        # refill (compared against the last one shown). Repeats stuck at the
        # tail can't be pushed forward, hence retrying the whole shuffle.
        for attempt in (seq 20)
            # Fisher-Yates shuffle
            for i in (seq (count $bag) -1 2)
                set -l j (random 1 $i)
                set -l tmp $bag[$i]
                set bag[$i] $bag[$j]
                set bag[$j] $tmp
            end

            # Spread out repeats by swapping with the next different one
            set -l prev $last
            for i in (seq (count $bag))
                if test "$bag[$i]" = "$prev"
                    for j in (seq (math $i + 1) (count $bag))
                        if test "$bag[$j]" != "$prev"
                            set -l tmp $bag[$i]
                            set bag[$i] $bag[$j]
                            set bag[$j] $tmp
                            break
                        end
                    end
                end
                set prev $bag[$i]
            end

            set -l clash 0
            set prev $last
            for name in $bag
                if test "$name" = "$prev"
                    set clash 1
                    break
                end
                set prev $name
            end
            test $clash -eq 0; and break
        end
    end

    # Image logos (kitty-direct) only render in kitty/ghostty; elsewhere
    # take the next text-logo config and leave the image ones in the bag.
    set -l can_img 0
    if set -q KITTY_WINDOW_ID; or string match -qr 'kitty|ghostty' -- "$TERM"
        set can_img 1
    end

    set -l pick 0
    for i in (seq (count $bag))
        if test $can_img -eq 0; and grep -q '"kitty' "$base/$bag[$i].jsonc"
            continue
        end
        set pick $i
        break
    end

    if test $pick -eq 0
        command fastfetch
        return
    end

    set -l selected $bag[$pick]
    set -e bag[$pick]

    begin
        echo "#$sig"
        echo "@$selected"
        printf "%s\n" $bag
    end >"$bag_file"

    command fastfetch --config "$base/$selected.jsonc"
end

if status is-interactive
    set -g fish_greeting

    # Perfil independiente para la consola Linux
    if test "$TERM" = linux
        set -gx STARSHIP_CONFIG "$HOME/.config/starship-tty.toml"

        # Nombres compatibles con fuentes PSF
        # Override either one in conf.d/local.fish (not versioned).
        set -q USER_PRETTY; or set -gx USER_PRETTY $USER
        set -q HOSTNAME_PRETTY; or set -gx HOSTNAME_PRETTY (prompt_hostname)
    else
        # Mantener Starship normal bajo Matugen
        set -e STARSHIP_CONFIG
    end

    if command -q starship
        starship init fish | source
    end

    if command -q thefuck
        function fuck --description "Loads thefuck only on first use (instant startup)"
            functions -e fuck
            thefuck --alias | source
            fuck $argv
        end
    end
    
end

# Created by pipx / local user binaries
#
# -g and not universal: this used to coexist with a universal fish_user_paths
# stored in fish_variables with the same value, meaning the path was defined
# in two places and only one of them is visible in the dotfiles. This one
# stays, readable here and versionable; the universal one was deleted.
fish_add_path -g "$HOME/.local/bin"

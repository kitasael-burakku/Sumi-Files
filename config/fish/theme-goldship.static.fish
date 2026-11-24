# ~/.config/fish/conf.d/theme-goldship.fish
# Minimaru · Glass Universal · Fish shell theme
# Palette: Minimaru · Universal Dark (roles de palettes/static/minimaru-dark.json)
# Mismo reparto de roles que la plantilla de matugen (theme-goldship.fish):
# comando = primary, palabra clave = secondary, builtin = tertiary…
#
# Real limitation: fish only reads conf.d/ when a shell STARTS — there's no
# hot-reload signal like kitty's. Already-open terminals keep the
# old colors until you open a new one.

# ── Syntax: core ──────────────────────────────────────────────
set -g fish_color_normal          e8e8e8
set -g fish_color_command         90cece
set -g fish_color_builtin         cfbf9f
set -g fish_color_keyword         ceb6df
set -g fish_color_end             6a6a62
set -g fish_color_error           b85c50

# on_*_container sale BLANCO en modo claro (scheme-content / --contrast > 0):
# en claro se usa el rol base (secondary/tertiary), que sí contrasta.

# ── Syntax: arguments & operators ───────────────────────────
set -g fish_color_param           a8a8a8
set -g fish_color_option          6a6a62
set -g fish_color_operator        ceb6df
set -g fish_color_redirection     42423e
set -g fish_color_escape          e8e8e8
set -g fish_color_quote           cfbf9f

# ── Syntax: structure ────────────────────────────────────────
set -g fish_color_comment         6a6a62
set -g fish_color_bracket         ceb6df

# ── Paths ─────────────────────────────────────────────────────
set -g fish_color_valid_path      e8e8e8 --underline
set -g fish_color_cwd             a8a8a8
set -g fish_color_cwd_root        ceb6df

# ── Autosuggestions & history ───────────────────────────────
set -g fish_color_autosuggestion  6a6a62
set -g fish_color_history_current e8e8e8 --bold
set -g fish_color_cancel          b85c50

# ── Search & selection ────────────────────────────────────────
set -g fish_color_search_match    e8e8e8 --background=2f2f2f
set -g fish_color_selection       e8e8e8 --background=262626
set -g fish_color_match           cfbf9f

# ── Prompt: user & host ───────────────────────────────────────
set -g fish_color_user            e8e8e8
set -g fish_color_host            6a6a62
set -g fish_color_host_remote     cfbf9f

# ── Prompt: status ────────────────────────────────────────────
set -g fish_color_status          b85c50

# ── Completions pager ─────────────────────────────────────────
set -g fish_pager_color_progress              42423e
set -g fish_pager_color_prefix                e8e8e8
set -g fish_pager_color_completion            a8a8a8
set -g fish_pager_color_description           6a6a62
set -g fish_pager_color_secondary             42423e

set -g fish_pager_color_selected_background   --background=262626
set -g fish_pager_color_selected_prefix       e8e8e8
set -g fish_pager_color_selected_completion   e8e8e8
set -g fish_pager_color_selected_description  cfbf9f

--  ██▀███ ▓██   ██▓ █    ██   ██████  █    ██  ██▓
-- ▓██ ▒ ██▒▒██  ██▒ ██  ▓██▒▒██    ▒  ██  ▓██▒▓██▒
-- ▓██ ░▄█ ▒ ▒██ ██░▓██  ▒██░░ ▓██▄   ▓██  ▒██░▒██▒
-- ▒██▀▀█▄   ░ ▐██▓░▓▓█  ░██░  ▒   ██▒▓▓█  ░██░░██░
-- ░██▓ ▒██▒ ░ ██▒▓░▒▒█████▓ ▒██████▒▒▒▒█████▓ ░██░
-- ░ ▒▓ ░▒▓░  ██▒▒▒ ░▒▓▒ ▒ ▒ ▒ ▒▓▒ ▒ ░░▒▓▒ ▒ ▒ ░▓
--
-- ║   流 水   ·   R Y Ū S U I   M O T I O N   ·  流 水
-- ║   Terminales sobre agua · Rigid panels, liquid surface

-- ─── Beziers ────────────────────────────────────────────────────────────
hl.curve("senal", { type = "bezier", points = { { 0.05, 0.90 }, { 0.10, 1.00 } } })
hl.curve("ryuOut", { type = "bezier", points = { { 0.16, 1.00 }, { 0.30, 1.00 } } })
hl.curve("stillWater", { type = "bezier", points = { { 0.37, 0.00 }, { 0.63, 1.00 } } })
hl.curve("hundir", { type = "bezier", points = { { 0.55, 0.00 }, { 0.80, 0.25 } } })
hl.curve("meniscus", { type = "bezier", points = { { 0.25, 0.10 }, { 0.25, 1.00 } } })
hl.curve("lineal", { type = "bezier", points = { { 0.00, 0.00 }, { 1.00, 1.00 } } })

-- ─── Springs ────────────────────────────────────────────────────────────
hl.curve("flotacion", { type = "spring", mass = 1, stiffness = 340, damping = 30 })
hl.curve("superficie", { type = "spring", mass = 1, stiffness = 280, damping = 31 })

-- ─── Ventanas ───────────────────────────────────────────────────────────
hl.animation({ leaf = "windowsIn", enabled = true, speed = 1.8, spring = "flotacion", style = "gnomed" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.0, bezier = "hundir", style = "gnomed" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.0, spring = "flotacion" })

-- ─── Fades ──────────────────────────────────────────────────────────────
hl.animation({ leaf = "fade", enabled = true, speed = 1.2, bezier = "stillWater" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.4, bezier = "senal" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.4, bezier = "hundir" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 2.0, bezier = "stillWater" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 1.6, bezier = "ryuOut" })

-- ─── Borde ──────────────────────────────────────────────────────────────
hl.animation({ leaf = "border", enabled = true, speed = 2.5, bezier = "ryuOut" })
-- Off since the border became solid: a "loop" animation keeps Hyprland
-- redrawing every frame even when nothing moves, for an angle there isn't.
hl.animation({ leaf = "borderangle", enabled = false })

-- ─── Layers (barra, lanzador, notificaciones) ───────────────────────────
hl.animation({ leaf = "layersIn", enabled = true, speed = 2.0, spring = "flotacion", style = "slide" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.4, bezier = "hundir", style = "slide" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.4, bezier = "senal" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.2, bezier = "hundir" })

-- ─── Popups (menús contextuales, tooltips) ──────────────────────────────
hl.animation({ leaf = "fadePopupsIn", enabled = true, speed = 0.8, bezier = "senal" })
hl.animation({ leaf = "fadePopupsOut", enabled = true, speed = 0.6, bezier = "hundir" })

-- ─── Workspaces ─────────────────────────────────────────────────────────
hl.animation({ leaf = "workspaces", enabled = true, speed = 3.0, spring = "superficie", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3.0, spring = "flotacion", style = "slide" })
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 3.0, spring = "flotacion", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 1.8, bezier = "hundir", style = "slidevert" })

-- ─── Varios ─────────────────────────────────────────────────────────────
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 2.6, bezier = "meniscus" })
hl.animation({ leaf = "monitorAdded", enabled = true, speed = 2.4, bezier = "ryuOut" })
hl.animation({ leaf = "fadeDpms", enabled = true, speed = 4.0, bezier = "stillWater" })
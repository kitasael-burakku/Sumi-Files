--  ____  __.            __________.__            .___
-- |    |/ _|____ ___.__.\______   \__| ____    __| _/______
-- |      <_/ __ <   |  | |    |  _/  |/    \  / __ |/  ___/
-- |    |  \  ___/\___  | |    |   \  |   |  \/ /_/ |\___ \
-- |____|__ \___  > ____| |______  /__|___|  /\____ /____  >
--         \/   \/\/             \/        \/      \/    \/ ---------

local V = require("modules.vars")
local mainMod = V.mainMod -- generate-keybinds-doc.sh lee los binds como `mainMod .. "..."`
local hyprDir = V.hyprDir
Programs = Programs or {}

------------------------------
----        APPS          ----
------------------------------

-- Terminal
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(Programs.terminal))

-- File Manager
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(Programs.fileManager))

-- Browser
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(Programs.browser))

-- Toggle theming dinámico (matugen)
--hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(Programs.themeToggle))

-- OBS Studio
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd(Programs.record))

-- Yazi
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd(Programs.terminal .. " --title yazi -e yazi"))

-- Open Music player
-- hl.bind(mainMod .. "+ M", hl.dsp.exec_cmd(Programs.music))

------------------------------
----     SUMI SHELL    ----
------------------------------
local function sumiShell(name)
	return hl.dsp.global("sumi:" .. name)
end

-- La descripción que reconoce la ayuda de atajos de la shell (Settings → Shell → Interaction → Keyboard
-- shortcuts): Hyprland 0.57 no dice qué atajo global llama un bind de Lua, sólo su descripción lo nombra.
local function sumiDesc(name)
	return { description = "Sumi Shell: " .. name }
end

-- App Launcher
hl.bind(mainMod .. " + SPACE", sumiShell("launcher"), sumiDesc("launcher"))

-- Wallpaper
hl.bind(mainMod .. " + W", sumiShell("wallpaper"), sumiDesc("wallpaper"))

-- Wallhaven: buscar y descargar
hl.bind(mainMod .. " + CTRL + W", sumiShell("wallhaven"), sumiDesc("wallhaven"))

-- Random Wallpaper
hl.bind(mainMod .. " + CTRL + R", sumiShell("wallRandom"), sumiDesc("wallRandom"))

-- Shell settings
hl.bind(mainMod .. " + CTRL + S", sumiShell("settings"), sumiDesc("settings"))

-- System Dashboard
hl.bind(mainMod .. " + Y", sumiShell("system"), sumiDesc("system"))

-- System Monitor: la UI de inspección flotante
hl.bind(mainMod .. " + CTRL + Y", sumiShell("monitor"), sumiDesc("monitor"))

-- Audio mixer
hl.bind(mainMod .. " + A", sumiShell("mixer"), sumiDesc("mixer"))

-- Audio: ajustes y ecualizador
hl.bind(mainMod .. " + SHIFT + A", sumiShell("audio"), sumiDesc("audio"))

-- Web hub
hl.bind(mainMod .. " + SHIFT + SLASH", sumiShell("web"), sumiDesc("web"))

-- Shell (suspend|poweroff|reboot|logout)
hl.bind(mainMod .. " + ESCAPE", sumiShell("power"), sumiDesc("power"))

-- Emergency Shutdown
-- hl.bind("CTRL + ALT + ESCAPE", hl.dsp.exec_cmd("systemctl poweroff"))

-- History clipboard
hl.bind(mainMod .. " + V", sumiShell("clipboard"), sumiDesc("clipboard"))

-- Emoji clipboard
hl.bind(mainMod .. " + PERIOD", sumiShell("emoji"), sumiDesc("emoji"))

-- Wifi
hl.bind(mainMod .. " + N", sumiShell("wifi"), sumiDesc("wifi"))

-- Centro de control
hl.bind(mainMod .. " + CTRL + N", sumiShell("controlCenter"), sumiDesc("controlCenter"))

-- Bluetooth
hl.bind(mainMod .. " + CTRL + B", sumiShell("bluetooth"), sumiDesc("bluetooth"))

-- Calendar
hl.bind(mainMod .. " + C", sumiShell("calendar"), sumiDesc("calendar"))

-- Calendar UI
hl.bind(mainMod .. " + CTRL + C", sumiShell("calendarUi"), sumiDesc("calendarUi"))

-- Login screen (Sumi SDDM): la ventana de la pantalla de inicio de sesión
hl.bind(mainMod .. " + CTRL + L", sumiShell("loginScreen"), sumiDesc("loginScreen"))

-- Screen Recorder
hl.bind(mainMod .. " + R", sumiShell("recorder"), sumiDesc("recorder"))

-- Dashboard
hl.bind(mainMod .. " + CTRL + D", sumiShell("dashboard"), sumiDesc("dashboard"))

-- Tasks (floating window: maintenance jobs)
hl.bind(mainMod .. " + CTRL + T", sumiShell("tasks"), sumiDesc("tasks"))

-- Window Minimizer
hl.bind(" ALT + TAB", sumiShell("minimizer"), sumiDesc("minimizer"))

-- Systemd User
hl.bind(mainMod .. " + U", sumiShell("services"), sumiDesc("services"))

-- Theme Selector
hl.bind(mainMod .. " + T", sumiShell("theme"), sumiDesc("theme"))

-- Persistent Bar
hl.bind(mainMod .. " + CTRL + P", sumiShell("barToggle"), sumiDesc("barToggle"))

-- Peek:
hl.bind(mainMod .. " + CTRL + SPACE", sumiShell("peek"), sumiDesc("peek"))

-- Command Palette
hl.bind(mainMod .. " + CTRL + X", sumiShell("cli"), sumiDesc("cli"))

-- Keep Awake
hl.bind(mainMod .. " + CTRL + K", sumiShell("keepAwake"), sumiDesc("keepAwake"))

-- Notification Center
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.global("sumi:notifications"), sumiDesc("notifications"))

-- Keyboard shortcuts (ayuda de la shell)
hl.bind(mainMod .. " + SHIFT + F1", sumiShell("keybinds"), sumiDesc("keybinds"))

------------------------------
----      WINDOWS         ----
------------------------------

-- Close focused window
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

-- Toggle floating mode
hl.bind(mainMod .. " + SHIFT + SPACE", function()
	local win = hl.get_active_window()
	local monitor = hl.get_active_monitor()

	if not win or not monitor then
		return
	end

	if not win.floating then
		local width = monitor.width * 0.58
		local height = monitor.height * 0.58

		hl.dispatch(hl.dsp.window.float({ action = "set" }))
		hl.dispatch(hl.dsp.window.resize({ x = width, y = height }))
		hl.dispatch(hl.dsp.window.center())
	else
		hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
	end
end)

-- Fullscreen mode 1
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = 1 }))

-- Fullscreen mode 0
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = 0 }))

------------------------------
----       SYSTEM         ----
------------------------------

-- Keybind Viewer
hl.bind(mainMod .. "+ F1", hl.dsp.exec_cmd("kitty --title keybinds -e fish -c keybinds"))

-- Update System
hl.bind(mainMod .. "+ F2", hl.dsp.exec_cmd("kitty --title sysupdate -e fish -c sysupdate"))

-- Lock screen
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(Programs.lockscreen))

-- System monitor (btop)
hl.bind("CTRL + SHIFT + ESCAPE", hl.dsp.exec_cmd(Programs.terminal .. " --title btop -e btop"))

-- System monitor (bottom)
hl.bind("SHIFT + ESCAPE", hl.dsp.exec_cmd(Programs.terminal .. " --title bottom -e btm"))

-- Restart shell (works if down).
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("systemctl --user restart sumi-shell.service"))

------------------------------
----   CLIPBOARD / COLOR  ----
------------------------------

-- Color picker
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("hyprpicker -a"))

------------------------------
----     SCREENSHOTS      ----
------------------------------

-- Full monitor
hl.bind(mainMod .. " + F12", hl.dsp.exec_cmd("hyprshot -m output -o ~/Pictures/Screenshots"))

-- Region screenshot with Swappy
hl.bind(mainMod .. " + F11", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | swappy -f -]]))

-- Active window screenshot
hl.bind(mainMod .. " + F10", hl.dsp.exec_cmd("hyprshot -m window -o ~/Pictures/Screenshots"))

------------------------------
----   INFINITE DESKTOP   ----
----      NAVIGATION      ----
------------------------------
-- Navegar entre ventanas.
-- Mosaico o mixto: foco nativo. Solo flotantes: canvas infinito.

hl.bind(mainMod .. " + left", hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/navigate_windows.py left"))
hl.bind(mainMod .. " + right", hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/navigate_windows.py right"))
hl.bind(mainMod .. " + up", hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/navigate_windows.py up"))
hl.bind(mainMod .. " + down", hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/navigate_windows.py down"))

------------------------------
----   INFINITE DESKTOP   ----
----         PAN          ----
------------------------------
-- Mover ventana en mosaico o flotante.
-- El script elige según el estado de la ventana activa.

hl.bind(
	mainMod .. " + SHIFT + left",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/move_window_tiled.py left"),
	{ repeating = true }
)
hl.bind(
	mainMod .. " + SHIFT + right",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/move_window_tiled.py right"),
	{ repeating = true }
)
hl.bind(
	mainMod .. " + SHIFT + up",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/move_window_tiled.py up"),
	{ repeating = true }
)
hl.bind(
	mainMod .. " + SHIFT + down",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/move_window_tiled.py down"),
	{ repeating = true }
)

------------------------------
----      WORKSPACES      ----
------------------------------

-- Volver al escritorio anterior
hl.bind(mainMod .. " + TAB", hl.dsp.focus({ workspace = "previous" }))

for i = 1, 10 do
	local key = i % 10
	-- Switch to workspace
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	-- Move window to workspace
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

------------------------------
----      SCRATCHPAD      ----
------------------------------

-- Toggle scratchpad
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))

-- Move window to scratchpad
hl.bind(mainMod .. " + SHIFT + S", function()
	local win = hl.get_active_window()
	if not win then
		return
	end

	if win.workspace.special then
		-- está en special, regresarla al workspace activo
		hl.dispatch(hl.dsp.window.move({ workspace = "e+0" }))
	else
		-- está en workspace normal, mandarla al special
		hl.dispatch(hl.dsp.window.move({ workspace = "special:magic" }))
	end
end)

------------------------------
----        MEDIA         ----
------------------------------

-- Volume
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 2%+"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"),
	{ locked = true, repeating = true }
)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })

-- Media playback
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

------------------------------
----        MOUSE         ----
------------------------------

-- Move / resize windows
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Workspace scrolling
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

------------------------------
----   LAYOUT SWITCHER    ----
------------------------------

-- Dwindle layout
hl.bind(mainMod .. "+ SHIFT + D", hl.dsp.exec_cmd([[hyprctl eval 'hl.config({ general = { layout = "dwindle" } })']]))

-- Master layout
hl.bind(mainMod .. "+ SHIFT + M", hl.dsp.exec_cmd([[hyprctl eval 'hl.config({ general = { layout = "master" } })']]))

-- Scrolling layout
hl.bind(mainMod .. "+ SHIFT + O", hl.dsp.exec_cmd([[hyprctl eval 'hl.config({ general = { layout = "scrolling" } })']]))

-------------------------------
----   INFINITE DESKTOP    ----
-------------------------------
-- hyprland-infinite-desktop-v2 — requiere los scripts en ~/.config/hypr/infinite_desktop/
-- (chmod +x) y el daemon infinite_desktop_core.py corriendo
-- (autostart configurado aparte)

-- Ciclar workspace — además de los binds numéricos y el scroll del mouse
hl.bind(mainMod .. " + Z", hl.dsp.focus({ workspace = "-1" }))
hl.bind(mainMod .. " + X", hl.dsp.focus({ workspace = "+1" }))
hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.window.move({ workspace = "-1" }))
hl.bind(mainMod .. " + SHIFT + X", hl.dsp.window.move({ workspace = "+1" }))

-- Toggle floating/tiling — todas las ventanas
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/floating_tile_toggle.py"))

-- Mover ventana (alternativa con Alt)
hl.bind(
	mainMod .. " + ALT + left",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/move_window_tiled.py left")
)
hl.bind(
	mainMod .. " + ALT + right",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/move_window_tiled.py right")
)
hl.bind(mainMod .. " + ALT + up", hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/move_window_tiled.py up"))
hl.bind(
	mainMod .. " + ALT + down",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/move_window_tiled.py down")
)

-- Redimensionar mosaico o flotante
hl.bind(
	mainMod .. " + CTRL + left",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/resize_window.py left"),
	{ repeating = true }
)
hl.bind(
	mainMod .. " + CTRL + right",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/resize_window.py right"),
	{ repeating = true }
)
hl.bind(
	mainMod .. " + CTRL + up",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/resize_window.py up"),
	{ repeating = true }
)
hl.bind(
	mainMod .. " + CTRL + down",
	hl.dsp.exec_cmd("python3 " .. hyprDir .. "/infinite_desktop/resize_window.py down"),
	{ repeating = true }
)

------------------------------
----   BINDS PRIVADOS     ----
------------------------------

-- Ver hypr/modules/private.example.lua — no versionado. pcall(): la
-- ausencia de private.lua no debe tumbar ninguno de los binds públicos de
-- arriba, solo deja sin registrar estos extras opcionales.
do
	local ok, private = pcall(require, "modules.private")
	if ok and type(private) == "table" and type(private.binds) == "function" then
		private.binds(mainMod)
	end
end

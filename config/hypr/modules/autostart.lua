--    _____          __                  __                 __
--   /  _  \  __ ___/  |_  ____  _______/  |______ ________/  |_
--  /  /_\  \|  |  \   __\/  _ \/  ___/\   __\__  \\_  __ \   __\
-- /    |    \  |  /|  | (  <_> )___ \  |  |  / __ \|  | \/|  |
-- \____|__  /____/ |__|  \____/____  > |__| (____  /__|   |__|
--         \/                       \/            \/

-- Migrado a systemd (ver ~/.config/systemd/user/*.service): antes este
-- archivo era ~60 líneas de hl.exec_cmd encadenadas a mano con "&&"/"&"
-- dentro de strings Lua para simular orden y backgrounding — sin
-- supervisión (si la barra o hypridle morían, quedaban muertos hasta un
-- SUPER+SHIFT+R o un reinicio) y con logs sueltos por todos lados en
-- $XDG_RUNTIME_DIR.

-- Ahora "systemctl --user start hyprland-session.service" alcanza: ese
-- servicio (BindsTo=/Wants=/After=graphical-session.target) activa el
-- target, y el target trae solo a todo lo que declara
-- WantedBy=graphical-session.target — sumi-shell,
-- hypridle, awww, wallpaper (restaura el último + dispara matugen),
-- cliphist-text/image, udiskie, infinite-desktop, y polkit-agent.
-- Cada uno con su propio Restart= y su journal (`journalctl --user -u
-- <servicio>`), y el orden real lo expresan After=/Requires= en vez de
-- concatenación de comandos.

local hyprDir = require("modules.vars").hyprDir

hl.on("hyprland.start", function()

    -- Entorno 
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XCURSOR_THEME XCURSOR_SIZE GTK_THEME GDK_BACKEND QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME GSK_RENDERER && systemctl --user start hyprland-session.service")

    -- Cursor
   hl.exec_cmd("hyprctl setcursor " .. CursorTheme .. " " .. CursorSize)
    
    --Plugins
    hl.exec_cmd("hyprpm reload -n")

    -- Symlink iconos
    hl.exec_cmd(hyprDir .. "/scripts/link-steam-icons.sh")
    
    -- Privados
    local ok, private = pcall(require, "modules.private")
    if ok and type(private) == "table" and type(private.autostart) == "table" then
        for _, cmd in ipairs(private.autostart) do
            hl.exec_cmd(cmd)
        end
    end
end)

-- Teardown:
hl.on("hyprland.shutdown", function()
    hl.exec_cmd("systemctl --user stop graphical-session.target")
end)

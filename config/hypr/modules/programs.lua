-- __________
-- \______   \_______  ____   ________________    _____   ______
--  |     ___/\_  __ \/  _ \ / ___\_  __ \__  \  /     \ /  ___/
--  |    |     |  | \(  <_> ) /_/  >  | \// __ \|  Y Y  \\___ \
--  |____|     |__|   \____/\___  /|__|  (____  /__|_|  /____  >
--                         /_____/            \/      \/     \/

-- Set programs that you use
Programs = {
    -- Apps 
    terminal       = "kitty",
    fileManager    = "nautilus",
    browser        = "zen-browser",
    lockscreen     = "loginctl lock-session",
    record         = "obs",
    --music        = "spotify" --Placeholder,
    themeToggle    = "bash $HOME/.config/hypr/scripts/matugen_toggle.sh",
    minimaruMenu    = "fish -c 'minimaru menu'",
}

-- Comandos privados
local ok, private = pcall(require, "modules.private")
if ok and type(private) == "table" and type(private.programs) == "table" then
    for key, value in pairs(private.programs) do
        Programs[key] = value
    end
end

hl.env("BROWSER", Programs.browser)
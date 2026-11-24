-- .___                      __   
-- |   | ____ ______  __ ___/  |_ 
-- |   |/    \\____ \|  |  \   __\
-- |   |   |  \  |_> >  |  /|  |  
-- |___|___|  /   __/|____/ |__|  
--          \/|__|                

hl.config({
    input = {
        kb_layout  = "us,es",
        kb_options = "grp:alt_shift_toggle",
        
        follow_mouse = 1,
        
        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification
        
        repeat_rate = 50,
        repeat_delay = 250
    },
})

-- Config por dispositivo
-- Ver https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/
--
-- OJO CON EL NOMBRE: tiene que ser el SLUG que imprime `hyprctl devices`
-- (minúsculas, cada tanda de caracteres no alfanuméricos colapsada a un
-- guión), no el nombre bonito del dispositivo. Un bloque cuyo nombre no
-- empareja NO da error: se ignora en silencio, y para colmo
-- `hyprctl eval` responde "ok" igual, porque valida la llamada y no que
-- el nombre case con algo.

-- Para ver los nombres válidos:  hyprctl devices

-- Examples (replace the names with the slugs `hyprctl devices` prints on
-- your machine, then uncomment):
--
-- hl.device({
--     name          = "your-mouse-slug",
--     sensitivity   = 0,
--     accel_profile = "flat",
-- })
--
-- hl.device({
--     name       = "your-keyboard-slug",
--     kb_layout  = "us,es",
--     kb_options = "grp:alt_shift_toggle",
-- })

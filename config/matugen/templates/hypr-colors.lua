-- Generado por matugen — no editar a mano.
-- El color del borde de las ventanas, PERSISTENTE (paletas estáticas F-d, 2026-11-04): lo lee
-- hypr/modules/decoration.lua con pcall(dofile) al arrancar Hyprland y en cada recarga (medido en 0.57:
-- `hyprctl reload` vuelve a ejecutar los `require` y relee este archivo; lo aplicado en caliente se perdía).
-- El cambio inmediato lo sigue haciendo dynamic-colors.sh (escribir aquí no recarga Hyprland).
-- Mismos colores que matugen/templates/hypr-colors.sh. Estático: hypr/colors.static.lua
return {
  active_border   = { colors = { "rgba({{colors.primary.default.hex_stripped}}cc)", "rgba({{colors.secondary.default.hex_stripped}}99)" }, angle = 45 },
  inactive_border = "rgba({{colors.primary.default.hex_stripped}}0f)",
}

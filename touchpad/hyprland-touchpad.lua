-- Hyprland (Lua config, e.g. Omarchy 4): add to ~/.config/hypr/input.lua (merge into an existing
-- hl.config({ input = { touchpad = { ... } } }) block if you already have one).
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,   -- macOS-style "natural" scroll direction
      tap_and_drag = false,    -- a palm brush right after typing can't start a drag (or move a window with Super)
      -- tap-to-click stays on (Hyprland default); disable_while_typing stays on (default)
    },
  },
})

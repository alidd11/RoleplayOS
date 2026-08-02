# Advanced settings

RoleplayOS persists game-owned preferences in `PlayerProfile.Settings`. `SettingsService` is the only server mutation boundary, and `SettingsValidator` rejects unknown keys and invalid values before marking a profile dirty. Changes are batched into normal autosaves rather than writing a DataStore on every click.

The Settings screen currently controls interface scale, interface motion, high contrast, reduced effects, camera shake permission and gameplay hints. Interface scale combines the player's choice with `GuiService.PreferredTextSize`, and listens for native preference changes. Reduced effects disables decorative particles, trails and beams locally, including effects added later. Original states are held in a weak-key table so destroyed effects do not leak memory. High contrast uses a local `ColorCorrectionEffect`.

RoleplayOS does not replace or imitate Roblox's native menu. Roblox remains authoritative for volume, graphics quality, camera and movement mode, fullscreen, input sensitivity and CoreGui. Future camera shake and hint producers must read `SettingsController:Get()` before displaying their optional effect.

Settings schema changes require a profile migration. Never accept arbitrary setting names or client-defined rendering objects.

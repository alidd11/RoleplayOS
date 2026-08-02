# Interface system

RoleplayOS uses a restrained civic-operations visual language: deep neutral surfaces, one blue interaction accent, clear status colours and Gotham typography. Information hierarchy and legibility take priority over decorative effects.

The experience name is the primary top-left brand. `Framework.Branding.GameName` may override it; an empty value uses `game.Name`. “Powered by RoleplayOS” is a smaller configurable framework mark and must never compete with the game's identity.

The start experience has three stable destinations: Play, Careers and Community. Play owns civilian character creation and selection. Careers keeps every role visible while explaining access requirements. Community presents private-server identity, membership policy and administration capabilities. Controllers supply view models; views never become an authority source.

Interactive screens use `CoreUISafeInsets` and device-safe clipping, Roblox's recommended inset for interfaces that must remain clear of the native top bar, chat, menu controls and device cutouts. RoleplayOS does not replace CoreGui, capture native buttons or imitate Roblox system prompts. Marketplace purchases continue through Roblox's native prompt.

Pressable elements give immediate 100–140 ms scale feedback. Screen and modal entrances use a strong ease-out and remain below 250 ms. Repeated navigation avoids ornamental motion. Future accessibility work must provide reduced-motion behaviour, controller focus order, sufficient contrast, scalable text and safe layouts across phone, tablet, console and desktop.

The Studio profile mode is deliberately explicit and in-memory. It makes unpublished baseplates demonstrable without enabling API access or weakening production persistence.

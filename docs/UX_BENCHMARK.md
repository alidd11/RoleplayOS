# Roleplay UX benchmark

The review considered Emergency Response: Liberty County's department XP and rank unlock model, Greenville's job-led civilian loop, compact Roblox XP HUD examples and Roblox's own accessibility guidance. RoleplayOS should borrow interaction principles, never another game's visual identity or assets.

## Product direction

1. **Progressive disclosure.** Keep the in-world HUD to current role, level, exact XP and one progress bar. Clicking it opens the full public-role catalogue. Large catalogues belong in menus, not permanently on screen.
2. **Progress with meaning.** XP should explain what activity earned it and what the next configured unlock is. Ranks without benefits feel cosmetic; rewards without visible requirements feel arbitrary.
3. **Stable navigation.** Play, Careers, Community and Settings retain their position and vocabulary. Contextual duty, property, vehicle and MDT interfaces open as focused tasks rather than adding more permanent top-level destinations.
4. **State clarity.** Loading, empty, locked, offline, success and failure states need distinct copy and visual treatment. Buttons must show pending state and prevent repeated submission.
5. **One design system.** Shared colour, spacing, typography, radius, stroke, motion and focus tokens should replace repeated values as the interface grows.
6. **Accessible by default.** Native safe insets, preferred text size, reduced motion, non-colour status symbols, gamepad selection and touch targets of at least 44 pixels remain release requirements.
7. **Public and operational separation.** Civilian progression can encourage broad long-term play. Whitelisted duty uses its own rank and qualification rules without leaking public XP UI.

## Delivery priorities

- **Now:** public progression HUD and expandable role catalogue; visible exact XP; public/private/whitelist policy enforced by the server.
- **Next:** central design-token module, reusable cards/buttons/empty states, responsive breakpoints and controller/gamepad focus order.
- **Then:** configured next-unlock presentation, XP gain toast, role mastery history, career comparison and first-session onboarding.
- **Before production:** phone/tablet/console usability testing, localisation expansion tests, colour-contrast review and moderated user testing of character-to-world time.

Reference material: Roblox Creator Hub accessibility and preferred-text-size documentation; ER:LC XP/rank documentation; public Roblox UI discussions and progression examples. Links are maintained in implementation reports rather than treated as runtime dependencies.

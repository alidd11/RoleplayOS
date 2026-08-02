# Controls and input accessibility

`ControlsController` provides an in-game controls reference that follows the player's
last-used input device. VR mode takes precedence while a headset is active. The panel
opens from its persistent launcher or with `F1` / D-pad Down and is responsive to the
safe viewport supplied by `UIOrchestrator`.

## Supported shortcuts

| Action | Keyboard and mouse | Gamepad / VR | Touch |
| --- | --- | --- | --- |
| Move and look | WASD and mouse | Left and right sticks; head movement in VR | Thumbstick and drag |
| Jump | Space | A / Cross | Jump button |
| Interact | E | X / Square | Tap the prompt |
| Sprint | Hold Left Shift | Hold L3 | Hold RUN |
| Phone | P | Y / Triangle | PHONE launcher |
| MDT | M | View / Select | MDT launcher |
| Controls | F1 | D-pad Down | CONTROLS launcher |

Roblox supplies character movement, camera, jump, tool and proximity-prompt input.
RoleplayOS owns the sprint, phone, MDT and controls bindings.

## Accessibility decisions

- Every custom action remains available through a labelled on-screen button.
- The reference uses text as well as colour, high-contrast labels, wrapped copy and a
  scrollable compact layout.
- Open gamepad and VR panels move selection to a visible CLOSE button and restore the
  previous selection on exit.
- Device changes update both the launcher hint and every mapping without a respawn.
- The layout respects Roblox Core UI safe insets and reserves a smaller central panel
  in VR.

## Device testing still required

Before release, verify button glyph names for each supported controller family, VR
panel comfort and scrolling in every target headset, touch controls on small phones,
and focus order across all phone and MDT screens. Platform certification and real
hardware testing cannot be replaced by Studio emulation.

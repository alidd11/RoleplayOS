RoleplayOS rotating avatar dealers

This folder is the publishable asset slot for the six StreetDealer avatars. The
actual avatar model must be created/imported in Roblox Studio because Roblox
avatar appearance data is not stored in this Rojo source tree.

Studio setup:

1. Place six copies of the owner's avatar model in Workspace. Name them Dealer1
   through Dealer6, or set a unique RoleplayOSDealerId attribute on each.
2. Tag each model with RoleplayOSDealerAvatar.
3. Place six anchored Parts (or small Models) at the intended map locations.
   Tag each one RoleplayOSDealerPoint and give them ids DealerPoint1 through
   DealerPoint6 using the RoleplayOSDealerPointId attribute.
4. Keep each avatar's HumanoidRootPart or PrimaryPart available so it can be
   moved safely. Do not put scripts inside the avatar models.
5. The server will assign RoleplayOSVendorId = StreetDealer and add the normal
   RoleplayOSVendor tag. The existing vendor prompt then sells the configured
   cash weapons and applies the normal server-side purchase checks.

Rotation is deterministic and changes every four hours. Dealer1 starts at the
first sorted point, Dealer2 at the second, and so on; each rotation shifts the
assignment by one point, so all six dealers move without overlapping.

The six avatar models and the user's Roblox avatar identity are intentionally
not fabricated in source control. After the models are placed and tagged in the
publishable Studio place, Rojo preserves them as map-authored instances while
this service supplies the runtime movement and vendor wiring.

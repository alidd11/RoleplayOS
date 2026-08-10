# Uniform changing rooms

Service players spawn in their Roblox clothing and select a uniform in the changing room. RoleplayOS does not dress them automatically on team selection.

The development baseplate creates one simple changing-room fixture beside each configured service locker-room spawn. Pressing **E** uses Roblox's native proximity prompt; touch, controller and VR receive their native equivalent. The server checks the player's active duty, department and role before applying the role's configured uniform. A client cannot request another service's clothing.

Production map artwork can replace a generated fixture by placing a `Model` or `BasePart` directly inside `Workspace/RoleplayOSChangingRooms` with the same attributes:

- `ChangingRoomId`: stable unique location ID;
- `DisplayName`: player-facing prompt name;
- `DepartmentId`: configured service;
- `UniformId`: configured uniform allowed at the fixture.

The shirt and trouser template IDs remain in `src/shared/Config/EDIT_HERE/04_Uniforms.luau`. Empty or malformed IDs make the fixture refuse to apply clothing and fail the production release gate. When duty ends, RoleplayOS restores the clothing that player wore before selecting the service uniform.

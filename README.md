# Pets vs Slimes

An original Roblox pet-rolling and slime-combat game built with Luau and Rojo. Players roll for pets, build a team, fight slimes, earn coins, unlock zones, and improve their collection.

## Project highlights

- Server-managed player data, rolls, combat, trading, and purchases.
- Pet inventory with equip and upgrade flows.
- Multiple zones, generated enemy tiers, and progression costs driven by shared configuration.
- Auto-roll, daily rewards, leaderboards, shop, and trading interfaces.
- A generated 3D valley world with a spawn plaza, zone gates, and environmental decoration.
- Rojo project structure that keeps shared configuration, server logic, and client UI separate.

## Run locally

Requirements: Roblox Studio, Rojo 7.7 or compatible, and the Rojo Studio plugin.

From this folder:

```powershell
rojo serve
```

Open a place in Roblox Studio and connect the Rojo plugin to the local server. To build a standalone place file instead:

```powershell
rojo build -o PetsVsSlimes.rbxlx
```

Only run one Rojo server at a time; another game project can otherwise sync into Studio.

## Structure

```text
src/
  client/   Player-facing controls and interface
  server/   World, player data, rolls, combat, trading, and monetization
  shared/   Configuration, pet presentation helpers, and remotes
default.project.json
```

## Playtest status

The current source was built with Rojo and opened in Roblox Studio on November 15, 2026. A local play session loaded the valley and player interface. The Developer Console showed no script errors and no longer showed the invalid music asset ID. One asset warning remains: `rbxassetid://203785492` has an asset type that does not match the requested type. This warning should be traced before presenting the game as a polished release.

The downloaded UI-fix copy was inspected separately and is not part of this source tree. The older published Roblox place file was not used as the source of truth and was not changed. No Roblox experience was published or updated during this verification.

## Portfolio demo checklist

Capture a short Studio or published-game recording that shows:

1. Spawn plaza and world layout.
2. One pet roll and the resulting Backpack entry.
3. Equipping a pet and showing it follow the player.
4. A slime fight, coin reward, and one upgrade or zone interaction.

Record only features that work in the final recording; mention any remaining limitations plainly.


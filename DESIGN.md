# Design Dock

**Status:** v0.3  
**Engine:** Blazium / Godot 4.3  
**Last updated:** 2026-10-18

This file is the source of truth. Change the doc before changing the fantasy in code.  
Concept images live in [`design/`](design/).

---

## 1. Pitch

A **grand-strategy-style** space game on a persistent **map**. You move a **mothership**, click **sites** to open **popups**, and **assign craft quotas**. The mothership runs an **undock sequence**, then launches craft to sites and **replenishes** losses. Mining craft **work the site, then fly home to drop off resources** before returning. Your job is to **balance assignments** and keep **production ahead of combat losses**.

---

## 2. Pillars

| Pillar | Intent |
|--------|--------|
| **Map first** | The strategic map is always the main view. |
| **Site popups** | Click a site → popup anchored at that site. Assignment happens there. |
| **Quota, not micro** | Player sets *how many* craft a site should have; the mothership maintains it. |
| **Undock, then go** | Assigned craft leave via a visible **undocking sequence**, not teleport. |
| **Mine → haul home** | Mining is a cycle: gather at site → return to mothership → drop off → go back. |
| **Auto replenish** | Destroyed or unassigned craft free a quota slot; mothership fills asap if stock allows. |
| **Balance under attrition** | Combat burns craft; economy must feed rebuild + reassignment. |
| **Mothership as avatar** | You move the mothership; it is launch bay, drop-off depot, and build hub. |

---

## 3. Core loop (locked)

```
Move mothership on the map
    → Sites appear / are reachable
    → Click site → popup at site
    → Assign craft quotas
    → Undock sequence → craft transit to site
    → At mining sites: mine → return to mothership → drop off resources → return to site
    → Combat losses (or unassign) → undock replacement asap
    → Rebalance quotas + build so production keeps up with losses
```

![Assignment and replenishment loop](design/design-assignment-loop.jpg)

*Quotas → undock/launch → hold site → loss → auto replacement. Mining adds a haul-home cycle under the same assignment.*

---

## 4. UI model (locked)

| Layer | Role |
|-------|------|
| **Map (always on)** | Mothership, sites, craft undocking / in transit / at sites / hauling home |
| **Site popup** | Opens **at the site’s map location**. Assignment UI lives here. |
| **Other popups** | Hangar / build / inventory — overlays; map stays underneath |
| **HUD** | Minimal chrome (resources, open panels, pause) |

**Not the model:** full-screen tab views that replace the map.

![Map with site popup wireframe](design/design-map-site-popup.jpg)

*Map stays primary; click a site → assignment popup anchored at that location.*

---

## 5. Mothership (locked)

- Player **moves** the mothership on the map.
- Mothership **builds / stores** craft, runs **undock**, and receives **resource drop-offs**.
- When a site is under quota (missing hulls), mothership undocks a replacement **as soon as a craft is available**.
- If hangar is empty, player must **build more**.

---

## 6. Undocking sequence (locked)

When the mothership sends craft to fill a site quota (first fill or replacement):

1. Craft is reserved from hangar / ready pool.  
2. **Undock sequence** plays at the mothership (timed / animated — not instant teleport).  
3. Craft enters **transit** toward the site on the map.  
4. Craft **arrives** and counts toward the site’s on-station numbers.

Undock queues if multiple craft launch; order / pad limits TBD (D8).

---

## 7. Sites (locked)

- Sites **appear on the map** (discovery rules TBD).
- **Click site** → **popup at that site**.
- Player **assigns quotas** (per craft type / role).
- Site work runs under those assignments.

### Assignment & replenishment (locked)

| Rule | Behavior |
|------|----------|
| **Quota** | Desired craft counts for the site |
| **Fill** | Undock → transit until on-station (+ assigned-but-hauling for miners) matches quota |
| **Loss** | Destroyed → slot free → undock replacement asap |
| **Unassign / recall** | Player lowers quota or recalls → extras return; stop sending |
| **Skill** | Spread limited craft; combat quotas cost economy |

Player manages **assignments and production**, not every steering input.

### Mining cycle (locked)

Mining craft assigned to a site follow this loop automatically:

```
At site → mine / load cargo
    → Leave site → transit to mothership
    → Drop off resources at mothership
    → Transit back to the same site
    → Repeat while still assigned
```

| Rule | Behavior |
|------|----------|
| **Still assigned** | Haul-home is **work**, not unassign. Do **not** treat drop-off as “left the roster” for a *new* hull unless quota requires more bodies on-station. |
| **On-station gap** | While a miner is hauling, fewer craft are *at* the site. Player can raise miner quota (e.g. 2+) so one mines while another hauls. |
| **Drop-off** | Resources only bank when cargo is delivered to the **mothership** (not left at the site). |

---

## 8. Economy & attrition (locked direction)

- Mining → mothership stores → build craft / supplies.  
- Combat sites **consume craft** over time.  
- Failure: over-assign combat, starve mining quotas, or empty hangar while quotas stay high.

Deeper industrial chains TBD — haul-home mining is the v1 gather path.

---

## 9. Open decisions

| # | Topic |
|---|--------|
| D1 | Continuous move vs node travel for mothership |
| D2 | Must mothership be in range to undock toward a site / receive drop-off? |
| D3 | Site types and which quotas each uses |
| D4 | Site resolution: abstract on map vs tactical layer |
| D5 | Build UI placement |
| D6 | Transit speed / how visible undock + haul flights are |
| D7 | Game name |
| D8 | Undock capacity (one at a time vs parallel pads) |
| D9 | Miner cargo size / mine duration before forced haul |

---

## 10. Non-goals (for now)

- Full-screen modes that replace the map  
- Instant teleport launch with no undock  
- Mining that banks resources without returning to the mothership  
- Player manually flying every haul as the main skill  

---

## 11. Vertical slice (proposed)

1. Map + movable mothership.  
2. Sites; click → popup at site; set miner quota.  
3. **Undock** → transit to site → mine → **haul to mothership** → drop off → return.  
4. Combat or simulated loss → undock replacement.  
5. Block launch when hangar empty until player builds.

---

*v0.3 — undock sequence; mining haul-home drop-off cycle; quota vs haul clarified.*

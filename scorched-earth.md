# Scorched Earth: Bash Edition

**Author:** Teo Espero  
**Current Revision:** v1.6

A terminal-based artillery game inspired by the classic DOS game **Scorched Earth**, rebuilt in Bash with ANSI terminal rendering, destructible terrain, projectile physics, MIRV weapons, and a CPU opponent that is smart enough to be competitive without being unfair.

If you are old enough to remember *Scorched Earth*, you already know the basic idea: choose an angle, choose the power, fire, miss horribly, destroy half the mountain, adjust, and try again.

This version asks a slightly different question:

> What happens when a sysadmin knows Bash and has too much free time?

Apparently, terminal-based artillery warfare.

---

## Features

- Full-screen terminal battlefield
- Automatic terminal dimension detection
- ANSI-based screen positioning and refresh
- Incremental projectile animation for faster rendering
- Mountains, Cityscape, and Random terrain modes
- Destructible terrain and crater damage
- Normal artillery rounds
- MIRV rounds that split into multiple projectiles
- Projectile trails and explosion effects
- Player-vs-CPU gameplay
- CPU trajectory analysis with intentional aiming error
- Limited ammunition for Normal and MIRV weapons
- UTF-8 terrain and projectile symbols
- Replay support

---

## Requirements

The game is designed for a modern Bash terminal environment.

Recommended:

```text
Bash 4+
UTF-8 terminal
ANSI-compatible terminal
GNOME Terminal
Windows Terminal with WSL
Linux terminal inside VS Code
```

The terminal should be reasonably large. The game detects the available terminal dimensions automatically and expands the battlefield to use the available space.

---

## Running the Game

Make the script executable:

```bash
chmod +x ScorchedEarth_Bash_Fullscreen_Fast.sh
```

Run it:

```bash
./ScorchedEarth_Bash_Fullscreen_Fast.sh
```

For the best experience, maximize the terminal before starting a new round.

---

## How Full-Screen Detection Works

The game checks the terminal dimensions using `tput`:

```bash
TERM_COLS=$(tput cols 2>/dev/null || printf '80')
TERM_LINES=$(tput lines 2>/dev/null || printf '35')
```

The battlefield width uses the full terminal width:

```bash
WIDTH=$TERM_COLS
```

A small area at the bottom of the terminal is reserved for status information and player input:

```bash
STATUS_ROWS=9
HEIGHT=$((TERM_LINES - STATUS_ROWS))
```

The ground level then follows the detected battlefield height:

```bash
GROUND_Y=$((HEIGHT - 2))
```

This means the game is no longer limited to the original fixed 80x25 battlefield.

---

## Why ANSI Rendering Is Used

The first Bash version redrew too much of the battlefield during every projectile frame. That worked on a small terminal but became noticeably slow when the game was expanded to fill a large terminal.

The current version uses ANSI escape sequences to move the cursor directly to specific positions on screen.

For example:

```bash
printf '\033[%d;%dH' "$row" "$column"
```

The cursor is hidden during animation:

```bash
ANSI_HIDE_CURSOR=$'\033[?25l'
```

and restored when the program exits:

```bash
ANSI_SHOW_CURSOR=$'\033[?25h'
```

This reduces flicker and makes animation feel more like a real terminal game instead of a scrolling Bash script.

---

## Incremental Screen Refresh

A full-screen battlefield can contain thousands of cells. Rebuilding every character for every animation frame causes Bash to slow down significantly.

The optimized version therefore updates only the parts of the battlefield that actually change during a projectile flight.

Conceptually:

```bash
paint_cell "$drawX" "$drawY" '▲'
paint_cell "$prevX" "$prevY" '.'
restore_cell "$oldX" "$oldY"
```

Instead of repainting the entire terrain for every projectile position, the script updates the projectile, its trail, and the cells that need to be restored.

A complete redraw is mainly needed after events such as:

- Terrain destruction
- Explosions
- Crater creation
- Round initialization
- Major state changes

This is the main performance improvement introduced in **v1.6**.

---

## Terrain System

Terrain is stored as an array where each horizontal position represents the first solid row in that column.

```bash
declare -a TERRAIN
```

Conceptually:

```text
TERRAIN[0] = 17
TERRAIN[1] = 16
TERRAIN[2] = 15
```

The renderer fills the terrain from that row downward using the Unicode dark-shade character:

```bash
TERRAIN_CHAR='▓'
```

The game supports three terrain choices:

```text
Mountains
Cityscape
Random
```

### Mountains

Mountain terrain uses mathematical variation to produce hills, ridges, and valleys.

### Cityscape

City terrain creates building-like columns and street-level areas where players can spawn.

### Random

Random mode chooses one of the available terrain generators automatically.

---

## Projectile Physics

The artillery system calculates horizontal and vertical velocity from the selected angle and power.

The general idea is:

```text
Horizontal velocity = cosine(angle) x power
Vertical velocity   = sine(angle) x power
```

Gravity reduces the vertical velocity over time:

```bash
velocityY=$((velocityY - gravity))
```

Bash does not provide native floating-point arithmetic, so the game uses **fixed-point integer math** for much of the projectile simulation.

Instead of storing something like:

```text
12.75
```

it can represent the value internally as:

```text
12750
```

and divide by the scale when converting it back to screen coordinates.

This avoids repeatedly launching external tools such as `awk` during each animation frame.

---

## Normal Weapon

The Normal weapon fires one artillery projectile.

The player selects:

```text
Angle
Power
```

The projectile follows its ballistic arc until it:

- Hits terrain
- Hits a player
- Leaves the side of the battlefield
- Falls back into the battlefield after traveling above the visible screen

A successful impact damages the terrain and may create a crater.

---

## MIRV Weapon

MIRV begins as one projectile and later splits into several independent projectiles.

The split creates a spread of trajectories, making it useful when the exact enemy location is difficult to reach with a single round.

Conceptually:

```bash
projectiles=(
    left_outer
    left_inner
    center
    right_inner
    right_outer
)
```

Each child projectile receives a slightly different horizontal and vertical velocity.

The result is one missile becoming several bad decisions at once.

---

## Destructible Terrain

Explosions permanently change the battlefield.

A crater lowers the terrain around the impact point. The center receives the greatest damage while neighboring columns receive slightly less.

Conceptually:

```bash
for ((dx=-1; dx<=1; dx++)); do
    damageDepth=$((3 - ${dx#-}))
done
```

Because terrain changes during the game, a hill that protected a player during one turn may disappear after the next explosion.

The CPU also has to reevaluate the battlefield after terrain changes.

---

## The CPU Opponent

Player **A** is the human player.

Player **B** is controlled by the computer.

The CPU is intentionally designed to be **competent but imperfect**.

It examines possible angle-and-power combinations and estimates where those trajectories would land. However, it does not simply choose a mathematically perfect shot every turn.

The AI uses several limitations to make the game fair:

- Searches a limited set of angles and power levels
- Considers several good candidate shots
- Does not always choose the best candidate
- Adds small angle and power errors
- Recalculates after the terrain changes

The goal is for the computer to feel like a reasonably experienced human player rather than an artillery-guidance computer with no sense of mercy.

---

## Ammunition

Each player begins with a limited number of rounds.

```bash
MAX_NORMAL_SHOTS=5
MAX_MIRV_SHOTS=5
```

This prevents endless firing and makes weapon choice matter.

A player may decide to save MIRV rounds for difficult shots instead of using them immediately.

---

## ANSI Cursor Handling

The script uses direct terminal cursor control so graphics can be redrawn in place.

The entire screen can be cleared with:

```bash
printf '\033[2J\033[H'
```

Individual cells can then be updated without causing the terminal to scroll.

The script also installs a trap so the cursor is restored even if the game is interrupted:

```bash
trap 'printf "%s" "$ANSI_SHOW_CURSOR$ANSI_RESET"' EXIT INT TERM
```

This is important because otherwise an interrupted terminal game can leave the shell cursor hidden.

---

## Code Organization

The script is divided into logical sections and includes inline comments explaining how the main systems work.

Major areas include:

```text
ANSI terminal setup
Terminal dimension detection
Terrain generation
Terrain rendering
Player placement
Projectile physics
Normal weapon handling
MIRV handling
Explosion and crater logic
CPU aiming
Turn processing
Winner detection
Replay logic
```

The comments are intended to make the project useful not only as a game, but also as an example of what Bash can do when used well outside its normal system-administration role.

---

## Revision History

### v1.0

Initial Bash conversion from the final PowerShell edition.

### v1.1

Added buffered ANSI rendering and fixed-point projectile physics to reduce flicker and improve animation speed.

### v1.2

Added a CPU-controlled Player B with trajectory-aware aiming.

### v1.3

Reduced CPU accuracy and added human-like aiming error so the computer remains challenging without becoming unfair.

### v1.4

Added author information, revision history, and detailed inline comments explaining the major game systems.

### v1.5

Added automatic terminal-size detection. The battlefield now uses the full terminal width and nearly all available terminal height.

### v1.6

Reworked projectile animation to use incremental ANSI updates. Full-screen terminals no longer redraw every battlefield cell for every projectile frame.

---

## Author

**Teo Espero**

Created as a terminal programming experiment combining Bash scripting, ANSI graphics, projectile physics, retro gaming, and the sort of questionable idea that starts with:

> Can Bash do this?

and ends several hours later with a MIRV flying across a terminal window.

---

## Final Thought

Bash was designed to automate systems.

Nobody said it could not also destroy a few imaginary mountains.

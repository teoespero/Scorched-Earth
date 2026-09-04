#!/usr/bin/env bash
# ==============================================================================
# Scorched Earth: Bash Edition
# Author: Teo Espero
# ==============================================================================
#
# A terminal-based artillery game inspired by the classic DOS game Scorched Earth.
# This Bash version uses ANSI escape sequences for fast screen refresh, Unicode
# terrain, fixed-point projectile physics, destructible terrain, Normal and MIRV
# weapons, and a deliberately imperfect CPU opponent so the player still has a
# fair chance to win.
#
# Recommended environment:
#   - Bash 4+
#   - UTF-8 terminal
#   - ANSI-compatible terminal (GNOME Terminal, Windows Terminal/WSL, etc.)
#   - Terminal size is detected automatically; the battlefield expands to fit
#
# Revision History:
#   v1.0 - Initial Bash conversion from the final PowerShell edition.
#   v1.1 - Added buffered ANSI rendering and fixed-point projectile physics
#          to reduce flicker and improve animation speed.
#   v1.2 - Added a CPU-controlled Player B with trajectory-aware aiming.
#   v1.3 - Reduced CPU accuracy and added human-like aiming error so the
#          computer is challenging without being unfair.
#   v1.4 - Added author information, revision history, and detailed inline
#          comments explaining the major game systems.
#   v1.5 - Added automatic terminal-size detection. The battlefield now uses
#          the full terminal width and nearly all available terminal height.
#   v1.6 - Reworked projectile animation to use incremental ANSI updates.
#          Fullscreen terminals no longer redraw every cell for every frame.
#
# Author: Teo Espero
# ==============================================================================

# Treat accidental references to undefined variables as errors.
set -u

# ANSI renderer: hide the cursor during animation and restore it on exit.
ANSI_RESET=$'\033[0m'
ANSI_HIDE_CURSOR=$'\033[?25l'
ANSI_SHOW_CURSOR=$'\033[?25h'
trap 'printf "%s" "$ANSI_SHOW_CURSOR$ANSI_RESET"' EXIT INT TERM

# Battlefield dimensions are detected from the current terminal.
# We reserve a small number of rows below the battlefield for status/prompts.
# WIDTH and HEIGHT are recalculated before each round, so a larger terminal
# gives you a larger battlefield instead of a fixed 80x25 play area.
WIDTH=80
HEIGHT=25
TERM_COLS=80
TERM_LINES=35
STATUS_ROWS=9
MIN_WIDTH=60
MIN_HEIGHT=18
GROUND_Y=23
MAX_NORMAL_SHOTS=5
MAX_MIRV_SHOTS=5
TERRAIN_CHAR='▓'
OFFSET_X=0
OFFSET_Y=0
TERRAIN_MODE='Mountains'

PLAYER1_NAME='A'
PLAYER2_NAME='B'
PLAYER1_SYMBOL='A'
PLAYER2_SYMBOL='B'
PLAYER1_X=0
PLAYER1_Y=0
PLAYER2_X=0
PLAYER2_Y=0
PLAYER1_NORMAL=$MAX_NORMAL_SHOTS
PLAYER1_MIRV=$MAX_MIRV_SHOTS
PLAYER2_NORMAL=$MAX_NORMAL_SHOTS
PLAYER2_MIRV=$MAX_MIRV_SHOTS

# TERRAIN[x] stores the first solid row for each battlefield column.
declare -a TERRAIN

# Small wrapper around sleep so animation timing can be tuned in one place.
action_sleep() {
  local secs="$1"
  sleep "$secs"
}

# Clear the entire terminal and return the cursor to the home position.
clear_screen() {
  printf '\033[2J\033[H'
}

# Detect the real terminal dimensions and size the battlefield to fit it.
# The game uses the full terminal width. Vertically, STATUS_ROWS are reserved
# for ammo, prompts, and messages so gameplay never scrolls the terminal.
update_screen_offsets() {
  TERM_COLS=$(tput cols 2>/dev/null || printf '80')
  TERM_LINES=$(tput lines 2>/dev/null || printf '35')

  # Fall back to sensible values if a terminal reports something unexpected.
  [[ "$TERM_COLS" =~ ^[0-9]+$ ]] || TERM_COLS=80
  [[ "$TERM_LINES" =~ ^[0-9]+$ ]] || TERM_LINES=35

  WIDTH=$TERM_COLS
  HEIGHT=$((TERM_LINES - STATUS_ROWS))

  # Very tiny terminals do not leave enough room for playable trajectories.
  # We keep safe minimum logical dimensions; the terminal should be enlarged
  # if it is smaller than these values.
  (( WIDTH < MIN_WIDTH )) && WIDTH=$MIN_WIDTH
  (( HEIGHT < MIN_HEIGHT )) && HEIGHT=$MIN_HEIGHT

  GROUND_Y=$((HEIGHT - 2))

  # Fullscreen mode begins at the top-left instead of centering an 80x25 box.
  OFFSET_X=0
  OFFSET_Y=0
}

# Move the terminal cursor using ANSI coordinates while respecting centering.
safe_set_cursor() {
  local x=$1 y=$2
  local tx=$((x + OFFSET_X))
  local ty=$((y + OFFSET_Y))
  (( tx < 0 || ty < 0 )) && return 0
  printf '\033[%d;%dH' "$((ty + 1))" "$((tx + 1))"
}

# Print a message centered inside the current full-width battlefield area.
write_centered_text() {
  local text="$1" y="$2" no_newline="${3:-0}"
  local cx=$(( (WIDTH - ${#text}) / 2 ))
  (( cx < 0 )) && cx=0
  safe_set_cursor "$cx" "$y"
  if [[ "$no_newline" == "1" ]]; then
    printf '%s' "$text"
  else
    printf '%s\n' "$text"
  fi
}

# Display the animated title/loading screen and a short game overview.
show_splash_screen() {
  clear_screen
  update_screen_offsets
  local title=(
    '============================================================'
    'SCORCHED EARTH'
    'Bash Edition'
    '============================================================'
    ''
    'A  vs  B'
    ''
    'Loading battlefield...'
  )

  local i=0 line
  for line in "${title[@]}"; do
    write_centered_text "$line" "$((2+i))"
    action_sleep 0.12
    ((i++))
  done

  for ((i=0; i<=30; i++)); do
    local filled spaces bar
    filled=$(printf '%*s' "$i" '' | tr ' ' '#')
    spaces=$(printf '%*s' "$((30-i))" '')
    bar="[$filled$spaces]"
    write_centered_text "$bar" 12 1
    action_sleep 0.035
  done

  action_sleep 0.3
  clear_screen
  update_screen_offsets

  write_centered_text '============================================================' 3
  write_centered_text 'SCORCHED EARTH' 4
  write_centered_text 'Bash Edition' 5
  write_centered_text '============================================================' 6
  write_centered_text 'Terrain: Mountains, Cityscape, or Random' 8
  write_centered_text 'Weapons:' 9
  write_centered_text '1 = Normal Shot' 10
  write_centered_text '2 = MIRV Shot' 11
  write_centered_text 'Rules:' 14
  write_centered_text 'A player is hit if inside the 3x3 explosion area.' 15
  write_centered_text 'Direct hit gets a special animated message.' 16
  write_centered_text 'Player hit triggers a second 5x5 explosion.' 17
  write_centered_text 'You vs B (CPU): 5 Normal shots and 5 MIRV shots each.' 18
  write_centered_text 'Terrain can be damaged. Because of course it can.' 20
  write_centered_text '============================================================' 21

  safe_set_cursor $((WIDTH/2 - 10)) 23
  read -r -p 'Press ENTER to start' _
}

# Let the player choose Mountains, Cityscape, or a randomly selected terrain.
select_terrain_mode() {
  clear_screen
  update_screen_offsets
  write_centered_text '============================================================' 4
  write_centered_text 'SELECT TERRAIN' 5
  write_centered_text '============================================================' 6
  write_centered_text '1 = Mountains  - ridges, cliffs, and bad hiking decisions' 8
  write_centered_text '2 = Cityscape  - buildings, streets, and civic consequences' 9
  write_centered_text '3 = Random     - democracy gives way to chaos' 10
  write_centered_text '============================================================' 12
  safe_set_cursor 22 14
  read -r -p 'Choose terrain type: ' choice
  case "$choice" in
    2) TERRAIN_MODE='Cityscape' ;;
    3) (( RANDOM % 2 == 0 )) && TERRAIN_MODE='Mountains' || TERRAIN_MODE='Cityscape' ;;
    *) TERRAIN_MODE='Mountains' ;;
  esac
  clear_screen
  update_screen_offsets
}

# Bash only supports integer arithmetic, so awk handles occasional decimal math.
float_eval() {
  awk "BEGIN { printf \"%.8f\", ($*) }"
}

# Round a floating-point expression to the nearest integer using awk.
float_round() {
  awk "BEGIN { x=($*); if (x>=0) printf \"%d\", int(x+0.5); else printf \"%d\", int(x-0.5) }"
}

# Evaluate a floating-point comparison and return success/failure like a Bash test.
float_cmp() {
  awk "BEGIN { if ($*) exit 0; else exit 1 }"
}

# Build mountain terrain from layered sine waves, random walk, smoothing, and ridges.
generate_mountain_terrain() {
  local -a data smooth
  local phase1=$((RANDOM % 629)) phase2=$((RANDOM % 629)) phase3=$((RANDOM % 629))
  local walk=$((RANDOM % 5 - 2))
  local x
  for ((x=0; x<WIDTH; x++)); do
    walk=$((walk + RANDOM % 3 - 1))
    (( walk > 4 )) && walk=4
    (( walk < -4 )) && walk=-4

    local hv
    hv=$(awk -v x="$x" -v p1="$phase1" -v p2="$phase2" -v p3="$phase3" -v w="$walk" -v H="$HEIGHT" 'BEGIN {
      pi=atan2(0,-1);
      base = H * 0.72;
      scale = H / 25.0; if (scale < 0.75) scale = 0.75;
      v=base + sin((x/7.0)+(p1/100.0))*3.0*scale + sin((x/13.0)+(p2/100.0))*2.0*scale + sin((x/3.5)+(p3/100.0))*1.0*scale + w;
      printf "%.8f", v;
    }')

    if (( (x>15 && x<22) || (x>48 && x<55) )); then
      hv=$(float_eval "$hv - (RANDOM % 3 + 1)")
    fi
    if (( (x>30 && x<38) || (x>60 && x<67) )); then
      hv=$(float_eval "$hv + (RANDOM % 3 + 1)")
    fi
    local min_top=$(( HEIGHT / 4 ))
    (( min_top < 5 )) && min_top=5
    float_cmp "$hv < $min_top" && hv=$min_top
    float_cmp "$hv > $GROUND_Y" && hv=$GROUND_Y
    data[$x]=$(float_round "$hv")
  done

  for ((x=0; x<WIDTH; x++)); do
    local l=${data[$x]} m=${data[$x]} r=${data[$x]}
    (( x>0 )) && l=${data[$((x-1))]}
    (( x<WIDTH-1 )) && r=${data[$((x+1))]}
    smooth[$x]=$(float_round "($l + $m + $r) / 3.0")
  done

  local feature start length shift
  for ((feature=0; feature<8; feature++)); do
    start=$((RANDOM % (WIDTH-15) + 3))
    length=$((RANDOM % 8 + 4))
    shift=$((RANDOM % 7 - 3))
    for ((x=start; x<start+length && x<WIDTH; x++)); do
      smooth[$x]=$(( smooth[$x] + shift ))
      local min_ridge=$(( HEIGHT / 5 ))
      (( min_ridge < 4 )) && min_ridge=4
      (( smooth[$x] < min_ridge )) && smooth[$x]=$min_ridge
      (( smooth[$x] > GROUND_Y )) && smooth[$x]=$GROUND_Y
    done
  done

  for ((x=1; x<WIDTH-1; x++)); do
    if (( RANDOM % 100 < 18 )); then
      smooth[$x]=$(( smooth[$x] + RANDOM % 5 - 2 ))
      local min_ridge=$(( HEIGHT / 5 ))
      (( min_ridge < 4 )) && min_ridge=4
      (( smooth[$x] < min_ridge )) && smooth[$x]=$min_ridge
      (( smooth[$x] > GROUND_Y )) && smooth[$x]=$GROUND_Y
    fi
  done
  TERRAIN=("${smooth[@]}")
}

# Build blocky city terrain with streets and buildings scaled to screen height.
generate_cityscape_terrain() {
  local x xPos=2 streetGap buildingWidth buildingTop top roofWobble alleyX
  local min_top=$((HEIGHT / 5))
  local max_top=$((HEIGHT * 3 / 4))
  local height_span=$((max_top - min_top))
  (( min_top < 4 )) && min_top=4
  (( height_span < 4 )) && height_span=4

  # GROUND_Y replaces the old hard-coded row 23, so streets follow screen size.
  for ((x=0; x<WIDTH; x++)); do TERRAIN[$x]=$GROUND_Y; done

  while (( xPos < WIDTH-4 )); do
    streetGap=$((RANDOM % 4 + 3))
    xPos=$((xPos + streetGap))
    (( xPos >= WIDTH-4 )) && break

    buildingWidth=$((RANDOM % 6 + 4))
    buildingTop=$((RANDOM % height_span + min_top))
    for ((x=xPos; x<xPos+buildingWidth && x<WIDTH-2; x++)); do
      roofWobble=$((RANDOM % 3 - 1))
      top=$((buildingTop + roofWobble))
      (( top < min_top )) && top=$min_top
      (( top > max_top )) && top=$max_top
      TERRAIN[$x]=$top
    done

    if (( RANDOM % 100 < 35 )); then
      local max=$((xPos + buildingWidth))
      (( max > WIDTH-2 )) && max=$((WIDTH-2))
      (( max <= xPos )) && max=$((xPos+1))
      alleyX=$((RANDOM % (max-xPos) + xPos))
      TERRAIN[$alleyX]=$GROUND_Y
    fi
    xPos=$((xPos + buildingWidth))
  done

  # Create generous street-level spawn zones in the left and right quarters.
  local left_end=$((WIDTH / 3))
  local right_start=$((WIDTH * 2 / 3))
  for ((x=3; x<left_end; x++)); do (( RANDOM % 100 < 65 )) && TERRAIN[$x]=$GROUND_Y; done
  for ((x=right_start; x<WIDTH-3; x++)); do (( RANDOM % 100 < 65 )) && TERRAIN[$x]=$GROUND_Y; done

  local p1_start=$((WIDTH / 10)) p1_end=$((WIDTH / 5))
  local p2_start=$((WIDTH * 4 / 5)) p2_end=$((WIDTH * 9 / 10))
  for ((x=p1_start; x<=p1_end; x++)); do TERRAIN[$x]=$GROUND_Y; done
  for ((x=p2_start; x<=p2_end && x<WIDTH; x++)); do TERRAIN[$x]=$GROUND_Y; done
}

# Dispatch terrain generation to the selected terrain algorithm.
generate_terrain() {
  [[ "$TERRAIN_MODE" == 'Cityscape' ]] && generate_cityscape_terrain || generate_mountain_terrain
}

# Flatten a small area around a spawn point so a player is not buried in terrain.
clear_player_area() {
  local center=$1 flat=$2 x
  for ((x=center-2; x<=center+2; x++)); do
    (( x>=0 && x<WIDTH )) && TERRAIN[$x]=$flat
  done
}

# Search a horizontal range for a reasonably flat and playable spawn location.
find_spawn_location() {
  local start=$1 end=$2 attempt candidate l m r x
  for ((attempt=0; attempt<150; attempt++)); do
    candidate=$((RANDOM % (end-start) + start))
    l=${TERRAIN[$((candidate>0 ? candidate-1 : candidate))]}
    m=${TERRAIN[$candidate]}
    r=${TERRAIN[$((candidate<WIDTH-1 ? candidate+1 : candidate))]}
    if [[ "$TERRAIN_MODE" == 'Cityscape' ]]; then
      (( m==GROUND_Y && l==GROUND_Y && r==GROUND_Y )) && { echo "$candidate"; return; }
    else
      local dl=$(( m-l )); (( dl<0 )) && dl=$((-dl))
      local dr=$(( m-r )); (( dr<0 )) && dr=$((-dr))
      (( dl<=4 && dr<=4 )) && { echo "$candidate"; return; }
    fi
  done
  if [[ "$TERRAIN_MODE" == 'Cityscape' ]]; then
    for ((x=start; x<end; x++)); do (( TERRAIN[$x]==GROUND_Y )) && { echo "$x"; return; }; done
  fi
  echo "$start"
}

# Recalculate player Y positions after terrain generation or crater damage.
update_player_heights() {
  (( PLAYER1_X >= 0 )) && PLAYER1_Y=$(( TERRAIN[$PLAYER1_X] - 1 ))
  (( PLAYER1_Y < 0 )) && PLAYER1_Y=0
  (( PLAYER2_X >= 0 )) && PLAYER2_Y=$(( TERRAIN[$PLAYER2_X] - 1 ))
  (( PLAYER2_Y < 0 )) && PLAYER2_Y=0
}

# Render the battlefield as one ANSI frame instead of thousands of tiny terminal writes.
# This avoids the major slowdown caused by command substitution for every cell.
draw_game() {
  local projectile_data="${1:-}"
  # Associative arrays provide fast lookup for temporary projectile/trail pixels.
  local -A overlay trail
  local px py pc key

  if [[ -n "$projectile_data" ]]; then
    while IFS='|' read -r px py pc; do
      [[ -z "${px:-}" || -z "${py:-}" ]] && continue
      key="$px,$py"
      if [[ "$pc" == '.' ]]; then
        trail[$key]='.'
      else
        overlay[$key]="$pc"
      fi
    done <<< "$projectile_data"
  fi

  local y x line frame='' ch pad=''
  local start_row=$((OFFSET_Y + 1))
  local start_col=$((OFFSET_X + 1))

  # Move once, then send the entire battlefield in one printf.
  printf -v frame '\033[%d;%dH' "$start_row" "$start_col"
  (( OFFSET_X > 0 )) && printf -v pad '%*s' "$OFFSET_X" ''

  for ((y=0; y<HEIGHT; y++)); do
    line=''
    for ((x=0; x<WIDTH; x++)); do
      key="$x,$y"
      if [[ -n "${overlay[$key]+x}" ]]; then
        ch="${overlay[$key]}"
      elif [[ -n "${trail[$key]+x}" ]]; then
        ch='.'
      elif (( x==PLAYER1_X && y==PLAYER1_Y )); then
        ch="$PLAYER1_SYMBOL"
      elif (( x==PLAYER2_X && y==PLAYER2_Y )); then
        ch="$PLAYER2_SYMBOL"
      elif (( y >= TERRAIN[$x] )); then
        ch="$TERRAIN_CHAR"
      else
        ch=' '
      fi
      line+="$ch"
    done

    frame+="$line"
    if (( y < HEIGHT-1 )); then
      # CR+LF, then restore the battlefield's left margin.
      frame+=$'\r\n'
      frame+="$pad"
    fi
  done

  printf '%s%s' "$ANSI_HIDE_CURSOR" "$frame"
}

clear_status_area() {
  local line
  for ((line=HEIGHT+1; line<=HEIGHT+8; line++)); do
    safe_set_cursor 0 "$line"
    printf '%*s' "$WIDTH" ''
  done
}

# Return the permanent battlefield character at one coordinate. This is used
# by the incremental ANSI animation when an old projectile/trail pixel needs
# to be erased without redrawing the entire fullscreen battlefield.
base_cell_char() {
  local x=$1 y=$2
  if (( x==PLAYER1_X && y==PLAYER1_Y )); then
    printf '%s' "$PLAYER1_SYMBOL"
  elif (( x==PLAYER2_X && y==PLAYER2_Y )); then
    printf '%s' "$PLAYER2_SYMBOL"
  elif (( x>=0 && x<WIDTH && y>=0 && y<HEIGHT && y>=TERRAIN[$x] )); then
    printf '%s' "$TERRAIN_CHAR"
  else
    printf ' '
  fi
}

# Restore one screen cell to its normal terrain/player/background character.
# Only a single ANSI cursor move and character write is required.
restore_cell() {
  local x=$1 y=$2
  (( x<0 || x>=WIDTH || y<0 || y>=HEIGHT )) && return 0
  safe_set_cursor "$x" "$y"
  base_cell_char "$x" "$y"
}

# Draw one temporary animation character without rebuilding the whole screen.
paint_cell() {
  local x=$1 y=$2 ch=$3
  (( x<0 || x>=WIDTH || y<0 || y>=HEIGHT )) && return 0
  safe_set_cursor "$x" "$y"
  printf '%s' "$ch"
}

# Return success when the target lies inside the 3x3 explosion hit box.
test_explosion_hit() {
  local cx=$1 cy=$2 tx=$3 ty=$4
  local dx=$((tx - cx))
  local dy=$((ty - cy))
  (( dx<0 )) && dx=$((-dx)); (( dy<0 )) && dy=$((-dy))
  (( dx<=1 && dy<=1 ))
}

# Draw a short expanding explosion animation centered on the impact point.
show_explosion() {
  local X=$1 Y=$2
  local frames=(
    '0,0'
    '0,-1;-1,0;0,0;1,0;0,1'
    '-1,-1;0,-1;1,-1;-1,0;0,0;1,0;-1,1;0,1;1,1'
  )
  local frame cell dx dy xx yy
  for frame in "${frames[@]}"; do
    draw_game
    IFS=';' read -ra cells <<< "$frame"
    for cell in "${cells[@]}"; do
      IFS=',' read -r dx dy <<< "$cell"
      xx=$((X+dx)); yy=$((Y+dy))
      if (( xx>=0 && xx<WIDTH && yy>=0 && yy<HEIGHT )); then safe_set_cursor "$xx" "$yy"; printf '*'; fi
    done
    action_sleep 0.07
  done
  draw_game
}

# A confirmed player hit triggers a larger 5x5 secondary explosion animation.
show_secondary_explosion() {
  local X=$1 Y=$2 frame dx dy xx yy
  action_sleep 1
  for ((frame=0; frame<3; frame++)); do
    draw_game
    for ((dx=-2; dx<=2; dx++)); do
      for ((dy=-2; dy<=2; dy++)); do
        if (( dx*dx + dy*dy <= 4 )); then
          xx=$((X+dx)); yy=$((Y+dy))
          if (( xx>=0 && xx<WIDTH && yy>=0 && yy<HEIGHT )); then safe_set_cursor "$xx" "$yy"; printf '*'; fi
        fi
      done
    done
    action_sleep 0.12
  done
  draw_game
}

# Flash a special message when the projectile lands directly on the target.
show_direct_hit_message() {
  local shooter=$1 target=$2 msg=">>> DIRECT HIT! $shooter nailed $target! <<<" i
  for ((i=0; i<3; i++)); do
    safe_set_cursor 0 $((HEIGHT+5)); printf '%*s' "$WIDTH" ''
    write_centered_text "$msg" $((HEIGHT+5))
    action_sleep 0.18
    safe_set_cursor 0 $((HEIGHT+5)); printf '%*s' "$WIDTH" ''
    action_sleep 0.12
  done
  write_centered_text "$msg" $((HEIGHT+5))
}

# Carve a three-column crater by pushing terrain downward near the impact point.
damage_terrain() {
  local centerX=$1 centerY=$2 dx x depth damage
  for ((dx=-1; dx<=1; dx++)); do
    x=$((centerX+dx))
    (( x<0 || x>=WIDTH )) && continue
    depth=$((3 - (dx<0 ? -dx : dx)))
    for ((damage=0; damage<depth; damage++)); do
      (( TERRAIN[$x] < HEIGHT-1 )) && TERRAIN[$x]=$((TERRAIN[$x]+1))
    done
  done
  update_player_heights
  draw_game
}

# Coordinate hit effects, crater damage, and removal of the defeated player.
handle_player_hit() {
  local shooter=$1 target=$2 impactX=$3 impactY=$4 direct=$5 prefix=${6:-BOOM}
  show_explosion "$impactX" "$impactY"
  if [[ "$direct" == '1' ]]; then show_direct_hit_message "$shooter" "$target"; else write_centered_text "$prefix! $shooter hit $target!" $((HEIGHT+5)); fi

  local tx ty
  if [[ "$target" == "$PLAYER1_NAME" ]]; then tx=$PLAYER1_X; ty=$PLAYER1_Y; else tx=$PLAYER2_X; ty=$PLAYER2_Y; fi
  show_secondary_explosion "$tx" "$ty"
  damage_terrain "$tx" "$ty"

  if [[ "$target" == "$PLAYER1_NAME" ]]; then PLAYER1_X=-999; PLAYER1_Y=-999; PLAYER1_SYMBOL=' '; else PLAYER2_X=-999; PLAYER2_Y=-999; PLAYER2_SYMBOL=' '; fi
  draw_game
  action_sleep 0.25
  return 0
}

# Show a simple ANSI fireworks animation after a player wins the round.
show_winner_animation() {
  local winner=$1 banner="*** $winner WINS THE BATTLEFIELD! ***" cycle burst cell bx by dx dy xx yy
  local bursts=("$((WIDTH/4)),$((HEIGHT/5))" "$((WIDTH/2)),$((HEIGHT/7))" "$((WIDTH*3/4)),$((HEIGHT/4))")
  local pattern=('0,0' '-1,0' '1,0' '0,-1' '0,1' '-1,-1' '1,-1' '-1,1' '1,1')
  for ((cycle=0; cycle<4; cycle++)); do
    draw_game
    write_centered_text "$banner" $((HEIGHT+2))
    for burst in "${bursts[@]}"; do
      IFS=',' read -r bx by <<< "$burst"
      for cell in "${pattern[@]}"; do
        IFS=',' read -r dx dy <<< "$cell"
        xx=$((bx+dx)); yy=$((by+dy))
        if (( xx>=0 && xx<WIDTH && yy>=0 && yy<HEIGHT )); then safe_set_cursor "$xx" "$yy"; printf '*'; fi
      done
    done
    action_sleep 0.22
    draw_game
    action_sleep 0.12
  done
  draw_game
  write_centered_text "$banner" $((HEIGHT+2))
}

# Simulate a single artillery projectile using fixed-point integer physics.
fire_normal_shot() {
  local shooter=$1 target=$2 angle=$3 power=$4
  local sx sy tx ty
  if [[ "$shooter" == "$PLAYER1_NAME" ]]; then
    sx=$PLAYER1_X; sy=$PLAYER1_Y; tx=$PLAYER2_X; ty=$PLAYER2_Y
  else
    sx=$PLAYER2_X; sy=$PLAYER2_Y; tx=$PLAYER1_X; ty=$PLAYER1_Y
  fi

  # Fixed-point physics (x1000). Only the initial sin/cos uses awk;
  # every animation frame after that is pure Bash integer arithmetic.
  local x_fp y_fp vx_fp vy_fp
  read -r vx_fp vy_fp < <(awk -v a="$angle" -v p="$power" 'BEGIN {
    pi=atan2(0,-1); r=a*pi/180.0;
    printf "%d %d\n", cos(r)*(p/1.5)*1000, sin(r)*(p/1.5)*1000
  }')
  (( sx > tx )) && vx_fp=$((-vx_fp))
  x_fp=$((sx * 1000)); y_fp=$((sy * 1000))

  local gravity_fp=280 timestep_fp=350 drawX drawY direct
  local prevX=-999 prevY=-999 old oldX oldY
  local -a trail_cells=()

  # Advance the shell frame by frame until it hits terrain, a player, or leaves the side.
  while :; do
    if (( x_fp >= 0 )); then drawX=$(((x_fp + 500) / 1000)); else drawX=$(((x_fp - 500) / 1000)); fi
    if (( y_fp >= 0 )); then drawY=$(((y_fp + 500) / 1000)); else drawY=$(((y_fp - 500) / 1000)); fi

    if (( drawX<0 || drawX>=WIDTH )); then
      draw_game
      write_centered_text "$shooter missed off the side." $((HEIGHT+5))
      action_sleep 0.15
      return 1
    fi

    direct=0
    (( drawX==tx && drawY==ty )) && direct=1

    if (( drawY>=0 )) && test_explosion_hit "$drawX" "$drawY" "$tx" "$ty"; then
      handle_player_hit "$shooter" "$target" "$drawX" "$drawY" "$direct"
      return 0
    fi

    if (( drawY>=0 && drawY>=TERRAIN[$drawX] )); then
      show_explosion "$drawX" "$drawY"
      if test_explosion_hit "$drawX" "$drawY" "$tx" "$ty"; then
        handle_player_hit "$shooter" "$target" "$drawX" "$drawY" "$direct"
        return 0
      fi
      damage_terrain "$drawX" "$drawY"
      write_centered_text "$shooter damaged the terrain." $((HEIGHT+5))
      action_sleep 0.15
      return 1
    fi

    # Incremental ANSI animation: turn the previous projectile position into
    # a trail dot, erase only the oldest dot, then draw the new projectile.
    # This avoids WIDTH x HEIGHT Bash work on every animation frame.
    if (( prevX>=0 && prevX<WIDTH && prevY>=0 && prevY<HEIGHT )); then
      paint_cell "$prevX" "$prevY" '.'
      trail_cells+=("$prevX,$prevY")
      if (( ${#trail_cells[@]} > 18 )); then
        old=${trail_cells[0]}
        trail_cells=("${trail_cells[@]:1}")
        IFS=',' read -r oldX oldY <<< "$old"
        restore_cell "$oldX" "$oldY"
      fi
    fi
    if (( drawY>=0 && drawY<HEIGHT )); then
      paint_cell "$drawX" "$drawY" '▲'
    fi
    prevX=$drawX
    prevY=$drawY

    x_fp=$(( x_fp + (vx_fp * timestep_fp / 1000) ))
    y_fp=$(( y_fp - (vy_fp * timestep_fp / 1000) ))
    vy_fp=$(( vy_fp - gravity_fp ))
    action_sleep 0.02
  done
}

# Launch a MIRV projectile that splits into five independently simulated warheads.
fire_mirv_shot() {
  local shooter=$1 target=$2 angle=$3 power=$4
  local sx sy tx ty
  if [[ "$shooter" == "$PLAYER1_NAME" ]]; then
    sx=$PLAYER1_X; sy=$PLAYER1_Y; tx=$PLAYER2_X; ty=$PLAYER2_Y
  else
    sx=$PLAYER2_X; sy=$PLAYER2_Y; tx=$PLAYER1_X; ty=$PLAYER1_Y
  fi

  local x_fp y_fp vx_fp vy_fp
  read -r vx_fp vy_fp < <(awk -v a="$angle" -v p="$power" 'BEGIN {
    pi=atan2(0,-1); r=a*pi/180.0;
    printf "%d %d\n", cos(r)*(p/1.8)*1000, sin(r)*(p/1.8)*1000
  }')
  (( sx > tx )) && vx_fp=$((-vx_fp))
  x_fp=$((sx * 1000)); y_fp=$((sy * 1000))

  local gravity_fp=280 timestep_fp=300 splitFrame=12 frame=0 drawX drawY direct
  local prevX=-999 prevY=-999 old oldX oldY
  local -a trail_cells=()

  # Fly the parent MIRV for a few frames before splitting into five child projectiles.
  while (( frame < splitFrame )); do
    if (( x_fp >= 0 )); then drawX=$(((x_fp + 500) / 1000)); else drawX=$(((x_fp - 500) / 1000)); fi
    if (( y_fp >= 0 )); then drawY=$(((y_fp + 500) / 1000)); else drawY=$(((y_fp - 500) / 1000)); fi

    if (( drawX<0 || drawX>=WIDTH )); then
      draw_game
      write_centered_text "$shooter's MIRV went out of bounds on the side." $((HEIGHT+5))
      action_sleep 0.15
      return 1
    fi

    direct=0
    (( drawX==tx && drawY==ty )) && direct=1
    if (( drawY>=0 )) && test_explosion_hit "$drawX" "$drawY" "$tx" "$ty"; then
      handle_player_hit "$shooter" "$target" "$drawX" "$drawY" "$direct" 'MIRV BOOM'
      return 0
    fi

    if (( drawY>=0 && drawY>=TERRAIN[$drawX] )); then
      show_explosion "$drawX" "$drawY"
      if test_explosion_hit "$drawX" "$drawY" "$tx" "$ty"; then
        handle_player_hit "$shooter" "$target" "$drawX" "$drawY" "$direct" 'MIRV BOOM'
        return 0
      fi
      damage_terrain "$drawX" "$drawY"
      write_centered_text "$shooter's MIRV hit terrain before splitting." $((HEIGHT+5))
      action_sleep 0.15
      return 1
    fi

    # Animate the MIRV parent incrementally instead of redrawing the complete
    # fullscreen battlefield for every frame.
    if (( prevX>=0 && prevX<WIDTH && prevY>=0 && prevY<HEIGHT )); then
      paint_cell "$prevX" "$prevY" '.'
      trail_cells+=("$prevX,$prevY")
      if (( ${#trail_cells[@]} > 18 )); then
        old=${trail_cells[0]}
        trail_cells=("${trail_cells[@]:1}")
        IFS=',' read -r oldX oldY <<< "$old"
        restore_cell "$oldX" "$oldY"
      fi
    fi
    if (( drawY>=0 && drawY<HEIGHT )); then
      paint_cell "$drawX" "$drawY" '▲'
    fi
    prevX=$drawX
    prevY=$drawY

    x_fp=$(( x_fp + (vx_fp * timestep_fp / 1000) ))
    y_fp=$(( y_fp - (vy_fp * timestep_fp / 1000) ))
    vy_fp=$(( vy_fp - gravity_fp ))
    ((frame++))
    action_sleep 0.02
  done

  local direction=1
  (( sx > tx )) && direction=-1
  local -a PX PY PVX PVY ACTIVE PTRAIL PCOUNT LASTX LASTY
  local -a offsets=(-4000 -2000 0 2000 4000)
  local -a boosts=(1500 1000 500 1000 1500)
  local i

  for ((i=0; i<5; i++)); do
    PX[$i]=$x_fp; PY[$i]=$y_fp
    PVX[$i]=$(( vx_fp + offsets[$i] * direction ))
    PVY[$i]=$(( vy_fp + boosts[$i] ))
    ACTIVE[$i]=1; PTRAIL[$i]=''; PCOUNT[$i]=0; LASTX[$i]=-999; LASTY[$i]=-999
  done

  while :; do
    local active_count=0
    for ((i=0; i<5; i++)); do
      (( ACTIVE[$i] == 1 )) || continue
      ((active_count++))

      if (( PX[$i] >= 0 )); then drawX=$(((PX[$i] + 500) / 1000)); else drawX=$(((PX[$i] - 500) / 1000)); fi
      if (( PY[$i] >= 0 )); then drawY=$(((PY[$i] + 500) / 1000)); else drawY=$(((PY[$i] - 500) / 1000)); fi

      if (( drawX<0 || drawX>=WIDTH )); then
        restore_cell "${LASTX[$i]}" "${LASTY[$i]}"
        ACTIVE[$i]=0
        continue
      fi
      direct=0
      (( drawX==tx && drawY==ty )) && direct=1

      if (( drawY>=0 )) && test_explosion_hit "$drawX" "$drawY" "$tx" "$ty"; then
        handle_player_hit "$shooter" "$target" "$drawX" "$drawY" "$direct" 'MIRV BOOM'
        return 0
      fi

      if (( drawY>=0 && drawY>=TERRAIN[$drawX] )); then
        show_explosion "$drawX" "$drawY"
        if test_explosion_hit "$drawX" "$drawY" "$tx" "$ty"; then
          handle_player_hit "$shooter" "$target" "$drawX" "$drawY" "$direct" 'MIRV BOOM'
          return 0
        fi
        damage_terrain "$drawX" "$drawY"
        ACTIVE[$i]=0
        continue
      fi

      # Each child warhead updates only its own old/new screen cells. Keep a
      # short queue of trail coordinates so old dots can be restored cleanly.
      if (( LASTX[$i]>=0 && LASTX[$i]<WIDTH && LASTY[$i]>=0 && LASTY[$i]<HEIGHT )); then
        paint_cell "${LASTX[$i]}" "${LASTY[$i]}" '.'
        PTRAIL[$i]+="${LASTX[$i]},${LASTY[$i]};"
        PCOUNT[$i]=$((PCOUNT[$i] + 1))
        if (( PCOUNT[$i] > 14 )); then
          local oldest=${PTRAIL[$i]%%;*}
          PTRAIL[$i]=${PTRAIL[$i]#*;}
          IFS=',' read -r oldX oldY <<< "$oldest"
          restore_cell "$oldX" "$oldY"
          PCOUNT[$i]=14
        fi
      fi
      if (( drawY>=0 && drawY<HEIGHT )); then
        paint_cell "$drawX" "$drawY" '▲'
      fi
      LASTX[$i]=$drawX
      LASTY[$i]=$drawY
    done

    (( active_count == 0 )) && break

    for ((i=0; i<5; i++)); do
      (( ACTIVE[$i] == 1 )) || continue
      PX[$i]=$(( PX[$i] + (PVX[$i] * timestep_fp / 1000) ))
      PY[$i]=$(( PY[$i] - (PVY[$i] * timestep_fp / 1000) ))
      PVY[$i]=$(( PVY[$i] - gravity_fp ))
    done
    action_sleep 0.02
  done

  # Remove any remaining temporary trail/projectile characters in one redraw.
  draw_game
  write_centered_text "$shooter's MIRV finished." $((HEIGHT+5))
  action_sleep 0.15
  return 1
}


# -----------------------------------------------------------------------------
# CPU opponent
# -----------------------------------------------------------------------------
# B is computer-controlled. The AI does not read your angle/power and it does
# not teleport a projectile onto the target. It searches legal shots using the
# same gravity, time step, terrain collision, and MIRV split rules as the game,
# then chooses the shot whose predicted impact comes closest to Player A.
#
# Because the search runs inside one awk process, it is much faster than doing
# hundreds of candidate simulations in Bash.
# Search a limited set of reasonable shots, then intentionally add human-like error.
# The CPU is meant to be competitive, not perfect.
ai_choose_shot() {
  local terrain_csv angle power weapon
  local IFS=,
  terrain_csv="${TERRAIN[*]}"

  # "Fair" CPU: it understands trajectories and terrain, but it is intentionally
  # imperfect. It searches a coarser set of shots, keeps several good choices,
  # then adds a small human-like aiming error. This gives the player a chance.
  read -r weapon angle power < <(
    awk \
      -v terrain="$terrain_csv" \
      -v sx="$PLAYER2_X" -v sy="$PLAYER2_Y" \
      -v tx="$PLAYER1_X" -v ty="$PLAYER1_Y" \
      -v W="$WIDTH" -v H="$HEIGHT" \
      -v normal_ammo="$PLAYER2_NORMAL" -v mirv_ammo="$PLAYER2_MIRV" '
    BEGIN {
      srand()
      n = split(terrain, T, ",")
      pi = atan2(0, -1)
      gravity = 280
      TOP = 8
      count = 0

      # Coarser search than the "expert" CPU. It knows what a sensible shot
      # looks like, but does not solve every possible angle/power combination.
      for (a = 14; a <= 82; a += 4) {
        for (p = 20; p <= 100; p += 5) {
          if (normal_ammo > 0) {
            score = normal_score(a, p)
            remember(1, a, p, score)
          }
          if (mirv_ammo > 0) {
            score = mirv_score(a, p) + 1.25
            remember(2, a, p, score)
          }
        }
      }

      if (count == 0) {
        printf "1 45 55\n"
        exit
      }

      # Pick from the best few shots rather than always choosing the mathematically
      # best answer. Better candidates are more likely, but not guaranteed.
      r = rand()
      if      (r < 0.32) pick = 1
      else if (r < 0.57) pick = min(2, count)
      else if (r < 0.76) pick = min(3, count)
      else if (r < 0.89) pick = min(4, count)
      else               pick = 1 + int(rand() * min(6, count))

      bestWeapon = BW[pick]
      bestAngle  = BA[pick]
      bestPower  = BP[pick]
      bestScore  = BS[pick]

      # Human-like error. Close solutions get modest error; difficult shots get
      # more. Even a perfect computed shot is not guaranteed to be a direct hit.
      if (bestScore <= 1.0) {
        angleErr = int(rand() * 5) - 2       # -2..+2 degrees
        powerErr = int(rand() * 7) - 3       # -3..+3 power
      } else if (bestScore <= 4.0) {
        angleErr = int(rand() * 7) - 3       # -3..+3
        powerErr = int(rand() * 11) - 5      # -5..+5
      } else {
        angleErr = int(rand() * 9) - 4       # -4..+4
        powerErr = int(rand() * 15) - 7      # -7..+7
      }

      bestAngle += angleErr
      bestPower += powerErr

      if (bestAngle < 8) bestAngle = 8
      if (bestAngle > 86) bestAngle = 86
      if (bestPower < 15) bestPower = 15
      if (bestPower > 100) bestPower = 100

      printf "%d %d %d\n", bestWeapon, bestAngle, bestPower
    }

    function min(a,b) { return a < b ? a : b }
    function abs(v) { return v < 0 ? -v : v }
    function roundi(v) { return v >= 0 ? int(v + 0.5) : int(v - 0.5) }
    function terrain_y(x) { return T[x + 1] + 0 }
    function dist_score(x, y,    dx, dy) {
      dx = abs(x - tx)
      dy = abs(y - ty)
      return dx + (dy * 0.55)
    }

    # Maintain a small sorted list of the best candidates.
    function remember(w, a, p, score,    i,j,pos) {
      pos = count + 1
      for (i = 1; i <= count; i++) {
        if (score < BS[i]) { pos = i; break }
      }
      if (pos > TOP) return
      if (count < TOP) count++
      for (j = count; j > pos; j--) {
        BS[j]=BS[j-1]; BW[j]=BW[j-1]; BA[j]=BA[j-1]; BP[j]=BP[j-1]
      }
      BS[pos]=score; BW[pos]=w; BA[pos]=a; BP[pos]=p
    }

    function normal_score(a, p,    r,vx,vy,x,y,dx,dy,step,lastx,lasty) {
      r = a * pi / 180.0
      vx = cos(r) * (p / 1.5) * 1000.0
      vy = sin(r) * (p / 1.5) * 1000.0
      if (sx > tx) vx = -vx
      x = sx * 1000.0
      y = sy * 1000.0

      for (step = 0; step < 360; step++) {
        dx = roundi(x / 1000.0)
        dy = roundi(y / 1000.0)
        if (dx < 0 || dx >= W) return 999 + abs(dx - tx)
        if (dy >= 0 && abs(dx - tx) <= 1 && abs(dy - ty) <= 1) return 0
        if (dy >= 0 && dy >= terrain_y(dx)) return dist_score(dx, dy)
        lastx = dx; lasty = dy
        x += vx * 350.0 / 1000.0
        y -= vy * 350.0 / 1000.0
        vy -= gravity
      }
      return 999 + dist_score(lastx, lasty)
    }

    function mirv_score(a, p,    r,vx,vy,x,y,dx,dy,f,i,dir,best,px,py,pvx,pvy,step,s) {
      r = a * pi / 180.0
      vx = cos(r) * (p / 1.8) * 1000.0
      vy = sin(r) * (p / 1.8) * 1000.0
      if (sx > tx) vx = -vx
      x = sx * 1000.0
      y = sy * 1000.0

      for (f = 0; f < 12; f++) {
        dx = roundi(x / 1000.0)
        dy = roundi(y / 1000.0)
        if (dx < 0 || dx >= W) return 999
        if (dy >= 0 && abs(dx - tx) <= 1 && abs(dy - ty) <= 1) return 0
        if (dy >= 0 && dy >= terrain_y(dx)) return dist_score(dx, dy) + 5
        x += vx * 300.0 / 1000.0
        y -= vy * 300.0 / 1000.0
        vy -= gravity
      }

      dir = (sx > tx) ? -1 : 1
      OFF[1] = -4000; OFF[2] = -2000; OFF[3] = 0; OFF[4] = 2000; OFF[5] = 4000
      BOOST[1] = 1500; BOOST[2] = 1000; BOOST[3] = 500; BOOST[4] = 1000; BOOST[5] = 1500
      best = 999

      for (i = 1; i <= 5; i++) {
        px = x; py = y
        pvx = vx + OFF[i] * dir
        pvy = vy + BOOST[i]
        s = 999

        for (step = 0; step < 320; step++) {
          dx = roundi(px / 1000.0)
          dy = roundi(py / 1000.0)
          if (dx < 0 || dx >= W) { s = 999; break }
          if (dy >= 0 && abs(dx - tx) <= 1 && abs(dy - ty) <= 1) return 0
          if (dy >= 0 && dy >= terrain_y(dx)) { s = dist_score(dx, dy); break }
          px += pvx * 300.0 / 1000.0
          py -= pvy * 300.0 / 1000.0
          pvy -= gravity
          s = dist_score(dx, dy)
        }
        if (s < best) best = s
      }
      return best
    }
    '
  )

  printf '%s %s %s\n' "$weapon" "$angle" "$power"
}

# Execute Player B's CPU-selected weapon, angle, and power.
fire_ai_shot() {
  local shooter=$1 target=$2 weapon angle power weapon_name

  draw_game
  clear_status_area
  write_centered_text "Ammo: A Normal=$PLAYER1_NORMAL MIRV=$PLAYER1_MIRV | B Normal=$PLAYER2_NORMAL MIRV=$PLAYER2_MIRV" $((HEIGHT+1))
  write_centered_text 'B (CPU) is lining up a shot...' $((HEIGHT+3))
  printf '%s' "$ANSI_HIDE_CURSOR"

  # Ask the AI planner for a deliberately imperfect but plausible shot.
  read -r weapon angle power < <(ai_choose_shot)
  if [[ "$weapon" == '2' ]]; then weapon_name='MIRV'; else weapon_name='Normal'; fi

  write_centered_text "B (CPU): $weapon_name | Angle=$angle | Power=$power" $((HEIGHT+4))
  action_sleep 0.45
  clear_status_area

  if [[ "$weapon" == '2' && $PLAYER2_MIRV -gt 0 ]]; then
    ((PLAYER2_MIRV--))
    fire_mirv_shot "$shooter" "$target" "$angle" "$power"
    return $?
  fi

  if (( PLAYER2_NORMAL > 0 )); then
    ((PLAYER2_NORMAL--))
    fire_normal_shot "$shooter" "$target" "$angle" "$power"
    return $?
  fi

  # Fallback if Normal is empty but MIRV remains.
  ((PLAYER2_MIRV--))
  fire_mirv_shot "$shooter" "$target" "$angle" "$power"
  return $?
}

# Prompt the human player for weapon, angle, and power, then fire the shot.
fire_shot() {
  local shooter=$1 target=$2 weapon angle power
  draw_game; clear_status_area
  write_centered_text "Ammo: A Normal=$PLAYER1_NORMAL MIRV=$PLAYER1_MIRV | B Normal=$PLAYER2_NORMAL MIRV=$PLAYER2_MIRV" $((HEIGHT+1))
  write_centered_text 'Weapon: 1 = Normal | 2 = MIRV' $((HEIGHT+2))
  printf '%s' "$ANSI_SHOW_CURSOR"; safe_set_cursor 22 $((HEIGHT+3)); read -r -p "$shooter choose weapon: " weapon
  safe_set_cursor 22 $((HEIGHT+4)); read -r -p "$shooter Angle (0-90): " angle
  safe_set_cursor 22 $((HEIGHT+5)); read -r -p "$shooter Power (1-100): " power
  clear_status_area

  if [[ "$shooter" == "$PLAYER1_NAME" ]]; then
    if [[ "$weapon" == '2' ]]; then
      (( PLAYER1_MIRV <= 0 )) && { write_centered_text "$shooter has no MIRV shots left." $((HEIGHT+5)); action_sleep 0.7; return 1; }
      ((PLAYER1_MIRV--)); fire_mirv_shot "$shooter" "$target" "$angle" "$power"; return $?
    else
      (( PLAYER1_NORMAL <= 0 )) && { write_centered_text "$shooter has no Normal shots left." $((HEIGHT+5)); action_sleep 0.7; return 1; }
      ((PLAYER1_NORMAL--)); fire_normal_shot "$shooter" "$target" "$angle" "$power"; return $?
    fi
  else
    if [[ "$weapon" == '2' ]]; then
      (( PLAYER2_MIRV <= 0 )) && { write_centered_text "$shooter has no MIRV shots left." $((HEIGHT+5)); action_sleep 0.7; return 1; }
      ((PLAYER2_MIRV--)); fire_mirv_shot "$shooter" "$target" "$angle" "$power"; return $?
    else
      (( PLAYER2_NORMAL <= 0 )) && { write_centered_text "$shooter has no Normal shots left." $((HEIGHT+5)); action_sleep 0.7; return 1; }
      ((PLAYER2_NORMAL--)); fire_normal_shot "$shooter" "$target" "$angle" "$power"; return $?
    fi
  fi
}

# Set up one complete round: terrain, spawns, ammo, turns, AI, and win detection.
start_game() {
  # Re-read the terminal size before every round. Resize the terminal between
  # rounds and the next battlefield will automatically use the new dimensions.
  clear_screen; update_screen_offsets; select_terrain_mode; update_screen_offsets; generate_terrain

  local left_start=$((WIDTH / 16))
  local left_end=$((WIDTH / 3))
  local right_start=$((WIDTH * 2 / 3))
  local right_end=$((WIDTH - WIDTH / 16))
  (( left_start < 3 )) && left_start=3
  (( right_end > WIDTH-3 )) && right_end=$((WIDTH-3))

  PLAYER1_X=$(find_spawn_location "$left_start" "$left_end")
  PLAYER2_X=$(find_spawn_location "$right_start" "$right_end")
  clear_player_area "$PLAYER1_X" "${TERRAIN[$PLAYER1_X]}"
  clear_player_area "$PLAYER2_X" "${TERRAIN[$PLAYER2_X]}"

  if [[ "$TERRAIN_MODE" == 'Mountains' ]]; then
    local ridge ridgeCenter ridgeHeight ridgeWidth offset x dist extra
    for ((ridge=0; ridge<3; ridge++)); do
      local range=$((PLAYER2_X - 8 - (PLAYER1_X + 8)))
      (( range <= 0 )) && break
      ridgeCenter=$((RANDOM % range + PLAYER1_X + 8))
      ridgeHeight=$((RANDOM % 4 + 2))
      ridgeWidth=$((RANDOM % 5 + 3))
      for ((offset=-ridgeWidth; offset<=ridgeWidth; offset++)); do
        x=$((ridgeCenter+offset)); (( x<0 || x>=WIDTH )) && continue
        dist=$offset; (( dist<0 )) && dist=$((-dist))
        extra=$((ridgeHeight-dist)); (( extra<0 )) && extra=0
        TERRAIN[$x]=$((TERRAIN[$x]-extra)); local ridge_floor=$((HEIGHT/5)); (( ridge_floor<4 )) && ridge_floor=4; (( TERRAIN[$x]<ridge_floor )) && TERRAIN[$x]=$ridge_floor
      done
    done
  fi

  PLAYER1_SYMBOL='A'; PLAYER2_SYMBOL='B'
  PLAYER1_NORMAL=$MAX_NORMAL_SHOTS; PLAYER1_MIRV=$MAX_MIRV_SHOTS
  PLAYER2_NORMAL=$MAX_NORMAL_SHOTS; PLAYER2_MIRV=$MAX_MIRV_SHOTS
  update_player_heights

  draw_game
  local current='A' target='B' hit winner='' win_label
  # Alternate turns until someone is hit or every available round is spent.
  while (( PLAYER1_NORMAL>0 || PLAYER1_MIRV>0 || PLAYER2_NORMAL>0 || PLAYER2_MIRV>0 )); do
    if [[ "$current" == 'A' ]]; then
      if (( PLAYER1_NORMAL<=0 && PLAYER1_MIRV<=0 )); then current='B'; target='A'; continue; fi
    else
      if (( PLAYER2_NORMAL<=0 && PLAYER2_MIRV<=0 )); then current='A'; target='B'; continue; fi
    fi

    if [[ "$current" == 'B' ]]; then
      if fire_ai_shot "$current" "$target"; then hit=1; else hit=0; fi
    else
      if fire_shot "$current" "$target"; then hit=1; else hit=0; fi
    fi
    if (( hit==1 )); then
      draw_game; clear_status_area; show_winner_animation "$current"; [[ "$current" == "B" ]] && win_label="B (CPU)" || win_label="$current"; write_centered_text "$win_label WINS!" $((HEIGHT+5)); winner=$current; break
    fi
    if [[ "$current" == 'A' ]]; then current='B'; target='A'; else current='A'; target='B'; fi
  done

  if [[ -z "$winner" ]]; then
    draw_game; clear_status_area
    write_centered_text 'DRAW!' $((HEIGHT+2))
    write_centered_text 'Both players ran out of Normal and MIRV ammunition.' $((HEIGHT+3))
  fi
  safe_set_cursor 0 $((HEIGHT+8))
}

# ------------------------------- MAIN PROGRAM -------------------------------
# Show the splash once, then keep starting new rounds until the player declines.
show_splash_screen
while :; do
  start_game
  printf '%s' "$ANSI_SHOW_CURSOR"
  safe_set_cursor $((WIDTH/2 - 14)) $((HEIGHT+8))
  read -r -p 'Play another round? (Y/N): ' play_again
  [[ "$play_again" =~ ^[Yy]$ ]] || break
done
clear_screen
update_screen_offsets
write_centered_text 'Thanks for playing!' $((HEIGHT/2))
printf '\n'

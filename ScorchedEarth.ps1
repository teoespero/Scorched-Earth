<#
.SYNOPSIS
    Scorched Earth: PowerShell Edition

.AUTHOR
    Teo Espero

.DESCRIPTION
    A two-player artillery game written in PowerShell because apparently PowerShell was not content
    with managing servers, parsing logs, annoying interns, and resetting passwords. It also wanted
    to recreate 1990s DOS artillery warfare in a terminal window.

    Players A and B take turns firing over randomized terrain. Terrain is rendered using Unicode
    dark shade block U+2593 (▓), because extended ASCII behaved like a clerk who misplaced the form.

.FEATURES
    - Terrain mode selection (Mountains / Cityscape / Random)
    - Centered animated splash screen
    - Centered battlefield and status area
    - Unicode terrain blocks
    - Harder terrain generation using waves, random walk, ridges, and smoothing
    - Random player placement
    - Narrow spawn platforms
    - Normal projectile
    - MIRV projectile that splits mid-air
    - Triangle projectile symbols with dotted trails for Normal and MIRV fire
    - Projectile can leave the top of the screen and come back down
    - Side exits count as misses
    - 3x3 explosion hit detection
    - 3-column crater damage
    - 5x5 secondary explosion after player hit
    - Animated DIRECT HIT message
    - Winner animation
    - Replay prompt after win/draw
    - Five Normal shots and five MIRV shots per player

.NOTES
    Recommended hosts:
      - Windows Terminal
      - PowerShell 7+
      - GNOME Terminal on Ubuntu
      - Regular Windows PowerShell console

    Avoid:
      - PowerShell ISE
      - Some VS Code output panes

.REVISION HISTORY
    v0.1 - Basic projectile demo.
    v0.2 - Added visible projectile animation.
    v0.3 - Added cursor drawing.
    v0.4 - Added random player heights.
    v0.5 - Added ammo limits and draw condition.
    v0.6 - Added terrain collapse.
    v0.7 - Added explosion-radius hit detection.
    v0.8 - Added random terrain.
    v0.9 - Added MIRV.
    v1.0 - Added explosion animation.
    v1.1 - Added crater damage.
    v1.2 - Added spawn clear zones.
    v1.3 - Added splash screen and replay.
    v1.4 - Added secondary explosion.
    v1.5 - Switched to Unicode terrain.
    v1.6 - Added harder terrain and randomized placement.
    v1.7 - Added centered battlefield and splash screen.
    v1.8 - Added winner animation.
    v1.9 - Added working terrain selection: Mountains, Cityscape, and Random.
           Cityscape now spawns players outside buildings at street level, because rooftops are for antennas, not infantry.
    v2.0 - Removed Fire and kept the arsenal focused on Normal and MIRV shots.
           Triangle projectiles and dotted trails remain for Normal and MIRV fire.
#>

Clear-Host

# ==========================================================
# GLOBAL SETTINGS
# ==========================================================

$script:width = 80
$script:height = 25
$script:maxShots = 5
$script:maxNormalShots = 5
$script:maxMirvShots = 5
$script:terrainChar = [char]0x2593   # Unicode dark shade block = ▓
$script:offsetX = 0
$script:offsetY = 0
$script:terrainMode = "Mountains"

# ==========================================================
# TERMINAL POSITIONING
# ==========================================================

function Update-ScreenOffsets {
    <#
    .SYNOPSIS
        Centers the game board inside the terminal.

    .DESCRIPTION
        Calculates horizontal and vertical offsets so the battlefield is centered instead of sulking
        in the upper-left corner like an old spreadsheet nobody wants to own.
    #>
    try {
        $windowWidth  = [Console]::WindowWidth
        $windowHeight = [Console]::WindowHeight

        $script:offsetX = [Math]::Max(0, [int](($windowWidth - $script:width) / 2))
        $script:offsetY = [Math]::Max(0, [int](($windowHeight - ($script:height + 10)) / 2))
    }
    catch {
        $script:offsetX = 0
        $script:offsetY = 0
$script:terrainMode = "Mountains"
    }
}

function Safe-SetCursor {
    <#
    .SYNOPSIS
        Safely moves the cursor using the global offsets.
    #>
    param (
        [int]$X,
        [int]$Y
    )

    try {
        $targetX = $X + $script:offsetX
        $targetY = $Y + $script:offsetY

        if (
            $targetX -ge 0 -and
            $targetY -ge 0 -and
            $targetX -lt [Console]::BufferWidth -and
            $targetY -lt [Console]::BufferHeight
        ) {
            [Console]::SetCursorPosition($targetX, $targetY)
        }
    }
    catch {
        # Some hosts do not support cursor positioning. We ignore the tantrum.
    }
}

function Write-CenteredText {
    <#
    .SYNOPSIS
        Writes text centered within the game width.
    #>
    param (
        [string]$Text,
        [int]$Y,
        [switch]$NoNewline
    )

    $centerX = [Math]::Max(0, [int](($script:width - $Text.Length) / 2))
    Safe-SetCursor -X $centerX -Y $Y

    if ($NoNewline) {
        Write-Host $Text -NoNewline
    }
    else {
        Write-Host $Text
    }
}

# ==========================================================
# SPLASH SCREEN
# ==========================================================

function Show-SplashScreen {
    Clear-Host
    Update-ScreenOffsets

    $title = @(
        "============================================================",
        "SCORCHED EARTH",
        "PowerShell Edition",
        "============================================================",
        "",
        "A  vs  B",
        "",
        "Loading battlefield..."
    )

    $lineIndex = 0
    foreach ($line in $title) {
        Write-CenteredText -Text $line -Y (2 + $lineIndex)
        Start-Sleep -Milliseconds 120
        $lineIndex++
    }

    for ($i = 0; $i -le 30; $i++) {
        Write-CenteredText -Text ("[" + ("#" * $i) + (" " * (30 - $i)) + "]") -Y 12 -NoNewline
        Start-Sleep -Milliseconds 35
    }

    Start-Sleep -Milliseconds 300
    Clear-Host
    Update-ScreenOffsets

    Write-CenteredText -Text "============================================================" -Y 3
    Write-CenteredText -Text "SCORCHED EARTH" -Y 4
    Write-CenteredText -Text "PowerShell Edition" -Y 5
    Write-CenteredText -Text "============================================================" -Y 6
    Write-CenteredText -Text "Terrain: Mountains, Cityscape, or Random" -Y 8
    Write-CenteredText -Text "Weapons:" -Y 9
    Write-CenteredText -Text "1 = Normal Shot" -Y 10
    Write-CenteredText -Text "2 = MIRV Shot" -Y 11
    Write-CenteredText -Text "Rules:" -Y 14
    Write-CenteredText -Text "A player is hit if inside the 3x3 explosion area." -Y 15
    Write-CenteredText -Text "Direct hit gets a special animated message." -Y 16
    Write-CenteredText -Text "Player hit triggers a second 5x5 explosion." -Y 17
    Write-CenteredText -Text "Each player has 5 Normal shots and 5 MIRV shots." -Y 18
    Write-CenteredText -Text "Terrain can be damaged. Because of course it can." -Y 20
    Write-CenteredText -Text "============================================================" -Y 21

    Safe-SetCursor -X 24 -Y 23
    Read-Host "Press ENTER to start"
}

<#
CITYSCAPE MODE DESIGN
=====================

If Cityscape mode is selected:
- Buildings generate as destructible vertical blocks.
- Players spawn at STREET LEVEL, not rooftops.
- A and B spawn in open streets between buildings.
- A small clear corridor is preserved around each player so they are not trapped.
- Buildings become artillery cover and can be destroyed.

Example:

███      ██████     █████
███      ██████     █████
███      ██████     █████
███                  ████
A                    B
████    ████████   █████
████    ████████   █████

This makes gameplay more tactical:
- low-angle shots matter
- building destruction creates new paths
- direct line-of-sight becomes difficult
- MIRV becomes useful for clearing cover
#>


function Select-TerrainMode {
    <#
    .SYNOPSIS
        Asks the player what kind of battlefield should be generated.

    .DESCRIPTION
        This is the polite little referendum before the shelling starts. Mountains create cruel
        geology. Cityscape creates destructible buildings and open streets. Random lets fate file
        the paperwork and deny responsibility afterward.
    #>
    Clear-Host
    Update-ScreenOffsets

    Write-CenteredText -Text "============================================================" -Y 4
    Write-CenteredText -Text "SELECT TERRAIN" -Y 5
    Write-CenteredText -Text "============================================================" -Y 6
    Write-CenteredText -Text "1 = Mountains  - ridges, cliffs, and bad hiking decisions" -Y 8
    Write-CenteredText -Text "2 = Cityscape  - buildings, streets, and civic consequences" -Y 9
    Write-CenteredText -Text "3 = Random     - democracy gives way to chaos" -Y 10
    Write-CenteredText -Text "============================================================" -Y 12

    Safe-SetCursor -X 22 -Y 14
    $choice = Read-Host "Choose terrain type"

    switch ($choice) {
        "2" {
            $script:terrainMode = "Cityscape"
        }
        "3" {
            if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
                $script:terrainMode = "Mountains"
            }
            else {
                $script:terrainMode = "Cityscape"
            }
        }
        default {
            $script:terrainMode = "Mountains"
        }
    }

    Clear-Host
    Update-ScreenOffsets
}

# ==========================================================
# MAIN GAME ROUND
# ==========================================================

function Start-ScorchedEarthGame {
    Clear-Host
    Update-ScreenOffsets

    # ------------------------------------------------------
    # TERRAIN GENERATION
    # ------------------------------------------------------

    function Generate-MountainTerrain {
        <#
        .SYNOPSIS
            Generates a hard mountain battlefield.

        .DESCRIPTION
            Uses layered sine waves, random walk, ridges, shelves, cuts, ledges, and small jagged
            insults to produce terrain that refuses to be a polite hill. This is geology with a
            grievance.
        #>
        $terrainData = New-Object int[] $script:width

        $phase1 = Get-Random -Minimum 0 -Maximum 628
        $phase2 = Get-Random -Minimum 0 -Maximum 628
        $phase3 = Get-Random -Minimum 0 -Maximum 628
        $walk = Get-Random -Minimum -2 -Maximum 3

        for ($x = 0; $x -lt $script:width; $x++) {
            $wave1 = [Math]::Sin(($x / 7.0) + ($phase1 / 100.0)) * 3.0
            $wave2 = [Math]::Sin(($x / 13.0) + ($phase2 / 100.0)) * 2.0
            $wave3 = [Math]::Sin(($x / 3.5) + ($phase3 / 100.0)) * 1.0

            $walk += Get-Random -Minimum -1 -Maximum 2
            if ($walk -gt 4) { $walk = 4 }
            if ($walk -lt -4) { $walk = -4 }

            $heightValue = 18 + $wave1 + $wave2 + $wave3 + $walk

            if (($x -gt 15 -and $x -lt 22) -or ($x -gt 48 -and $x -lt 55)) {
                $heightValue -= Get-Random -Minimum 1 -Maximum 4
            }

            if (($x -gt 30 -and $x -lt 38) -or ($x -gt 60 -and $x -lt 67)) {
                $heightValue += Get-Random -Minimum 1 -Maximum 4
            }

            if ($heightValue -lt 8)  { $heightValue = 8 }
            if ($heightValue -gt 23) { $heightValue = 23 }

            $terrainData[$x] = [int][Math]::Round($heightValue)
        }

        $smoothed = New-Object int[] $script:width
        for ($x = 0; $x -lt $script:width; $x++) {
            $left  = if ($x -gt 0) { $terrainData[$x - 1] } else { $terrainData[$x] }
            $mid   = $terrainData[$x]
            $right = if ($x -lt ($script:width - 1)) { $terrainData[$x + 1] } else { $terrainData[$x] }
            $smoothed[$x] = [int][Math]::Round(($left + $mid + $right) / 3.0)
        }

        for ($feature = 0; $feature -lt 8; $feature++) {
            $start = Get-Random -Minimum 3 -Maximum ($script:width - 12)
            $length = Get-Random -Minimum 4 -Maximum 12
            $shift = Get-Random -Minimum -3 -Maximum 4

            for ($x = $start; $x -lt ($start + $length) -and $x -lt $script:width; $x++) {
                $smoothed[$x] += $shift

                if ($smoothed[$x] -lt 6)  { $smoothed[$x] = 6 }
                if ($smoothed[$x] -gt 23) { $smoothed[$x] = 23 }
            }
        }

        for ($x = 1; $x -lt ($script:width - 1); $x++) {
            if ((Get-Random -Minimum 0 -Maximum 100) -lt 18) {
                $smoothed[$x] += Get-Random -Minimum -2 -Maximum 3

                if ($smoothed[$x] -lt 6)  { $smoothed[$x] = 6 }
                if ($smoothed[$x] -gt 23) { $smoothed[$x] = 23 }
            }
        }

        return $smoothed
    }

    function Generate-CityscapeTerrain {
        <#
        .SYNOPSIS
            Generates a destructible cityscape battlefield.

        .DESCRIPTION
            The terrain array still uses the same rule: each X column stores the first solid Y.
            Buildings are tall solid columns. Streets are open columns with the road at the bottom.
            Players are placed in street gaps at street level, not on rooftops, because this is
            Scorched Earth, not a municipal roof inspection.
        #>
        $city = New-Object int[] $script:width

        # Default to open street. The road is the bottom row.
        for ($x = 0; $x -lt $script:width; $x++) {
            $city[$x] = 23
        }

        $xPos = 2
        while ($xPos -lt ($script:width - 4)) {
            $streetGap = Get-Random -Minimum 3 -Maximum 7
            $xPos += $streetGap

            if ($xPos -ge ($script:width - 4)) {
                break
            }

            $buildingWidth = Get-Random -Minimum 4 -Maximum 10
            $buildingTop = Get-Random -Minimum 6 -Maximum 17

            for ($x = $xPos; $x -lt ($xPos + $buildingWidth) -and $x -lt ($script:width - 2); $x++) {
                $roofWobble = Get-Random -Minimum -1 -Maximum 2
                $top = $buildingTop + $roofWobble

                if ($top -lt 5)  { $top = 5 }
                if ($top -gt 18) { $top = 18 }

                $city[$x] = $top
            }

            # Punch occasional alley/light-well gaps through buildings.
            if ((Get-Random -Minimum 0 -Maximum 100) -lt 35) {
                $alleyX = Get-Random -Minimum $xPos -Maximum ([Math]::Min($xPos + $buildingWidth, $script:width - 2))
                $city[$alleyX] = 23
            }

            $xPos += $buildingWidth
        }

        # Preserve left and right spawn districts as streets.
        for ($x = 4; $x -le 24; $x++) {
            if ((Get-Random -Minimum 0 -Maximum 100) -lt 65) {
                $city[$x] = 23
            }
        }

        for ($x = 55; $x -le 76; $x++) {
            if ((Get-Random -Minimum 0 -Maximum 100) -lt 65) {
                $city[$x] = 23
            }
        }

        # Force guaranteed street pockets so the players have somewhere sane to stand.
        foreach ($x in 8..14)  { $city[$x] = 23 }
        foreach ($x in 65..71) { $city[$x] = 23 }

        return $city
    }

    function Generate-Terrain {
        <#
        .SYNOPSIS
            Dispatches to the selected terrain generator.
        #>
        if ($script:terrainMode -eq "Cityscape") {
            return Generate-CityscapeTerrain
        }

        return Generate-MountainTerrain
    }

    Select-TerrainMode
    $script:terrain = Generate-Terrain

    function Clear-PlayerArea {
        <#
        .SYNOPSIS
            Creates a narrow spawn platform.
        #>
        param (
            [int]$CenterX,
            [int]$FlatY
        )

        for ($x = $CenterX - 2; $x -le $CenterX + 2; $x++) {
            if ($x -ge 0 -and $x -lt $script:width) {
                $script:terrain[$x] = $FlatY
            }
        }
    }

    function Find-SpawnLocation {
        <#
        .SYNOPSIS
            Finds a spawn point in a zone without absurd cliffs.
        #>
        param (
            [int]$StartX,
            [int]$EndX
        )

        for ($attempt = 0; $attempt -lt 150; $attempt++) {
            $candidate = Get-Random -Minimum $StartX -Maximum $EndX

            $left  = $script:terrain[[Math]::Max(0, $candidate - 1)]
            $mid   = $script:terrain[$candidate]
            $right = $script:terrain[[Math]::Min($script:width - 1, $candidate + 1)]

            if ($script:terrainMode -eq "Cityscape") {
                # Street level is terrain value 23. Buildings have smaller Y values.
                # The player must stand outside buildings, in an actual street gap.
                if ($mid -eq 23 -and $left -eq 23 -and $right -eq 23) {
                    return $candidate
                }
            }
            else {
                if (([Math]::Abs($mid - $left) -le 4) -and ([Math]::Abs($mid - $right) -le 4)) {
                    return $candidate
                }
            }
        }

        if ($script:terrainMode -eq "Cityscape") {
            for ($x = $StartX; $x -lt $EndX; $x++) {
                if ($script:terrain[$x] -eq 23) {
                    return $x
                }
            }
        }

        return $StartX
    }

    $playerAX = Find-SpawnLocation -StartX 5 -EndX 25
    $playerBX = Find-SpawnLocation -StartX 55 -EndX 75

    Clear-PlayerArea -CenterX $playerAX -FlatY $script:terrain[$playerAX]
    Clear-PlayerArea -CenterX $playerBX -FlatY $script:terrain[$playerBX]

    # Add ridges between players only in mountain mode.
    # Cityscape already has buildings; adding ridges would be urban planning by artillery.
    if ($script:terrainMode -eq "Mountains") {
        for ($ridge = 0; $ridge -lt 3; $ridge++) {
        $ridgeCenter = Get-Random -Minimum ($playerAX + 8) -Maximum ($playerBX - 8)
        $ridgeHeight = Get-Random -Minimum 2 -Maximum 6
        $ridgeWidth  = Get-Random -Minimum 3 -Maximum 8

        for ($offset = -$ridgeWidth; $offset -le $ridgeWidth; $offset++) {
            $x = $ridgeCenter + $offset

            if ($x -ge 0 -and $x -lt $script:width) {
                $distanceFactor = [Math]::Abs($offset)
                $extraHeight = [Math]::Max(0, $ridgeHeight - $distanceFactor)
                $script:terrain[$x] -= $extraHeight

                if ($script:terrain[$x] -lt 6) {
                    $script:terrain[$x] = 6
                }
            }
        }
    }

    }

    # ------------------------------------------------------
    # PLAYERS
    # ------------------------------------------------------

    $script:player1 = @{
        Name        = "A"
        X           = $playerAX
        Y           = $script:terrain[$playerAX] - 1
        Symbol      = "A"
        NormalShots = $script:maxNormalShots
        MirvShots   = $script:maxMirvShots
    }

    $script:player2 = @{
        Name        = "B"
        X           = $playerBX
        Y           = $script:terrain[$playerBX] - 1
        Symbol      = "B"
        NormalShots = $script:maxNormalShots
        MirvShots   = $script:maxMirvShots
    }

    function Update-PlayerHeights {
        <#
        .SYNOPSIS
            Keeps players standing on terrain.
        #>
        if ($script:player1.X -ge 0) {
            $script:player1.Y = [Math]::Max(0, $script:terrain[$script:player1.X] - 1)
        }
        if ($script:player2.X -ge 0) {
            $script:player2.Y = [Math]::Max(0, $script:terrain[$script:player2.X] - 1)
        }
    }

    function Get-CellChar {
        <#
        .SYNOPSIS
            Returns the character drawn at a map coordinate.
        #>
        param (
            [int]$X,
            [int]$Y
        )

        if ($X -eq $script:player1.X -and $Y -eq $script:player1.Y) { return $script:player1.Symbol }
        if ($X -eq $script:player2.X -and $Y -eq $script:player2.Y) { return $script:player2.Symbol }
        if ($Y -ge $script:terrain[$X]) { return $script:terrainChar }
        return " "
    }

    function Draw-Game {
        <#
        .SYNOPSIS
            Redraws the centered battlefield.

        .DESCRIPTION
            Supports two kinds of animation overlays:
            - Triangle projectile symbols such as ▲ or ▴
            - Dotted trail marks using .

            If a projectile and a trail land on the same cell, the projectile wins. The dot may be
            dramatic, but the triangle is the thing ruining someone's afternoon.
        #>
        param (
            [array]$Projectiles = @()
        )

        for ($y = 0; $y -lt $script:height; $y++) {
            $line = ""

            for ($x = 0; $x -lt $script:width; $x++) {
                $overlayChar = $null
                $trailChar = $null

                foreach ($p in $Projectiles) {
                    if ([int][Math]::Round($p.X) -eq $x -and [int][Math]::Round($p.Y) -eq $y) {
                        $char = "▲"

                        if ($p.ContainsKey("Char")) {
                            $char = [string]$p.Char
                        }

                        if ($char -eq ".") {
                            $trailChar = "."
                        }
                        else {
                            $overlayChar = $char
                            break
                        }
                    }
                }

                if ($null -ne $overlayChar) {
                    $line += $overlayChar
                }
                elseif ($null -ne $trailChar) {
                    $line += $trailChar
                }
                else {
                    $line += Get-CellChar -X $x -Y $y
                }
            }

            Safe-SetCursor -X 0 -Y $y
            Write-Host $line -NoNewline
        }
    }

    function Clear-StatusArea {
        for ($line = $script:height + 1; $line -le $script:height + 8; $line++) {
            Safe-SetCursor -X 0 -Y $line
            Write-Host (" " * $script:width) -NoNewline
        }
    }

    function Test-ExplosionHit {
        <#
        .SYNOPSIS
            Returns true if target is inside a 3x3 blast radius.
        #>
        param (
            [int]$CenterX,
            [int]$CenterY,
            $Target
        )

        return (
            [Math]::Abs($Target.X - $CenterX) -le 1 -and
            [Math]::Abs($Target.Y - $CenterY) -le 1
        )
    }

    function Show-Explosion {
        <#
        .SYNOPSIS
            Shows a 3x3 asterisk explosion.
        #>
        param (
            [int]$X,
            [int]$Y
        )

        $patterns = @(
            @(@{ X = 0; Y = 0 }),
            @(
                @{ X =  0; Y = -1 }, @{ X = -1; Y =  0 }, @{ X = 0; Y = 0 },
                @{ X =  1; Y =  0 }, @{ X =  0; Y =  1 }
            ),
            @(
                @{ X = -1; Y = -1 }, @{ X = 0; Y = -1 }, @{ X = 1; Y = -1 },
                @{ X = -1; Y =  0 }, @{ X = 0; Y =  0 }, @{ X = 1; Y =  0 },
                @{ X = -1; Y =  1 }, @{ X = 0; Y =  1 }, @{ X = 1; Y =  1 }
            )
        )

        foreach ($pattern in $patterns) {
            Draw-Game

            foreach ($cell in $pattern) {
                $drawX = $X + $cell.X
                $drawY = $Y + $cell.Y

                if ($drawX -ge 0 -and $drawX -lt $script:width -and $drawY -ge 0 -and $drawY -lt $script:height) {
                    Safe-SetCursor -X $drawX -Y $drawY
                    Write-Host "*" -NoNewline
                }
            }

            Start-Sleep -Milliseconds 70
        }

        Draw-Game
    }

    function Show-SecondaryExplosion {
        <#
        .SYNOPSIS
            Shows a delayed 5x5 circular blast.
        #>
        param (
            [int]$X,
            [int]$Y
        )

        Start-Sleep -Seconds 1

        for ($frame = 0; $frame -lt 3; $frame++) {
            Draw-Game

            for ($dx = -2; $dx -le 2; $dx++) {
                for ($dy = -2; $dy -le 2; $dy++) {
                    if (($dx * $dx + $dy * $dy) -le 4) {
                        $drawX = $X + $dx
                        $drawY = $Y + $dy

                        if ($drawX -ge 0 -and $drawX -lt $script:width -and $drawY -ge 0 -and $drawY -lt $script:height) {
                            Safe-SetCursor -X $drawX -Y $drawY
                            Write-Host "*" -NoNewline
                        }
                    }
                }
            }

            Start-Sleep -Milliseconds 120
        }

        Draw-Game
    }

    function Show-DirectHitMessage {
        param ($Shooter, $Target)

        $message = ">>> DIRECT HIT! $($Shooter.Name) nailed $($Target.Name)! <<<"

        for ($i = 0; $i -lt 3; $i++) {
            Safe-SetCursor -X 0 -Y ($script:height + 5)
            Write-Host (" " * $script:width) -NoNewline

            Write-CenteredText -Text $message -Y ($script:height + 5)
            Start-Sleep -Milliseconds 180

            Safe-SetCursor -X 0 -Y ($script:height + 5)
            Write-Host (" " * $script:width) -NoNewline
            Start-Sleep -Milliseconds 120
        }

        Write-CenteredText -Text $message -Y ($script:height + 5)
    }

    function Damage-Terrain {
        <#
        .SYNOPSIS
            Digs a 3x3 circular-ish crater.

        .DESCRIPTION
            Damage now follows the same idea as the visible explosion: a small circular blast pattern.
            The center column takes the deepest damage, adjacent columns take less damage, and the
            result looks less like a spreadsheet deletion and more like something actually exploded.
        #>
        param (
            [int]$CenterX,
            [int]$CenterY
        )

        for ($dx = -1; $dx -le 1; $dx++) {
            $x = $CenterX + $dx

            if ($x -lt 0 -or $x -ge $script:width) {
                continue
            }

            # Circular 3x3 damage profile:
            # center column = deeper crater, side columns = shallower crater.
            $damageDepth = 3 - [Math]::Abs($dx)

            for ($damage = 0; $damage -lt $damageDepth; $damage++) {
                if ($script:terrain[$x] -lt ($script:height - 1)) {
                    $script:terrain[$x]++
                }
            }
        }

        Update-PlayerHeights
        Draw-Game
    }
    function Handle-PlayerHit {
        <#
        .SYNOPSIS
            Runs hit effects, crater, and player removal.
        #>
        param (
            $Shooter,
            $Target,
            [int]$ImpactX,
            [int]$ImpactY,
            [bool]$DirectHit,
            [string]$Prefix = "BOOM"
        )

        Show-Explosion -X $ImpactX -Y $ImpactY

        if ($DirectHit) {
            Show-DirectHitMessage -Shooter $Shooter -Target $Target
        }
        else {
            Write-CenteredText -Text "$Prefix! $($Shooter.Name) hit $($Target.Name)!" -Y ($script:height + 5)
        }

        $targetX = $Target.X
        $targetY = $Target.Y

        Show-SecondaryExplosion -X $targetX -Y $targetY
        Damage-Terrain -CenterX $targetX -CenterY $targetY

        # Remove defeated player.
        $Target.X = -999
        $Target.Y = -999
        $Target.Symbol = " "

        Draw-Game
        Start-Sleep -Milliseconds 250
        return $true
    }

    function Show-WinnerAnimation {
        <#
        .SYNOPSIS
            Displays fireworks and a centered winner banner.
        #>
        param ($Winner)

        $banner = "*** $($Winner.Name) WINS THE BATTLEFIELD! ***"
        $fireworks = @(
            @{ X = 20; Y = 4 },
            @{ X = 40; Y = 3 },
            @{ X = 60; Y = 5 }
        )

        for ($cycle = 0; $cycle -lt 4; $cycle++) {
            Draw-Game
            Write-CenteredText -Text $banner -Y ($script:height + 2)

            foreach ($burst in $fireworks) {
                $pattern = @(
                    @{ X = 0; Y = 0 }, @{ X = -1; Y = 0 }, @{ X = 1; Y = 0 },
                    @{ X = 0; Y = -1 }, @{ X = 0; Y = 1 }, @{ X = -1; Y = -1 },
                    @{ X = 1; Y = -1 }, @{ X = -1; Y = 1 }, @{ X = 1; Y = 1 }
                )

                foreach ($cell in $pattern) {
                    $drawX = $burst.X + $cell.X
                    $drawY = $burst.Y + $cell.Y

                    if ($drawX -ge 0 -and $drawX -lt $script:width -and $drawY -ge 0 -and $drawY -lt $script:height) {
                        Safe-SetCursor -X $drawX -Y $drawY
                        Write-Host "*" -NoNewline
                    }
                }
            }

            Start-Sleep -Milliseconds 220
            Draw-Game
            Start-Sleep -Milliseconds 120
        }

        Draw-Game
        Write-CenteredText -Text $banner -Y ($script:height + 2)
    }

    function Fire-NormalShot {
        param ($Shooter, $Target, [double]$Angle, [double]$Power)

        $radians = $Angle * [Math]::PI / 180
        $velocityX = [Math]::Cos($radians) * ($Power / 1.5)
        $velocityY = [Math]::Sin($radians) * ($Power / 1.5)

        if ($Shooter.X -gt $Target.X) { $velocityX *= -1 }

        $x = [double]$Shooter.X
        $y = [double]$Shooter.Y
        $gravity = 0.28
        $timeStep = 0.35
        $trail = @()

        while ($true) {
            $drawX = [int][Math]::Round($x)
            $drawY = [int][Math]::Round($y)

            if ($drawX -lt 0 -or $drawX -ge $script:width) {
                Draw-Game
                Write-CenteredText -Text "$($Shooter.Name) missed off the side." -Y ($script:height + 5)
                Start-Sleep -Milliseconds 150
                return $false
            }

            $directHit = ($drawX -eq $Target.X -and $drawY -eq $Target.Y)

            if ($drawY -ge 0 -and (Test-ExplosionHit -CenterX $drawX -CenterY $drawY -Target $Target)) {
                return Handle-PlayerHit -Shooter $Shooter -Target $Target -ImpactX $drawX -ImpactY $drawY -DirectHit $directHit
            }

            if ($drawY -ge 0 -and $drawY -ge $script:terrain[$drawX]) {
                Show-Explosion -X $drawX -Y $drawY

                if (Test-ExplosionHit -CenterX $drawX -CenterY $drawY -Target $Target) {
                    return Handle-PlayerHit -Shooter $Shooter -Target $Target -ImpactX $drawX -ImpactY $drawY -DirectHit $directHit
                }

                Damage-Terrain -CenterX $drawX -CenterY $drawY
                Write-CenteredText -Text "$($Shooter.Name) damaged the terrain." -Y ($script:height + 5)
                Start-Sleep -Milliseconds 150
                return $false
            }

            if ($drawY -ge 0 -and $drawY -lt $script:height) {
                $trail += @{ X = $drawX; Y = $drawY; Char = "." }

                if ($trail.Count -gt 18) {
                    $trail = @($trail | Select-Object -Last 18)
                }
            }

            $overlay = @()
            $overlay += $trail
            $overlay += @{ X = $x; Y = $y; Char = "▲" }
            Draw-Game -Projectiles $overlay
            Start-Sleep -Milliseconds 0

            $x += $velocityX * $timeStep
            $y -= $velocityY * $timeStep
            $velocityY -= $gravity
        }
    }

    function Fire-MIRVShot {
        param ($Shooter, $Target, [double]$Angle, [double]$Power)

        $radians = $Angle * [Math]::PI / 180
        $velocityX = [Math]::Cos($radians) * ($Power / 1.8)
        $velocityY = [Math]::Sin($radians) * ($Power / 1.8)

        if ($Shooter.X -gt $Target.X) { $velocityX *= -1 }

        $x = [double]$Shooter.X
        $y = [double]$Shooter.Y
        $gravity = 0.28
        $timeStep = 0.30
        $splitFrame = 12
        $frame = 0
        $trail = @()

        while ($frame -lt $splitFrame) {
            $drawX = [int][Math]::Round($x)
            $drawY = [int][Math]::Round($y)

            if ($drawX -lt 0 -or $drawX -ge $script:width) {
                Draw-Game
                Write-CenteredText -Text "$($Shooter.Name)'s MIRV went out of bounds on the side." -Y ($script:height + 5)
                Start-Sleep -Milliseconds 150
                return $false
            }

            $directHit = ($drawX -eq $Target.X -and $drawY -eq $Target.Y)

            if ($drawY -ge 0 -and (Test-ExplosionHit -CenterX $drawX -CenterY $drawY -Target $Target)) {
                return Handle-PlayerHit -Shooter $Shooter -Target $Target -ImpactX $drawX -ImpactY $drawY -DirectHit $directHit -Prefix "MIRV BOOM"
            }

            if ($drawY -ge 0 -and $drawY -ge $script:terrain[$drawX]) {
                Show-Explosion -X $drawX -Y $drawY

                if (Test-ExplosionHit -CenterX $drawX -CenterY $drawY -Target $Target) {
                    return Handle-PlayerHit -Shooter $Shooter -Target $Target -ImpactX $drawX -ImpactY $drawY -DirectHit $directHit -Prefix "MIRV BOOM"
                }

                Damage-Terrain -CenterX $drawX -CenterY $drawY
                Write-CenteredText -Text "$($Shooter.Name)'s MIRV hit terrain before splitting." -Y ($script:height + 5)
                Start-Sleep -Milliseconds 150
                return $false
            }

            if ($drawY -ge 0 -and $drawY -lt $script:height) {
                $trail += @{ X = $drawX; Y = $drawY; Char = "." }

                if ($trail.Count -gt 18) {
                    $trail = @($trail | Select-Object -Last 18)
                }
            }

            $overlay = @()
            $overlay += $trail
            $overlay += @{ X = $x; Y = $y; Char = "▲" }
            Draw-Game -Projectiles $overlay
            Start-Sleep -Milliseconds 0

            $x += $velocityX * $timeStep
            $y -= $velocityY * $timeStep
            $velocityY -= $gravity
            $frame++
        }

        $direction = if ($Shooter.X -gt $Target.X) { -1 } else { 1 }

        $projectiles = @(
            @{ X = $x; Y = $y; VX = $velocityX + (-4 * $direction); VY = $velocityY + 1.5; Active = $true; Trail = @() },
            @{ X = $x; Y = $y; VX = $velocityX + (-2 * $direction); VY = $velocityY + 1.0; Active = $true; Trail = @() },
            @{ X = $x; Y = $y; VX = $velocityX;                    VY = $velocityY + 0.5; Active = $true; Trail = @() },
            @{ X = $x; Y = $y; VX = $velocityX + ( 2 * $direction); VY = $velocityY + 1.0; Active = $true; Trail = @() },
            @{ X = $x; Y = $y; VX = $velocityX + ( 4 * $direction); VY = $velocityY + 1.5; Active = $true; Trail = @() }
        )

        while (($projectiles | Where-Object { $_.Active }).Count -gt 0) {
            $activeProjectiles = @()

            foreach ($p in $projectiles) {
                foreach ($trailDot in $p.Trail) {
                    $activeProjectiles += @{ X = $trailDot.X; Y = $trailDot.Y; Char = "." }
                }

                if (-not $p.Active) { continue }

                $drawX = [int][Math]::Round($p.X)
                $drawY = [int][Math]::Round($p.Y)

                if ($drawX -lt 0 -or $drawX -ge $script:width) {
                    $p.Active = $false
                    continue
                }

                $directHit = ($drawX -eq $Target.X -and $drawY -eq $Target.Y)

                if ($drawY -ge 0 -and (Test-ExplosionHit -CenterX $drawX -CenterY $drawY -Target $Target)) {
                    return Handle-PlayerHit -Shooter $Shooter -Target $Target -ImpactX $drawX -ImpactY $drawY -DirectHit $directHit -Prefix "MIRV BOOM"
                }

                if ($drawY -ge 0 -and $drawY -ge $script:terrain[$drawX]) {
                    Show-Explosion -X $drawX -Y $drawY

                    if (Test-ExplosionHit -CenterX $drawX -CenterY $drawY -Target $Target) {
                        return Handle-PlayerHit -Shooter $Shooter -Target $Target -ImpactX $drawX -ImpactY $drawY -DirectHit $directHit -Prefix "MIRV BOOM"
                    }

                    Damage-Terrain -CenterX $drawX -CenterY $drawY
                    $p.Active = $false
                    continue
                }

                if ($drawY -ge 0 -and $drawY -lt $script:height) {
                    $p.Trail += @{ X = $drawX; Y = $drawY }

                    if ($p.Trail.Count -gt 14) {
                        $p.Trail = @($p.Trail | Select-Object -Last 14)
                    }
                }

                $activeProjectiles += @{ X = $p.X; Y = $p.Y; Char = "▲" }
            }

            Draw-Game -Projectiles $activeProjectiles
            Start-Sleep -Milliseconds 0

            foreach ($p in $projectiles) {
                if ($p.Active) {
                    $p.X += $p.VX * $timeStep
                    $p.Y -= $p.VY * $timeStep
                    $p.VY -= $gravity
                }
            }
        }

        Write-CenteredText -Text "$($Shooter.Name)'s MIRV finished." -Y ($script:height + 5)
        Start-Sleep -Milliseconds 150
        return $false
    }
    function Fire-Shot {
        param ($Shooter, $Target)

        Draw-Game
        Clear-StatusArea

        Write-CenteredText -Text "Ammo: A Normal=$($script:player1.NormalShots) MIRV=$($script:player1.MirvShots) | B Normal=$($script:player2.NormalShots) MIRV=$($script:player2.MirvShots)" -Y ($script:height + 1)
        Write-CenteredText -Text "Weapon: 1 = Normal | 2 = MIRV" -Y ($script:height + 2)

        Safe-SetCursor -X 22 -Y ($script:height + 3)
        $weapon = Read-Host "$($Shooter.Name) choose weapon"

        Safe-SetCursor -X 22 -Y ($script:height + 4)
        $angle = [double](Read-Host "$($Shooter.Name) Angle (0-90)")

        Safe-SetCursor -X 22 -Y ($script:height + 5)
        $power = [double](Read-Host "$($Shooter.Name) Power (1-100)")

        Clear-StatusArea
        if ($weapon -eq "2") {
            if ($Shooter.MirvShots -le 0) {
                Write-CenteredText -Text "$($Shooter.Name) has no MIRV shots left." -Y ($script:height + 5)
                Start-Sleep -Milliseconds 700
                return $false
            }

            $Shooter.MirvShots--
            return Fire-MIRVShot -Shooter $Shooter -Target $Target -Angle $angle -Power $power
        }
        else {
            if ($Shooter.NormalShots -le 0) {
                Write-CenteredText -Text "$($Shooter.Name) has no Normal shots left." -Y ($script:height + 5)
                Start-Sleep -Milliseconds 700
                return $false
            }

            $Shooter.NormalShots--
            return Fire-NormalShot -Shooter $Shooter -Target $Target -Angle $angle -Power $power
        }
    }

    # ------------------------------------------------------
    # TURN LOOP
    # ------------------------------------------------------

    Draw-Game

    $currentPlayer = $script:player1
    $targetPlayer = $script:player2
    $winner = $false

    while (
        $script:player1.NormalShots -gt 0 -or
        $script:player1.MirvShots -gt 0 -or
        $script:player2.NormalShots -gt 0 -or
        $script:player2.MirvShots -gt 0
    ) {
        if ($currentPlayer.NormalShots -le 0 -and $currentPlayer.MirvShots -le 0) {
            if ($currentPlayer -eq $script:player1) {
                $currentPlayer = $script:player2
                $targetPlayer = $script:player1
            }
            else {
                $currentPlayer = $script:player1
                $targetPlayer = $script:player2
            }
            continue
        }
        $hit = Fire-Shot -Shooter $currentPlayer -Target $targetPlayer

        if ($hit) {
            Draw-Game
            Clear-StatusArea
            Show-WinnerAnimation -Winner $currentPlayer
            Write-CenteredText -Text "$($currentPlayer.Name) WINS!" -Y ($script:height + 5)
            $winner = $true
            break
        }

        if ($currentPlayer -eq $script:player1) {
            $currentPlayer = $script:player2
            $targetPlayer = $script:player1
        }
        else {
            $currentPlayer = $script:player1
            $targetPlayer = $script:player2
        }
    }

    if (-not $winner) {
        Draw-Game
        Clear-StatusArea
        Write-CenteredText -Text "DRAW!" -Y ($script:height + 2)
        Write-CenteredText -Text "Both players ran out of Normal and MIRV ammunition." -Y ($script:height + 3)
    }

    Safe-SetCursor -X 0 -Y ($script:height + 8)
}

# ==========================================================
# IMPORTANT CODE WALKTHROUGH
# ==========================================================

<#
IMPORTANT LINES OF CODE
=======================

1. Terrain Character
--------------------
$script:terrainChar = [char]0x2593

Why this matters:
Uses Unicode ▓ to render terrain. This avoids the old extended ASCII problem where Windows Terminal
occasionally decides character 178 should become the number 2, which is mathematically interesting
but visually disappointing.

2. Cursor Movement
------------------
[Console]::SetCursorPosition($targetX, $targetY)

Why this matters:
This gives the illusion of animation without clearing the whole console like a person panic-deleting
files before an audit.

3. Centering
------------
$script:offsetX = [Math]::Max(0, [int](($windowWidth - $script:width) / 2))

Why this matters:
The game appears in the middle of the terminal, where civilization expects it.

4. Terrain Generation
---------------------
$wave1 = [Math]::Sin(($x / 7.0) + ($phase1 / 100.0)) * 3.0

Why this matters:
Terrain uses layered sine waves plus randomness. Translation: hills, valleys, and unfair geography.

5. Gravity
----------
$velocityY -= $gravity

Why this matters:
This line makes the projectile arc. Newton would approve. The player missing by twenty columns will not.

6. Projectile Persistence
-------------------------
if ($drawX -lt 0 -or $drawX -ge $script:width)

Why this matters:
Shots can leave the top of the screen and come back down. Only side exits count as misses.
Because what goes up must come down — except budgets.

7. Explosion Radius Hit Detection
---------------------------------
[Math]::Abs($Target.X - $CenterX) -le 1

Why this matters:
A player is hit inside a 3x3 explosion radius. No pixel-perfect nonsense. War has splash damage.

8. MIRV Splitting
-----------------
$splitFrame = 12

Why this matters:
After enough travel time, one projectile becomes five. Because sometimes solving a problem with one
explosion feels inefficient.

9. Player Removal
-----------------
$Target.X = -999
$Target.Y = -999

Why this matters:
When defeated, a player disappears. Not reassigned. Not reorganized. Gone.


10. Terrain Selection
---------------------
Select-TerrainMode

Why this matters:
The game now asks whether you want Mountains, Cityscape, or Random. It is the only democratic
process in the program, and even then Random may overthrow it.

11. Cityscape Street-Level Spawn
--------------------------------
if ($mid -eq 23 -and $left -eq 23 -and $right -eq 23)

Why this matters:
In Cityscape mode, players spawn in open street gaps outside buildings. They do not appear on
rooftops like confused HVAC contractors. Buildings are cover. Streets are where the poor souls stand.

12. City Buildings
------------------
$city[$x] = $top

Why this matters:
Each building column stores the first solid Y position. Lower number means taller building.
A city is therefore just an array of bad policy decisions rendered in Unicode.

FINAL THOUGHT
=============
"The problem with artillery is not that people miss.
The problem is that eventually, someone gets the angle right."

— Scorched Earth, PowerShell Edition
#>

# ==========================================================
# PROGRAM ENTRY POINT
# ==========================================================

Show-SplashScreen

do {
    Start-ScorchedEarthGame
    Safe-SetCursor -X 23 -Y ($script:height + 8)
    $playAgain = Read-Host "Play another round? (Y/N)"
} while ($playAgain -eq "Y" -or $playAgain -eq "y")

Clear-Host
Update-ScreenOffsets
Write-CenteredText -Text "Thanks for playing!" -Y ([Math]::Max(0, [int]($script:height / 2)))
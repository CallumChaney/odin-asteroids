// This file is compiled as part of the `odin.dll` file. It contains the
// procs that `game.exe` will call, such as:
//
// game_init: Sets up the game state
// game_update: Run once per frame
// game_shutdown: Shuts down game and frees memory
// game_memory: Run just before a hot reload, so game.exe has a pointer to the
//		game's memory.
// game_hot_reloaded: Run after a hot reload so that the `g_mem` global variable
//		can be set to whatever pointer it was in the old DLL.

package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import rand "core:math/rand"
import rl "vendor:raylib"


THICKNESS :: 2.5
PLAYER_POINTS :: []Vec2{{-1, -1}, {-0.6, -0.5}, {0.6, -0.5}, {1, -1}, {0, 2}}
PLAYER_THUSTER :: []Vec2{{0.4, -0.6}, {-0.4, -0.6}, {0, -1.7}}
ROTATE_SPEED :: 5
MOVE_SPEED :: 3
MAX_VELOCITY :: 1.5
SCALE :: 20

ASTEROID_POINTS :: 10

Vec2 :: rl.Vector2

AsteroidSize :: enum {
    SMALL,
    MEDIUM,
    LARGE,
}

get_asteroid_scale :: proc(size: AsteroidSize) -> f32 {
    scale: f32
    switch size {
    case .LARGE:
        scale = SCALE * 7.0
    case .MEDIUM:
        scale = SCALE * 1.4
    case .SMALL:
        scale = SCALE * 0.8
    }
    return scale
}

Asteroid :: struct {
    pos, vel: Vec2,
    size:     AsteroidSize,
    points:   [ASTEROID_POINTS]Vec2,
}


asteroid_create :: proc(pos, vel: Vec2, size: AsteroidSize) -> Asteroid {

    points: [ASTEROID_POINTS]Vec2

    switch size {
    case .SMALL:
    case .MEDIUM:
    case .LARGE:
        for i in 0 ..< ASTEROID_POINTS {

            radius := 0.3 + (0.2 * rand.float32())

            if rand.float32() < 0.2 {
                radius -= 0.2
            }
            phi := math.TAU * f32(i) / ASTEROID_POINTS

            points[i] = {
                math.cos(f32(phi)) * radius,
                math.sin(f32(phi)) * radius,
            }
        }
    }

    return {pos, vel, size, points}
}

Projectile :: struct {
    pos, vel: Vec2,
    remove:   bool,
}

Game_Memory :: struct {
    player:      struct {
        using pos: Vec2,
        vel:       Vec2,
        rot:       f32,
        thrusting: bool,
    },
    asteroids:   [dynamic]Asteroid,
    projectiles: [dynamic]Projectile,
}

g_mem: ^Game_Memory


player_update :: proc() {
    player := &g_mem.player
    if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
        player.rot -= ROTATE_SPEED * rl.GetFrameTime()
    }
    if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
        player.rot += ROTATE_SPEED * rl.GetFrameTime()
    }


    ship_dir := rl.Vector2Rotate({0, 1}, player.rot)

    if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) {
        player.thrusting = true
        player.vel += ship_dir * MOVE_SPEED * rl.GetFrameTime()
    } else {
        player.thrusting = false
    }

    player.vel = rl.Vector2ClampValue(player.vel, 0, MAX_VELOCITY)


    DRAG :: 0.002
    player.vel *= (1 - DRAG) //* rl.GetFrameTime()
    player.pos += player.vel

    screen_wrap(&player.pos)

    if rl.IsKeyPressed(.SPACE) {
        append(
            &g_mem.projectiles,
            Projectile {
                pos = player.pos + ship_dir * SCALE * 1.5,
                vel = ship_dir * 1000,
            },
        )
    }

}

asteroids_update :: proc() {
    for &asteroid in g_mem.asteroids {
        asteroid.pos += asteroid.vel * rl.GetFrameTime()
        screen_wrap(&asteroid.pos)
    }
}

projectile_update :: proc() {
    for &projectile in g_mem.projectiles {
        projectile.pos += projectile.vel * rl.GetFrameTime()
    }
}

screen_wrap :: proc(pos: ^Vec2) {
    if pos.x < 0 {
        pos.x = f32(rl.GetScreenWidth())
    }
    if pos.x > f32(rl.GetScreenWidth()) {
        pos.x = 0
    }
    if pos.y < 0 {
        pos.y = f32(rl.GetScreenHeight())
    }
    if pos.y > f32(rl.GetScreenHeight()) {
        pos.y = 0
    }
}

update :: proc() {
    player_update()
    asteroids_update()
    projectile_update()
}


draw_shape :: proc(origin: Vec2, scale, rotation: f32, points: []Vec2) {

    transform :: proc(point, origin: Vec2, scale, rotation: f32) -> Vec2 {
        return rl.Vector2Rotate(point, rotation) * scale + origin
    }

    for point, idx in points {
        rl.DrawLineEx(
            transform(point, origin, scale, rotation),
            transform(
                points[(idx + 1) % len(points)],
                origin,
                scale,
                rotation,
            ),
            THICKNESS,
            rl.WHITE,
        )
    }
}


draw :: proc() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.BLACK)
    draw_shape(g_mem.player.pos, SCALE, g_mem.player.rot, PLAYER_POINTS)
    if g_mem.player.thrusting && i32(rl.GetTime() * 20) % 2 == 0 {
        draw_shape(g_mem.player.pos, SCALE, g_mem.player.rot, PLAYER_THUSTER)
    }
    for &asteroid in g_mem.asteroids {
        draw_shape(
            asteroid.pos,
            get_asteroid_scale(asteroid.size),
            0,
            asteroid.points[:],
        )
    }
    for &projectile in g_mem.projectiles {
        rl.DrawCircleV(projectile.pos, math.max(SCALE * 0.05, 1), rl.WHITE)
    }
    rl.EndDrawing()
}

@(export)
game_update :: proc() -> bool {
    update()
    draw()
    return !rl.WindowShouldClose()
}

@(export)
game_init_window :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE})
    rl.InitWindow(1280, 720, "Project Omega")
    rl.SetWindowPosition(200, 200)
    rl.SetTargetFPS(500)
}

@(export)
game_init :: proc() {
    g_mem = new(Game_Memory)
    g_mem^ = Game_Memory {
        player = {
            pos = {
                f32(rl.GetScreenWidth() / 2),
                f32(rl.GetScreenHeight() / 2),
            },
        },
    }
    for i in 0 ..< 4 {
        append(
            &g_mem.asteroids,
            asteroid_create(
                {
                    rand.float32_range(0, f32(rl.GetScreenWidth())),
                    rand.float32_range(0, f32(rl.GetScreenHeight())),
                },
                {
                    rand.float32_range(-1, 1) * 100,
                    rand.float32_range(-1, 1) * 100,
                },
                .LARGE,
            ),
        )
    }
    game_hot_reloaded(g_mem)
}

@(export)
game_shutdown :: proc() {
    delete(g_mem.asteroids)
    delete(g_mem.projectiles)
    free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
    rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
    return g_mem
}

@(export)
game_memory_size :: proc() -> int {
    return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
    g_mem = (^Game_Memory)(mem)
}

@(export)
game_force_reload :: proc() -> bool {
    return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
    return rl.IsKeyPressed(.F6)
}

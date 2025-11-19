const std = @import("std");
const rl = @import("raylib");

// GLOBAL DATA
const WWIDTH = 600;
const WHEIGHT = 500;
const DEFAULT_SCALING: i32 = 2;
// GLOBAL DATA

// CACTUS
const Cactus = struct {
    position: rl.Vector2,
    velocity: f32, // x velocity
    width: i32,
    height: i32,

    const Self = @This();

    fn init(texture_width: i32, texture_height: i32) Self {
        var self: Self = .{
            .position = undefined,
            .velocity = -200,
            .width = texture_width,
            .height = texture_height,
        };
        self.reset();
        return self;
    }

    fn reset(self: *Self) void {
        self.position = .init(
            @floatFromInt(rl.getScreenWidth() - self.width),
            @floatFromInt(rl.getScreenHeight() - self.height * DEFAULT_SCALING),
        );
    }
};

fn onCactusUpdate(cactus: *Cactus, game: *Game, dt: f32) void {
    if (game.is_over) return;
    cactus.position = cactus.position.add(.init(cactus.velocity * dt, 0));
    if (cactus.position.x < -1) {
        cactus.reset();
    }
}

fn onCactusDraw(cactus: *Cactus, texture: rl.Texture2D) void {
    rl.drawTextureEx(texture, cactus.position, 0, DEFAULT_SCALING, .black);
}
// CACTUS

// DINO
const DINO_RUN_FRAMES: [2]u8 = .{ 24, 48 };
const DINO_IDLE_FRAMES: [2]u8 = .{ 0, 72 };
const DINO_GRAVITY: i32 = 2000;
const DINO_JUMP: i32 = -600;
const DINO_TOTAL_FRAMES: i32 = 4;
const DINO_ANIMATION_TIMEOUT: f32 = 0.1;
const Dino = struct {
    position: rl.Vector2,
    velocity: f32, // y velocity
    grounded: bool,
    current_frame: u8,
    frame_index: usize,
    animation_timer: f32,
    width: i32,
    height: i32,

    const Self = @This();

    fn init(width: i32, height: i32) Self {
        return .{
            .position = .init(50, @floatFromInt(rl.getScreenHeight() - height)),
            .velocity = 0,
            .grounded = false,
            .frame_index = 0,
            .current_frame = DINO_RUN_FRAMES[0],
            .animation_timer = 0.0,
            .width = width,
            .height = height,
        };
    }

    fn reset(self: *Self) void {
        self.velocity = 0;
        self.position = .init(50, @floatFromInt(rl.getScreenHeight() - self.height));
        self.grounded = false;
        self.frame_index = 0;
        self.current_frame = DINO_RUN_FRAMES[self.frame_index];
        self.animation_timer = 0.0;
    }
};

fn onDinoUpdate(dino: *Dino, game: *Game, dt: f32) void {
    if (game.is_over) return;
    // PLAYER STUFF
    dino.velocity += DINO_GRAVITY * dt;

    if (dino.grounded and rl.isKeyPressed(.space)) {
        dino.velocity = DINO_JUMP;
        dino.grounded = false;
    }

    // multiply both x and y by frame time
    dino.position = dino.position.add(.init(0, dino.velocity * dt));

    // we reached the ground, therefore we should stop falling
    const floor_h: f32 = @floatFromInt(rl.getScreenHeight() - dino.height * DEFAULT_SCALING);
    if (dino.position.y > floor_h) {
        dino.position.y = floor_h;
        dino.grounded = true;
    }

    dino.animation_timer += dt;
    if (dino.grounded and dino.animation_timer > DINO_ANIMATION_TIMEOUT) {
        if (dino.frame_index > DINO_RUN_FRAMES.len - 1) {
            dino.frame_index = 0;
        }
        dino.current_frame = DINO_RUN_FRAMES[dino.frame_index];
        dino.frame_index += 1;
        dino.animation_timer = 0;
    } else if (!dino.grounded) {
        dino.current_frame = DINO_IDLE_FRAMES[0];
    }
}

fn onDinoDraw(dino: *Dino, texture: rl.Texture2D) void {
    const player_run_width: f32 = @floatFromInt(dino.width);
    const player_run_height: f32 = @floatFromInt(dino.height);

    // which part of the texture to display
    const player_source: rl.Rectangle = .init(
        @floatFromInt(dino.current_frame),
        0,
        player_run_width / DINO_TOTAL_FRAMES,
        player_run_height,
    );
    const player_dest: rl.Rectangle = .init(
        dino.position.x,
        dino.position.y,
        player_run_width * DEFAULT_SCALING / DINO_TOTAL_FRAMES,
        player_run_height * DEFAULT_SCALING,
    );

    rl.drawTexturePro(texture, player_source, player_dest, .{ .x = 0, .y = 0 }, 0, .black);
}
// DINO

// game
const Game = struct {
    is_over: bool = false,
};

fn onGameUpdate(dino: *Dino, cactus: *Cactus, game: *Game) void {
    if (game.is_over and rl.isKeyPressed(.space)) {
        game.is_over = false;
        dino.reset();
        cactus.reset();
        return;
    }
    const cactus_width: f32 = @floatFromInt(cactus.width);
    const cactus_radius: f32 = cactus_width / 1.1;
    const dino_width: f32 = @floatFromInt(@divExact(dino.width, DINO_TOTAL_FRAMES));
    const dino_radius: f32 = dino_width / 1.1;
    if (rl.checkCollisionCircles(
        dino.position,
        dino_radius,
        cactus.position,
        cactus_radius,
    )) {
        dino.current_frame = @intCast(DINO_IDLE_FRAMES[1]);
        game.is_over = true;
    }
}

fn onGameDraw(game: *Game) void {
    if (game.is_over) {
        drawCenteredText("Game Over", 30, 0);
        drawCenteredText("Press 'space' key to restart the game", 20, 40);
    }
}

fn drawCenteredText(text: [:0]const u8, font_size: i32, y: i32) void {
    const text_width: f32 = @floatFromInt(rl.measureText(text, font_size));
    const x: i32 = @intFromFloat(WWIDTH / 2 - text_width / 2.0);
    rl.drawText(text, x, WHEIGHT / 2 + y, font_size, .black);
}

// TODO:
//    * Spawn more cactuses
//      * add random scale to at least one
//    * fix reset visual bug
//    * add background music
//    * add jump sound
//    * add score
//    * add more speed when the dino jump over a cactus
pub fn main() !void {
    rl.initWindow(WWIDTH, WHEIGHT, "google dino clone?");
    const dino_texture = try rl.loadTexture("dino.png");
    const cactus_texture = try rl.loadTexture("cactus.png");

    defer {
        cactus_texture.unload();
        dino_texture.unload();
        rl.closeWindow();
    }

    var game: Game = .{};

    // by now only one cactus need it
    var cactus: Cactus = .init(
        @intCast(cactus_texture.width),
        @intCast(cactus_texture.height),
    );

    // we only need one dinosour
    var dino: Dino = .init(
        @intCast(dino_texture.width),
        @intCast(dino_texture.height),
    );

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        const dt: f32 = rl.getFrameTime();

        onCactusUpdate(&cactus, &game, dt);
        onDinoUpdate(&dino, &game, dt);
        onGameUpdate(&dino, &cactus, &game);

        rl.beginDrawing();
        defer rl.endDrawing();

        // draw background
        rl.clearBackground(.{ .r = 204, .g = 224, .b = 255, .a = 0 });

        // draw cactus
        onCactusDraw(&cactus, cactus_texture);

        // draw dinosour
        onDinoDraw(&dino, dino_texture);

        // draw game stats
        onGameDraw(&game);
    }
}

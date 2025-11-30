const std = @import("std");
const assert = std.debug.assert;
const rl = @import("raylib");

fn getScreenWidthF() f32 {
    return @floatFromInt(rl.getScreenWidth());
}

fn getScreenHeightF() f32 {
    return @floatFromInt(rl.getScreenHeight());
}

const Handle = struct {
    idx: u32,
    gen: u32,
};

fn HandleMap(comptime T: type, capacity: i32) type {
    assert(@hasField(T, "handle"));

    return struct {
        entities: [capacity]T = undefined,
        num_items: u32 = 0,
        next_unused: u32 = 0,
        unused_items: [capacity]u32 = undefined,
        num_unused: u32 = 0,

        const Self = @This();

        fn add(self: *Self, handle: T) void {
            if (self.next_unused != 0) {
                const idx = self.next_unused;
                var item: *T = &self.entities[@intCast(idx)];
                self.next_unused = self.unused_items[idx];
                const gen = item.handle.gen;
                item.* = handle;
                item.handle.idx = idx;
                item.handle.gen = gen + 1;
                self.num_unused -= 1;
                return;
            }

            var item: *T = &self.entities[@intCast(self.num_items)];
            item.* = handle;
            item.handle.idx = self.num_items;
            self.num_items += 1;
        }

        fn remove(self: *Self, handle: Handle) void {
            if (handle.idx < 0 or handle.idx > capacity) return;
            var item: *T = &self.entities[@intCast(handle.idx)];
            if (item.handle.idx == handle.idx) {
                self.unused_items[handle.idx] = self.next_unused;
                self.next_unused = handle.idx;
                self.num_unused += 1;
                item.handle.idx = 0xfff;
            }
        }

        const Iterator = struct {
            items: []T,
            len: u32,
            pos: usize,

            fn next(self: *Iterator) ?*T {
                if (self.pos >= self.len) return null;
                const item = &self.items[self.pos];
                self.pos += 1;
                return @constCast(item);
            }
        };

        fn iterator(self: *Self) Iterator {
            return .{
                .items = &self.entities,
                .len = self.num_items,
                .pos = 0,
            };
        }

        // O(n)
        fn getByQuery(self: *Self, query: *const fn (v: *const T) bool) ?*T {
            var it = self.iterator();
            var n = it.next();
            while (n != null) : (n = it.next()) {
                if (query(n.?) and self.isValid(n.?.handle)) return n;
            }

            return null;
        }

        fn isValid(_: *Self, h: Handle) bool {
            return h.idx >= 0 and h.idx <= capacity;
        }
    };
}

const EntityType = enum(u3) {
    DINO,
    CACTUS,
    CLOUDS,
};

const Texture2D = struct {
    entity_type: EntityType,
    raylib_texture_2d: rl.Texture2D,

    handle: Handle = undefined,

    const Self = @This();

    fn init(path_name: [:0]const u8, entity_type: EntityType) !Self {
        return .{
            .raylib_texture_2d = try rl.loadTexture(path_name),
            .entity_type = entity_type,
        };
    }

    inline fn widthF(self: *const Self) f32 {
        return @floatFromInt(self.raylib_texture_2d.width);
    }

    inline fn heightF(self: *const Self) f32 {
        return @floatFromInt(self.raylib_texture_2d.height);
    }

    fn unload(self: *Self) void {
        self.raylib_texture_2d.unload();
    }

    fn drawTextureEx(
        self: *Self,
        position: rl.Vector2,
        rotation: f32,
        scale: f32,
        tint: rl.Color,
    ) void {
        rl.drawTextureEx(self.raylib_texture_2d, position, rotation, scale, tint);
    }

    fn drawPro(
        self: *Self,
        source: rl.Rectangle,
        dest: rl.Rectangle,
        origin: rl.Vector2,
        rotation: f32,
        tint: rl.Color,
    ) void {
        self.raylib_texture_2d.drawPro(source, dest, origin, rotation, tint);
    }
};

const Music = struct {
    raylib_music: rl.Music,

    const Self = @This();

    fn load(path_name: [:0]const u8) !Self {
        return .{
            .raylib_music = try rl.loadMusicStream(path_name),
        };
    }

    fn unload(self: *Self) void {
        self.raylib_music.unload();
    }

    fn setVolume(self: *Self, volume: f32) void {
        rl.setMusicVolume(self.raylib_music, volume);
    }

    fn play(self: *Self) void {
        rl.playMusicStream(self.raylib_music);
    }

    fn stop(self: *Self) void {
        rl.stopMusicStream(self.raylib_music);
    }

    fn update(self: *Self) void {
        rl.updateMusicStream(self.raylib_music);
    }
};

const SoundType = enum(u1) {
    JUMP,
    GAME_OVER,
};

const Sound = struct {
    sound_type: SoundType,
    raylib_sound: rl.Sound,

    handle: Handle = undefined,

    const Self = @This();

    fn load(path_name: [:0]const u8, sound_type: SoundType) !Self {
        return .{
            .raylib_sound = try rl.loadSound(path_name),
            .sound_type = sound_type,
        };
    }

    fn unload(self: *Self) void {
        self.raylib_sound.unload();
    }

    fn play(self: *Self) void {
        rl.playSound(self.raylib_sound);
    }

    fn stop(self: *Self) void {
        rl.stopSound(self.raylib_sound);
    }
};

const Entity = struct {
    entity_type: EntityType,

    position: rl.Vector2 = undefined,
    velocity: rl.Vector2 = undefined,

    // animation stuff
    current_frame: u8 = 0,
    frame_index: usize = 0,
    animation_timer: f32 = 0,

    // texture stuff
    image_scale: f32 = 1.0,

    handle: Handle = undefined,
};

fn Queries(entity_type: EntityType) type {
    return struct {
        fn getEntity(entity: *const Entity) bool {
            return entity.entity_type == entity_type;
        }

        fn getTextures(resource: *const Texture2D) bool {
            return resource.entity_type == entity_type;
        }
    };
}

const clouds_queries = Queries(.CLOUDS);
const cactus_queries = Queries(.CACTUS);
const dino_queries = Queries(.DINO);

const CLOUD_FRAMES: [4]u8 = .{ 0, 24, 48, 72 };
const CLOUD_TOTAL_FRAMES: f32 = 4.0;
const CLOUDS_SPAWN_DELAY: f32 = 1.3;
const CLOUDS_SCALING: f32 = 5.0;
const CLOUDS_SPEED: f32 = -120.0;
const CLOUD_Y_POS: [3]u16 = .{ 25, 100, 200 };
var clouds_spawn_timer: f32 = 0.0;
var last_cloud_y_pos: u16 = 0;

fn getCloudY(game_state: *GameState) u16 {
    var cloud_y: u16 = last_cloud_y_pos;
    while (cloud_y == last_cloud_y_pos) {
        cloud_y = CLOUD_Y_POS[@intCast(game_state.rand.intRangeAtMost(i16, 1, 3) - 1)];
    }

    last_cloud_y_pos = cloud_y;
    return cloud_y;
}

fn onCloudsUpdate(game_state: *GameState, dt: f32) void {
    if (game_state.game_over) return;

    const texture: *Texture2D = game_state.textures_2D.getByQuery(
        clouds_queries.getTextures,
    ).?;

    if (clouds_spawn_timer > CLOUDS_SPAWN_DELAY) {
        clouds_spawn_timer = 0;
        const rand_frame_index: usize = @intCast(game_state.rand.intRangeAtMost(i8, 1, 4));
        const cloud_y_position: f32 = @floatFromInt(getCloudY(game_state));
        game_state.entities.add(Entity{
            .image_scale = CLOUDS_SCALING,
            .entity_type = .CLOUDS,
            .current_frame = @intCast(CLOUD_FRAMES[rand_frame_index - 1]),
            .position = .init(
                getScreenWidthF() + texture.widthF(),
                cloud_y_position,
            ),
            .velocity = .init(CLOUDS_SPEED, 0),
        });
    }

    clouds_spawn_timer += dt;
    var it = game_state.entities.iterator();
    var entity = it.next();
    while (entity != null) : (entity = it.next()) {
        switch (entity.?.entity_type) {
            .CLOUDS => {
                var clouds: *Entity = entity.?;
                if (!game_state.entities.isValid(clouds.handle)) continue;
                clouds.position = clouds.position.add(
                    clouds.velocity.multiply(.init(dt, 0)),
                );
                const outside_screen: f32 = 0.0 - texture.widthF() - 10.0;
                if (clouds.position.x < outside_screen) {
                    game_state.entities.remove(clouds.handle);
                }
            },
            else => {},
        }
    }
}

fn onCloudsDraw(game_state: *GameState) void {
    const texture: *Texture2D = game_state.textures_2D.getByQuery(
        clouds_queries.getTextures,
    ).?;

    var it = game_state.entities.iterator();
    var entity = it.next();
    while (entity != null) : (entity = it.next()) {
        switch (entity.?.entity_type) {
            .CLOUDS => {
                const cloud: *Entity = entity.?;
                if (!game_state.entities.isValid(cloud.handle)) continue;
                const source: rl.Rectangle = .init(
                    @floatFromInt(cloud.current_frame),
                    0,
                    texture.widthF() / CLOUD_TOTAL_FRAMES,
                    texture.heightF(),
                );
                const dst: rl.Rectangle = .init(
                    cloud.position.x,
                    cloud.position.y,
                    texture.widthF() * cloud.image_scale / CLOUD_TOTAL_FRAMES,
                    texture.heightF() * cloud.image_scale,
                );
                texture.drawPro(source, dst, .{ .x = 0, .y = 0 }, 0, .black);
            },
            else => {},
        }
    }
}

const CACTUS_SPAWN_DELAY: f32 = 2.0;
const CACTUS_SCALING: f32 = 1.6;
const CACTUS_BASE_SPEED: f32 = -200.0;

const CactusProperties = struct {
    spawn_delay: f32,

    const Self = @This();

    inline fn buildBasedOnScore(score: i32) Self {
        var delay: f32 = CACTUS_SPAWN_DELAY;

        if (score >= 5) {
            delay = 1.7;
        }
        if (score >= 20) {
            delay = 1.4;
        }
        if (score >= 40) {
            delay = 1.1;
        }

        return .{
            .spawn_delay = delay,
        };
    }
};

fn onCactusUpdate(game_state: *GameState, dt: f32) void {
    if (game_state.game_over) return;

    const prop: CactusProperties = .buildBasedOnScore(game_state.score);
    const texture: *Texture2D = game_state.textures_2D.getByQuery(
        cactus_queries.getTextures,
    ).?;

    if (game_state.cactus_spawn_timer > prop.spawn_delay) {
        game_state.cactus_spawn_timer = 0;
        const spawn_count: usize = @intCast(game_state.rand.intRangeAtMost(i8, 1, 3));
        for (0..spawn_count) |i| {
            const index: f32 = @floatFromInt(i);
            game_state.entities.add(Entity{
                .image_scale = CACTUS_SCALING,
                .entity_type = .CACTUS,
                .position = .init(
                    getScreenWidthF() - (index * texture.widthF() * CACTUS_SCALING),
                    getScreenHeightF() - texture.heightF() * CACTUS_SCALING,
                ),
                .velocity = .init(CACTUS_BASE_SPEED, 0),
            });
        }
    }

    game_state.cactus_spawn_timer += dt;
    var it = game_state.entities.iterator();
    var entity = it.next();
    while (entity != null) : (entity = it.next()) {
        switch (entity.?.entity_type) {
            .CACTUS => {
                var cactus: *Entity = entity.?;
                if (!game_state.entities.isValid(cactus.handle)) continue;
                cactus.position = cactus.position.add(
                    cactus.velocity.multiply(.init(dt, 0)),
                );
                const outside_screen: f32 = 0.0 - texture.widthF() - 10.0;
                if (cactus.position.x < outside_screen) {
                    game_state.entities.remove(cactus.handle);
                    game_state.score += 1;
                }
            },
            else => {},
        }
    }
}

fn onCactusDraw(game_state: *GameState) void {
    const texture: *Texture2D = game_state.textures_2D.getByQuery(
        cactus_queries.getTextures,
    ).?;
    var it = game_state.entities.iterator();
    var entity = it.next();
    while (entity != null) : (entity = it.next()) {
        switch (entity.?.entity_type) {
            .CACTUS => {
                const cactus: *Entity = entity.?;
                if (!game_state.entities.isValid(cactus.handle)) continue;
                texture.drawTextureEx(cactus.position, 0, CACTUS_SCALING, .black);
            },
            else => {},
        }
    }
}

const DINO_RUN_FRAMES: [2]u8 = .{ 24, 48 };
const DINO_IDLE_FRAMES: [2]u8 = .{ 0, 72 };
const DINO_GRAVITY: i32 = 2000;
const DINO_JUMP: i32 = -750;
const DINO_TOTAL_FRAMES: i32 = 4;
const DINO_ANIMATION_TIMEOUT: f32 = 0.1;
const DINO_SCALING: f32 = 2.0;
fn onDinoUpdate(game_state: *GameState, dt: f32) void {
    if (game_state.game_over) return;

    const dino: *Entity = game_state.entities.getByQuery(
        dino_queries.getEntity,
    ).?;
    const dino_texture: *Texture2D = game_state.textures_2D.getByQuery(
        dino_queries.getTextures,
    ).?;
    const jump_sound: *Sound = game_state.sounds.getByQuery(
        struct {
            fn getSound(sound: *const Sound) bool {
                return sound.sound_type == .JUMP;
            }
        }.getSound,
    ).?;

    const floor_pos: f32 = getScreenHeightF() - dino_texture.heightF() * dino.image_scale;
    var grounded: bool = dino.position.y >= floor_pos;

    dino.velocity = dino.velocity.add(
        .init(0, DINO_GRAVITY * dt),
    );

    if (grounded and rl.isKeyPressed(.space)) {
        dino.velocity = .init(0, DINO_JUMP);
        jump_sound.play();
        grounded = false;
    }

    // multiply both x and y by frame time
    dino.position = dino.position.add(
        dino.velocity.multiply(.init(0, dt)),
    );

    // we reached the ground, therefore we should stop falling
    if (dino.position.y > floor_pos) {
        dino.position.y = floor_pos;
        grounded = true;
    }

    dino.animation_timer += dt;
    if (grounded and dino.animation_timer > DINO_ANIMATION_TIMEOUT) {
        if (dino.frame_index > DINO_RUN_FRAMES.len - 1) {
            dino.frame_index = 0;
        }
        dino.current_frame = DINO_RUN_FRAMES[dino.frame_index];
        dino.frame_index += 1;
        dino.animation_timer = 0;
    } else if (!grounded) {
        dino.current_frame = DINO_IDLE_FRAMES[0];
    }
}

fn onDinoDraw(game_state: *GameState) void {
    const dino: *Entity = game_state.entities.getByQuery(
        dino_queries.getEntity,
    ).?;
    const texture: *Texture2D = game_state.textures_2D.getByQuery(
        dino_queries.getTextures,
    ).?;

    // which part of the texture to display
    const player_source: rl.Rectangle = .init(
        @floatFromInt(dino.current_frame),
        0,
        texture.widthF() / DINO_TOTAL_FRAMES,
        texture.heightF(),
    );
    const player_dest: rl.Rectangle = .init(
        dino.position.x,
        dino.position.y,
        texture.widthF() * dino.image_scale / DINO_TOTAL_FRAMES,
        texture.heightF() * dino.image_scale,
    );
    texture.drawPro(player_source, player_dest, .{ .x = 0, .y = 0 }, 0, .black);
}

fn onCollision(game_state: *GameState) void {
    if (game_state.game_over) return;
    const dino: *Entity = game_state.entities.getByQuery(
        dino_queries.getEntity,
    ).?;
    const dino_texture: *Texture2D = game_state.textures_2D.getByQuery(
        dino_queries.getTextures,
    ).?;

    const dino_width: f32 = dino_texture.widthF() / DINO_TOTAL_FRAMES;
    const dino_radius: f32 = dino_width / 1.0;

    const cactus_texture: *Texture2D = game_state.textures_2D.getByQuery(
        cactus_queries.getTextures,
    ).?;
    const cactus_width: f32 = cactus_texture.widthF();
    const cactus_radius: f32 = cactus_width / 3.0;

    var it = game_state.entities.iterator();
    var entity = it.next();
    while (entity != null) : (entity = it.next()) {
        if (!game_state.entities.isValid(entity.?.handle)) continue;
        switch (entity.?.entity_type) {
            .CACTUS => {
                const cactus: *Entity = entity.?;
                if (rl.checkCollisionCircles(
                    dino.position,
                    dino_radius,
                    cactus.position,
                    cactus_radius,
                )) {
                    if (!game_state.play_game_over_sound) {
                        game_state.play_game_over_sound = true;
                    }
                    game_state.background_music.stop();
                    dino.current_frame = @intCast(DINO_IDLE_FRAMES[1]);
                    game_state.game_over = true;
                }
            },
            else => {},
        }
    }
}

fn drawCenteredText(text: [:0]const u8, font_size: i32, y: i32) void {
    const text_width: f32 = @floatFromInt(rl.measureText(text, font_size));
    const x: i32 = @intFromFloat(WWIDTH / 2 - text_width / 2.0);
    rl.drawText(text, x, WHEIGHT / 2 + y, font_size, .black);
}

const WWIDTH = 1000;
const WHEIGHT = 600;
const MAX_ENTITIES = 1024;
const MAX_TEXTURES = 3;
const MAX_SOUND = 2;

const GameState = struct {
    game_over: bool = false,
    entities: HandleMap(Entity, MAX_ENTITIES) = .{},
    textures_2D: HandleMap(Texture2D, MAX_TEXTURES) = .{},
    sounds: HandleMap(Sound, MAX_SOUND) = .{},

    score: i32 = 0,
    cactus_spawn_timer: f32 = 0.0,
    rand: std.Random = undefined,

    play_game_over_sound: bool = false,

    background_music: Music = undefined,

    const Self = @This();

    fn init() !Self {
        var self: Self = .{};
        const dino_texture: Texture2D = try .init("assets/dino.png", .DINO);
        self.textures_2D.add(dino_texture);
        self.textures_2D.add(try .init("assets/cactus.png", .CACTUS));
        self.textures_2D.add(try .init("assets/clouds.png", .CLOUDS));
        self.background_music = try Music.load("assets/background.ogg");
        self.background_music.play();
        self.background_music.setVolume(0.2);
        self.sounds.add(try Sound.load("assets/jump.wav", .JUMP));
        self.sounds.add(try Sound.load("assets/game_over.ogg", .GAME_OVER));
        self.entities.add(Entity{
            .entity_type = .DINO,
            .animation_timer = 0.5,
            .current_frame = 0,
            .frame_index = 0,
            .image_scale = DINO_SCALING,
            .position = .init(50, getScreenHeightF() - dino_texture.heightF()),
            .velocity = .init(0, 0),
        });
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        self.rand = prng.random();
        return self;
    }

    fn deinit(self: *Self) void {
        {
            // unload textures
            var it = self.textures_2D.iterator();
            var texture = it.next();
            while (texture != null) : (texture = it.next()) {
                texture.?.unload();
            }
        }

        {
            var it = self.sounds.iterator();
            var sound = it.next();
            while (sound != null) : (sound = it.next()) {
                sound.?.unload();
            }
        }

        self.background_music.unload();
    }

    fn onUpdate(self: *Self) void {
        self.background_music.update();
        const dt: f32 = rl.getFrameTime();

        onCloudsUpdate(self, dt);
        onDinoUpdate(self, dt);
        onCactusUpdate(self, dt);
        onCollision(self);

        if (self.play_game_over_sound) {
            self.getGameOverSound().play();
            self.play_game_over_sound = false;
        }

        if (self.game_over and rl.isKeyPressed(.space)) {
            self.reset();
        }
    }

    fn reset(self: *Self) void {
        self.getGameOverSound().stop();
        self.background_music.play();
        self.play_game_over_sound = false;
        self.game_over = false;
        self.score = 0;
        var it = self.entities.iterator();
        var entity = it.next();
        while (entity != null) : (entity = it.next()) {
            switch (entity.?.entity_type) {
                .DINO => {
                    entity.?.current_frame = DINO_RUN_FRAMES[0];
                },
                .CACTUS => {
                    self.entities.remove(entity.?.handle);
                },
                else => {},
            }
        }
    }

    fn getGameOverSound(self: *Self) *Sound {
        return self.sounds.getByQuery(
            struct {
                fn getSound(sound: *const Sound) bool {
                    return sound.sound_type == .GAME_OVER;
                }
            }.getSound,
        ).?;
    }

    fn playGameOverSound(self: *Self) void {
        self.getGameOverSound().play();
    }

    fn onDraw(self: *Self) void {
        rl.clearBackground(.{ .r = 204, .g = 224, .b = 255, .a = 0 });
        self.drawScore();
        onCloudsDraw(self);
        onDinoDraw(self);
        onCactusDraw(self);
        self.drawGameOver();
    }

    fn drawScore(self: *Self) void {
        rl.drawText(rl.textFormat("Score: %d", .{self.score}), 10, 10, 20, .black);
    }

    fn drawGameOver(self: *Self) void {
        if (self.game_over) {
            drawCenteredText("Game Over", 30, 0);
            drawCenteredText("Press 'space' key to restart the game", 20, 40);
        }
    }
};

pub fn main() !void {
    rl.initWindow(WWIDTH, WHEIGHT, "google dino clone?");
    rl.initAudioDevice();
    var game_state: GameState = try .init();

    defer {
        game_state.deinit();
        rl.closeAudioDevice();
        rl.closeWindow();
    }

    while (!rl.windowShouldClose()) {
        game_state.onUpdate();

        rl.beginDrawing();
        defer rl.endDrawing();
        game_state.onDraw();
    }
}

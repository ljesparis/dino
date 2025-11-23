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
            if (handle.idx <= 0 or handle.idx >= capacity) return;
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

const EntityType = enum(u1) {
    DINO,
    CACTUS,
};

const Resource = struct {
    entity_type: EntityType,
    handle: Handle = undefined,

    resource: union(enum) {
        texture_2d: rl.Texture2D,
        audio: rl.Sound,
    },

    const Self = @This();

    fn unload(self: *Self) void {
        switch (self.resource) {
            .texture_2d => self.resource.texture_2d.unload(),
            .audio => self.resource.audio.unload(),
        }
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

        fn getResources(resource: *const Resource) bool {
            return resource.entity_type == entity_type;
        }
    };
}

const cactus_queries = Queries(.CACTUS);
const dino_queries = Queries(.DINO);

const CACTUS_SPAWN_DELAY: f32 = 2.0;
const CACTUS_SCALING: f32 = 1.6;
const CACTUS_SPEED: f32 = 200.0;
const CACTUS_SPEED_INC: f32 = 50.0;

fn getSpeedBasedOnScore(score: i32) f32 {
    var speed = CACTUS_SPEED;
    if (score >= 5) {
        speed = CACTUS_SPEED + CACTUS_SPEED_INC * 2;
    }
    if (score >= 20) {
        speed = CACTUS_SPEED + CACTUS_SPEED_INC * 3;
    }
    if (score >= 30) {
        speed = CACTUS_SPEED + CACTUS_SPEED_INC * 4;
    }
    if (score >= 40) {
        speed = CACTUS_SPEED + CACTUS_SPEED_INC * 5;
    }
    return -1.0 * speed;
}

fn getSpawnDelayBasedOnScore(score: i32) f32 {
    var delay: f32 = 2.0;
    if (score >= 5) {
        delay = 1.7;
    }
    if (score >= 20) {
        delay = 1.4;
    }
    if (score >= 30) {
        delay = 1.1;
    }
    if (score >= 40) {
        delay = 0.8;
    }

    return delay;
}

fn onCactusUpdate(game_state: *GameState, dt: f32) void {
    if (game_state.game_over) return;

    const texture: rl.Texture2D = game_state.textures_2D.getByQuery(cactus_queries.getResources).?.resource.texture_2d;
    if (game_state.cactus_spawn_timer > getSpawnDelayBasedOnScore(game_state.score)) {
        game_state.cactus_spawn_timer = 0;
        const spawn_count: usize = @intCast(game_state.rand.intRangeAtMost(i8, 1, 3));
        for (0..spawn_count) |i| {
            const index: f32 = @floatFromInt(i);
            const width: f32 = @floatFromInt(texture.width);
            const height: f32 = @floatFromInt(texture.height);
            game_state.entities.add(Entity{
                .image_scale = CACTUS_SCALING,
                .entity_type = .CACTUS,
                .position = .init(
                    getScreenWidthF() - width - (index * width * CACTUS_SCALING),
                    getScreenHeightF() - height * CACTUS_SCALING,
                ),
                .velocity = .init(getSpeedIncAccordingToScore(game_state.score), 0),
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
                const outside_screen: f32 = @floatFromInt(0 - texture.width - 10);
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
    const texture: rl.Texture2D = game_state.textures_2D.getByQuery(cactus_queries.getResources).?.resource.texture_2d;
    var it = game_state.entities.iterator();
    var entity = it.next();
    while (entity != null) : (entity = it.next()) {
        switch (entity.?.entity_type) {
            .CACTUS => {
                const cactus: *Entity = entity.?;
                if (!game_state.entities.isValid(cactus.handle)) continue;
                rl.drawTextureEx(texture, cactus.position, 0, CACTUS_SCALING, .black);
            },
            else => {},
        }
    }
}

const DINO_RUN_FRAMES: [2]u8 = .{ 24, 48 };
const DINO_IDLE_FRAMES: [2]u8 = .{ 0, 72 };
const DINO_GRAVITY: i32 = 2000;
const DINO_JUMP: i32 = -680;
const DINO_TOTAL_FRAMES: i32 = 4;
const DINO_ANIMATION_TIMEOUT: f32 = 0.1;
const DINO_SCALING: f32 = 2.0;
fn onDinoUpdate(game_state: *GameState, dt: f32) void {
    if (game_state.game_over) return;

    const dino: *Entity = game_state.entities.getByQuery(dino_queries.getEntity).?;
    const dino_texture: rl.Texture2D = game_state.textures_2D.getByQuery(dino_queries.getResources).?.resource.texture_2d;

    const texture_height: f32 = @floatFromInt(dino_texture.height);
    const floor_pos: f32 = getScreenHeightF() - texture_height * dino.image_scale;
    var grounded: bool = dino.position.y >= floor_pos;

    dino.velocity = dino.velocity.add(
        .init(0, DINO_GRAVITY * dt),
    );

    if (grounded and rl.isKeyPressed(.space)) {
        dino.velocity = .init(0, DINO_JUMP);
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
    const dino: *Entity = game_state.entities.getByQuery(dino_queries.getEntity).?;
    const texture: rl.Texture2D = game_state.textures_2D.getByQuery(dino_queries.getResources).?.resource.texture_2d;

    const width: f32 = @floatFromInt(texture.width);
    const height: f32 = @floatFromInt(texture.height);
    const scale: f32 = dino.image_scale;

    // which part of the texture to display
    const player_source: rl.Rectangle = .init(
        @floatFromInt(dino.current_frame),
        0,
        width / DINO_TOTAL_FRAMES,
        height,
    );
    const player_dest: rl.Rectangle = .init(
        dino.position.x,
        dino.position.y,
        width * scale / DINO_TOTAL_FRAMES,
        height * scale,
    );
    rl.drawTexturePro(texture, player_source, player_dest, .{ .x = 0, .y = 0 }, 0, .black);
}

fn onCollision(game_state: *GameState) void {
    const dino: *Entity = game_state.entities.getByQuery(dino_queries.getEntity).?;
    const dino_texture: rl.Texture2D = game_state.textures_2D.getByQuery(dino_queries.getResources).?.resource.texture_2d;

    const dino_width: f32 = @floatFromInt(@divExact(dino_texture.width, DINO_TOTAL_FRAMES));
    const dino_radius: f32 = dino_width / 1.1;

    const cactus_texture: rl.Texture2D = game_state.textures_2D.getByQuery(cactus_queries.getResources).?.resource.texture_2d;
    const cactus_width: f32 = @floatFromInt(cactus_texture.width);
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

const WWIDTH = 600;
const WHEIGHT = 500;
const MAX_ENTITIES = 1024;
const MAX_TEXTURES = 2;
const GameState = struct {
    game_over: bool = false,
    entities: HandleMap(Entity, MAX_ENTITIES) = .{},
    textures_2D: HandleMap(Resource, MAX_TEXTURES) = .{},

    score: i32 = 0,
    cactus_spawn_timer: f32 = 0.0,
    rand: std.Random = undefined,

    const Self = @This();

    fn init() !Self {
        var self: Self = .{};
        const dino_texture = try rl.loadTexture("assets/dino.png");
        const cactus_texture = try rl.loadTexture("assets/cactus.png");
        const texture_height: f32 = @floatFromInt(dino_texture.height);
        self.entities.add(Entity{
            .entity_type = .DINO,
            .animation_timer = 0.5,
            .current_frame = 0,
            .frame_index = 0,
            .image_scale = DINO_SCALING,
            .position = .init(50, getScreenHeightF() - texture_height),
            .velocity = .init(0, 0),
        });
        self.textures_2D.add(Resource{
            .entity_type = .DINO,
            .resource = .{ .texture_2d = dino_texture },
        });
        self.textures_2D.add(Resource{
            .entity_type = .CACTUS,
            .resource = .{ .texture_2d = cactus_texture },
        });
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        self.rand = prng.random();
        return self;
    }

    fn deinit(self: *Self) void {
        // unload textures
        var it = self.textures_2D.iterator();
        var texture = it.next();
        while (texture != null) : (texture = it.next()) {
            texture.?.unload();
        }
    }

    fn onUpdate(self: *Self) void {
        const dt: f32 = rl.getFrameTime();
        onDinoUpdate(self, dt);
        onCactusUpdate(self, dt);
        onCollision(self);

        if (self.game_over and rl.isKeyPressed(.space)) {
            self.reset();
        }
    }

    fn reset(self: *Self) void {
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
            }
        }
    }

    fn onDraw(self: *Self) !void {
        rl.clearBackground(.{ .r = 204, .g = 224, .b = 255, .a = 0 });
        try self.drawScore();
        onDinoDraw(self);
        onCactusDraw(self);

        if (self.game_over) {
            drawCenteredText("Game Over", 30, 0);
            drawCenteredText("Press 'space' key to restart the game", 20, 40);
        }
    }

    fn drawScore(self: *Self) !void {
        var buffer: [32:0]u8 = undefined;
        const slice = try std.fmt.bufPrint(&buffer, "Score: {}", .{self.score});
        buffer[slice.len] = 0;
        const cstr: [:0]const u8 = buffer[0..slice.len :0];
        rl.drawText(cstr, 10, 10, 20, .black);
    }
};

pub fn main() !void {
    rl.initWindow(WWIDTH, WHEIGHT, "google dino clone?");
    var game_state: GameState = try .init();

    defer {
        game_state.deinit();
        rl.closeWindow();
    }

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        game_state.onUpdate();

        rl.beginDrawing();
        defer rl.endDrawing();
        try game_state.onDraw();
    }
}

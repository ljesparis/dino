const std = @import("std");
const assert = std.debug.assert;
const rl = @import("raylib");

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
    image_scale: i32 = 1,

    handle: Handle = undefined,
};

const WWIDTH = 600;
const WHEIGHT = 500;
const MAX_ENTITIES = 1024;
const MAX_TEXTURES = 2;

const DEFAULT_SCALING: i32 = 2;

// CACTUS
const cactus_query_entity = struct {
    pub fn q(entity: *const Entity) bool {
        return entity.entity_type == .CACTUS;
    }
};

const cactus_query_resource = struct {
    pub fn q(resource: *const Resource) bool {
        return resource.entity_type == .CACTUS;
    }
};

fn onCactusUpdate(game_state: *GameState, dt: f32) void {
    if (game_state.game_over) return;
    var cactus: ?*Entity = game_state.entities.getByQuery(cactus_query_entity.q);
    const texture: rl.Texture2D = game_state.textures_2D.getByQuery(cactus_query_resource.q).?.resource.texture_2d;
    if (cactus == null) {
        game_state.entities.add(Entity{
            .image_scale = DEFAULT_SCALING,
            .entity_type = .CACTUS,
            .position = .init(
                @floatFromInt(rl.getScreenWidth() - texture.width),
                @floatFromInt(rl.getScreenHeight() - texture.height * DEFAULT_SCALING),
            ),
            .velocity = .init(-200, 0),
        });
        return;
    }

    cactus.?.position = cactus.?.position.add(
        cactus.?.velocity.multiply(.init(dt, 0)),
    );

    const outside_screen: f32 = @floatFromInt(0 - texture.width * cactus.?.image_scale + 10);
    if (cactus.?.position.x < outside_screen) {
        game_state.entities.remove(cactus.?.handle);
    }
}

fn onCactusDraw(game_state: *GameState) void {
    const cactus: ?*Entity = game_state.entities.getByQuery(cactus_query_entity.q);
    if (cactus == null) return;
    const texture: rl.Texture2D = game_state.textures_2D.getByQuery(cactus_query_resource.q).?.resource.texture_2d;
    const scaling: f32 = @floatFromInt(cactus.?.image_scale);
    rl.drawTextureEx(texture, cactus.?.position, 0, scaling, .black);
}
// CACTUS

// DINO
const DINO_RUN_FRAMES: [2]u8 = .{ 24, 48 };
const DINO_IDLE_FRAMES: [2]u8 = .{ 0, 72 };
const DINO_GRAVITY: i32 = 2000;
const DINO_JUMP: i32 = -600;
const DINO_TOTAL_FRAMES: i32 = 4;
const DINO_ANIMATION_TIMEOUT: f32 = 0.1;

const dino_query_entity = struct {
    pub fn q(entity: *const Entity) bool {
        return entity.entity_type == .DINO;
    }
};

const dino_query_resource = struct {
    pub fn q(resource: *const Resource) bool {
        return resource.entity_type == .DINO;
    }
};

fn onDinoUpdate(game_state: *GameState, dt: f32) void {
    if (game_state.game_over) return;

    const dino: *Entity = game_state.entities.getByQuery(dino_query_entity.q).?;
    const dino_texture: rl.Texture2D = game_state.textures_2D.getByQuery(dino_query_resource.q).?.resource.texture_2d;

    const floor_pos: f32 = @floatFromInt(rl.getScreenHeight() - dino_texture.height * dino.image_scale);
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

    // animation
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

    // collisions
    // we're going to always have a cactus.
    const cactus: ?*Entity = game_state.entities.getByQuery(cactus_query_entity.q);
    if (cactus == null) return;
    const cactus_texture: rl.Texture2D = game_state.textures_2D.getByQuery(cactus_query_resource.q).?.resource.texture_2d;

    const cactus_width: f32 = @floatFromInt(cactus_texture.width);
    const cactus_radius: f32 = cactus_width / 1.1;
    const dino_width: f32 = @floatFromInt(@divExact(dino_texture.width, DINO_TOTAL_FRAMES));
    const dino_radius: f32 = dino_width / 1.1;
    if (rl.checkCollisionCircles(
        dino.position,
        dino_radius,
        cactus.?.position,
        cactus_radius,
    )) {
        dino.current_frame = @intCast(DINO_IDLE_FRAMES[1]);
        game_state.game_over = true;
    }
}

fn onDinoDraw(game_state: *GameState) void {
    const dino: *Entity = game_state.entities.getByQuery(dino_query_entity.q).?;
    const texture: rl.Texture2D = game_state.textures_2D.getByQuery(dino_query_resource.q).?.resource.texture_2d;

    const width: f32 = @floatFromInt(texture.width);
    const height: f32 = @floatFromInt(texture.height);
    const scale: f32 = @floatFromInt(dino.image_scale);

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
// DINO

fn drawCenteredText(text: [:0]const u8, font_size: i32, y: i32) void {
    const text_width: f32 = @floatFromInt(rl.measureText(text, font_size));
    const x: i32 = @intFromFloat(WWIDTH / 2 - text_width / 2.0);
    rl.drawText(text, x, WHEIGHT / 2 + y, font_size, .black);
}

// GAME STATE
const GameState = struct {
    game_over: bool = false,
    entities: HandleMap(Entity, MAX_ENTITIES) = .{},
    textures_2D: HandleMap(Resource, MAX_TEXTURES) = .{},

    const Self = @This();

    fn init() !Self {
        var self: Self = .{};
        const dino_texture = try rl.loadTexture("assets/dino.png");
        const cactus_texture = try rl.loadTexture("assets/cactus.png");
        self.entities.add(Entity{
            .entity_type = .DINO,
            .animation_timer = 0.5,
            .current_frame = 0,
            .frame_index = 0,
            .image_scale = DEFAULT_SCALING,
            .position = .init(50, @floatFromInt(rl.getScreenHeight() - dino_texture.height)),
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
        if (!self.game_over) {
            const dt: f32 = rl.getFrameTime();
            onDinoUpdate(self, dt);
            onCactusUpdate(self, dt);
        }
    }

    fn onDraw(self: *Self) void {
        rl.clearBackground(.{ .r = 204, .g = 224, .b = 255, .a = 0 });
        onDinoDraw(self);
        onCactusDraw(self);

        if (self.game_over) {
            drawCenteredText("Game Over", 30, 0);
            drawCenteredText("Press 'space' key to restart the game", 20, 40);
        }
    }
};

// GAME STATE

// TODO:
//    * Spawn more cactuses
//      * add random scale to at least one
//      * also we need to be able to spawn 1, 2 or 3 in a row
//    * fix reset visual bug
//    * add background music
//    * add jump sound
//    * add score
//    * add more speed when the dino jump over a cactus
//    * investigate
//      * Entity Component System
//      * Entity Map
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
        game_state.onDraw();
    }
}

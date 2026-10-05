const std = @import("std");
const native = @import("native.zig");
const c = native.c;

const log = std.log.scoped(.Application);

const BackendSettings = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
};

const AppSettings = struct {
    target_fps: ?f64 = 60,
    vsync_enabled: bool = false,
};

pub const SubSystem = enum {
    Audio,
    Video,
    Joystick,
    Haptic,
    Gamepad,
    Events,
    Sensor,
    Camera
};

pub const ApplicationError = error {
    ResourceFailure,
    InvalidSettings
};

allocator: std.mem.Allocator,
io: std.Io,
settings: AppSettings,

/// Holds the internal application state. Any scope outside the
/// application should not mutate this state.
internal: struct {
    /// Hold framerate regulation state.
    framerate: struct {
        clock: std.Io.Clock,
        timestamp: std.Io.Timestamp,
    }
},

/// Initializes an application.
fn init(allocator: std.mem.Allocator, io: std.Io) @This() {

    const clock = std.Io.Clock.awake;
    const timestamp = clock.now(io);

    return .{
        .allocator = allocator,
        .io = io,
        .settings = .{},

        // Initialize internal state.
        .internal = .{
            .framerate = .{
                .clock = clock,
                .timestamp = timestamp,
            }
        }
    };
}

/// Run the application along with user-defined event callbacks.
pub fn run(settings: BackendSettings, callbacks: anytype) !void {
    const allocator = settings.allocator;

    var app = try allocator.create(@This());
    app.* = init(settings.allocator, settings.io);
    defer allocator.destroy(app);

    // Initialize SDL.
    try native.run(c.SDL_Init(0));

    // Run user-defined `onInit` function.
    try callbacks.onInit(app);

    while (true) {
        const delta = try app.syncFramerate();

        try callbacks.onUpdate(app, delta);
        try callbacks.onRender(app, delta);
    }

    try callbacks.onQuit(app);

    // Wait for GPU idle, then quit SDL.
    // (add when ready!) --- try native.run(c.SDL_WaitForGPUIdle(...));
    try native.run(c.SDL_Quit());
}

pub fn useSubSystems(_: *@This(), subsystems: []const SubSystem) !void {
    for (subsystems) |subsystem| {

        const native_subsys = switch (subsystem) {
            .Audio    => c.SDL_INIT_AUDIO,
            .Video    => c.SDL_INIT_VIDEO,
            .Joystick => c.SDL_INIT_JOYSTICK,
            .Haptic   => c.SDL_INIT_HAPTIC,
            .Gamepad  => c.SDL_INIT_GAMEPAD,
            .Events   => c.SDL_INIT_EVENTS,
            .Sensor   => c.SDL_INIT_SENSOR,
            .Camera   => c.SDL_INIT_CAMERA
        };

        native.run(c.SDL_InitSubSystem(native_subsys))
        catch {
            log.err("Failed to enable {s} subsystem. SDL error: {s}", .{ @tagName(subsystem), c.SDL_GetError() });
            return ApplicationError.ResourceFailure;
        };
    }
}

/// Calculate delta-time between frames (in seconds).
/// If the target FPS is set, regulate the framerate by blocking
/// the main thread.
fn syncFramerate(self: *@This()) !f64 {

    var elapsed = self.internal.framerate.timestamp.untilNow(
        self.io,
        self.internal.framerate.clock);

    const has_target_fps = (
        !self.settings.vsync_enabled and self.settings.target_fps != null
    );

    if (has_target_fps) {
        if (self.settings.target_fps.? < 1.0) {
            log.err("The target FPS cannot be less than one.", .{});
            return ApplicationError.InvalidSettings;
        }

        // Get actual deltatime (nanoseconds)
        const actual_delta_ns: i96 = elapsed.toNanoseconds();

        // Given the FPS, inverse it to get expected duration between frames.
        // (Expected deltatime as seconds)
        const target_delta_sec: f64 = 1.0 / self.settings.target_fps.?;
        
        // Convert expected deltatime into nanoseconds
        const target_delta_ns: i96 = @intFromFloat(target_delta_sec * @as(f64, @floatFromInt(std.time.ns_per_s)));

        if (actual_delta_ns < target_delta_ns) {
            const remaining_delta = target_delta_ns - actual_delta_ns;

            // Pause the thread to reach the expected framerate.
            try self.io.sleep(.fromNanoseconds(remaining_delta), self.internal.framerate.clock);

            // Re-calculate the final elapsed time using the updated time context
            elapsed = self.internal.framerate.timestamp.untilNow(
                self.io,
                self.internal.framerate.clock);
        }
    }

    // Capture the current timestamp to anchor the next frame's baseline.
    self.internal.framerate.timestamp = self.internal.framerate.clock.now(self.io);

    const elapsed_sec: f64 = @as(f64, @floatFromInt(elapsed.toNanoseconds())) / @as(f64, @floatFromInt(std.time.ns_per_s));
    return elapsed_sec;
}
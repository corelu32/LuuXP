const std = @import("std");
const log = std.log.scoped(.root);
const c   = native.c;

pub const native    = @import("native.zig");
pub const Window    = @import("Window.zig");
pub const GpuDevice = @import("GpuDevice.zig");

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

pub const RuntimeSettings = struct {
    target_fps: ?f64 = 60,
    vsync_enabled: bool = false,
};

pub const ApplicationError = error {
    ResourceFailure,
    InvalidSettings
};

pub fn run(TState: type, callbacks: anytype, init_params: anytype) !void {

    const allocator: std.mem.Allocator = init_params.@"0";
    const io: std.Io = init_params.@"1";

    var clock = std.Io.Clock.awake;
    var timestamp = clock.now(io);
    var event: c.SDL_Event = undefined;
    var running = true;

    const state = try allocator.create(TState);
    defer allocator.destroy(state);
    
    // Initialize SDL.
    native.run(c.SDL_Init(0))
    catch {
        log.err("Failed to initialize SDL. SDL error: {s}", .{ c.SDL_GetError() });
        return ApplicationError.ResourceFailure;
    };
    defer c.SDL_Quit();

    // Initialize the application state.
    state.* = try callbacks.onInit(allocator, io);

    while (true) {
        const settings: RuntimeSettings = callbacks.onQuerySettings(state);

        const delta = try syncFramerate(
            io,
            clock,
            &timestamp,
            settings.target_fps,
            settings.vsync_enabled);

        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                else => { }
            }
        }

        try callbacks.onUpdate(state, delta);
        try callbacks.onRender(state, delta);
    }

    try callbacks.onQuit(state);
}

pub fn useSubSystems(subsystems: []const SubSystem) !void {
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
pub fn syncFramerate(
    io: std.Io,
    clock: std.Io.Clock,
    timestamp: *std.Io.Timestamp,
    target_fps: ?f64,
    vsync_enabled: bool) !f64 {

    var elapsed = timestamp.untilNow(io, clock);

    const has_target_fps = ( !vsync_enabled and target_fps != null );

    if (has_target_fps) {
        if (target_fps.? < 1.0) {
            log.err("The target FPS cannot be less than one.", .{});
            return ApplicationError.InvalidSettings;
        }

        // Get actual deltatime (nanoseconds)
        const actual_delta_ns: i96 = elapsed.toNanoseconds();

        // Given the FPS, inverse it to get expected duration between frames.
        // (Expected deltatime as seconds)
        const target_delta_sec: f64 = 1.0 / target_fps.?;
        
        // Convert expected deltatime into nanoseconds
        const target_delta_ns: i96 = @intFromFloat(target_delta_sec * @as(f64, @floatFromInt(std.time.ns_per_s)));

        if (actual_delta_ns < target_delta_ns) {
            const remaining_delta = target_delta_ns - actual_delta_ns;

            // Pause the thread to reach the expected framerate.
            try io.sleep(.fromNanoseconds(remaining_delta), clock);

            // Re-calculate the final elapsed time using the updated time context
            elapsed = timestamp.untilNow(io, clock);
        }
    }

    // Capture the current timestamp to anchor the next frame's baseline.
    timestamp.* = clock.now(io);

    const elapsed_sec: f64 = @as(f64, @floatFromInt(elapsed.toNanoseconds())) / @as(f64, @floatFromInt(std.time.ns_per_s));
    return elapsed_sec;
}
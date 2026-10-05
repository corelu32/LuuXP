const std = @import("std");
const log = std.log.scoped(.Application);

allocator: std.mem.Allocator,
io: std.Io,

settings: struct {
    target_fps: ?f64 = 60,
    vsync_enabled: bool = false,
},

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
pub fn init(allocator: std.mem.Allocator, io: std.Io) @This() {

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
pub fn run(self: *@This(), callbacks: anytype) !void {
    try callbacks.onInit();

    while (true) {
        const delta = try self.syncFramerate();

        try callbacks.onUpdate(delta);
        try callbacks.onRender(delta);
    }

    try callbacks.onQuit();
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
            return error.InvalidFps;
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
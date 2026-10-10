const std = @import("std");
const native = @import("native.zig");
const util = @import("util.zig");

pub const IoRepoType = enum {
    Directory,
    ZipFile,
};

pub const IoRepoError = enum {
    InvalidPath,
    InitFailure,
};

const log = std.log.scoped(.IoRepo);

io: std.Io,
repo_type: IoRepoType,

/// Absolute path to the physical directory or ZIP file.
absolute_path: []const u8,

/// Initialize the IO repository as a physical parent directory or ZIP archive file.
/// Automatically initializes PhysFS if it hadn't been already.
pub fn init(io: std.Io, path: []const u8, repo_type: IoRepoType) !@This() {
    switch (repo_type) {
        .Directory => {
            const exists = try doesDirectoryExist();

            if (!exists) {
                log.err("The parent directory at '{s}' does not exist.", .{ path } );
                return IoRepoError.InvalidPath;
            }

            log.info("Initialized IO repository as physical directory '{s}'.", .{ path });
        },
        .ZipFile => {
            if (!native.c.PHYSFS_isInit()) {
                const result = native.c.PHYSFS_init(null);

                if (result == 0) {
                    log.err("Failed to initialize PhysFS.", .{ });
                    return IoRepoError.InitFailure;
                }
            }

            // If multiple archives are mounted and conflicting file names exist,
            // use APPEND_TO_PATH=0 to prioritize the most recently mounted file
            // (Prior files will be replaced!)
            const APPEND_TO_PATH = 0;
            const MOUNT_POINT = "/";

            var c_path = try native.AllocedCString.init(path);
            defer c_path.deinit();

            const result = native.c.PHYSFS_mount(c_path.value, MOUNT_POINT, APPEND_TO_PATH);

            if (result == 0) {
                log.err("Failed to mount the archive. PHYSFS error: {s}", .{ util.getPhysFSErrorMessage() });
                return IoRepoError.InitFailure;
            }
        }
    }

    return .{
        .io = io,
        .repo_type = repo_type,
        .absolute_path = path,
    };
}

/// Check if a directory exists or not.
fn doesDirectoryExist(io: std.Io, path: []const u8) !bool {

    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return false,
            error.AccessDenied => return true,
            else => return err
        }
    };

    dir.close(io);
    return true;
}
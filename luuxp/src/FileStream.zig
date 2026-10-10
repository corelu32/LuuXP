const std = @import("std");
const util = @import("util.zig");
const native = @import("native.zig");
const FileRepo = @import("FileRepo.zig");

pub const FileStreamError = error {
    InitFailure,
    FileNotFound,
    OperationFailed,
};

const log = std.log.scoped(.IoStream);

handle: *native.c.SDL_IOStream,

/// Open a file stream from a file repository.
pub fn open(file_repo: *FileRepo, relative_path: []const u8) !@This() {
    var sdl_stream: ?*native.c.SDL_IOStream = null;

    switch (file_repo.repo_type) {
        
        .ParentDirectory => {
            // Concatenate the relative path with the file repository's parent directory
            // using a stack-allocated buffer.
            var path_buffer: [4096]u8 = undefined;

            const path_concat: [:0]u8 = try std.fmt.bufPrintZ(&path_buffer, "{s}/{s}", .{
                file_repo.absolute_path,
                relative_path
            });

            sdl_stream = native.c.SDL_IOFromFile(path_concat.ptr);
        },
        .ZipFile => {

            var c_path = try native.AllocedCString.init(relative_path);
            defer c_path.deinit();

            // Ensure PhysFS was initialized.
            if (native.c.PHYSFS_isInit() == 0) {
                log.err("Failed to open archive because PhysFS was not initialized.", .{ });
                return FileStreamError.InitFailure;
            }

            // Ensure the file exists within the archive.
            if (native.c.PHYSFS_exists(c_path.value)) {
                log.err("The file path '{s}' does not exist in the archive.", .{ relative_path });
                return FileStreamError.FileNotFound;
            }

            // Open the file using PhysFS.
            const file = native.c.PHYSFS_openRead(c_path.value) orelse {
                log.err("PhysFS could not open the file '{s}'. PHYSFS error: {s}", .{ relative_path, util.getPhysFSErrorMessage() });
                return FileStreamError.FileNotFound;
            };

            // Open the stream using SDL's IO callback interface.
            sdl_stream = native.c.SDL_OpenIO(
                &native.c.SDL_IOStreamInterface {
                    .version = @sizeOf(native.c.SDL_IOStreamInterface),
                    .read    = SdlIoInterface.read,
                    .seek    = SdlIoInterface.seek,
                    .size    = SdlIoInterface.getSize,
                    .close   = SdlIoInterface.close,
                    .write   = null,
                    .flush   = null
                },
                file);
        }
    }

    const handle = sdl_stream orelse {
        log.err("Failed to load the file from relative path '{s}'.", .{ relative_path });
        return FileStreamError.FileNotFound;
    };

    return .{ .handle = handle };
}

/// Close the file stream.
pub fn close(self: *@This()) !void {
    const ok = native.c.SDL_CloseIO(self.handle);

    if (!ok) {
        log.err("Failed to close the file stream. SDL error: {s}", .{ native.c.SDL_GetError() });
        return FileStreamError.OperationFailed;
    }
}

/// Get the total number of bytes in the file stream.
pub fn getSize(self: *@This()) !u64 {
    const result = native.c.SDL_GetIOSize(self.handle);

    if (result < 0) {
        log.err("Failed to fetch the file stream size. SDL error: {s}", .{ native.c.SDL_GetError() });
        return FileStreamError.OperationFailed;
    }

    return @intCast(result);
}

/// Write N bytes from the file stream into the provided byte buffer.
pub fn writeToBuffer(self: *@This(), buffer: []u8, size: u64) !void {
    if (buffer.len > size) {
        log.err("The provided buffer cannot fit {} bytes from the file stream.", .{ size });
        return FileStreamError.OperationFailed;
    }

    const result = native.c.SDL_ReadIO(self.handle, buffer.ptr, size);

    if (result != size) {
        log.err("Failed to read all {} bytes from the file stream.", .{ size });
        return FileStreamError.OperationFailed;
    }
}

/// Interface functions allowing an SDL IO stream to operate on PhysFS files.
const SdlIoInterface = struct {

    fn read(userdata: ?*anyopaque, buffer: ?*anyopaque, size: usize, status: ?*native.c.SDL_IOStatus) callconv(.c) usize {
        
        // Interpret userdata as the PHYSFS file handle.
        const virt_file: ?*native.c.PHYSFS_File = if (userdata) |v| (
            @ptrCast(@alignCast(v))
        ) else null;

        const bytes_read: usize = @intCast(native.c.PHYSFS_readBytes(virt_file, buffer, size));

        if (bytes_read < 0) {
            log.err("Error reading bytes from stream. PHYSFS error: {s}", .{ util.getPhysFSErrorMessage() });
            
            if (status) |s|
                s.* = native.c.SDL_IO_STATUS_ERROR;
        }

        if (bytes_read < size)
        {
            if (status) |s| {
                if (native.c.PHYSFS_eof(virt_file) == 0) {
                    log.err("Error reading bytes from stream. PHYSFS error: {s}", .{ util.getPhysFSErrorMessage() });
                    s.* = native.c.SDL_IO_STATUS_ERROR;
                }
                else {
                    s.* = native.c.SDL_IO_STATUS_EOF;
                }
            }
        }

        return bytes_read;
    }

    fn seek(userdata: ?*anyopaque, offset: i64, whence: native.c.SDL_IOWhence) callconv(.c) i64 {
        
        // Interpret userdata as the PHYSFS file handle.
        const virt_file: ?*native.c.PHYSFS_File = if (userdata) |v| (
            @ptrCast(@alignCast(v))
        ) else null;

        var new_pos: native.c.PHYSFS_sint64 = 0;

        // Process SDL's 'whence object' as PhysFS commands.
        switch (whence) {
            native.c.SDL_IO_SEEK_SET => new_pos = offset,
            native.c.SDL_IO_SEEK_CUR => new_pos = native.c.PHYSFS_tell(virt_file) + offset,
            native.c.SDL_IO_SEEK_END => new_pos = native.c.PHYSFS_fileLength(virt_file) + offset,
            
            else => {
                log.err("Failed to seek within IO stream. PHYSFS error: {s}", .{ util.getPhysFSErrorMessage() });
                return -1;
            }
        }

        if (new_pos < 0) {
            log.err("Failed to seek within IO stream. PHYSFS error: {s}", .{ util.getPhysFSErrorMessage() });
            return -1;
        }
        
        if (native.c.PHYSFS_seek(virt_file, @intCast(new_pos)) == 0)
        {
            log.err("Failed to seek within IO stream. PHYSFS error: {s}", .{ util.getPhysFSErrorMessage() });
            return -1;
        }
        
        return new_pos;
    }

    fn getSize(userdata: ?*anyopaque) callconv(.c) i64 {
        
        // Interpret userdata as the PHYSFS file handle.
        const virt_file: ?*native.c.PHYSFS_File = if (userdata) |v| (
            @ptrCast(@alignCast(v))
        ) else null;

        const bytes = native.c.PHYSFS_fileLength(virt_file);

        return if (bytes < 0) -1 else bytes; 
    }

    fn close(userdata: ?*anyopaque) callconv(.c) bool {

        // Interpret userdata as the PHYSFS file handle.
        const virt_file: ?*native.c.PHYSFS_File = if (userdata) |v| (
            @ptrCast(@alignCast(v))
        ) else null;

        if (virt_file != null and native.c.PHYSFS_close(virt_file) == 0) {
            log.err("Error closing IO stream. PHYSFS error: {s}", .{ util.getPhysFSErrorMessage() });
            return false;
        }
        
        return true;
    }
};
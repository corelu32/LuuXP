const std = @import("std");
const native = @import("native.zig");

pub fn getPhysFSErrorMessage() []const u8 {
    const code = native.c.PHYSFS_getLastErrorCode();

    if (code == native.c.PHYSFS_ERR_OK) {
        return "Unknown.";
    }
    else {
        return std.mem.span(native.c.PHYSFS_getErrorByCode(code));
    }
}
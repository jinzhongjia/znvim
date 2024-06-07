//! this is for window's named pipe
//! more info:
//! https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/

const std = @import("std");
const windows = std.os.windows;
const LPCWSTR = windows.LPCWSTR;
const DWORD = windows.DWORD;
const LPDWORD = *DWORD;
const BOOL = windows.BOOL;
const HANDLE = windows.HANDLE;
const LPVOID = windows.LPVOID;
const WINAPI = windows.WINAPI;

/// Waits until either a time-out interval elapses or an instance of the specified named pipe is available for connection
/// (that is, the pipe's server process has a pending ConnectNamedPipe operation on the pipe).
extern "kernel32" fn WaitNamedPipeW(
    lpNamedPipeName: LPCWSTR,
    nTimeOut: DWORD,
) callconv(WINAPI) BOOL;

/// Copies data from a named or anonymous pipe into a buffer
/// without removing it from the pipe.
/// It also returns information about data in the pipe.
extern "kernel32" fn PeekNamedPipe(
    hNamedPipe: HANDLE,
    lpBuffer: ?LPVOID,
    nBufferSize: DWORD,
    lpBytesRead: ?LPDWORD,
    lpTotalBytesAvail: ?LPDWORD,
    lpBytesLeftThisMessage: ?LPDWORD,
) callconv(WINAPI) BOOL;

const CheckNamePipeResult = union(enum) {
    win_error: windows.Win32Error,
    result: bool,
};

/// check named pipe is available
pub fn checkNamePipeData(pipe: std.fs.File) CheckNamePipeResult {
    var bytesAvailable: DWORD = undefined;
    const result = PeekNamedPipe(
        pipe.handle,
        null,
        0,
        null,
        &bytesAvailable,
        null,
    );
    if (result == windows.TRUE) {
        return CheckNamePipeResult{
            .result = bytesAvailable > 0,
        };
    }
    return CheckNamePipeResult{
        .win_error = windows.kernel32.GetLastError(),
    };
}

/// this function will try to connect named pipe on windows
/// no need to free the mem
pub fn connectNamedPipe(path: []const u8, allocator: std.mem.Allocator) !std.fs.File {
    // use 256 * 2 bytes
    var stack_alloc = std.heap.stackFallback(256 * @sizeOf(u16), allocator);
    const stack_allocator = stack_alloc.get();

    var arena = std.heap.ArenaAllocator.init(stack_allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();

    // convert utf8 to utf16
    const utf16_path = try std.unicode.utf8ToUtf16LeWithNull(arena_allocator, path);
    // try to connect named pipe
    const handle = windows.kernel32.CreateFileW(
        utf16_path,
        windows.GENERIC_READ | windows.GENERIC_WRITE,
        0,
        null,
        windows.OPEN_EXISTING,
        0,
        null,
    );
    if (handle == windows.INVALID_HANDLE_VALUE) {
        return windows.unexpectedError(windows.kernel32.GetLastError());
    }

    return std.fs.File{
        .handle = handle,
    };
}

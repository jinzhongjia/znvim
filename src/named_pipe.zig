//! this is for window's named pipe
//! more info:
//! https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/

const std = @import("std");
const windows = std.os.windows;
const LPCWSTR = windows.LPCWSTR;
const DWORD = windows.DWORD;
const BOOL = windows.BOOL;
const WINAPI = windows.WINAPI;

/// Waits until either a time-out interval elapses or an instance of the specified named pipe is available for connection
/// (that is, the pipe's server process has a pending ConnectNamedPipe operation on the pipe).
pub extern "kernel32" fn WaitNamedPipeW(
    lpNamedPipeName: LPCWSTR,
    nTimeOut: DWORD,
) callconv(WINAPI) BOOL;

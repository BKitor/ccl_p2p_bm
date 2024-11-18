const c = @cImport({
    @cDefine("__HIP_PLATFORM_AMD__", {}); // make build flag for Green systems
    @cInclude("nccl.h");
    @cInclude("hip/hip_runtime_api.h");
});

pub const CCL_VERSION_CODE = c.NCCL_VERSION_CODE;
pub const cclComm_t = c.ncclComm_t;

pub fn devGetDeviceCount() !usize {
    var dev_count: c_int = -1;
    var hipe: c.hipError_t = c.hipSuccess;
    hipe = c.hipGetDeviceCount(&dev_count);
    if (hipe != c.hipSuccess or dev_count < 0) {
        return error.devGetDeviceCount;
    }
    return @intCast(dev_count);
}

pub fn devSetDevice(devid: usize) !void {
    const hipe = c.hipSetDevice(@intCast(devid));
    if (hipe != c.hipSuccess) {
        return error.devSetDevice;
    }
}

pub const devStream_t = c.hipStream_t;
pub fn devStreamCreate() !devStream_t {
    var stream: devStream_t = undefined;
    const hipe = c.hipStreamCreate(&stream);
    if (hipe != c.hipSuccess) {
        return error.devStreamCreate;
    }
    return stream;
}

pub fn devStreamDestroy(stream: devStream_t) !void {
    const hipe = c.hipStreamDestroy(stream);
    if (hipe != c.hipSuccess) {
        return error.devStreamDestroy;
    }
}

pub fn devStreamSyncronize(stream: devStream_t) !void {
    const hipe = c.hipStreamSynchronize(stream);
    if (hipe != c.hipSuccess) {
        return error.devStreamDestroy;
    }
}

pub fn devStreamQuery(stream: devStream_t) !bool {
    const hipe = c.hipStreamQuery(stream);
    if (hipe == c.hipSuccess) {
        return true;
    } else if (hipe == c.hipErrorNotReady) {
        return false;
    } else {
        return error.devStreamQuery;
    }
}

pub fn devStreamGetDevice(stream: devStream_t) !usize {
    var device: c_int = undefined;
    const hipe = c.hipStreamGetDevice(stream, &device);
    if (hipe != c.hipSuccess) {
        return error.devStreamGetDevice;
    }
    return device;
}

pub fn cclCommInitAll(comms: []cclComm_t, ndev: usize) !void {
    var nccle: c.ncclResult_t = c.ncclSuccess;

    nccle = c.ncclCommInitAll(@ptrCast(comms), @intCast(ndev), null);
    if (nccle != c.ncclSuccess) {
        return error.cclCommInitAll;
    }
}

pub fn cclCommDestroy(comm: cclComm_t) !void {
    const nccle = c.ncclCommDestroy(comm);
    if (nccle != c.ncclSuccess) {
        return error.cclCommDestroy;
    }
}

pub fn cclCommCuDevice(comm: cclComm_t) !usize {
    var devid: c_int = undefined;
    const nccle = c.ncclCommCuDevice(comm, &devid);
    if (nccle != c.ncclSuccess or devid < 0) {
        return error.cclCommDevice;
    }
    return @intCast(devid);
}

pub fn cclMemAlloc(comptime T: type, nelem: usize) ![]T {
    var ptr: [*]T = undefined;
    const nccle = c.ncclMemAlloc(@ptrCast(&ptr), nelem * @sizeOf(T));
    if (nccle != c.ncclSuccess) {
        return error.cclMemAlloc;
    }
    return ptr[0..nelem];
}

pub fn cclMemFree(ptr: anytype) !void {
    const nccle = c.ncclMemFree(@ptrCast(ptr));
    if (nccle != c.ncclSuccess) {
        return error.cclMemFree;
    }
}

fn ncclType(comptime T: type) c.ncclDataType_t {
    if (T == u8) {
        return c.ncclUint8;
    }
}

pub fn cclGroupStart() !void {
    const nccle = c.ncclGroupStart();
    if (nccle != c.ncclSuccess) {
        return error.cclGroupStart;
    }
}

pub fn cclGroupEnd() !void {
    const nccle = c.ncclGroupEnd();
    if (nccle != c.ncclSuccess) {
        return error.cclGroupEnd;
    }
}

pub fn cclSend(comptime T: type, sendbuff: []T, comm: cclComm_t, dst: usize, stream: devStream_t) !void {
    const nccle = c.ncclSend(@ptrCast(sendbuff), sendbuff.len, ncclType(T), @intCast(dst), comm, stream);
    if (nccle != c.ncclSuccess) {
        return error.cclSend;
    }
}

pub fn cclRecv(comptime T: type, recvbuf: []T, comm: cclComm_t, src: usize, stream: devStream_t) !void {
    const nccle = c.ncclRecv(@ptrCast(recvbuf), recvbuf.len, ncclType(T), @intCast(src), comm, stream);
    if (nccle != c.ncclSuccess) {
        return error.cclRecv;
    }
}

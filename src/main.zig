const std = @import("std");
const c = @import("ccl.zig");

const ca = std.heap.c_allocator;

fn cleq(ctx: void, l: f64, r: f64) bool {
    _ = ctx;
    return l <= r;
}

const BMRes = struct {
    min: f64,
    max: f64,
    median: f64,
    avg: f64,
};

const Barrier = struct {
    const Self = @This();
    s1: std.Thread.Semaphore,
    s2: std.Thread.Semaphore,
    c: std.atomic.Value(usize),
    nthreads: usize,
    fn init(nthreads: usize) Self {
        return Self{
            .s1 = std.Thread.Semaphore{ .permits = 0 },
            .s2 = std.Thread.Semaphore{ .permits = 1 },
            .c = std.atomic.Value(usize).init(0),
            .nthreads = nthreads,
        };
    }
    fn sync(self: *Self) void {
        var cnt = self.c.fetchAdd(1, std.builtin.AtomicOrder.monotonic) + 1;
        if (cnt == self.nthreads) {
            self.s2.wait();
            self.s1.post();
        }
        self.s1.wait();
        self.s1.post();

        cnt = self.c.fetchSub(1, std.builtin.AtomicOrder.monotonic) - 1;
        if (cnt == 0) {
            self.s1.wait();
            self.s2.post();
        }
        self.s2.wait();
        self.s2.post();
    }
};

fn calc_bw(latencies: []f64, msize: usize) BMRes {
    std.mem.sort(f64, latencies, {}, comptime std.sort.asc(f64));
    const nlatencies_f = @as(f64, @floatFromInt(latencies.len));
    const msize_f = @as(f64, @floatFromInt(msize));
    var avg: f64 = 0;
    for (latencies) |m| {
        avg += m / nlatencies_f;
    }

    const ret: BMRes = .{
        .max = msize_f / latencies[0],
        .min = msize_f / latencies[latencies.len - 1],
        .median = msize_f / latencies[(latencies.len - 1) / 2],
        .avg = msize_f / avg,
    };
    return ret;
}

const BMConfig = struct { nitters: usize, nwarmups: usize, msize: usize, ndevs: usize, comm: c.cclComm_t, barrier: *Barrier };

fn bm_uni_bw(sendbuff: []u8, recvbuff: []u8, src: usize, dst: usize, devid: usize, bmcfg: BMConfig, stream: c.devStream_t) !BMRes {
    const msize = bmcfg.msize;
    const comm = bmcfg.comm;
    const sender = devid == src;
    const receiver = devid == dst;

    if (!(sender or receiver)) {
        return error.NotParticipating;
    }

    var latencies = std.ArrayList(f64).init(ca);
    defer latencies.deinit();
    for (0..bmcfg.nitters + bmcfg.nwarmups) |itter| {
        var timer = try std.time.Timer.start();
        try c.devStreamSyncronize(stream);
        try c.cclGroupStart();
        if (sender) {
            try c.cclSend(u8, sendbuff[0..msize], comm, dst, stream);
        } else {
            try c.cclRecv(u8, recvbuff[0..msize], comm, src, stream);
        }
        try c.cclGroupEnd();
        try c.devStreamSyncronize(stream);
        const tf = timer.lap(); // tf in nanosecs
        if (itter >= bmcfg.nwarmups) {
            try latencies.append(@as(f64, @as(f64, @floatFromInt(tf)))); // GB/s
        }
    }

    return calc_bw(latencies.items, msize);
}

fn thread_fn(bmcfg: BMConfig, results: []BMRes) !void {
    const comm = bmcfg.comm;
    const msize = bmcfg.msize;
    const ndevs = bmcfg.ndevs;
    const devid = try c.cclCommCuDevice(comm);
    try c.devSetDevice(devid);

    const stream = try c.devStreamCreate();
    const sendbuff = try c.cclMemAlloc(u8, msize);
    const recvbuff = try c.cclMemAlloc(u8, msize);

    for (0..ndevs) |sender| {
        for (0..ndevs) |receiver| {
            if (sender == receiver) {
                continue;
            }
            if (devid == sender or devid == receiver) {
                const idx = sender * ndevs + receiver;
                const res = try bm_uni_bw(sendbuff, recvbuff, sender, receiver, devid, bmcfg, stream);
                if (devid == sender) {
                    results[idx] = res;
                    std.debug.print("sender: {}, receiver: {} median: {}\n", .{ sender, receiver, results[idx].median });
                }
            }
            bmcfg.barrier.sync();
        }
    }

    try c.cclMemFree(sendbuff);
    try c.cclMemFree(recvbuff);

    try c.devStreamDestroy(stream);
    try c.cclCommDestroy(comm);
}

// The format string must be comptime-known and may contain placeholders following this format: {[argument][specifier]:[fill][alignment][width].[precision]}
pub fn print_results(results: []BMRes, ndevs: usize) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("{s: <10}", .{""});
    for (0..ndevs) |d| {
        try stdout.print("R{: <10}", .{d});
    }
    try stdout.print("\n", .{});
    for (0..ndevs) |s| {
        try stdout.print("S{: <3} ", .{s});
        for (0..ndevs) |r| {
            try stdout.print("{d: >6.2}GB/s ", .{results[s * ndevs + r].median});
        }
        try stdout.print("\n", .{});
    }
    try bw.flush(); // don't forget to flush!
}

pub fn main() !void {
    std.debug.print("test nccl_version: {}\n", .{c.CCL_VERSION_CODE});

    const ndevs = try c.devGetDeviceCount();
    const comms = try ca.alloc(c.cclComm_t, ndevs);
    defer ca.free(comms);
    try c.cclCommInitAll(comms, ndevs);
    std.debug.print("initialized library\n", .{});

    var tlst = std.ArrayList(std.Thread).init(ca);
    var b = Barrier.init(ndevs);
    const results = try ca.alloc(BMRes, ndevs * ndevs);
    defer ca.free(results);
    for (0..ndevs * ndevs) |i| {
        results[i] = std.mem.zeroInit(BMRes, .{});
    }
    for (0..ndevs) |i| {
        const sc: std.Thread.SpawnConfig = .{ .allocator = ca };
        const bmcfg: BMConfig = .{
            .nwarmups = 1,
            .nitters = 10,
            .msize = 1 << 25,
            .ndevs = ndevs,
            .comm = comms[i],
            .barrier = &b,
        };
        try tlst.append(try std.Thread.spawn(sc, thread_fn, .{ bmcfg, results }));
    }

    for (tlst.items) |t| {
        t.join();
    }

    try print_results(results, ndevs);
}

test "sample_test" {
    std.debug.print("Nothing here yet", .{});
    try std.testing.expect(true);
}

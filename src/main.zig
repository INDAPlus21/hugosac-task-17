
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const ArenaAllocator = struct {
    underlying: Allocator,
    buffers: std.SinglyLinkedList([]u8),
    end_index: usize,

    const BufNode = std.SinglyLinkedList([]u8).Node;

    pub fn allocator(self: *ArenaAllocator) Allocator {
        return Allocator.init(self, alloc, resize, free);
    }

    pub fn init(underlying: Allocator) ArenaAllocator {
        return ArenaAllocator {
            .underlying = underlying,
            .buffers = @as(std.SinglyLinkedList([]u8), .{}),
            .end_index = 0,
        };
    }

    pub fn deinit(self: ArenaAllocator) void {
        var buffer = self.buffers.first;
        while (buffer) |first| {
            const next = first.next;
            self.underlying.free(first.data);
            buffer = next;
        }
    }

    fn newBufNode(self: *ArenaAllocator, prev_len: usize, requested_size: usize) !*BufNode {
        const new_len = @maximum(prev_len * 2, requested_size);
        const new_buffer = try self.underlying.alloc(u8, new_len);
        const buf_node = @ptrCast(*BufNode, @alignCast(@alignOf(BufNode), new_buffer.ptr));
        buf_node.* = BufNode {
            .data = new_buffer,
            .next = null,
        };

        self.buffers.prepend(buf_node);
        self.end_index = 0;
        return buf_node;
    }

    pub fn alloc(self: *ArenaAllocator, size: usize, ptr_align: u29, len_align: u29, ret_addr: usize) ![]u8 {
        _ = len_align;
        _ = ret_addr;

        var buf_node = if (self.buffers.first == null) try self.newBufNode(2048, size) else self.buffers.first;

        while (true) {
            const buffer = buf_node.?.data[@sizeOf(BufNode)..];

            const aligned_ptr = std.mem.alignForward(@ptrToInt(buffer.ptr) + self.end_index, ptr_align);
            
            // Index in the buffer of the aligned pointer
            const aligned_index = aligned_ptr - @ptrToInt(buffer.ptr);

            // End index of the allocation
            const new_end_index = aligned_index + size;

            if (new_end_index <= buffer.len) {
                self.end_index = new_end_index;
                return buffer[aligned_index..new_end_index];
            }

            // No buffer is big enough. Allocate a new one.
            buf_node = try self.newBufNode(buffer.len, size);
        }
    }

    // Can't resize
    fn resize(self: *ArenaAllocator, buf: []u8, buf_align: u29, new_size: usize, len_align: u29, ret_addr: usize) ?usize {
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = new_size;
        _ = len_align;
        _ = ret_addr;
        return 0;
    }

    // Can't free memory
    fn free(self: *ArenaAllocator, buf: []u8, buf_align: u29, ret_addr: usize) void {
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
    }
};

test "arena allocator test" {
    var arena_allocator = ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const allocator = arena_allocator.allocator();

    const arr = try allocator.alloc(u8, 500);
    assert(arr.len == 500);

    const arr_2 = try allocator.alloc(u32, 100);
    assert(arr_2.len == 100);

    const arr_3 = try allocator.alloc(u94, 300);
    assert(std.mem.sliceAsBytes(arr_3).len == @sizeOf(u94) * 300);
}
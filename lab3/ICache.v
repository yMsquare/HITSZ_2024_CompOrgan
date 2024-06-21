`timescale 1ns / 1ps

// `define BLK_LEN  4
// `define BLK_SIZE (`BLK_LEN*32)

module ICache(
    input  wire         cpu_clk,
    input  wire         cpu_rst,        // high active
    // Interface to CPU
    input  wire         inst_rreq,      // 来自CPU的取指请求
    input  wire [31:0]  inst_addr,      // 来自CPU的取指地址
    output reg          inst_valid,     // 输出给CPU的指令有效信号（读指令命中）
    output reg  [31:0]  inst_out,       // 输出给CPU的指令
    // Interface to Read Bus
    input  wire         mem_rrdy,       // 主存就绪信号（高电平表示主存可接收ICache的读请求
    output reg  [ 3:0]  mem_ren,        // 输出给主存的读使能信号
    output reg  [31:0]  mem_raddr,      // 输出给主存的读地址
    input  wire         mem_rvalid,     // 来自主存的数据有效信号
    input  wire [`BLK_SIZE-1:0] mem_rdata   // 来自主存的读数据
);

`ifdef ENABLE_ICACHE    /******** 不要修改此行代码 ********/
    localparam TAG_WIDTH = 5;
    localparam INDEX_WIDTH = 6;
    localparam OFFSET_WIDTH = 4;
    localparam CACHE_LINES = 64;

    reg [TAG_WIDTH:0] cache_tags [0:CACHE_LINES-1];

    wire [TAG_WIDTH-1:0] tag_from_cpu = inst_addr[14:15-TAG_WIDTH];
    wire [OFFSET_WIDTH-1:0] offset = inst_addr[OFFSET_WIDTH-1:0];
    wire [INDEX_WIDTH-1:0] cache_index = inst_addr[INDEX_WIDTH + OFFSET_WIDTH-1:OFFSET_WIDTH];
    wire valid_bit = cache_tags[cache_index][TAG_WIDTH];
    wire [TAG_WIDTH-1:0] tag_from_cache = cache_tags[cache_index][TAG_WIDTH-1:0];

    wire cache_we = mem_rvalid;
    wire [127:0] cache_line_w = mem_rdata;
    wire [127:0] cache_line_r;

    reg [1:0] IDLE = 2'b00, TAG_CHECK = 2'b01, REFILL = 2'b10, WAIT = 2'b11;
    reg [1:0] cur_state, next_state;

    wire hit = valid_bit && (tag_from_cache == tag_from_cpu);

    always @(*) begin
        //inst_valid = hit;
        inst_out = (offset[OFFSET_WIDTH-1:OFFSET_WIDTH-2] == 2'b00) ? cache_line_r[31:0] :
                   (offset[OFFSET_WIDTH-1:OFFSET_WIDTH-2] == 2'b01) ? cache_line_r[63:32] :
                   (offset[OFFSET_WIDTH-1:OFFSET_WIDTH-2] == 2'b10) ? cache_line_r[95:64] :
                   cache_line_r[127:96];
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin: RESET_LOGIC
        integer i;
        if (cpu_rst) begin
            for (i = 0; i < CACHE_LINES; i = i + 1) begin
                cache_tags[i] <= 0;
            end
        end
    end

    //
    blk_mem_gen_1 U_isram (
        .clka   (cpu_clk),    // in
        .wea    (cache_we),   // in
        .addra  (cache_index),// in
        .dina   (cache_line_w),// in
        .douta  (cache_line_r)// out
    );

    // 
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cur_state <= IDLE;
        end else begin
            cur_state <= next_state;
        end
    end

    // 
    always @(*) begin
        case (cur_state)
            IDLE: begin
                if (inst_rreq) begin
                    next_state = TAG_CHECK;
                end else begin
                    next_state = IDLE;
                end
            end
            TAG_CHECK: begin
                if (hit) begin
                    next_state = WAIT;
                end else if (mem_rrdy) begin
                    next_state = REFILL;
                end else begin
                    next_state = TAG_CHECK;
                end
            end
            REFILL: begin
                if (mem_rvalid) begin
                    next_state = WAIT;
                end else begin
                    next_state = REFILL;
                end
            end
            WAIT:begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // 
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            mem_ren <= 4'h0;
            mem_raddr <= 32'b0;
            inst_valid <= 1'b0;
        end else begin
            case (cur_state)
                IDLE: begin
                    mem_ren <= 4'h0;
                    mem_raddr <= inst_rreq ? inst_addr : 32'h0;
                    inst_valid <= 1'b0;
                end
                TAG_CHECK: begin
                    if (hit) begin
                        mem_ren <= 4'h0;
                        mem_raddr <= 32'h0;
                        inst_valid <= 1'b0;
                    end else if (mem_rrdy) begin
                        mem_ren <= 4'hF;
                        mem_raddr <= {tag_from_cpu, cache_index, 4'b0000};
                        inst_valid <= 1'b0;
                    end
                end
                REFILL: begin
                    if (mem_rvalid) begin
                        inst_valid = 1'b0;
                        cache_tags[cache_index] <= {1'b1, tag_from_cpu};
                    end
                    mem_ren <= 4'h0;
                end
                WAIT:begin
                    inst_valid  <= 1'b1;
                end
                default: begin
                    inst_valid <= 1'b0;
                    mem_ren <= 4'h0;
                end
            endcase
        end
    end


`else

    localparam IDLE = 2'b00;
    localparam STAT0 = 2'b01;
    localparam STAT1 = 2'b11;
    reg [1:0] state, nstat;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        state <= cpu_rst ? IDLE : nstat;
    end

    always @(*) begin
        case (state)
            IDLE:    nstat = inst_rreq ? (mem_rrdy ? STAT1 : STAT0) : IDLE;
            STAT0:   nstat = mem_rrdy ? STAT1 : STAT0;
            STAT1:   nstat = mem_rvalid ? IDLE : STAT1;
            default: nstat = IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            inst_valid <= 1'b0;
            mem_ren <= 4'h0;
        end else begin
            case (state)
                IDLE: begin
                    inst_valid <= 1'b0;
                    mem_ren <= (inst_rreq & mem_rrdy) ? 4'hF : 4'h0;
                    mem_raddr <= inst_rreq ? inst_addr : 32'h0;
                end
                STAT0: begin
                    mem_ren <= mem_rrdy ? 4'hF : 4'h0;
                end
                STAT1: begin
                    mem_ren <= 4'h0;
                    inst_valid <= mem_rvalid ? 1'b1 : 1'b0;
                    inst_out <= mem_rvalid ? mem_rdata[31:0] : 32'h0;
                end
                default: begin
                    inst_valid <= 1'b0;
                    mem_ren <= 4'h0;
                end
            endcase
        end
    end

`endif

endmodule

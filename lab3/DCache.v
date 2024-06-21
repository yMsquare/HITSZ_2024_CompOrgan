`timescale 1ns / 1ps

// `define BLK_LEN  4
// `define BLK_SIZE (`BLK_LEN*32)

module DCache(
    input  wire         cpu_clk,
    input  wire         cpu_rst,        // high active
    // Interface to CPU
    input  wire [ 3:0]  data_ren,       // 来自CPU的读使能信号
    input  wire [31:0]  data_addr,      // 来自CPU的地址（读、写共用）
    output reg          data_valid,     // 输出给CPU的数据有效信号
    output reg  [31:0]  data_rdata,     // 输出给CPU的读数据
    input  wire [ 3:0]  data_wen,       // 来自CPU的写使能信号
    input  wire [31:0]  data_wdata,     // 来自CPU的写数据
    output reg          data_wresp,     // 输出给CPU的写响应（高电平表示DCache已完成写操作）
    // Interface to Write Bus
    input  wire         dev_wrdy,       // 主存的写就绪信号（高电平表示主存可接收DCache的写请求）
    output reg  [ 3:0]  dev_wen,        // 输出给主存的写使能信号
    output reg  [31:0]  dev_waddr,      // 输出给主存的写地址
    output reg  [31:0]  dev_wdata,      // 输出给主存的写数据
    // Interface to Read Bus
    input  wire         dev_rrdy,       // 主存的读就绪信号（高电平表示主存可接收DCache的读请求）
    output reg  [ 3:0]  dev_ren,        // 输出给主存的读使能信号
    output reg  [31:0]  dev_raddr,      // 输出给主存的读地址
    input  wire         dev_rvalid,     // 来自主存的数据有效信号
    input  wire [`BLK_SIZE-1:0] dev_rdata   // 来自主存的读数据
);

    // Peripherals access should be uncached.
    wire uncached = (data_addr[31:16] == 16'hFFFF) & (data_ren != 4'h0 | data_wen != 4'h0) ? 1'b1 : 1'b0;

`ifdef ENABLE_DCACHE    /******** 不要修改此行代码 ********/
    localparam TAG_WIDTH = 5;
    localparam INDEX_WIDTH = 6;
    localparam OFFSET_WIDTH = 4;
    localparam CACHE_LINES = 64;

    reg [TAG_WIDTH:0] cache_tags [0:CACHE_LINES-1];//标签表

    wire [INDEX_WIDTH-1:0] cache_index = data_addr[INDEX_WIDTH + OFFSET_WIDTH-1:OFFSET_WIDTH];//cacheline 索引

    wire [TAG_WIDTH-1:0] tag_from_cpu   = data_addr[14:15-TAG_WIDTH];    // 主存地址的TAG
    wire [OFFSET_WIDTH-1:0] offset         = data_addr[OFFSET_WIDTH-1:0];    // 32位字偏移量
    wire       valid_bit      = cache_tags[cache_index][TAG_WIDTH];    // Cache行的有效位
    wire [TAG_WIDTH-1:0] tag_from_cache = cache_tags[cache_index][TAG_WIDTH-1:0];    // Cache行的TAG

    // TODO: 定义DCache读状态机的状态变量

    reg [3:0] IDLE_R=4'b0000,TAG_CHECK_R=4'b0001,WAIT_R = 4'b0010,REFILL_R = 4'b0011,UNCACHED_READ = 4'b1000;
    reg [3:0] IDLE_W = 4'b0100, TAG_CHECK_W = 4'B0101,WRITE_BACK = 4'b0110,ALLOCATE = 4'b0111,UNCACHED_WRITE = 4'b1001,WAIT_W = 4'b1010,HIT_W = 4'b1011;   
    reg [3:0] WRITE_BACK1 = 4'b1100,WRITE_BACK2 = 4'b1101,WRITE_BACK3 = 4'B1110;
    reg [3:0] cur_state_r, next_state_r;
    reg [3:0] cur_state_w, next_state_w;

    wire hit_r = (dev_ren!=0 || ren_reg != 0 )&&(tag_from_cache == tag_from_cpu)&&(valid_bit)&&(!uncached);        // 读命中
    wire hit_w = (dev_wen!=0 || wen_reg !=0)&&(tag_from_cache == tag_from_cpu)&&(valid_bit)&&(!uncached);        // 写命中


    reg [31:0] rdata_reg;
    reg [3:0] ren_reg;

    always @(*) begin
        //data_valid = hit_r;
        data_rdata = rdata_reg; /* TODO: 根据字偏移，选择Cache行中的某个32位字输出数据 (需要考虑写使能的有效字节位)*/; 
    end



    wire       cache_we    = (hit_w)&&(cur_state_w == HIT_W) || dev_rvalid;     // DCache存储体的写使能信号，可以是mem_rrdy,也可以是写命中后直接写入，hit_w && data_wen!=0 ,
    
    reg [127:0] cache_line_to_be_written;
    wire [127:0] cache_line_w = (cur_state_w == HIT_W)?(cache_line_to_be_written):dev_rdata;
    //(dev_rvalid)?(dev_rdata):(hit_w)?cache_line_w_from_dev;
    
    
    // 待写入DCache的Cache行,可以是CPU的数据，也可以是来自主存的数据
    wire [127:0] cache_line_r;                  // 从DCache读出的Cache行


    reg [31:0] wdata;


    reg [CACHE_LINES-1:0] dirty;//脏标志位


    // DCache存储体：Block RAM IP核
    blk_mem_gen_1 U_dsram (
        .clka   (cpu_clk),
        .wea    (cache_we),
        .addra  (cache_index),
        .dina   (cache_line_w),
        .douta  (cache_line_r)
    );
    always @(posedge cpu_clk or posedge cpu_rst) begin: RESET_LOGIC
        integer i;
        if (cpu_rst) begin
            for (i = 0; i < CACHE_LINES; i = i + 1) begin
                cache_tags[i] <= 0;
                dirty[i] <= 0;
            end
        end
    end


    always @(*)begin
        if(cpu_rst)begin
            wdata = 32'h0;
        end
        else if(data_wen!= 0)begin
            wdata = data_wdata;
        end
    end

    always @(*)begin
        if(cpu_rst)begin
            rdata_reg = 32'h0;
        end
        else begin
            case(offset[OFFSET_WIDTH-1:OFFSET_WIDTH-2])
            2'b00:begin
                case(ren_reg)
                4'b0001:rdata_reg = cache_line_r[7:0];
                4'b0011:rdata_reg = cache_line_r[15:0];
                4'b1111:rdata_reg = cache_line_r[31:0];
                endcase
            end
            2'b01:begin
                case(ren_reg)
                4'b0001:rdata_reg = cache_line_r[39:32];
                4'b0011:rdata_reg = cache_line_r[47:32];
                4'b1111:rdata_reg = cache_line_r[63:32];
                endcase
            end
            2'b10:begin
                case(ren_reg)
                4'b0001:rdata_reg = cache_line_r[71:64];
                4'b0011:rdata_reg = cache_line_r[79:64];
                4'b1111:rdata_reg = cache_line_r[95:64];
                endcase
            end
            2'b11:begin
                case(ren_reg)
                4'b0001:rdata_reg = cache_line_r[103:96];
                4'b0011:rdata_reg = cache_line_r[111:96];
                4'b1111:rdata_reg = cache_line_r[127:96];
                endcase
            end
            endcase
        end
    end


    always @(*)begin
        if(cpu_rst)begin
            cache_line_to_be_written = 128'h0;
        end
        else begin
            case(offset[OFFSET_WIDTH-1:OFFSET_WIDTH-2])
            2'b00:begin
                case(wen_reg)
                4'b0001:cache_line_to_be_written = {cache_line_r[127:8],wdata[7:0]};
                4'b0011:cache_line_to_be_written = {cache_line_r[127:16],wdata[15:0]};
                4'b1111:cache_line_to_be_written = {cache_line_r[127:32],wdata[31:0]};
                endcase
            end
            2'b01:begin
                case(wen_reg)
                4'b0001:cache_line_to_be_written = {cache_line_r[127:40],wdata[7:0],cache_line_r[31:0]};
                4'b0011:cache_line_to_be_written = {cache_line_r[127:48],wdata[15:0],cache_line_r[31:0]};
                4'b1111:cache_line_to_be_written = {cache_line_r[127:64],wdata[31:0],cache_line_r[31:0]};
                endcase
            end
            2'b10:begin
                case(wen_reg)
                4'b0001:cache_line_to_be_written = {cache_line_r[127:72],wdata[7:0],cache_line_r[63:0]};
                4'b0011:cache_line_to_be_written = {cache_line_r[127:80],wdata[15:0],cache_line_r[63:0]};
                4'b1111:cache_line_to_be_written = {cache_line_r[127:96],wdata[31:0],cache_line_r[63:0]};
                endcase
            end
            2'b11:begin
                case(wen_reg)
                4'b0001:cache_line_to_be_written = {cache_line_r[127:104],wdata[7:0],cache_line_r[95:0]};
                4'b0011:cache_line_to_be_written = {cache_line_r[127:112],wdata[15:0],cache_line_r[95:0]};
                4'b1111:cache_line_to_be_written = {wdata[31:0],cache_line_r[95:0]};
                endcase
            end
            endcase
        end
    end

    // TODO: 编写DCache读状态机现态的更新逻辑
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cur_state_r <= IDLE_R;
        end else begin
            cur_state_r <= next_state_r;
        end
    end


    // TODO: 编写DCache读状态机的状态转移逻辑（注意处理uncached访问）
    always @(*) begin
        case (cur_state_r)
            IDLE_R: begin
                if(uncached && data_ren!=0)begin
                    next_state_r = UNCACHED_READ;
                end
                else if (data_ren!=0) begin
                    next_state_r = TAG_CHECK_R;
                end else begin
                    next_state_r = IDLE_R;
                end
            end
            TAG_CHECK_R: begin
                if (hit_r) begin
                    next_state_r = WAIT_R;
                end else if (dev_rrdy) begin
                    next_state_r = REFILL_R;
                end else begin
                    next_state_r = TAG_CHECK_R;
                end
            end
            REFILL_R: begin
                if (dev_rvalid) begin
                    next_state_r = WAIT_R;
                end else begin
                    next_state_r = REFILL_R;
                end
            end
            WAIT_R:begin
                next_state_r = IDLE_R;
            end
            UNCACHED_READ: begin
            if (dev_rvalid) begin
                next_state_r = WAIT_R;
            end else begin
                next_state_r = UNCACHED_READ;
            end
        end
            default: next_state_r = IDLE_R;
        endcase
    end



    // TODO: 生成DCache读状态机的输出信号
 always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            dev_ren <= 4'h0;
            dev_raddr <= 32'b0;
            data_valid <= 1'b0;
            ren_reg <= 0;
        end else begin
            case (cur_state_r)
            
                IDLE_R: begin
                    if(hit_r)begin
                        dev_ren <= 4'h0;
                        dev_raddr <= 32'h0;
                        data_valid <= 1'b0;
                    end
                    else begin
                    dev_ren <= 4'h0;
                    dev_raddr <= dev_ren!=0 ? data_addr : 32'h0;
                    data_valid <= 1'b0;
                    ren_reg <= data_ren;
                    end
                end
                TAG_CHECK_R: begin
                    if (hit_r) begin
                        dev_ren <= 4'h0;
                        dev_raddr <= 32'h0;
                        data_valid <= 1'b0;
                    end else if (!hit_r && dev_rrdy) begin
                        dev_ren <= 4'hF;
                        dev_raddr <= {tag_from_cpu, cache_index, 4'b0000};
                        data_valid <= 1'b0;
                    end
                end
                REFILL_R: begin
                    if (dev_rvalid) begin
                        data_valid = 1'b0;
                        cache_tags[cache_index] <= {1'b1, tag_from_cpu};
                    end
                    dev_ren <= 4'h0;
                end
                WAIT_R:begin
                    data_valid  <= 1'b1;
                    
                end
                UNCACHED_READ: begin
                    dev_ren <= data_ren;
                    dev_raddr <= data_addr;
                    if (dev_rvalid) begin
                        data_rdata <= dev_rdata[31:0]; // Assuming a 32-bit data word is required
                        data_valid <= 1'b1;
                        dev_ren <= 4'h0;
                    end
            end
                default: begin
                    data_valid <= 1'b0;
                    dev_ren <= 4'h0;
                end
            endcase
        end
    end




    ///////////////////////////////////////////////////////////
    // TODO: 定义DCache写状态机的状态变量
    // TODO: 编写DCache写状态机的现态更新逻辑


    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cur_state_w <= IDLE_W;
        end else begin
            cur_state_w <= next_state_w;
        end
    end

    // TODO: 编写DCache写状态机的状态转移逻辑（注意处理uncached访问）
    always @(*)begin
        case(cur_state_w)
        IDLE_W:begin
            if(data_wen!=0)begin
               next_state_w = uncached ? UNCACHED_WRITE : TAG_CHECK_W;
            end
            else next_state_w = IDLE_W;
        end
        TAG_CHECK_W:begin
            if(hit_w)begin
                next_state_w = HIT_W;
            end
            else if(!hit_w && dirty[cache_index]&& dev_wrdy)begin
                next_state_w = WRITE_BACK;
            end
            else if(!hit_w && !dirty[cache_index] && dev_wrdy)begin
                next_state_w = ALLOCATE;
            end
            else begin
                next_state_w = TAG_CHECK_W;
            end
        end
        WAIT_W:begin
            if(dev_wrdy)begin
            next_state_w = IDLE_W;
            end
            else next_state_w = WAIT_W;
        end
        WRITE_BACK:begin
            if(dev_wrdy)begin
                next_state_w =WRITE_BACK1;
            end
            else begin
                next_state_w = WRITE_BACK;
            end
        end
        WRITE_BACK1:begin
            if(dev_wrdy)begin
                next_state_w =WRITE_BACK2;
            end
            else begin
                next_state_w = WRITE_BACK1;
            end
        end
        WRITE_BACK2:begin
            if(dev_wrdy)begin
                next_state_w =WRITE_BACK3;
            end
            else begin
                next_state_w = WRITE_BACK2;
            end
        end
        WRITE_BACK3:begin
            if(dev_wrdy)begin
                next_state_w =ALLOCATE;
            end
            else begin
                next_state_w = WRITE_BACK3;
            end
        end
        HIT_W:begin
            next_state_w = WAIT_W;
        end
        ALLOCATE:begin
            if(dev_rvalid)begin
                next_state_w = TAG_CHECK_W;
                end
            else begin
                next_state_w = ALLOCATE;
            end
        end 
        UNCACHED_WRITE: begin
            if (dev_wrdy) begin
                next_state_w = WAIT_W;
            end else begin
                next_state_w = UNCACHED_WRITE;
            end
        end
        default:next_state_w = IDLE_W;
        endcase
    end


    reg [3:0] wen_reg;


    always@(*)begin
        if(cpu_rst)begin
            wen_reg = 0;
        end
        else if (data_wen != 0)begin
            wen_reg = data_wen;
        end
        else if(data_wresp == 1'b1)begin
            wen_reg = 0;
        end
    end

    // TODO: 生成DCache写状态机的输出信号
    always @(posedge cpu_clk or posedge cpu_rst)begin
        if(cpu_rst)begin
            dev_wen <= 4'b0;
            dev_waddr <= 32'h0;
            dev_raddr <= 32'h0;
            dev_wdata <= 32'h0;
            data_valid <= 0;
            //data_rdata <= 
            data_wresp <= 0;
        end
        case(cur_state_w)
        IDLE_W:begin
                dev_waddr <= data_addr;
                data_wresp <= 0;
                if(uncached)begin
                    dev_wdata <= data_wdata;
                    dev_wen <= data_wen;
                end
                else begin
                    dev_wen <= 0;
                end
        end
        TAG_CHECK_W:begin
            if(hit_w)begin//写命中，直接更新cache
                dev_wen <= 0;//
                dev_ren <= 0;
                //ce 1
            end
            else if(!hit_w && dirty[cache_index]&& dev_wrdy)begin//写缺失，脏，需要写回
               
            end
            else if(!hit_w && !dirty[cache_index] && dev_wrdy)begin//进入ALLOCATE
                dev_ren <= 4'hf;
                dev_raddr <= data_addr;
            end
            else begin
                
            end
        end
        HIT_W:begin
            dirty[cache_index] <= 1'b1;//修改脏位
            cache_tags[cache_index] <= {1'b1,tag_from_cpu};

        end
        WAIT_W:begin
            if(dev_wrdy)begin
                data_wresp <= 1'b1;
                dev_wen <= 0;
            end
        end
        WRITE_BACK:begin
            if(dev_wrdy)begin
                dev_wen <= 4'hf;
                dev_wdata <= cache_line_r[31:0];
                dev_waddr <= {tag_from_cache,cache_index, 4'b0000};
            end
        end
        WRITE_BACK1:begin
            if(dev_wrdy)begin
                dev_wen <= 4'hf;
                dev_wdata <= cache_line_r[63:32];
                dev_waddr <= {tag_from_cache,cache_index, 4'b0100};
            end
        end
        WRITE_BACK2:begin
            if(dev_wrdy)begin
                dev_wen <= 4'hf;
                dev_wdata <= cache_line_r[95:64];
                dev_waddr <= {tag_from_cache,cache_index, 4'b1000};
            end
        end
        WRITE_BACK3:begin
            if(dev_wrdy)begin
                dev_wen <= 4'hf;
                dev_wdata <= cache_line_r[127:96];
                dev_waddr <= {tag_from_cache,cache_index, 4'b1100};
            end
        end

        ALLOCATE:begin
            if(dev_rvalid)begin
                dirty[cache_index] <= 1'b0;//脏位
                cache_tags[cache_index]<= {1'b1, tag_from_cpu};
            end
            else begin
                dev_ren  <= 4'h0;
            end
        end
       UNCACHED_WRITE: begin
                dev_wen <= 0;
            end
        default:begin
            dev_wen <= 4'b0;
        end
        endcase
    end


    // TODO: 写命中时，只需修改Cache行中的其中一个字。请在此实现之。


    /******** 不要修改以下代码 ********/
`else

    localparam R_IDLE  = 2'b00;
    localparam R_STAT0 = 2'b01;
    localparam R_STAT1 = 2'b11;
    reg [1:0] r_state, r_nstat;
    reg [3:0] ren_r;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        r_state <= cpu_rst ? R_IDLE : r_nstat;
    end

    always @(*) begin
        case (r_state)
            R_IDLE:  r_nstat = (|data_ren) ? (dev_rrdy ? R_STAT1 : R_STAT0) : R_IDLE;
            R_STAT0: r_nstat = dev_rrdy ? R_STAT1 : R_STAT0;
            R_STAT1: r_nstat = dev_rvalid ? R_IDLE : R_STAT1;
            default: r_nstat = R_IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_valid <= 1'b0;
            dev_ren    <= 4'h0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    data_valid <= 1'b0;

                    if (|data_ren) begin
                        if (dev_rrdy)
                            dev_ren <= data_ren;
                        else
                            ren_r   <= data_ren;

                        dev_raddr <= data_addr;
                    end else
                        dev_ren   <= 4'h0;
                end
                R_STAT0: begin
                    dev_ren    <= dev_rrdy ? ren_r : 4'h0;
                end   
                R_STAT1: begin
                    dev_ren    <= 4'h0;
                    data_valid <= dev_rvalid ? 1'b1 : 1'b0;
                    data_rdata <= dev_rvalid ? dev_rdata : 32'h0;
                end
                default: begin
                    data_valid <= 1'b0;
                    dev_ren    <= 4'h0;
                end 
            endcase
        end
    end

    localparam W_IDLE  = 2'b00;
    localparam W_STAT0 = 2'b01;
    localparam W_STAT1 = 2'b11;
    reg  [1:0] w_state, w_nstat;
    reg  [3:0] wen_r;
    wire       wr_resp = dev_wrdy & (dev_wen == 4'h0) ? 1'b1 : 1'b0;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        w_state <= cpu_rst ? W_IDLE : w_nstat;
    end

    always @(*) begin
        case (w_state)
            W_IDLE:  w_nstat = (|data_wen) ? (dev_wrdy ? W_STAT1 : W_STAT0) : W_IDLE;
            W_STAT0: w_nstat = dev_wrdy ? W_STAT1 : W_STAT0;
            W_STAT1: w_nstat = wr_resp ? W_IDLE : W_STAT1;
            default: w_nstat = W_IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_wresp <= 1'b0;
            dev_wen    <= 4'h0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    data_wresp <= 1'b0;

                    if (|data_wen) begin
                        if (dev_wrdy)
                            dev_wen <= data_wen;
                        else
                            wen_r   <= data_wen;

                        dev_waddr  <= data_addr;
                        dev_wdata  <= data_wdata;
                    end else
                        dev_wen    <= 4'h0;
                end
                W_STAT0: begin
                    dev_wen    <= dev_wrdy ? wen_r : 4'h0;
                end
                W_STAT1: begin
                    dev_wen    <= 4'h0;
                    data_wresp <= wr_resp ? 1'b1 : 1'b0;
                end
                default: begin
                    data_wresp <= 1'b0;
                    dev_wen    <= 4'h0;
                end
            endcase
        end
    end

`endif

endmodule

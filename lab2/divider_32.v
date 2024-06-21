`timescale 1ns / 1ps

module divider (
    input  wire       clk,
    input  wire       rst,
    input  wire [31:0] x,
    input  wire [31:0] y,
    input  wire       start,
    output wire [31:0] z,  // �??
    output wire [31:0] r,  // 余数
    output reg        busy
);
    wire rstn;
    assign rstn = ~rst;
    reg [30:0] dividend_reg;  // 缓存被除�??
    reg [30:0] divisor_reg;   // 缓存除数

    reg [30:0] dividend_abs; //被除数绝对�?
    reg [30:0] divisor_abs;  //除数绝对�??

    reg [30:0] quotient_reg;  // �??
    reg [31:0] remainder_reg; // 余数
    reg [31:0] remainder_reg_add; // 余数_加之�??
    reg [4:0] count_reg;     // 计数
    reg quotient_sign;//商符号位
    reg remainder_sign;//余数符号�??

    always @(posedge clk or negedge rstn) begin
        if(~rstn)begin
            count_reg <= 5'd31;
        end
        else if(count_reg == 5'd31 || start == 1'b1)begin
            count_reg<= 0;
        end
        else if(busy)begin
            count_reg <= count_reg +1'b1;
        end
        else count_reg <= count_reg;
    end

    always @(posedge clk or negedge rstn)begin
        if(~rstn)begin
            busy <= 0;     
            dividend_reg <= 0;
            remainder_reg <= 0;
            quotient_reg <= 0;
            divisor_reg <= 0; 
            dividend_abs <= 0;
            divisor_abs <= 0;       
            quotient_sign <= 0;
            remainder_sign <= 0;
        end
        else if(start)begin
            busy <= 1;
            remainder_reg <= {1'b1,~y[30:0]+1'b1};
            quotient_reg <= 0;
            dividend_reg <= x[30:0];
            dividend_abs <= x[30:0];
            divisor_reg <= y[30:0]; 
            divisor_abs <= y[30:0];
            quotient_sign <= x[31]^y[31];
            remainder_sign <= x[31];
        end
        if(busy)begin
            case(count_reg)
                31:begin
                busy = 1'b0;
                quotient_reg <= (remainder_reg_add[31])?quotient_reg<<1:quotient_reg<<1|1'b1;
                remainder_reg <= (remainder_reg_add[31])?(remainder_reg_add  + {1'b0,divisor_abs}):remainder_reg_add;
                end
                default:begin
                    if(remainder_reg_add[31] == 1'b1)begin
                    quotient_reg <= {quotient_reg[30:0],1'b0};
                    remainder_reg <= {remainder_reg_add[30:0],dividend_reg[30]};
                    dividend_reg <= dividend_reg << 1;
                    end
                    else begin
                    quotient_reg <= {quotient_reg[30:0],1'b1};
                    remainder_reg <= {remainder_reg_add[30:0],dividend_reg[30]};
                    dividend_reg <= dividend_reg << 1;
                end
                end
            endcase
        end
    end

    always @(*)begin
        if(start)begin
        remainder_reg_add = remainder_reg;
    end  
        else begin
        remainder_reg_add = (remainder_reg[31])?remainder_reg + {1'b0,divisor_abs}:remainder_reg +{1'b1,~divisor_abs +1'b1};
    end
    end
assign z = {quotient_sign,quotient_reg};
assign r = {remainder_sign,remainder_reg[30:0]};

endmodule
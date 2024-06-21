    module multiplier (
    input  wire         clk,
	input  wire         rst,       
	input  wire [31:0]  x,         
	input  wire [31:0]  y,          
	input  wire         start,      
	output wire  [63:0]  z,          
	output reg          busy       
);

    wire rstn;
    assign rstn = ~rst;
    reg [5:0] count_reg;
    reg [31:0] part_product;//部分积
    reg [31:0] part_product_add;//部分积加和
    reg [31:0] multiplier;//乘数
    reg [31:0] x_cp;//x补码
    reg [31:0] x_data;//x补码
    reg [31:0] x_data_2;//-x补码
    reg [31:0] y_data;//y补码
    reg multiplier_plus;

    always @(posedge clk or negedge rstn) begin
        if(~rstn)begin
            count_reg <= 6'd31;
        end
        else if(count_reg == 6'd31|| start == 1'b1)begin
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
            x_data<=0;
            y_data<=0;
            x_data_2<=0;
            part_product<=32'h0;
            part_product_add<=32'h0;
            multiplier<=0;
            multiplier_plus<=0;
        end
        else if(start == 1'b1)begin
            busy <= 1;
            multiplier <=y;
            multiplier_plus <= 1'b0;
            part_product = 0;//(y[0]==1'b1)?~x+1'b1:32'h0;
            x_data <= x;//x补
            x_data_2 <= ~x + 1'b1;//-x补
            y_data <= y;
        end
        else if(busy)begin
            if(count_reg == 6'd31)begin
                    multiplier_plus <= multiplier[0];
                    multiplier <= {part_product_add[0],multiplier[31:1]};
                    part_product <= {part_product_add[31],part_product_add[31:1]};
                    busy<=0;
            end
            else begin
                multiplier_plus <= multiplier[0];
                multiplier <= {part_product_add[0],multiplier[31:1]};
                part_product <= {part_product_add[31],part_product_add[31:1]};
            end
        end
    end
    

always @(*) begin
    if(start)begin
        part_product_add = 32'h0;
    end
    else begin
        part_product_add = ({multiplier[0],multiplier_plus}==2'b01)?part_product + x_data :
                           ({multiplier[0],multiplier_plus}==2'b10)?part_product + x_data_2:
                           part_product;
    end
end
assign z = {part_product,multiplier};

endmodule
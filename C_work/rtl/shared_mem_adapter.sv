`timescale 1ns/1ps
// C-owned: B element requests -> one-outstanding, 32-bit physical ICB master.
module shared_mem_adapter #(
    parameter integer ROWS=99, COLS=256,
    parameter [31:0] SRAM_BASE=32'ha0000000,
    parameter integer SRAM_BYTES=524288
) (
    input wire clk, rst_n,
    input wire [31:0] x_base, w_base, b_base, y_base,
    input wire mem_req_valid, mem_req_write,
    output wire mem_req_ready,
    input wire [1:0] mem_req_tensor,
    input wire [31:0] mem_req_index,
    input wire [63:0] mem_req_wdata,
    output wire mem_rsp_valid,
    input wire mem_rsp_ready,
    output reg [63:0] mem_rsp_rdata,
    output reg mem_rsp_error,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire [31:0] cmd_addr,
    output wire cmd_read,
    output wire [31:0] cmd_wdata,
    output wire [3:0] cmd_wmask,
    input wire rsp_valid,
    output wire rsp_ready,
    input wire [31:0] rsp_rdata,
    input wire rsp_err
);
    localparam IDLE=0, SEND=1, WAIT_RSP=2, RESPONSE=3;
    reg [1:0] state;
    reg [31:0] address;
    reg [15:0] write_value;
    reg [31:0] bias_low;
    reg write_op, bias_op, second_beat, upper_half;
    reg [32:0] physical;
    reg [32:0] last_byte;
    reg invalid;
    always_comb begin
        physical=0; last_byte=0; invalid=0;
        case (mem_req_tensor)
            0: begin
                physical={1'b0,x_base}+({1'b0,mem_req_index}<<1);
                invalid=x_base[0] || mem_req_index>=ROWS*64;
            end
            1: begin
                physical={1'b0,w_base}+({1'b0,mem_req_index}<<1);
                invalid=w_base[0] || mem_req_index>=64*COLS;
            end
            2: begin
                physical={1'b0,b_base}+({1'b0,mem_req_index}<<3);
                invalid=(b_base[2:0]!=0) || mem_req_index>=COLS;
            end
            3: begin
                physical={1'b0,y_base}+({1'b0,mem_req_index}<<1);
                invalid=y_base[0] || mem_req_index>=ROWS*COLS;
            end
        endcase
        last_byte=physical+((mem_req_tensor==2) ? 33'd7 : 33'd1);
        invalid=invalid || (mem_req_write != (mem_req_tensor==3)) ||
            physical< {1'b0,SRAM_BASE} || last_byte>=({1'b0,SRAM_BASE}+SRAM_BYTES);
    end
    assign mem_req_ready=state==IDLE;
    assign mem_rsp_valid=state==RESPONSE;
    assign cmd_valid=state==SEND;
    assign cmd_addr=address+(second_beat ? 32'd4 : 32'd0);
    assign cmd_read=!write_op;
    assign cmd_wdata=upper_half ? {write_value,16'd0} : {16'd0,write_value};
    assign cmd_wmask=write_op ? (upper_half ? 4'b1100 : 4'b0011) : 4'b1111;
    assign rsp_ready=state==WAIT_RSP;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; address<=0; write_value<=0; bias_low<=0;
            write_op<=0; bias_op<=0; second_beat<=0; upper_half<=0;
            mem_rsp_rdata<=0; mem_rsp_error<=0;
        end else case (state)
            IDLE: if (mem_req_valid) begin
                address<={physical[31:2],2'b00}; upper_half<=physical[1];
                write_value<=mem_req_wdata[15:0]; write_op<=mem_req_write;
                bias_op<=mem_req_tensor==2; second_beat<=0;
                mem_rsp_rdata<=0; mem_rsp_error<=invalid;
                state<=invalid ? RESPONSE : SEND;
            end
            SEND: if (cmd_ready) state<=WAIT_RSP;
            WAIT_RSP: if (rsp_valid) begin
                if (rsp_err) begin mem_rsp_error<=1; state<=RESPONSE; end
                else if (bias_op && !second_beat) begin
                    bias_low<=rsp_rdata; second_beat<=1; state<=SEND;
                end else begin
                    if (bias_op) mem_rsp_rdata<={24'd0,rsp_rdata[7:0],bias_low};
                    else if (!write_op) mem_rsp_rdata<=upper_half ? {48'd0,rsp_rdata[31:16]} : {48'd0,rsp_rdata[15:0]};
                    state<=RESPONSE;
                end
            end
            RESPONSE: if (mem_rsp_ready) state<=IDLE;
        endcase
    end
endmodule

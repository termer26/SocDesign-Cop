`timescale 1ns/1ps
// Functional SRAM backend with fair CPU/accelerator/loader arbitration.
// Replace the storage backend with the official platform SRAM for ASIC signoff.
module icb_shared_sram #(
    parameter integer BYTES=524288, WAIT_CYCLES=0,
    parameter [31:0] BASE=32'ha0000000
) (
    input wire clk,rst_n,
    input wire [2:0] cmd_valid,cmd_read,
    output reg [2:0] cmd_ready,
    input wire [95:0] cmd_addr,cmd_wdata,
    input wire [11:0] cmd_wmask,
    output reg [2:0] rsp_valid,rsp_err,
    input wire [2:0] rsp_ready,
    output wire [95:0] rsp_rdata
);
    reg [31:0] mem [0:BYTES/4-1];
    reg pending,failed;
    reg [1:0] owner,next_owner;
    reg [31:0] value;
    integer selected,scan,candidate,lane,delay_count;
    reg [31:0] address,data;
    reg [3:0] mask;
    assign rsp_rdata={3{value}};
    always @* begin
        selected=-1; cmd_ready=0; rsp_valid=0; rsp_err=0;
        for (scan=0;scan<3;scan=scan+1) begin
            candidate={30'd0,next_owner}+scan;
            if (candidate>=3) candidate=candidate-3;
            if (selected==-1 && cmd_valid[candidate]) selected=candidate;
        end
        if (!pending && selected>=0) cmd_ready[selected]=1;
        if (pending && delay_count==0) begin rsp_valid[owner]=1; rsp_err[owner]=failed; end
        address=0;data=0;mask=0;
        if (selected>=0) begin
            address=cmd_addr[selected*32+:32]; data=cmd_wdata[selected*32+:32]; mask=cmd_wmask[selected*4+:4];
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin pending<=0; owner<=0; next_owner<=0; value<=0; failed<=0; delay_count<=0; end
        else begin
            if (pending) begin
                if (delay_count!=0) delay_count<=delay_count-1;
                else if (rsp_ready[owner]) pending<=0;
            end else if (selected>=0) begin
                pending<=1; owner<=selected[1:0]; next_owner<=selected==2 ? 2'd0 : selected[1:0]+2'd1;
                delay_count<=WAIT_CYCLES; failed<=address<BASE || address>=BASE+BYTES;
                value<=0;
                if (address>=BASE && address<BASE+BYTES) begin
                    if (cmd_read[selected]) value<=mem[(address-BASE)>>2];
                    else for (lane=0;lane<4;lane=lane+1)
                        if (mask[lane]) mem[(address-BASE)>>2][lane*8+:8]<=data[lane*8+:8];
                end
            end
        end
    end
endmodule

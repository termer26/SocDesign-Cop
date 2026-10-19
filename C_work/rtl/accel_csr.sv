`timescale 1ns/1ps
// C-owned: native ICB slave, configuration lock, START pulse and sticky status.
module accel_csr (
    input wire clk, rst_n,
    input wire cmd_valid,
    output wire cmd_ready,
    input wire [31:0] cmd_addr, cmd_wdata,
    input wire cmd_read,
    input wire [3:0] cmd_wmask,
    output reg rsp_valid,
    input wire rsp_ready,
    output reg [31:0] rsp_rdata,
    output reg rsp_err,
    output reg start,
    output reg [3:0] layer_id,
    output reg [5:0] task_shift,
    output reg [31:0] x_base, w_base, b_base, y_base,
    input wire start_ready, busy, done, error,
    input wire [3:0] error_code,
    input wire [31:0] completed_outputs, task_cycles,
    output wire irq
);
    reg sticky_done, sticky_error, irq_enable;
    reg [3:0] saved_error;
    wire locked=busy || !start_ready || start;
    wire [7:0] offset=cmd_addr[7:0];
    reg [31:0] read_value;
    reg bad;
    always @* begin
        read_value=0;
        bad=(cmd_addr[31:8]!=24'h110000) || (cmd_addr[1:0]!=0) || (!cmd_read && cmd_wmask!=4'hf);
        case (offset)
            'h00: if (!cmd_read && ((cmd_wdata & ~32'd3)!=0 || (cmd_wdata[0] && locked))) bad=1;
            'h04: begin read_value={28'd0,start_ready,sticky_error,sticky_done,(busy || start)}; if (!cmd_read) bad=1; end
            'h08: begin read_value={28'd0,layer_id}; if (!cmd_read && (locked || cmd_wdata>=12)) bad=1; end
            'h0c: begin read_value={26'd0,task_shift}; if (!cmd_read && (locked || cmd_wdata>63)) bad=1; end
            'h10: begin read_value=x_base; if (!cmd_read && locked) bad=1; end
            'h14: begin read_value=w_base; if (!cmd_read && locked) bad=1; end
            'h18: begin read_value=b_base; if (!cmd_read && locked) bad=1; end
            'h1c: begin read_value=y_base; if (!cmd_read && locked) bad=1; end
            'h20: begin read_value=completed_outputs; if (!cmd_read) bad=1; end
            'h24: begin read_value=task_cycles; if (!cmd_read) bad=1; end
            'h28: begin read_value={28'd0,saved_error}; if (!cmd_read) bad=1; end
            'h2c: begin read_value=32'h00010000; if (!cmd_read) bad=1; end
            'h30: begin read_value={31'd0,irq_enable}; if (!cmd_read && cmd_wdata>1) bad=1; end
            default: bad=1;
        endcase
    end
    assign cmd_ready=!rsp_valid;
    assign irq=irq_enable && (sticky_done || sticky_error);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid<=0; rsp_rdata<=0; rsp_err<=0; start<=0;
            layer_id<=0; task_shift<=16; x_base<=32'ha0000000;
            w_base<=32'ha0004000; b_base<=32'ha000c000; y_base<=32'ha0010000;
            sticky_done<=0; sticky_error<=0; saved_error<=0; irq_enable<=0;
        end else begin
            start<=0;
            if (rsp_valid && rsp_ready) rsp_valid<=0;
            if (cmd_valid && cmd_ready) begin
                rsp_valid<=1; rsp_rdata<=read_value; rsp_err<=bad;
                if (!cmd_read && !bad) case (offset)
                    'h00: begin
                        if (cmd_wdata[1] || cmd_wdata[0]) begin sticky_done<=0; sticky_error<=0; saved_error<=0; end
                        if (cmd_wdata[0]) start<=1;
                    end
                    'h08: layer_id<=cmd_wdata[3:0];
                    'h0c: task_shift<=cmd_wdata[5:0];
                    'h10: x_base<=cmd_wdata;
                    'h14: w_base<=cmd_wdata;
                    'h18: b_base<=cmd_wdata;
                    'h1c: y_base<=cmd_wdata;
                    'h30: irq_enable<=cmd_wdata[0];
                endcase
            end
            // A completion/error on the same cycle as ACK must remain observable.
            if (done) sticky_done<=1;
            if (error) begin sticky_error<=1; saved_error<=error_code; end
        end
    end
endmodule

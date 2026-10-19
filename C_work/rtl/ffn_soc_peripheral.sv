`timescale 1ns/1ps
// C integration boundary: upstream sysper ICB slave + shared-SRAM ICB master.
module ffn_soc_peripheral #(parameter integer ROWS=99, COLS=256) (
    input wire clk, rst_n,
    input wire csr_cmd_valid, csr_cmd_read,
    output wire csr_cmd_ready,
    input wire [31:0] csr_cmd_addr, csr_cmd_wdata,
    input wire [3:0] csr_cmd_wmask,
    output wire csr_rsp_valid, csr_rsp_err,
    input wire csr_rsp_ready,
    output wire [31:0] csr_rsp_rdata,
    output wire mem_cmd_valid, mem_cmd_read,
    input wire mem_cmd_ready,
    output wire [31:0] mem_cmd_addr, mem_cmd_wdata,
    output wire [3:0] mem_cmd_wmask,
    input wire mem_rsp_valid, mem_rsp_err,
    output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_rdata,
    output wire irq
);
    wire start,start_ready,busy,done,error,start_rejected;
    wire [3:0] layer_id,active_layer,error_code;
    wire [5:0] task_shift,active_shift;
    wire [31:0] x_base,w_base,b_base,y_base,completed_outputs,task_cycles;
    wire req_valid,req_ready,req_write,rsp_valid,rsp_ready,rsp_error;
    wire [1:0] req_tensor;
    wire [31:0] req_index;
    wire [63:0] req_wdata,rsp_rdata;
    accel_csr u_csr (
        .clk(clk),.rst_n(rst_n),.cmd_valid(csr_cmd_valid),.cmd_ready(csr_cmd_ready),
        .cmd_read(csr_cmd_read),.cmd_addr(csr_cmd_addr),.cmd_wdata(csr_cmd_wdata),.cmd_wmask(csr_cmd_wmask),
        .rsp_valid(csr_rsp_valid),.rsp_ready(csr_rsp_ready),.rsp_err(csr_rsp_err),.rsp_rdata(csr_rsp_rdata),
        .start(start),.layer_id(layer_id),.task_shift(task_shift),
        .x_base(x_base),.w_base(w_base),.b_base(b_base),.y_base(y_base),
        .start_ready(start_ready),.busy(busy),.done(done),.error(error),.error_code(error_code),
        .completed_outputs(completed_outputs),.task_cycles(task_cycles),.irq(irq));
    linear_accel_a_top #(.ROWS(ROWS),.COLS(COLS)) u_ab (
        .clk(clk),.rst_n(rst_n),.start(start),.layer_id(layer_id),.task_shift(task_shift),.active_shift(active_shift),
        .start_ready(start_ready),.busy(busy),.done(done),.error(error),.start_rejected(start_rejected),
        .active_layer(active_layer),.error_code(error_code),.completed_outputs(completed_outputs),.task_cycles(task_cycles),
        .mem_req_valid(req_valid),.mem_req_ready(req_ready),.mem_req_write(req_write),
        .mem_req_tensor(req_tensor),.mem_req_index(req_index),.mem_req_wdata(req_wdata),
        .mem_rsp_valid(rsp_valid),.mem_rsp_ready(rsp_ready),.mem_rsp_rdata(rsp_rdata),.mem_rsp_error(rsp_error));
    shared_mem_adapter #(.ROWS(ROWS),.COLS(COLS)) u_mem (
        .clk(clk),.rst_n(rst_n),.x_base(x_base),.w_base(w_base),.b_base(b_base),.y_base(y_base),
        .mem_req_valid(req_valid),.mem_req_ready(req_ready),.mem_req_write(req_write),
        .mem_req_tensor(req_tensor),.mem_req_index(req_index),.mem_req_wdata(req_wdata),
        .mem_rsp_valid(rsp_valid),.mem_rsp_ready(rsp_ready),.mem_rsp_rdata(rsp_rdata),.mem_rsp_error(rsp_error),
        .cmd_valid(mem_cmd_valid),.cmd_ready(mem_cmd_ready),.cmd_addr(mem_cmd_addr),
        .cmd_read(mem_cmd_read),.cmd_wdata(mem_cmd_wdata),.cmd_wmask(mem_cmd_wmask),
        .rsp_valid(mem_rsp_valid),.rsp_ready(mem_rsp_ready),.rsp_rdata(mem_rsp_rdata),.rsp_err(mem_rsp_err));
endmodule

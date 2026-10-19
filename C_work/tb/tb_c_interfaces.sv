`timescale 1ns/1ps
module tb_c_interfaces;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [31:0] x_base=32'ha0000000,w_base=32'ha0004000,b_base=32'ha000c000,y_base=32'ha0010000;
    reg mem_req_valid=0,mem_req_write=0,mem_rsp_ready=0;
    reg [1:0] mem_req_tensor=0;
    reg [31:0] mem_req_index=0;
    reg [63:0] mem_req_wdata=0;
    wire mem_req_ready,mem_rsp_valid,mem_rsp_error;
    wire [63:0] mem_rsp_rdata;
    wire cmd_valid,cmd_read,rsp_ready;
    wire [31:0] cmd_addr,cmd_wdata;
    wire [3:0] cmd_wmask;
    reg cmd_ready=0,rsp_valid=0,rsp_err=0;
    reg [31:0] rsp_rdata=0;
    reg [31:0] data[0:32767];
    reg [31:0] error_address=32'hffffffff;
    integer ticks=0,transactions=0,k;
    reg [31:0] last_addr,last_data;
    reg [3:0] last_mask;
    reg last_read,was_waiting=0;
    shared_mem_adapter #(.ROWS(3),.COLS(5)) u_mem(.*);
    always @(negedge clk) begin
        ticks=ticks+1;
        cmd_ready=rst_n && !rsp_valid && (ticks%3==0);
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin rsp_valid<=0;rsp_err<=0;rsp_rdata<=0;end
        else begin
            if(rsp_valid && rsp_ready)rsp_valid<=0;
            if(cmd_valid && cmd_ready)begin
                transactions=transactions+1;rsp_valid<=1;rsp_err<=cmd_addr==error_address;
                rsp_rdata<=data[(cmd_addr-32'ha0000000)>>2];
                if(!cmd_read && cmd_addr!=error_address)
                    for(k=0;k<4;k=k+1)if(cmd_wmask[k])data[(cmd_addr-32'ha0000000)>>2][k*8+:8]<=cmd_wdata[k*8+:8];
            end
        end
        if(rst_n && was_waiting && (!cmd_valid || {cmd_addr,cmd_wdata,cmd_wmask,cmd_read}!=={last_addr,last_data,last_mask,last_read}))
            $fatal(1,"ICB command changed under backpressure");
        was_waiting=rst_n && cmd_valid && !cmd_ready;
        last_addr=cmd_addr;last_data=cmd_wdata;last_mask=cmd_wmask;last_read=cmd_read;
    end
    task automatic request(input reg wr,input reg[1:0] tensor,input reg[31:0] index,
                           input reg[63:0] input_value,input reg[63:0] wanted,input reg want_error,input integer beats);
        integer before_count,timeout,n;
        begin
            before_count=transactions;
            @(negedge clk);mem_req_valid=1;mem_req_write=wr;mem_req_tensor=tensor;mem_req_index=index;mem_req_wdata=input_value;
            @(posedge clk);while(!mem_req_ready)@(posedge clk);
            @(negedge clk);mem_req_valid=0;timeout=0;
            while(!mem_rsp_valid)begin @(negedge clk);timeout=timeout+1;if(timeout>100)$fatal(1,"Tensor response timeout");end
            for(n=0;n<4;n=n+1)begin
                if(!mem_rsp_valid || mem_rsp_error!==want_error || (!want_error && mem_rsp_rdata!==wanted))
                    $fatal(1,"Tensor response error tensor=%0d index=%0d got=%h err=%b expected=%h err=%b",tensor,index,mem_rsp_rdata,mem_rsp_error,wanted,want_error);
                @(negedge clk);
            end
            if(transactions-before_count!=beats)$fatal(1,"Wrong number of physical beats");
            mem_rsp_ready=1;@(negedge clk);mem_rsp_ready=0;
        end
    endtask

    reg c_cmd_valid=0,c_cmd_read=0,c_rsp_ready=0;
    wire c_cmd_ready,c_rsp_valid,c_rsp_err,start,irq;
    reg [31:0] c_cmd_addr=0,c_cmd_wdata=0;
    reg [3:0] c_cmd_wmask=15;
    wire [31:0] c_rsp_rdata,cx,cw,cb,cy;
    wire [3:0] layer_id;
    wire [5:0] task_shift;
    reg start_ready=1,busy=0,done=0,error=0;
    reg [3:0] error_code=0;
    reg [31:0] completed_outputs=0,task_cycles=0;
    integer starts=0;
    always @(posedge clk)if(start)starts=starts+1;
    accel_csr u_csr(.clk(clk),.rst_n(rst_n),.cmd_valid(c_cmd_valid),.cmd_ready(c_cmd_ready),
        .cmd_read(c_cmd_read),.cmd_addr(c_cmd_addr),.cmd_wdata(c_cmd_wdata),.cmd_wmask(c_cmd_wmask),
        .rsp_valid(c_rsp_valid),.rsp_ready(c_rsp_ready),.rsp_err(c_rsp_err),.rsp_rdata(c_rsp_rdata),
        .start(start),.layer_id(layer_id),.task_shift(task_shift),.x_base(cx),.w_base(cw),.b_base(cb),.y_base(cy),
        .start_ready(start_ready),.busy(busy),.done(done),.error(error),.error_code(error_code),
        .completed_outputs(completed_outputs),.task_cycles(task_cycles),.irq(irq));
    task automatic csr(input reg rd,input reg[31:0] addr,input reg[31:0] val,
                       input reg[3:0] mask,input reg want_error,input reg[31:0] expected_value);
        integer n;
        begin
            @(negedge clk);c_cmd_valid=1;c_cmd_read=rd;c_cmd_addr=addr;c_cmd_wdata=val;c_cmd_wmask=mask;
            @(posedge clk);while(!c_cmd_ready)@(posedge clk);
            @(negedge clk);c_cmd_valid=0;
            for(n=0;n<3;n=n+1)begin
                if(!c_rsp_valid || c_rsp_err!==want_error || (rd && !want_error && c_rsp_rdata!==expected_value))
                    $fatal(1,"CSR response invalid addr=%h got=%h error=%b",addr,c_rsp_rdata,c_rsp_err);
                @(negedge clk);
            end
            c_rsp_ready=1;@(negedge clk);c_rsp_ready=0;
        end
    endtask
    initial begin
        data[0]=32'hfedc1234;data['h4000/4]=32'h80017fff;
        data['hc000/4]=32'h89abcdef;data['hc004/4]=32'hffffffd5;
        data['h10000/4]=32'h55aa1122;
        repeat(4)@(negedge clk);rst_n=1;
        request(0,0,0,0,64'h1234,0,1);request(0,0,1,0,64'hfedc,0,1);
        request(0,1,1,0,64'h8001,0,1);request(0,2,0,0,64'hd589abcdef,0,2);
        request(1,3,0,64'hffff,0,0,1);
        if(data['h10000/4]!==32'h55aaffff)$fatal(1,"Lower half write corrupts upper half");
        request(1,3,1,64'h8000,0,0,1);
        if(data['h10000/4]!==32'h8000ffff)$fatal(1,"Upper half write corrupts lower half");
        request(0,0,192,0,0,1,0);request(1,0,0,0,0,1,0);request(0,3,0,0,0,1,0);
        x_base=32'ha0000001;request(0,0,0,0,0,1,0);
        x_base=32'hfffffffe;request(0,0,1,0,0,1,0);x_base=32'ha0000000;
        error_address=32'ha000c004;request(0,2,0,0,0,1,2);
        error_address=32'ha0000000;request(0,0,0,0,0,1,1);
        error_address=32'ha0010000;request(1,3,0,0,0,1,1);
        if(data['h10000/4]!==32'h8000ffff)$fatal(1,"Errored write modified storage");
        error_address=32'hffffffff;
        csr(1,32'h1100002c,0,15,0,32'h00010000);
        csr(0,32'h11000008,2,15,0,0);csr(0,32'h1100000c,17,15,0,0);
        csr(1,32'h11000008,0,15,0,2);csr(1,32'h1100000c,0,15,0,17);
        csr(0,32'h11000008,12,15,1,0);csr(0,32'h1100000c,64,15,1,0);
        csr(0,32'h11000008,0,3,1,0);csr(1,32'h11000009,0,15,1,0);
        csr(1,32'h1100012c,0,15,1,0);csr(0,32'h1100002c,0,15,1,0);
        csr(0,32'h11000030,1,15,0,0);csr(0,32'h11000000,1,15,0,0);
        if(starts!=1)$fatal(1,"START is not exactly one pulse");
        busy=1;start_ready=0;
        csr(0,32'h11000000,1,15,1,0);csr(0,32'h11000008,3,15,1,0);
        if(layer_id!=2 || task_shift!=17 || starts!=1)$fatal(1,"Busy configuration changed");
        busy=0;done=1;@(negedge clk);done=0;start_ready=1;
        csr(1,32'h11000004,0,15,0,10);if(!irq)$fatal(1,"Sticky DONE IRQ missing");
        csr(0,32'h11000000,2,15,0,0);if(irq)$fatal(1,"ACK did not clear IRQ");
        error=1;error_code=1;@(negedge clk);error=0;
        csr(1,32'h11000004,0,15,0,12);csr(1,32'h11000028,0,15,0,1);
        rst_n=0;repeat(3)@(negedge clk);rst_n=1;
        csr(1,32'h11000004,0,15,0,8);if(irq)$fatal(1,"Reset did not clear IRQ");
        request(0,2,0,0,64'hd589abcdef,0,2);
        // Abort an accepted request before its response is consumed.
        @(negedge clk);mem_req_valid=1;mem_req_tensor=0;mem_req_index=0;mem_req_write=0;
        @(posedge clk);while(!mem_req_ready)@(posedge clk);
        @(negedge clk);mem_req_valid=0;
        while(!mem_rsp_valid)@(negedge clk);
        rst_n=0;#1;
        if(mem_rsp_valid || rsp_valid)$fatal(1,"Reset retained an old response");
        repeat(3)@(negedge clk);rst_n=1;
        request(0,0,1,0,64'hfedc,0,1);
        $display("C_INTERFACES_PASS packing=16/40/16 waits=1 response_backpressure=1 errors=1 csr=1 reset=1");
        $finish;
    end
    initial begin #1000000;$fatal(1,"Unit test timeout");end
endmodule

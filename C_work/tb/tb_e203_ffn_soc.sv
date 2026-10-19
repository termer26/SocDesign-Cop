`timescale 1ns/1ps
module tb_e203_ffn_soc;
    parameter integer ROWS=3,COLS=5,JOBS=3,SRAM_WAIT=1;
    reg clk=0,ls_clk=0,rst_n=0,core_hold=1;
    always #3.333 clk=~clk;
    always #15258.789 ls_clk=~ls_clk;
    reg host_cmd_valid=0,host_cmd_read=0,host_rsp_ready=0;
    reg [31:0] host_cmd_addr=0,host_cmd_wdata=0;
    reg [3:0] host_cmd_wmask=15;
    wire host_cmd_ready,host_rsp_valid,host_rsp_err,accel_irq;
    wire [31:0] host_rsp_rdata;
    e203_ffn_soc #(.ROWS(ROWS),.COLS(COLS),.SRAM_WAIT(SRAM_WAIT)) dut(.*);
    reg [31:0] firmware[0:16383];
    reg [31:0] loads[0:JOBS*24576-1];
    reg [15:0] expected[0:JOBS*ROWS*COLS-1];
    reg [3:0] job_layers[0:JOBS-1];
    reg [5:0] job_shifts[0:JOBS-1];
    integer fw_words,load_words,i,j,job,polls,observed;
    reg [31:0] value,status,result,checksum,expected_sum,cycles;
    reg [63:0] total_ticks=0,start_tick,writeback_tick=0;
    integer output_writes=0;
    always @(posedge clk) total_ticks<=total_ticks+1;
    always @(posedge clk) begin
        if(dut.a_cmd_valid && dut.a_cmd_ready && !dut.a_cmd_read)begin
            if(dut.a_cmd_addr<32'ha0010000 || dut.a_cmd_addr>=32'ha0010000+ROWS*COLS*2)
                $fatal(1,"Accelerator output write outside Y");
            output_writes<=output_writes+1;
        end
        if(dut.u_accel.done)begin
            if(dut.u_accel.completed_outputs!=ROWS*COLS || output_writes!=ROWS*COLS)
                $fatal(1,"DONE before all output writes were acknowledged");
            writeback_tick<=total_ticks;
        end
    end

    task automatic transaction(input reg rd,input reg [31:0] addr,input reg [31:0] data,output reg [31:0] response);
        integer timeout;
        begin
            @(negedge clk);host_cmd_valid=1;host_cmd_read=rd;host_cmd_addr=addr;host_cmd_wdata=data;
            timeout=0;
            @(posedge clk);
            while (!host_cmd_ready) begin
                timeout=timeout+1;if(timeout>20000)$fatal(1,"Loader request timeout at %h",addr);
                @(posedge clk);
            end
            @(negedge clk);host_cmd_valid=0;host_rsp_ready=1;
            @(posedge clk);timeout=0;
            while(!host_rsp_valid)begin
                timeout=timeout+1;if(timeout>20000)$fatal(1,"Loader response timeout");
                @(posedge clk);
            end
            if(host_rsp_err)$fatal(1,"Loader bus error at %h",addr);
            response=host_rsp_rdata;
            @(negedge clk);host_rsp_ready=0;
        end
    endtask
    task automatic put(input reg [31:0] addr,input reg [31:0] data);
        reg [31:0] ignored;begin transaction(0,addr,data,ignored);end
    endtask
    task automatic get(input reg [31:0] addr,output reg [31:0] data);
        begin transaction(1,addr,0,data);end
    endtask
    task automatic wait_status(input reg [31:0] wanted);
        begin
            polls=0;status=0;
            while(status!=wanted)begin
                get(32'ha006000c,status);
                if(status==32'hbad0 || status==32'hbad1 || status==32'hbad2)begin
                    get(32'ha0060010,result);
                    $fatal(1,"CPU failure status=%h result/mcause=%h PC=%h",status,result,dut.u_e203.inspect_pc);
                end
                polls=polls+1;
                if(polls>5000000)$fatal(1,"CPU status timeout want=%h got=%h PC=%h",wanted,status,dut.u_e203.inspect_pc);
                repeat(32)@(negedge clk);
            end
        end
    endtask
    initial begin
        if(!$value$plusargs("FW_WORDS=%d",fw_words))$fatal(1,"FW_WORDS required");
        if(!$value$plusargs("LOAD_WORDS=%d",load_words))$fatal(1,"LOAD_WORDS required");
        $readmemh("firmware.hex",firmware,0,fw_words-1);
        $readmemh("loads.hex",loads,0,JOBS*load_words-1);
        $readmemh("expected.hex",expected);
        $readmemh("layers.hex",job_layers);$readmemh("shifts.hex",job_shifts);
        repeat(12)@(negedge clk);rst_n=1;
        repeat(12)@(negedge clk);
        for(i=0;i<8;i=i+1)put(32'ha0060000+i*4,0);
        for(i=0;i<fw_words;i=i+1)put(32'ha0070000+i*4,firmware[i]);
        $display("E203_FIRMWARE_LOADED ticks=%0d",total_ticks);
        core_hold=0;
        wait_status(32'hb007);
        $display("E203_BOOT_PASS pc=%h firmware_words=%0d",dut.u_e203.inspect_pc,fw_words);
        observed=$fopen("observed.txt","w");
        for(job=0;job<JOBS;job=job+1)begin
            // Clear this task's data regions, including old parameters/output.
            // Start timing before load, so host load and CPU arbitration are included.
            for(i=0;i<ROWS*COLS;i=i+2)put(32'ha0010000+i*2,32'hcafea55a);
            start_tick=total_ticks;output_writes=0;
            j=job*load_words;
            for(i=0;i<ROWS*64/2;i=i+1)put(32'ha0000000+i*4,loads[j+i]);
            j=j+ROWS*64/2;
            for(i=0;i<64*COLS/2;i=i+1)put(32'ha0004000+i*4,loads[j+i]);
            j=j+64*COLS/2;
            for(i=0;i<COLS*2;i=i+1)put(32'ha000c000+i*4,loads[j+i]);
            put(32'ha0060004,{28'd0,job_layers[job]});put(32'ha0060008,{26'd0,job_shifts[job]});
            put(32'ha006000c,0);
            put(32'ha0060000,1);
            wait_status(32'h600d);
            get(32'ha0060010,result);if(result!=0)$fatal(1,"driver returned %h",result);
            get(32'ha0060014,checksum);get(32'ha0060018,cycles);
            expected_sum=0;
            for(i=0;i<ROWS*COLS;i=i+1)begin
                get(32'ha0010000+(i/2)*4,value);
                value=(i%2!=0) ? (value>>16) : (value & 32'hffff);
                if(value[15:0]!==expected[job*ROWS*COLS+i])
                    $fatal(1,"Output mismatch job=%0d index=%0d got=%h expected=%h",job,i,value,expected[job*ROWS*COLS+i]);
                expected_sum=expected_sum+value;
                $fdisplay(observed,"%0d %0d %04h",job,i,value[15:0]);
            end
            if(checksum!==expected_sum)$fatal(1,"CPU did not read complete output checksum got=%h want=%h",checksum,expected_sum);
            get(32'ha006001c,value);if(value!==job+1)$fatal(1,"CPU continuous-task count mismatch");
            $display("E203_JOB_PASS job=%0d layer=%0d outputs=%0d core_cycles=%0d window_cycles=%0d checksum=%h",
                job,job_layers[job],ROWS*COLS,cycles,writeback_tick-start_tick,checksum);
        end
        $fclose(observed);
        $display("E203_SOC_ALL_PASS jobs=%0d outputs=%0d",JOBS,JOBS*ROWS*COLS);
        $finish;
    end
    initial begin
        #20000000000;$fatal(1,"Global timeout PC=%h",dut.u_e203.inspect_pc);
    end
endmodule

/////////////////////////////////////////////////////////////////////////
//                                                                     //
//                                                                     //
//   Modulename :  r10k_tb                                             //
//                                                                     //
//  Description :  Testbench module for the r10k milestone2;           //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`timescale 1ns/100ps

module r10k_tb;

    logic clock, reset;
    logic [63:0] mem2proc_data;
    // logic mem2proc_valid;
    logic [31:0] proc2mem_addr;
    logic [1:0] proc2mem_command;
    logic [3:0] mem2proc_tag;
    logic [3:0] mem2proc_response;

    EXCEPTION_CODE error_status;

    logic [31:0] clock_count;
	logic [31:0] instr_count;
    logic [63:0] proc2mem_data;
    logic [2:0] retire_insts;
    ROB_OUT_PACKET [2:0] rob_out;
    integer detected_wfi = 0;

    //counter used for when pipeline infinite loops, forces termination
    logic [63:0] debug_counter;
    DCACHE_SET [`SET-1:0] cache_data_out;
    logic [`FL_SIZE-1:0] [`XLEN-1:0] preg_out;
    logic branch_correct, branch_flush;

    `DUT(r10k_top) DUT(
        .clock(clock),
        .reset(reset),
        .mem2proc_response(mem2proc_response),
        .mem2proc_data(mem2proc_data),
        .mem2proc_tag(mem2proc_tag),
        .proc2mem_command(proc2mem_command),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data(proc2mem_data),

        .error_status(error_status),
        .rob_out_packet_out(rob_out),
        .cache_data_out(cache_data_out),
        .preg_out(preg_out),
        .branch_correct_out(branch_correct),
        .branch_flush_out(branch_flush)
    );

    // Instantiate the Data Memory
	mem memory (
		// Inputs
		.clk               (clock),
		.proc2mem_command  (proc2mem_command),
		.proc2mem_addr     (proc2mem_addr),
		.proc2mem_data     (proc2mem_data),

		// Outputs

		.mem2proc_response (mem2proc_response),
		.mem2proc_data     (mem2proc_data),
		.mem2proc_tag      (mem2proc_tag)
	);

    // Generate System Clock
	always begin
		#(`VERILOG_CLOCK_PERIOD/2.0);
		clock = ~clock;
	end
	
    // Count the number of posedges and number of instructions completed
	// till simulation ends
    assign retire_insts = rob_out[0].retire_valid
                        + rob_out[1].retire_valid
                        + rob_out[2].retire_valid;

	always @(posedge clock) begin
		if(reset) begin
			clock_count <= 0;
			instr_count <= 0;
		end else begin
			clock_count <= (clock_count + 1);
			instr_count <= (instr_count + retire_insts);
		end
	end  

	// Task to display # of elapsed clock edges
	task show_clk_count;
		real cpi;
		
		begin
			cpi = (clock_count + 1.0) / (instr_count - 1.0);
			$display("@@  %0d cycles / %0d instrs = %f CPI\n@@",
			          clock_count+1, (instr_count - 1), cpi);
			$display("@@  %4.2f ns total time to execute\n@@\n",
			          clock_count*`VERILOG_CLOCK_PERIOD);
		end
	endtask  // task show_clk_count 

    task display_fetch_data;
        input [1:0] [63:0] data_read; // data return from cache
        input return_valid; // return data from cache is valid
        input [2:0] insn_taken; // Tailmove in instruction buffer
        input FU_OUT_BRANCH_ENTRY branch_entry;
        // output items
        input INSN_BUFFER_ENTRY [3:0] insnbuffer_input; // Output to instruction buffer
        input logic [31:0] read_addr; // Read address after alignment
        input logic read_valid; // Read address is valid
        $write("\n");
        $display("================================================ fetch data ================================================");
        $display("data read line1: %h", data_read[0]);
        $display("data read line2: %h", data_read[1]);
        $display("read address after alignment: %h", read_addr);
        $display("return_valid | insn_taken | read_valid | branch_result | branch_entry_valid");
        $write("%-12b | ", return_valid);
        $write("%-10d | ", insn_taken);
        $write("%-10b | ", read_valid);
        $write("%-13b | ", branch_entry.branch_result);
        $write("%-18b ", branch_entry.valid);
        if (branch_entry.valid) $display("branch_address: %h", branch_entry.branch_address);
        $write("\n");
        $display("instruction to buffer | validity | PC address");
        for (integer i = 0; i < 4; i ++) begin
            $write("%-21h | ", insnbuffer_input[i].insn); 
            $write("%-8b | ", insnbuffer_input[i].insn_valid);
            $write("%-10h ", insnbuffer_input[i].PC_addr);
            $write("\n");
        end
        $display("==========================================================================================================");
        $write("\n");
    endtask

    task display_insnbuffer;
        input logic [1:0] headmove; // only used to calculate the next available space
        input INST_BUF_PACKET [2:0] insnbuffer_output;
        input logic [2:0] available_entry;
        input logic [2:0] tailmove;
        input INSN_BUFFER_STATE instruction_buffer;
        $write("\n");
        $display("================================================ instruction buffer data ================================================");
        $display("head     =   %d", instruction_buffer.head);
        $display("tail     =   %d", instruction_buffer.tail);
        $display("headmove =   %d", headmove);
        $display("tailmove =   %d", tailmove);
        $display("available=   %d", available_entry);
        $display("----------------------------------------------------------------------------------------------------------");
        $display(" insnbuffer entry | entry_valid | PC_address");
        for (integer i = 0; i < `INSN_BUFFER_SIZE; i ++ ) begin
            $write("%-17d | ", instruction_buffer.insn_buffer_content[i].inst);
            $write("%-12d | ", instruction_buffer.insn_buffer_content[i].valid);
            $write("%-15d ", instruction_buffer.insn_buffer_content[i].PC);
            $write("\n");
        end
        $display("----------------------------------------------------------------------------------------------------------");
        $display("instruction output | validity | PC address");
        for (integer i = 0; i < 3; i ++) begin
            $write("%-18h | ", insnbuffer_output[i].inst); 
            $write("%-8b | ", insnbuffer_output[i].valid);
            $write("%-10h ", insnbuffer_output[i].PC);
            $write("\n");
        end
        $display("==========================================================================================================");
        $write("\n");
    endtask

    // ROB print task
    task display_rob_data;
        input [`ROB_SIZE-1:0] valid;
        input [$clog2(`ROB_SIZE):0] head;
        input [$clog2(`ROB_SIZE):0] tail;
        input ROB_ENTRY [`ROB_SIZE-1:0] rob_data;
        $write("\n");
        $display("================================================ ROB data ================================================");
        $display("head   =   %d", head);
        $display("tail   =   %d", tail);
        $display("----------------------------------------------------------------------------------------------------------");
        $display(" rob entry|entry_valid|rename_preg|rename_preg_old|dest_reg|is_wb_inst|complete|PC |Stack|");
        for(int i = 0 ; i <  `ROB_SIZE ; i = i +1) begin
            $write(" %-8d | ",i);
            $write(" %-8b | ",valid[i]);
            $write("%-10d| ",rob_data[i].rename_preg);
            $write("%-14d| ",rob_data[i].rename_preg_old);
            $write("%-7d| ",rob_data[i].dest_reg);
            $write("%-9d |",rob_data[i].is_wb_inst);
            $write("%-7d| ",rob_data[i].complete);
            $write("%-2h| ",rob_data[i].PC);
            $write("%-4b| ",rob_data[i].branch_stack);
            $write("\n");
        end
        $display("==========================================================================================================");
        $write("\n");
    endtask
    // end ROB print task

    // cdb print task
    task display_cdb_data;
        input [1:0] available_entry;
        input CDB_PACKET [2:0] cdb_packet;
        input PRF_WRITE_PACKET prf_write;
        $write("\n");
        $display("================================================ CDB data ================================================");
        $display("cdb entry|complete_preg|complete_lreg|rob_tail|complete_valid|complete_rob_valid|preg_to_write|preg_value|write_enable|avail_entry|Mask|");
        for(int i = 0 ; i <  3 ; i = i +1) begin
            $write("%-9d| ",i);
            $write("%-12d| ",cdb_packet[i].complete_preg);
            $write("%-12d| ",cdb_packet[i].complete_lreg);
            $write("%-7d| ",cdb_packet[i].rob_tail);
            $write("%-13d| ",cdb_packet[i].complete_valid);
            $write("%-17d| ",cdb_packet[i].complete_rob_valid);
            $write("%-12d| ",prf_write.prf_write_packet[i].preg_to_write);
            $write("%-9d| ",prf_write.prf_write_packet[i].preg_value);
            $write("%-11d| ",prf_write.write_enable[i]);
            $write("%-10d|",available_entry);
            $write("%-4b| ",cdb_packet[i].branch_mask);
            $write("\n");
        end
        $display("==========================================================================================================");
        $write("\n");
    endtask


    // RS print task
    task display_rs_data;
        input RS_ENTRY[`RS_SIZE-1:0] rs_data;
        $write("\n");
        $display("================================================ RS data ================================================");
        $display("RS entry|valid|is_mult_inst|store_inst|wb_inst|renamed_preg|s1_preg|s1_valid|s2_preg|s2_valid|rob_tail| PC |Mask|");
        for(int i = 0 ; i < `RS_SIZE ; i = i +1) begin
            $write("%-8d| ",i);
            $write("%-4d| ",rs_data[i].valid);
            $write("%-11d| ",rs_data[i].is_mult_inst);
            $write("%-9d| ",rs_data[i].is_store_inst);
            $write("%-6d| ",rs_data[i].is_wb_inst);
            $write("%-11d| ",rs_data[i].renamed_preg);
            $write("%-6d| ",rs_data[i].source1_preg.renamed_preg);
            $write("%-7d| ",rs_data[i].source1_preg.valid);
            $write("%-5d | ",rs_data[i].source2_preg.renamed_preg);
            $write("%-7d| ",rs_data[i].source2_preg.valid);
            $write("%-7d|",rs_data[i].rob_tail);
            $write(" %-3h|",rs_data[i].PC);
            $write("%-4b| ",rs_data[i].branch_mask);
            $write("\n");
        end
        $display("==========================================================================================================");
        $write("\n");
    endtask

    task display_rs_issue_data;
        input RS_IN_PACKET rs_data;
        $write("\n");
        $display("================================================ RS in data ================================================");
        $display("RS entry|in_valid|is_mult_inst|store_inst|wb_inst|renamed_preg|s1_preg|s1_valid|s2_preg|s2_valid|rob_tail| PC |Mask");
        for(int i = 0 ; i <  3 ; i = i +1) begin
            $write(" %-7d| ",i);
            $write(" %-5d | ",rs_data.rs_in_packet[i].valid);
            $write(" %-9d | ",rs_data.rs_in_packet[i].is_mult_inst);
            $write(" %-7d | ",rs_data.rs_in_packet[i].is_store_inst);
            $write(" %-4d | ",rs_data.rs_in_packet[i].is_wb_inst);
            $write(" %-9d | ",rs_data.rs_in_packet[i].renamed_preg);
            $write(" %-4d | ",rs_data.rs_in_packet[i].source1_preg.renamed_preg);
            $write(" %-5d | ",rs_data.rs_in_packet[i].source1_preg.valid);
            $write(" %-4d | ",rs_data.rs_in_packet[i].source2_preg.renamed_preg);
            $write(" %-5d | ",rs_data.rs_in_packet[i].source2_preg.valid);
            $write(" %-5d |",rs_data.rs_in_packet[i].rob_tail);
            $write(" %-3h|",rs_data.rs_in_packet[i].PC);
            $write("%-4b| ",rs_data.rs_in_packet[i].branch_mask);
            $write("\n");
        end
        $display("==========================================================================================================");
        $write("\n");
    endtask
    // end cdb print task
    
    task display_mult_in_data;
        input FU_IN_ENTRY mult_data;
        $write("\n");
        $display("================================================ mult data ================================================");
        $display(" valid | is_mult_inst | is_store_inst | is_wb_inst | renamed_preg | rs1_value | rs2_value | PC");
            $write(" %-5d | ",mult_data.valid);
            $write(" %-11d | ",mult_data.is_mult_inst);
            $write(" %-12d | ",mult_data.is_store_inst);
            $write(" %-9d | ",mult_data.is_wb_inst);
            $write(" %-11d | ",mult_data.renamed_preg);
            $write(" %-8d | ",mult_data.rs1_value);
            $write(" %-8d | ",mult_data.rs2_value);
            $write(" %-10h | ",mult_data.PC);
            $write("\n");
        $display("==========================================================================================================");
        $write("\n");
    endtask



    integer errno, fd;
    string error_msg;
    int          wb_fileno;

    task reset_init;
        //$dumpvars;
        // Pulse the reset signal
	    $display("@@\n@@\n@@  %t  Asserting System reset......", $realtime);
		clock = 1'b0;
		reset = 1'b1;
		@(posedge clock);
		@(posedge clock);
		fd = $fopen("program.mem", "r");
        errno = $ferror(fd, error_msg);
        if(errno != 0) begin
            $display("ERROR NUM = %0d MSG = %s", errno, error_msg);
            $finish;
        end
        wb_fileno = $fopen("writeback.out");
        $fclose(fd);
		$readmemh("program.mem", memory.unified_memory);
		@(posedge clock);
		@(posedge clock);
		`SD;
		// This reset is at an odd time to avoid the pos & neg clock edges
		
		reset = 1'b0;
		$display("@@  %t  Deasserting System reset......\n@@\n@@", $realtime);
    endtask
    `ifndef SYNTH_TEST
    task display_cycle;
        $display("########################################################################################################################################\n\n");
        $display("Current Cycle: %5d, completed instructions: %5d.",debug_counter, instr_count);
        $display("branch_valid: %1b, branch_recovery: %1b , branch_correct: %1b , branch_stack: %4b",DUT.bs_2_if.valid, DUT.branch_flush, DUT.branch_correct, DUT.resolved_branch);
        $display("Branch PC: %4h", DUT.bs_2_if.jump_pc);
        $display("ROB branch head: %d",DUT.ROB.head);
        $display("ROB branch tail: %d",DUT.ROB.branch_tail);
        $display("head_retire_0: %d,head_retire_1: %d, head_retire_2 : %d, head_add[1]: %d", DUT.ROB.head_retire_0, DUT.ROB.head_retire_1, DUT.ROB.head_retire_2, DUT.ROB.head_add[0]);
        $display("available_entry: %d", DUT.ROB.entry_available);
        $display("inst_valid_in : %d, %d, %d",DUT.id_packet[0].valid,DUT.id_packet[1].valid,DUT.id_packet[2].valid);
        display_rob_data(DUT.ROB.entry_valid,DUT.ROB.head,DUT.ROB.tail,DUT.ROB.rob_data);
        display_cdb_data(DUT.CDB.cdb_available_entry_num[`CDB_BUFFER_SIZE],DUT.cdb_out,DUT.prf_write);
        $display("tail: %d",DUT.RS.tail);
        $display("num_issued: %d",DUT.RS.num_inst_issued);
        $display("tail_after_compress: %d",DUT.RS.tail_after_compress_comb);
        $display("rs_squash_entry : %b",DUT.RS.rs_squash_entry);
        $display("tail_squash_move : %b",DUT.RS.tail_squash_move[`RS_SIZE-1]);
        display_rs_data(DUT.RS.rs_data);
        display_rs_issue_data(DUT.rs_in_packet);
        // display_mult_in_data(DUT.fu_in.fu_in_packet[3]);
        $display("End of Cycle%5d",debug_counter);
        $display("########################################################################################################################################\n\n");
    endtask
    `endif
    task display_writeback;
        if(rob_out[0].retire_valid) begin
            if(rob_out[0].is_wb_inst)
                $fdisplay(wb_fileno, "PC=%h, REG[%d]=%h",rob_out[0].PC,rob_out[0].arm_entry,preg_out[rob_out[0].new_preg]);
            else
                $fdisplay(wb_fileno, "PC=%h, ---",rob_out[0].PC);
        end
        if(rob_out[1].retire_valid) begin
            if(rob_out[1].is_wb_inst)
                $fdisplay(wb_fileno, "PC=%h, REG[%d]=%h",rob_out[1].PC,rob_out[1].arm_entry,preg_out[rob_out[1].new_preg]);
            else
                $fdisplay(wb_fileno, "PC=%h, ---",rob_out[1].PC);
        end
        if(rob_out[2].retire_valid) begin
            if(rob_out[2].is_wb_inst)
                $fdisplay(wb_fileno, "PC=%h, REG[%d]=%h",rob_out[2].PC,rob_out[2].arm_entry,preg_out[rob_out[2].new_preg]);
            else
                $fdisplay(wb_fileno, "PC=%h, ---",rob_out[2].PC);
        end
    endtask
    `ifndef SYNTH_TEST
    task display_sq_data;
            // sq_data
            input SQ_ENTRY [`LSQ_SIZE-1:0] sq_data;
            input [$clog2(`LSQ_SIZE):0] head;
            input [$clog2(`LSQ_SIZE):0] tail;
            //
            $write("\n");
            $display("==============================================sq_data=====================================================");
            $display(" Entry | valid | complete | retire | cache_valid | branch_mask | address  |  data    | data_offset | PC       | instruction   ");
            for (integer i = 0; i <  `LSQ_SIZE; i ++) begin
            $write(" %-5d |", i);
            $write(" %-5b |", sq_data[i].valid);
            $write(" %-8b |", sq_data[i].complete);
            $write(" %-6b |", sq_data[i].retire);
            $write(" %-11b |", sq_data[i].cache_valid);
            $write(" %-11b |", sq_data[i].branch_mask);
            $write(" %-8h |", sq_data[i].address);
            $write(" %-8h |", sq_data[i].data);
            $write(" %-11d |", sq_data[i].data_offset);
            $write(" %-8h |", sq_data[i].PC);
            $write(" %-11h ", sq_data[i].inst);

            $write("\n");
            end
            $display("head = %d, tail = %d",head,tail);
            $display("==========================================================================================================");
            $write("\n");
    endtask

    task display_lq_data;
    // lq_data
        input LQ_ENTRY[`LSQ_SIZE-1:0] lq_data;
        input LQ_ISSUED_PACKET lq_issued_packet;
        input [$clog2(`LSQ_SIZE)-1:0] head;
        input [$clog2(`LSQ_SIZE)-1:0] tail;

        logic [`LSQ_SIZE-1:0] issued_to_sq;
        logic [`LSQ_SIZE-1:0] issued_to_dcache;
        logic [`LSQ_SIZE-1:0] issued_to_cdb;
        
        assign issued_to_sq = lq_issued_packet.issued_to_sq;
        assign issued_to_dcache = lq_issued_packet.issued_to_dcache;
        assign issued_to_cdb = lq_issued_packet.issued_to_cdb;

        $write("\n");
        
        $display("==============================================lq_data=====================================================");
        $display(" Entry | valid | address_ready | ready_to_search_sq | forwarded | complete | branch_mask | address  |  data    |   sq_complete      | data_offset | forward_data_offset | pc       | sq_tail | rob_tail | preg | issued to sq | issued to dache | issued to cdb ");
        for (integer i = 0; i < `LSQ_SIZE; i ++) begin
        $write(" %-5d |", i);
        $write(" %-5b |", lq_data[i].valid);
        $write(" %-13b |", lq_data[i].address_ready);
        $write(" %-18b |", lq_data[i].ready_to_search_sq);
        $write(" %-9b |", lq_data[i].forwarded);
        $write(" %-8b |", lq_data[i].complete);
        $write(" %-11b |", lq_data[i].branch_mask);
        $write(" %-8h |", lq_data[i].address);
        $write(" %-8h |", lq_data[i].data);
        $write(" %b   |", lq_data[i].sq_complete);
        $write(" %-11d |", lq_data[i].data_offset);
        $write(" %-19b |", lq_data[i].forward_data_offset);
        $write(" %-8h |", lq_data[i].PC);
        $write(" %-7d |", lq_data[i].sq_tail);
        $write(" %-8d |", lq_data[i].rob_tail);
        $write(" %-4d |", lq_data[i].preg);
        $write(" %-12b |", issued_to_sq[i]);
        $write(" %-15b |", issued_to_dcache[i]);
        $write(" %-13d ", issued_to_cdb[i]);
        $write("\n");
        end
        $display("head = %d, tail = %d",head,tail);
        $display("==========================================================================================================");
        $write("\n");

    endtask

    task display_mshr;
        input MSHR_ENTRY [`MSHR_SIZE-1:0] mshr_data;
        $display("============================================ MSHR data ============================================");
        foreach (mshr_data[i]) begin
            $display("MSHR entry: %-2d, valid: %-1d, addr: 0x%-4h, wait_to_issue: %-1d, mem_tag: %-3d", i, mshr_data[i].valid, mshr_data[i].address,  mshr_data[i].wait_to_issue, mshr_data[i].mem2proc_tag);
        end
        $display("");
    endtask

    task display_load_table_array;
        input LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array;
        $display("============================================ Load Table data ============================================");
        for(int j = 0; j <  `MSHR_SIZE; j++) begin
            $display("load_table num : %d",j);
            display_one_load_table(load_table_array[j]);
        end
        $display("");
    endtask

    task display_one_load_table;
        input LOAD_TABLE_PACKET load_table;
        foreach (load_table.load_table[i]) begin
            $display("Load table entry: %-2d, valid: %-1d, addr: 0x%-4h, branch_mask: %-1d, PC: 0x%-4h", i,load_table.load_table[i].valid, load_table.load_table[i].address, load_table.load_table[i].branch_mask, load_table.load_table[i].PC);
        end
        $display("tail: %-3d", load_table.tail);
    endtask

    task display_store_table_array;
        input STORE_TABLE_PACKET [`MSHR_SIZE-1:0] store_table_array;
        $display("============================================ Store Table data ============================================");
        for(int j = 0; j <  `MSHR_SIZE; j++) begin
            $display("store_table num : %d",j);
            display_one_store_table(store_table_array[j]);
        end
        $display("");
    endtask

    task display_one_store_table;
        input STORE_TABLE_PACKET store_table;
        foreach (store_table.store_table[i]) begin
            $display("Store table entry: %-2d, valid: %-1d, addr: 0x%-4h, branch_mask: %-1d, PC: 0x%-4h", i, store_table.store_table[i].valid, store_table.store_table[i].address,  store_table.store_table[i].branch_mask, store_table.store_table[i].PC);
        end
        $display("tail: %-3d", store_table.tail);
    endtask


    task display_lsq_dcache;
        $display("sq_write_pointer : %d",DUT.SQ.write_cache_ptr);
        display_sq_data(DUT.SQ.sq_data,DUT.SQ.head,DUT.SQ.tail);
        $display("lq num_to_squash : %d, tail_rl_1 : %d, tail : %d, branch_recovery_lq_tail_rl  : %d",DUT.LQ.num_to_squash,DUT.LQ.tail_rl_1,DUT.LQ.tail,DUT.LQ.branch_recovery_lq_tail_rl);
        display_lq_data(DUT.LQ.lq_data,DUT.LQ.lq_issued_packet,DUT.LQ.head,DUT.LQ.tail);
        $display("mem2proc_response : %d , dcache2mem_command : %b, dcache2mem_addr : %h, mem2proc_tag : %d",DUT.DCACHE.mem2proc_response,DUT.DCACHE.dcache2mem_command,DUT.DCACHE.dcache2mem_addr,DUT.DCACHE.mem2proc_tag);
        $display("mshr_issue_stall : %b",DUT.DCACHE.mshr_issue_stall);
        $display("branch_recovery : %b",DUT.DCACHE.branch_recovery);
        display_mshr(DUT.DCACHE.mshr_data);//display_mshr(DUT.DCACHE.mshr_data_store_comb);
        display_store_table_array(DUT.DCACHE.store_table_array);
        display_load_table_array(DUT.DCACHE.load_table_array);
        $display("memory_data_to_cache_set_tag : %h",DUT.DCACHE.memory_data_to_cache_set_tag);
        display_dcache(DUT.DCACHE.cache_data);
    endtask
    `endif
    // Branch predictor score board
    integer correct_count;
    integer wrong_count;
    always_ff @(posedge clock) begin
        if(reset) begin
            correct_count <= 0;
            wrong_count <= 0;
        end
        else if(branch_correct) correct_count <= correct_count + 1;
        else if(branch_flush) wrong_count <= wrong_count + 1;
    end

    task display_branch_count;
        real predict_rate;
        predict_rate = (correct_count+1.0-1.0)/ (correct_count + wrong_count);
        $display("@@ Total prediction: %0d, correct prediction: %0d, predicted rate: %f.",correct_count + wrong_count, correct_count, predict_rate);
    endtask

    task display_dcache;
        input DCACHE_SET [`SET-1:0] cache_data;
        logic[16:0] addr;
        $display("============================================ DCACHE data ============================================");
        foreach (cache_data[i]) begin
            $display("dcache_set: %d" , i);
            foreach(cache_data[i].cache_line[j]) begin
                addr = {cache_data[i].cache_line[j].tag, i[2:0], 3'b0};
                $display("dcache line: %-2d, valid: %-1d, addr: 0x%-4h, data : 0x%h, dirty : %-1d", j, cache_data[i].cache_line[j].valid, addr, cache_data[i].cache_line[j].data, cache_data[i].cache_line[j].dirty);
            end
        end
        $display("");
    endtask

    // task display_rob_out;
    //     input ROB_OUT_PACKET [2:0] rob_out_packet_out;
    //     logic[16:0] addr;
    //     $display("============================================ ROB OUT data ============================================");
    //     for(int i = 0; i < 3; i++) begin
    //         display("retire_valid : %d, PC : %h, is_wfi_inst : %b, is_wb_inst");
    //     end
    //     $display("");
    // endtask

    // Show contents of a range of Unified Memory, in both hex and decimal
	task show_mem_with_decimal;
		input [31:0] start_addr;
		input [31:0] end_addr;
        input DCACHE_SET [`SET-1:0] cache_data;
		int showing_data;
        logic [2:0] cache_set;
		begin
			$display("@@@");
			showing_data=0;
			for(int k=start_addr;k<=end_addr; k=k+1) begin
                cache_set = k[2:0];
                if(cache_data[cache_set].cache_line[0].tag == k[12:3] & cache_data[cache_set].cache_line[0].valid & cache_data[cache_set].cache_line[0].dirty) begin
                    if(|cache_data[cache_set].cache_line[0].data) begin
                        $display("@@@ mem[%5d] = %x : %0d", k*8, cache_data[cache_set].cache_line[0].data, cache_data[cache_set].cache_line[0].data);
                        showing_data=1;
                    end
                    else if(showing_data!=0) begin
					$display("@@@");
					showing_data=0;
				end
                end else if(cache_data[cache_set].cache_line[1].tag == k[12:3] & cache_data[cache_set].cache_line[1].valid & cache_data[cache_set].cache_line[1].dirty) begin
                    if(|cache_data[cache_set].cache_line[1].data) begin
                        $display("@@@ mem[%5d] = %x : %0d", k*8, cache_data[cache_set].cache_line[1].data, cache_data[cache_set].cache_line[1].data);
                        showing_data=1;
                    end
                    else if(showing_data!=0) begin
					$display("@@@");
					showing_data=0;
				end
                end else if(cache_data[cache_set].cache_line[2].tag == k[12:3] & cache_data[cache_set].cache_line[2].valid & cache_data[cache_set].cache_line[2].dirty) begin
                    if(|cache_data[cache_set].cache_line[2].data) begin
                        $display("@@@ mem[%5d] = %x : %0d", k*8, cache_data[cache_set].cache_line[2].data, cache_data[cache_set].cache_line[2].data);
                        showing_data=1;
                    end
                    else if(showing_data!=0) begin
					$display("@@@");
					showing_data=0;
				end
                end else if(cache_data[cache_set].cache_line[3].tag == k[12:3] & cache_data[cache_set].cache_line[3].valid & cache_data[cache_set].cache_line[3].dirty) begin
                    if(|cache_data[cache_set].cache_line[3].data) begin
                        $display("@@@ mem[%5d] = %x : %0d", k*8, cache_data[cache_set].cache_line[3].data, cache_data[cache_set].cache_line[3].data);
                        showing_data=1;
                    end
                    else if(showing_data!=0) begin
					$display("@@@");
					showing_data=0;
                    end
                end else if (memory.unified_memory[k] != 0) begin
					$display("@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k], 
				                                            memory.unified_memory[k]);
					showing_data=1;
				end else if(showing_data!=0) begin
					$display("@@@");
					showing_data=0;
				end
            end
			$display("@@@");
		end
	endtask  // task show_mem_with_decimal

    parameter time_limit = 1000000;



    always @(negedge clock) begin
        if(reset) begin
			$display("@@\n@@  %t : System STILL at reset, can't show anything\n@@",
			         $realtime);
            debug_counter <= 0;
        end
        // deal with any halting conditions
		else if(error_status != NO_ERROR || debug_counter > time_limit) begin
            $display("@@@ Unified Memory contents hex on left, decimal on right: ");
			show_mem_with_decimal(0,`MEM_64BIT_LINES - 1, cache_data_out); 
			// 8Bytes per line, 16kB total
			$display("@@  %t : System halted\n@@", $realtime);
			
			case(error_status)
				HALTED_ON_WFI:          
					$display("@@@ System halted on WFI instruction");
				ILLEGAL_INST:
					$display("@@@ System halted on illegal instruction");
			endcase
            if(debug_counter > time_limit) begin
                $display("@@@ Time out.");
            end
			$display("@@@\n@@");
            
            display_branch_count;
			show_clk_count;
            
            $fclose(wb_fileno);
			#20 $finish;
		end
        else begin
            //`ifndef  SYNTH_TEST
            display_writeback();
            //`endif
            debug_counter <= debug_counter + 1;
        end
    end

    initial begin
        reset_init();
    end
endmodule



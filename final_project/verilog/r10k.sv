//////////////////////////////////////////////////////////
//                                                      //
// Module: r10k_top                                     //
//                                                      //
// Description: top module of r10k                      //
//                                                      //
//////////////////////////////////////////////////////////
`ifndef __R10K_TOP_V__
`define __R10K_TOP_V__
`timescale 1ns/100ps
module r10k_top(
    input         clock,                    // System clock
	input         reset,                    // System reset
    
    // Memory interface
	input [3:0]   mem2proc_response,        // Tag from memory about current request
	input [63:0]  mem2proc_data,            // Data coming back from memory
	input [3:0]   mem2proc_tag,              // Tag from memory about current reply
	output logic [1:0]  proc2mem_command,    // command sent to memory
	output logic [`XLEN-1:0] proc2mem_addr,      // Address sent to memory
	output logic [63:0] proc2mem_data,      // Data sent to memory
    /*
    // Virtual cache interface for milestone 2
    input [1:0] [63:0] mem2proc_data, // data return from cache
    input mem2proc_valid, // return data from cache is valid
    output logic [31:0] proc2mem_addr, // Read address after alignment
    output logic proc2mem_command, // Read address is valid
    */
    // Excetion
    output EXCEPTION_CODE   error_status,

    // Output for testbench check
    output ROB_OUT_PACKET [2:0] rob_out_packet_out,
    output DCACHE_SET [7:0] cache_data_out,
    output [`FL_SIZE-1:0] [`XLEN-1:0] preg_out,
    output branch_correct_out,
    output branch_flush_out
);  

    // Internal logic defination //
    logic [63:0]  mem2proc_data_gated;
    assign mem2proc_data_gated = (mem2proc_tag == 0)? 64'b0: mem2proc_data;

    // I-cache, d-cache, mem bus output
    // i-cache
    logic [1:0][63:0] icache_data_out; // Data return from i-cache
    logic [1:0] icache_data_valid;  // Data valid bit
    logic [31:0] icache2mem_addr; // I-cache to memory address
    logic icache2mem_read; // Icache to memory read valid
    logic [3:0] bus2icache_response; // Bus response to i-cache
    // d-cache
    logic [3:0] bus2dcache_response;// Bus response to d-cache
    logic [31:0] dcache2mem_addr; // D-cache address to memory
    // logic [31:0] dcache2mem_data; // D-cache write data to memory
    logic [1:0] dcache2mem_command; // D-cache to memory command

    // Temp assign
    //assign dcache2mem_addr = 0;
    //assign dcache2mem_data = 0;
    //assign dcache2mem_command = BUS_NONE;

    // Instruction fetch, buffer, and decode output
    logic [31:0] proc2Icache_addr;
    logic fetch_valid;
    ID_PACKET [2:0] id_packet; // Output from ID
    INST_BUF_PACKET [3:0] insnbuffer_input; // Instruction buffer input from fetch
    INST_BUF_PACKET [2:0] insnbuffer_output; // Output from instruction buffer
    logic [2:0] insnbuffer_available_entry; // Empty entry count of insnbuffer, 4 of greater than 4
    logic [2:0] insnbuffer_tailmove; // How many instructions that insn buffer accepted from fetch
    logic [3:0][3:0] branch_stack_2_buffer;
    // Packet_Generate output
    ROB_IN_PACKET [2:0] rob_in_packet; // ROB input packet
    MAPTABLE_IN_PACKET_RENAME maptable_in_packet_rename; // Maptable input for renaming register
    logic [5:0][$clog2(`LOGIC_REG_SIZE)-1:0] lreg_read; // Logic register indec for maptable read
    RS_IN_PACKET rs_in_packet;
    logic [1:0] freelist_head_move;
    logic [1:0] inst_buffer_head_move;
    SQ_RESERVE_PACKET sq_reserve_packet;
    LQ_RESERVE_PACKET lq_reserve_packet;

    // ROB output
    ROB_OUT_PACKET [2:0] rob_out_packet; // ROB output packet
    logic [1:0] rob_entry_available; // avaliable entry of ROB
    ROB_TAIL_PACKET rob_tail_out; // rob tail pointer
    ROB_TAIL_SNAP_PACKET rob_tail_snap_packet;
    assign rob_out_packet_out = rob_out_packet;

    // Maptable output
    MAPTABLE_OUT_PACKET maptable_out_packet; // maptable output for logic register read
    MAPTABLE_STATE maptable_state_out; // maptable current state out for branch stack

    // Freelist output
    FREELIST_OUT_PACKET freelist_out_packet; // Output from freelist
    FREELIST_STATE_PACKET freelist_state_out;

    // RS output
    logic [1:0] rs_entry_available;
    RS_OUT_PACKET rs_out;

    // FU_allocate output
    PRF_READIN_PACKET prf_idx;
    FU_IN_PACKET fu_in;

    // execute_stage output
    FU_OUT_PACKET fu_out_packet;
    FU_CDB_PACKET fu_cdb_packet;
    

    // CDB output
    CDB_PACKET [2:0] cdb_out; // CDB output packet
    PRF_WRITE_PACKET prf_write;
    logic rs_stall;

    // Physical register output
    PRF_READOUT_PACKET prf_value;

    // Branch stack output
    logic [$clog2(`ROB_SIZE):0] rob_branch_tail; // rob tail for branch recovery
    logic branch_flush; // Flash pipeline for branch misprediction
    MAPTABLE_IN_PACKET_RECOVERY maptable_in_packet_recovery; // maptable input for branch recovery
    logic branch_mispredict; // Branch has been mispredicted. May need to flush if use a branch stack.
    logic branch_correct; // Branch was correctly predicted. May need to free a branch stack.
    logic [3:0] resolved_branch; // Branch stack which have branch resolved
    FREELIST_STATE_PACKET freelist_recovery; // Freelist recovery state
    BS_2_IF bs_2_if; // Branch stack to instruction fetch packet
    assign branch_flush = |resolved_branch & branch_mispredict;
    assign branch_flush_out = branch_flush;
    assign branch_correct_out = branch_correct;

    // LSQ and D-cache output
    logic [1:0] lq_entry_available;
    logic [1:0] sq_entry_available;
    logic [$clog2(`LSQ_SIZE):0] sq_tail;
    logic [$clog2(`LSQ_SIZE):0] lq_tail;
    logic sq_empty;

    // assign lq_entry_available = 3;
    // assign sq_entry_available = 3;
    // assign sq_tail = 0;
    // assign lq_tail = 0;

    ROB_TO_LQ_PACKET rob_to_lq_packet;
    SQ_TO_LQ_PACKET sq_to_lq_packet;
    CACHE_TO_LQ_PACKET cache_to_lq_packet;
    logic [$clog2(`LSQ_SIZE):0] sq_head;
    logic [`LSQ_SIZE-1:0] completed_store;
    logic [$clog2(`LSQ_SIZE):0] branch_recovery_lq_tail;
    logic [`LSQ_SIZE-1:0] load_accepted_cache;
    LQ_TO_SQ_PACKET lq_to_sq_packet;
    LQ_TO_CACHE_PACKET lq_to_cache_packet;
    FU_OUT_CDB_ENTRY [2:0] lq_to_cdb_packet;

    ROB_TO_SQ_PACKET rob_to_sq_packet;
    CACHE_TO_SQ_PACKET cache_to_sq_packet;
    logic write_cache_ptr_move;
    logic [$clog2(`LSQ_SIZE):0] branch_recovery_sq_tail;
    SQ_TO_CACHE_ENTRY sq_to_cache_packet;

    assign fu_cdb_packet.fu_cdb_packet[0] = fu_out_packet.fu_cdb_packet[0];
    assign fu_cdb_packet.fu_cdb_packet[1] = fu_out_packet.fu_cdb_packet[1];
    assign fu_cdb_packet.fu_cdb_packet[2] = fu_out_packet.fu_cdb_packet[2];
    assign fu_cdb_packet.fu_cdb_packet[3] = fu_out_packet.fu_cdb_packet[3];
    assign fu_cdb_packet.fu_cdb_packet[4] = lq_to_cdb_packet[2];
    assign fu_cdb_packet.fu_cdb_packet[5] = lq_to_cdb_packet[1];
    assign fu_cdb_packet.fu_cdb_packet[6] = lq_to_cdb_packet[0];

    // Exception
    logic wfi_detected, detect_wfi;

    assign detect_wfi = (rob_out_packet[0].is_wfi_inst & rob_out_packet[0].retire_valid)
                        | (rob_out_packet[1].is_wfi_inst & rob_out_packet[1].retire_valid)
                        | (rob_out_packet[2].is_wfi_inst & rob_out_packet[2].retire_valid);
    logic illegal_inst;
    assign illegal_inst = (id_packet[0].valid & id_packet[0].illegal)
                        | (id_packet[1].valid & id_packet[1].illegal)
                        | (id_packet[2].valid & id_packet[2].illegal);

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) error_status <= NO_ERROR;
        else if(wfi_detected & sq_empty) error_status <= HALTED_ON_WFI;
        else if(illegal_inst) error_status <= ILLEGAL_INST;
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) wfi_detected <= 0;
        else if(detect_wfi) wfi_detected <= 1;
    end

    // Submodule instantiate //

    // Dcache
    dcache DCACHE(
        //Input
        .clock(clock),
        .reset(reset),
        .sq_to_cache_packet(sq_to_cache_packet),
        .lq_to_cache_packet(lq_to_cache_packet),
        .branch_recovery(branch_flush),
        .branch_correct(branch_correct),
        .branch_stack(resolved_branch),
        .mem2proc_response(bus2dcache_response),
        .mem2proc_data(mem2proc_data_gated),
        .mem2proc_tag(mem2proc_tag),

        // Output
        .store_write_ptr_move(write_cache_ptr_move),
        .load_accepted_cache(load_accepted_cache),
        .cache_to_lq_packet(cache_to_lq_packet),
        .cache_to_sq_packet(cache_to_sq_packet),
        .dcache2mem_command(dcache2mem_command),
        .dcache2mem_addr(dcache2mem_addr),
        .dcache2mem_data(proc2mem_data),

        .cache_data_out(cache_data_out)
    );

    // Load queue
    assign rob_to_lq_packet.valid[0] = rob_out_packet[0].retire_valid & rob_out_packet[0].is_load_inst;
    assign rob_to_lq_packet.valid[1] = rob_out_packet[1].retire_valid & rob_out_packet[1].is_load_inst;
    assign rob_to_lq_packet.valid[2] = rob_out_packet[2].retire_valid & rob_out_packet[2].is_load_inst;
    assign rob_to_lq_packet.lq_idx[0] = rob_out_packet[0].lq_idx;
    assign rob_to_lq_packet.lq_idx[1] = rob_out_packet[1].lq_idx;
    assign rob_to_lq_packet.lq_idx[2] = rob_out_packet[2].lq_idx;

    assign rob_to_sq_packet.valid[0] = rob_out_packet[0].retire_valid & rob_out_packet[0].is_store_inst;
    assign rob_to_sq_packet.valid[1] = rob_out_packet[1].retire_valid & rob_out_packet[1].is_store_inst;
    assign rob_to_sq_packet.valid[2] = rob_out_packet[2].retire_valid & rob_out_packet[2].is_store_inst;
    assign rob_to_sq_packet.sq_idx[0] = rob_out_packet[0].sq_idx;
    assign rob_to_sq_packet.sq_idx[1] = rob_out_packet[1].sq_idx;
    assign rob_to_sq_packet.sq_idx[2] = rob_out_packet[2].sq_idx;

    LQ LQ(
        //Input
        .clock(clock),
        .reset(reset),
        .lq_reserve_packet(lq_reserve_packet),
        .lq_address_packet(fu_out_packet.fu_lq_packet),
        .rob_to_lq_packet(rob_to_lq_packet),
        .sq_to_lq_packet(sq_to_lq_packet),
        .cache_to_lq_packet(cache_to_lq_packet),
        .sq_head(sq_head),
        .completed_store(completed_store),
        .branch_recovery(branch_flush),
        .branch_correct(branch_correct),
        .branch_stack(resolved_branch),
        .branch_recovery_lq_tail(branch_recovery_lq_tail),
        .load_accepted_cache(load_accepted_cache),
        //Output
        .lq_to_sq_packet(lq_to_sq_packet),
        .lq_to_cache_packet(lq_to_cache_packet),
        .lq_to_cdb_packet(lq_to_cdb_packet),
        .entry_available(lq_entry_available),
        .lq_tail(lq_tail)
    );

    SQ SQ(
        //Input
        .clock(clock),
        .reset(reset),
        .sq_reserve_packet(sq_reserve_packet),
        .sq_complete_packet(fu_out_packet.fu_sq_packet),
        .lq_to_sq_packet(lq_to_sq_packet),
        .rob_to_sq_packet(rob_to_sq_packet),
        .cache_to_sq_packet(cache_to_sq_packet),
        .write_cache_ptr_move(write_cache_ptr_move),
        .branch_recovery(branch_flush),
        .branch_stack(resolved_branch),
        .branch_recovery_sq_tail(branch_recovery_sq_tail),
        //Output
        .sq_head(sq_head),
        .sq_tail(sq_tail),
        .sq_to_lq_packet(sq_to_lq_packet),
        .sq_to_cache_packet(sq_to_cache_packet),
        .entry_available(sq_entry_available),
        .sq_complete(completed_store),
        .empty(sq_empty)
    );

    // Memory bus
    /*
        Assign memory port to i-cache or d-cache
        D-cache get more priority over i-cache
    */
    membus MEMBUS(
        // Input
        .clock(clock),
        .reset(reset),
        .icache2mem_addr(icache2mem_addr),
        .dcache2mem_addr(dcache2mem_addr),
        .dcache2mem_command(dcache2mem_command),
        .icache2mem_read(icache2mem_read),
        .mem2proc_response(mem2proc_response),
        // Output
        .bus2dcache_response(bus2dcache_response),
        .bus2icache_response(bus2icache_response),
        .bus2mem_command(proc2mem_command),
        .bus2mem_addr(proc2mem_addr)
    );

    // Branch Stack
    /*
        Branch stack module take a snapshot of current state when a predicted branch is issued.
        Branch stack will also determined whether the state machine need to be flushed when
        a branch is resolved.
    */
    branch_stack BRANCH_STACK(
        // Input
        .clock(clock),
        .reset(reset),
        .cond_branch(fu_out_packet.fu_cond_branch_packet),
        .uncond_branch(fu_out_packet.fu_uncond_branch_packet),
        .maptable_state_in(maptable_state_out),
        .maptable_in_packet(maptable_in_packet_rename),
        .freelist_state_in(freelist_state_out),
        .rob_packet(rob_out_packet),
        // .rob_tail_packet(rob_tail_out),
        .rob_tail_packet(rob_tail_snap_packet),
        .inst_buf_out(insnbuffer_output[0]),
        .inst_taken(inst_buffer_head_move),
        .cdb_in(cdb_out),
        .lq_tail(lq_tail),
        .sq_tail(sq_tail),
        // Output
        .mispredict(branch_mispredict),
        .correct_predict(branch_correct),
        .resolved_branch(resolved_branch),
        .maptable_recovery(maptable_in_packet_recovery),
        .freelist_recovery(freelist_recovery),
        .rob_tail_recovery(rob_branch_tail),
        .bs_2_if(bs_2_if),
        .lq_tail_recovery(branch_recovery_lq_tail),
        .sq_tail_recovery(branch_recovery_sq_tail)
    );

    // Instruction Cache
    /*
        256 bytes, 32 cache line, 64bit/ 2 instructions per line, no associative
        Prefetch 16 cache line in advance
        Address format
        addr [31 16] [15 8] [7   3] [2  0]
            | 16'b0 | tags | index | 3'b0 |
    */
    icache ICACHE(
        .clock(clock),
        .reset(reset),
        // Input
        .proc2Icache_addr(proc2Icache_addr),
        .fetch_valid(fetch_valid),
        .mem2proc_data(mem2proc_data_gated),
        .mem2proc_response(bus2icache_response),
        .mem2proc_tag(mem2proc_tag),
        // Output
        .icache_data_out(icache_data_out),
        .data_valid(icache_data_valid),
        .icache2mem_addr(icache2mem_addr),
        .icache2mem_read(icache2mem_read)
    );
    // Instruction fetch
    /*
        Temperary mode for milestone 2
        Stall at all unsolved branch
    */
    insn_fetch INSN_FETCH(
        // Input
        .clock(clock),
        .reset(reset),
        .data_read(icache_data_out), // data return from cache
        .return_valid(icache_data_valid), // return data from cache is valid
        .insn_taken(insnbuffer_tailmove), // Tailmove in instruction buffer
        .bs_out(bs_2_if),
        // Output
        .insnbuffer_input(insnbuffer_input), // Output to instruction buffer
        .read_addr(proc2Icache_addr), // Read address after alignment
        .read_valid(fetch_valid), // Read address is valid
        .branch_stack_out(branch_stack_2_buffer)
    );

    // insnbuffer
    // Instruction buffer
    // Buffer for instruction before entering ROB
    insnbuffer INSNBUFFER(
        // Input
        .clock(clock),
        .reset(reset),
        .flush(branch_flush),
        .branch_correct(branch_correct),
        .branch_stack(resolved_branch),
        .insnbuffer_input(insnbuffer_input),
        .headmove(inst_buffer_head_move),
        .branch_stack_in(branch_stack_2_buffer),
        // Output
        .insnbuffer_output(insnbuffer_output),
        .available_entry(insnbuffer_available_entry),
        .tailmove(insnbuffer_tailmove)
    );

    // Decoder
    id_stage ID_STAGE(
        // Input
        .inst_buf_in(insnbuffer_output),
        // Output
        .id_packet_out(id_packet)
    );

    // ROB
    // Reorder buffer for out of order dispatch and in order retire
    ROB ROB(
        // Input
        .clock(clock),
        .rob_in_packet(rob_in_packet),
        .cdb_packet(cdb_out),
        .branch_tail(rob_branch_tail),
        .rob_squash(branch_flush),
        .branch_correct(branch_correct),
        .branch_stack(resolved_branch),
        .reset(reset),
        // Output
        //output current rob tail if current instruction is branch
        //the first bit of current_rob_tail is valid bit
        .rob_out_packet(rob_out_packet),
        .entry_available(rob_entry_available),
        .rob_tail_packet(rob_tail_out),
        .rob_tail_snap_packet(rob_tail_snap_packet)
    );

    // Maptable
    // Store register renaming state
    maptable MAPTABLE(
        // Input
        .clock(clock),
        .reset(reset),
        .maptable_in_packet_rename(maptable_in_packet_rename),
        .maptable_in_packet_recovery(maptable_in_packet_recovery),
        .lreg_read_in(lreg_read),
        .cdb_in(cdb_out),
        // Output
        .maptable_out_packet(maptable_out_packet),
        .current_state_out(maptable_state_out)
    );
    
    // Freelist
    freelist FREELIST(
        // Input
        .clock(clock),
        .reset(reset),
        .rob_packet(rob_out_packet),
        .preg_out_num({1'b0,freelist_head_move}),
        .branch_stack_state(freelist_recovery),
        .squash(branch_flush),
        // Output
        .fl_out(freelist_out_packet),
        .current_state_out(freelist_state_out)
    );
    // Packet generate
    // Generate input packet for ROB, RS, Freelist, instruction buffer during instruction issue
    Packet_Generate PACKET_GENERATE(
        // Input
        .clock(clock),
        .reset(reset),
        .branch_recovery(branch_flush),
        .id_packet(id_packet),
        .maptable_out_packet(maptable_out_packet),
        .freelist_out_packet(freelist_out_packet),
        .rob_tail_packet(rob_tail_out),
        .rob_entry_available(rob_entry_available),
        .rs_entry_available(rs_entry_available),
        .lq_entry_available(lq_entry_available),
        .sq_entry_available(sq_entry_available),
        .sq_tail(sq_tail),
        .lq_tail(lq_tail),
        //.detected_wfi(wfi_detected),
        // Output
        .rob_in_packet(rob_in_packet),
        .rs_in(rs_in_packet),
        .lreg_read(lreg_read),
        .maptable_in_packet(maptable_in_packet_rename),
        .sq_reserve_packet(sq_reserve_packet),
        .lq_reserve_packet(lq_reserve_packet),
        .freelist_head_move(freelist_head_move),
        .inst_buffer_head_move(inst_buffer_head_move)
    );

    RS RS(
        // Input
        .clock(clock),
        .reset(reset),
        .rs_in(rs_in_packet),
        .cdb_in_packet(cdb_out),
        .branch_recovery(branch_flush),
        .branch_correct(branch_correct),
        .branch_stack(resolved_branch),
        .stall(1'b0),
        // Output
        .rs_out(rs_out),
        .available_rs_entry(rs_entry_available)
    );

    FU_allocate FU_ALLOCATE(
        // Input
        .rs_out(rs_out),
        .prf_value(prf_value),
        .branch_recovery(branch_flush),
        .branch_correct(branch_correct),
        .branch_stack(resolved_branch),
        // Output
        .prf_idx(prf_idx),
        .fu_in(fu_in)
    );

    execute_stage EX_STAGE(
        // Input
        .clock(clock),
        .reset(reset),
        .fu_in(fu_in),
        .branch_recovery(branch_flush),
        .branch_correct(branch_correct),
        .branch_stack(resolved_branch),
        // Output
        .fu_out_packet(fu_out_packet)
    );

    cdb_param_early_branch CDB(
        // Input
        .clock(clock),
        .reset(reset),
        .fu_cdb_packet(fu_cdb_packet),

        .branch_recovery(branch_flush),
        .branch_correct(branch_correct),
        .branch_stack(resolved_branch),

        // Output
        .cdb_packet(cdb_out),
        .prf_write(prf_write),
        .rs_stall(rs_stall)
    );

    regfile REGFILE(
        // Input
        .rd_idx(prf_idx),
        .wr_in(prf_write),
        .wr_clk(clock),
        .reset(reset),

        // Output
        .readout(prf_value),
        .preg_out(preg_out)
    );
endmodule

`endif
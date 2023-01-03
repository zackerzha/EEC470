// Instruction fetch for milestone 2
// Stall at any unsolved branch until resolved
`ifndef __INSN_FETCH_V__
`define __INSN_FETCH_V__

`timescale 1ns/100ps
module insn_fetch(
    input clock,
    input reset,
    input [1:0] [63:0] data_read, // data return from cache
    input [1:0] return_valid, // return data from cache is valid
    input [2:0] insn_taken, // Tailmove in instruction buffer
    // input branch_resolve, // Previous branch is resolved
    // input [31:0] branch_pc, PC jump to
    // input FU_OUT_BRANCH_ENTRY branch_entry,
    // input FU_OUT_BRANCH_ENTRY jalr_branch,
    // input mispredict, // Cond branch mispredicted
    input BS_2_IF bs_out,

    output INST_BUF_PACKET [3:0] insnbuffer_input, // Output to instruction buffer
    output logic [31:0] read_addr, // Read address after alignment
    output logic read_valid, // Read address is valid
    output logic [3:0] [3:0] branch_stack_out
    `ifdef DEBUG
    , output logic [31:0] pc
    , output logic [31:0] npc
    , output logic [2:0] valid_out // Number of valid output
    , output logic detect_branch_full
    , output PREDECODE_ENTRY [3:0] predecode
    , output logic branch_stall // Stall for branch
    `endif
);
    `ifndef DEBUG
    logic [31:0] pc, npc;
    logic [2:0] valid_out; // Number of valid output
    logic detect_branch_full; // Detect branch inst when branch stack is full
    logic branch_stall;
    PREDECODE_ENTRY [3:0] predecode;
    `endif
    // logic [2:0] branch_stall_count; // Instruction that cause the stall
    //logic [2:0] valid_out; // Number of valid output
    INST [3:0] inst;
    logic [3:0] return_valid_ff; // Pipelined return valid
    logic take_branch; // Take branch or not from predictor
    logic [31:0] pc_with_branch;
    logic need_predict;
    logic detect_jalr;
    logic [3:0] branch_stack, current_mask;
    logic branch_stall_full; // Stall for branch stack full
    logic branch_stall_jalr; // Stall for unpredicted jalr
    logic stack_full;

    // logic go; 
    // go = 1 when no unresolved branch and insnbuffer took previous input

    assign read_valid = !branch_stall;
    assign branch_stall = branch_stall_full | branch_stall_jalr;

    // PC register
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            pc <= 0;
        end
        else begin
            pc <= npc;
        end
    end

    // Stall register
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            branch_stall_full <= 0;
        end
        else if(detect_branch_full) begin
            branch_stall_full <= 1;
        end
        else if(bs_out.valid & !bs_out.is_uncond & !(|bs_out.branch_stack)) begin
            branch_stall_full <= 0;
        end
        else if(bs_out.valid & !bs_out.is_uncond & (|bs_out.branch_stack) & bs_out.mispredict) begin
            branch_stall_full <= 0;
        end
    end

    // Stall register
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            branch_stall_jalr <= 0;
        end
        else if(detect_jalr) begin
            branch_stall_jalr <= 1;
        end
        else if(bs_out.valid & bs_out.jalr_complete) begin
            branch_stall_jalr <= 0;
        end
        else if(bs_out.valid & !bs_out.is_uncond & bs_out.mispredict) begin
            branch_stall_jalr <= 0;
        end
    end

    // Memory read
    assign read_addr = {npc[`XLEN-1:3], 3'b0};

    // Instruction alignment
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            inst <= '0;
            return_valid_ff <= 0;
        end
        else begin
            if(return_valid[0]) begin
                return_valid_ff[0] <= 1;
                return_valid_ff[1] <= npc[2]? return_valid[1]: 1;
                inst[0].inst <= npc[2]? data_read[0][63:32]:data_read[0][31:0];
                inst[1].inst <= npc[2]? data_read[1][31:0]:data_read[0][63:32];
            end
            else begin
                return_valid_ff[0] <= 0;
                return_valid_ff[1] <= 0;
                inst[0].inst <= 0;
                inst[1].inst <= 0;
            end
            if(return_valid[1]) begin
                return_valid_ff[2] <= return_valid[1];
                return_valid_ff[3] <= npc[2]? 0: return_valid[1];
                inst[2].inst <= npc[2]? data_read[1][63:32]:data_read[1][31:0];
                inst[3].inst <= npc[2]? 32'h0:data_read[1][63:32];
            end
            else begin
                return_valid_ff[2] <= 0;
                return_valid_ff[3] <= 0;
                inst[2].inst <= 0;
                inst[3].inst <= 0;
            end
        end
         // Input check
        assert (reset | !(insn_taken == 5 | insn_taken == 6 | insn_taken == 7));
        assert (reset | !(valid_out == 5 | valid_out == 6 | valid_out == 7));
        assert (reset | insn_taken <= valid_out);
    end

    // Output to insn buffer
    always_comb begin
        // insn 0
        insnbuffer_input[0].inst = inst[0].inst;
        insnbuffer_input[0].valid = |inst[0].inst & return_valid_ff[0] & !branch_stall & !(bs_out.mispredict & bs_out.valid);
        insnbuffer_input[0].PC = pc;
        insnbuffer_input[0].NPC = pc + 4;
        insnbuffer_input[0].pred_pc = predecode[0].jal? predecode[0].jal_npc: predecode[0].cond_branch? npc: '0;
        insnbuffer_input[0].branch_mask = current_mask; // | ({4{predecode[0].cond_branch}} & (branch_stack));
        insnbuffer_input[0].branch_stack = 0;//{4{predecode[0].cond_branch}} & (branch_stack);
        // insn 1
        insnbuffer_input[1].inst = inst[1].inst;
        insnbuffer_input[1].valid = |inst[1].inst & return_valid_ff[1] & insnbuffer_input[0].valid & !predecode[0].jal & !predecode[0].jalr & !predecode[0].cond_branch;
        insnbuffer_input[1].PC = pc + 4;
        insnbuffer_input[1].NPC = pc + 8;
        insnbuffer_input[1].pred_pc = predecode[1].jal? predecode[1].jal_npc: predecode[1].cond_branch? npc: '0;
        insnbuffer_input[1].branch_mask = current_mask; // | ({4{predecode[1].cond_branch}} & (branch_stack));
        insnbuffer_input[1].branch_stack = 0;//{4{predecode[1].cond_branch}} & (branch_stack);
        // insn 2
        insnbuffer_input[2].inst = inst[2].inst;
        insnbuffer_input[2].valid = |inst[2].inst & return_valid_ff[2] & insnbuffer_input[1].valid & !predecode[1].jal & !predecode[1].jalr & !predecode[1].cond_branch;
        insnbuffer_input[2].PC = pc + 8;
        insnbuffer_input[2].NPC = pc + 12;
        insnbuffer_input[2].pred_pc = predecode[2].jal? predecode[2].jal_npc: predecode[2].cond_branch? npc: '0;
        insnbuffer_input[2].branch_mask = current_mask; // | ({4{predecode[2].cond_branch}} & (branch_stack));
        insnbuffer_input[2].branch_stack = 0;//{4{predecode[2].cond_branch}} & (branch_stack);
        // insn 3
        insnbuffer_input[3].inst = inst[3].inst;
        insnbuffer_input[3].valid = |inst[3].inst & return_valid_ff[2] & !pc[2] & insnbuffer_input[2].valid & !predecode[2].jal & !predecode[2].jalr & !predecode[2].cond_branch;
        insnbuffer_input[3].PC = pc + 12;
        insnbuffer_input[3].NPC = pc + 16;
        insnbuffer_input[3].pred_pc = predecode[3].jal? predecode[3].jal_npc: predecode[3].cond_branch? npc: '0;
        insnbuffer_input[3].branch_mask = current_mask; // | ({4{predecode[3].cond_branch}} & (branch_stack));
        insnbuffer_input[3].branch_stack = 0;//{4{predecode[3].cond_branch}} & (branch_stack);
    end

    always_comb begin
        branch_stack_out[0] = {4{predecode[0].cond_branch}} & (branch_stack);
        branch_stack_out[1] = {4{predecode[1].cond_branch}} & (branch_stack);
        branch_stack_out[2] = {4{predecode[2].cond_branch}} & (branch_stack);
        branch_stack_out[3] = {4{predecode[3].cond_branch}} & (branch_stack);
    end
    
    assign valid_out = insnbuffer_input[0].valid 
                    + insnbuffer_input[1].valid 
                    + insnbuffer_input[2].valid 
                    + insnbuffer_input[3].valid; 
    // Branch detection
    // output 1 when detecting a branch instruction get in instruction buffer
    /*
    always_comb begin
        detect_branch_full = 0;
        if ((predecode[0].jalr | predecode[0].cond_branch) & insn_taken == 1) detect_branch_full = 1;
        if ((predecode[1].jalr | predecode[1].cond_branch) & insn_taken == 2) detect_branch_full = 1;
        if ((predecode[2].jalr | predecode[2].cond_branch) & insn_taken == 3) detect_branch_full = 1;
        if ((predecode[3].jalr | predecode[3].cond_branch) & insn_taken == 4) detect_branch_full = 1;
    end
    */
    always_comb begin
        need_predict = 0;
        pc_with_branch = 0;
        detect_jalr = 0;
        detect_branch_full = 0;
        case(insn_taken)
        1: begin
            if(predecode[0].jalr) detect_jalr = 1;
            else if(predecode[0].cond_branch) begin
                pc_with_branch = pc;
                need_predict = 1;
                if(stack_full) detect_branch_full = 1; // Need to stall for cond branch if stack full
            end
        end
        2: begin
            if(predecode[1].jalr) detect_jalr = 1;
            else if(predecode[1].cond_branch) begin
                pc_with_branch = pc + 4;
                need_predict = 1;
                if(stack_full) detect_branch_full = 1; // Need to stall for cond branch if stack full
            end
        end
        3: begin
            if(predecode[2].jalr) detect_jalr = 1;
            else if(predecode[2].cond_branch) begin
                pc_with_branch = pc + 8;
                need_predict = 1;
                if(stack_full) detect_branch_full = 1; // Need to stall for cond branch if stack full
            end
        end
        4: begin
            if(predecode[3].jalr) detect_jalr = 1;
            else if(predecode[3].cond_branch) begin
                pc_with_branch = pc + 12;
                need_predict = 1;
                if(stack_full) detect_branch_full = 1; // Need to stall for cond branch if stack full
            end
        end
        endcase
    end

    // Determine next pc
    always_comb begin
        npc = pc;
        if(bs_out.valid & !bs_out.is_uncond & (bs_out.mispredict | !(|bs_out.branch_stack)) & !bs_out.jalr_complete) begin
            npc = bs_out.jump_pc;
        end
        else if(bs_out.valid & bs_out.jalr_complete) begin
            npc = bs_out.jalr_pc;
        end
        // npc determined by number of instruction taken by buffer
        // If a jal insn is taken, npc = jal_npc
        else if(branch_stall) npc = pc;
        else if(detect_branch_full) npc = pc + 4;
        else if(insn_taken == 1) begin
            if(predecode[0].jal) npc = predecode[0].jal_npc;
            else if(take_branch) npc = predecode[0].cond_npc;
            else npc = pc + 4*1;
        end
        else if(insn_taken == 2) begin
            if(predecode[1].jal) npc = predecode[1].jal_npc;
            else if(take_branch) npc = predecode[1].cond_npc;
            else npc = pc + 4*2;
        end
        else if(insn_taken == 3) begin
            if(predecode[2].jal) npc = predecode[2].jal_npc;
            else if(take_branch) npc = predecode[2].cond_npc;
            else npc = pc + 4*3;
        end
        else if(insn_taken == 4) begin
            if(predecode[3].jal) npc = predecode[3].jal_npc;
            else if(take_branch) npc = predecode[3].cond_npc;
            else npc = pc + 4*4;
        end
        else npc = pc;
    end

    // Predecode module
    predecode PREDECODE_0(.inst(inst[0]), .return_valid(return_valid_ff[0]), .pc(pc+0), .predecode(predecode[0]));
    predecode PREDECODE_1(.inst(inst[1]), .return_valid(return_valid_ff[1]), .pc(pc+4), .predecode(predecode[1]));
    predecode PREDECODE_2(.inst(inst[2]), .return_valid(return_valid_ff[2]), .pc(pc+8), .predecode(predecode[2]));
    predecode PREDECODE_3(.inst(inst[3]), .return_valid(return_valid_ff[3]), .pc(pc+12), .predecode(predecode[3]));

    branch_predictor BRANCH_PREDICTOR(
        .clock(clock),
        .reset(reset),
        // .branch_entry(branch_entry),
        .pc(pc_with_branch),
        .need_predict(need_predict),
        .take_branch(take_branch),
        .bs_out(bs_out),
        .stack_full(stack_full),
        .branch_stack(branch_stack),
        .current_mask(current_mask)
    );

endmodule

// Branch Predictor unit
module branch_predictor(
    input clock,
    input reset,
    // input FU_OUT_BRANCH_ENTRY branch_entry,
    input [31:0] pc,
    input need_predict,
    input BS_2_IF bs_out,

    output logic take_branch,
    output logic stack_full,
    output logic [3:0] branch_stack,
    output logic [3:0] current_mask
);
    /*
     * typedef struct packed{
	 *     logic valid, // The packet is valid
	 *     logic is_uncond, // Is unconditional branch
	 *     logic [31:0] pc, // PC with branch instrution
	 *     logic [31:0] jump_pc, // pc 2 jump to
	 *     logic [3:0] branch_mask,
	 *     logic [3:0] branch_stack,
	 *     logic mispredict, // If mispredict, need flush
	 *     logic take_branch // Whether branch is taken
     * } BS_2_IF;
     */

    logic [3:0] mask_comb;
    logic [3:0] [3:0] branch_stack_mask, branch_stack_mask_comb; // Branch mask for each stack

    // Branch mask for each stack
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            branch_stack_mask <= '0;
        end
        else branch_stack_mask <= branch_stack_mask_comb;
    end

    always_comb begin
        branch_stack_mask_comb = branch_stack_mask;
        if(branch_stack == 4'b0001) begin
            branch_stack_mask_comb[0] = mask_comb;
        end
        else if(branch_stack == 4'b0010) begin
            branch_stack_mask_comb[1] = mask_comb;
        end
        else if(branch_stack == 4'b0100) begin
            branch_stack_mask_comb[2] = mask_comb;
        end
        else if(branch_stack == 4'b1000) begin
            branch_stack_mask_comb[3] = mask_comb;
        end
        // Clear certain bit when a stack is free
        if(bs_out.valid) begin
            branch_stack_mask_comb[0] = branch_stack_mask_comb[0] & ~(bs_out.branch_stack);
            branch_stack_mask_comb[1] = branch_stack_mask_comb[1] & ~(bs_out.branch_stack);
            branch_stack_mask_comb[2] = branch_stack_mask_comb[2] & ~(bs_out.branch_stack);
            branch_stack_mask_comb[3] = branch_stack_mask_comb[3] & ~(bs_out.branch_stack);
        end
    end

    assign stack_full = &current_mask;
    // Random predict
    // assign take_branch = need_predict & !stack_full & pc[2];
    local_history_predictor LHP(
            .clock(clock),
            .reset(reset),
            .branch_prediction_pc(pc),
            .branch_prediction_valid(need_predict & !stack_full),
            .branch_resolved_pc(bs_out.pc),
            .branch_resolved_valid(bs_out.valid & !bs_out.is_uncond),
            .branch_stack_predict(branch_stack),
            .branch_stack_resolved(bs_out.branch_stack),
            .branch_resolved_result(bs_out.take_branch),
            .branch_prediction_result(take_branch)
        );

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) current_mask <= '0;
        else current_mask <= mask_comb;
    end

    // Next branch stack to allocate
    always_comb begin
        branch_stack = 0;
        if(need_predict) begin
            if(!current_mask[0]) branch_stack = 4'b0001;
            else if(!current_mask[1]) branch_stack = 4'b0010;
            else if(!current_mask[2]) branch_stack = 4'b0100;
            else if(!current_mask[3]) branch_stack = 4'b1000;
        end
    end

    always_comb begin
        mask_comb = current_mask;
        if(bs_out.valid & bs_out.mispredict) begin
            mask_comb[0] = mask_comb[0] & !(|(bs_out.branch_stack & branch_stack_mask[0]));
            mask_comb[1] = mask_comb[1] & !(|(bs_out.branch_stack & branch_stack_mask[1]));
            mask_comb[2] = mask_comb[2] & !(|(bs_out.branch_stack & branch_stack_mask[2]));
            mask_comb[3] = mask_comb[3] & !(|(bs_out.branch_stack & branch_stack_mask[3]));
        end
        else if(bs_out.valid & !bs_out.mispredict) begin
            mask_comb = mask_comb & ~bs_out.branch_stack;
        end
        if(need_predict) begin
            mask_comb = mask_comb | branch_stack;
        end
    end
endmodule

// Instruction fetch stage predecode for branch detection
module predecode(
    input INST inst,
    input return_valid,
    input [31:0] pc,
    output PREDECODE_ENTRY predecode
);
    always_comb begin
        predecode.jal = 0;
        predecode.jalr = 0;
        predecode.cond_branch = 0;
        predecode.jal_npc = 0;
        predecode.cond_npc = 0;
        if(return_valid) begin
            casez(inst)
                `RV32_JAL: begin
                    predecode.jal = 1;
                    predecode.jal_npc = `RV32_signext_Jimm(inst) + pc;
                end
                `RV32_JALR: begin
                    predecode.jalr = 1;
                end
                `RV32_BEQ, `RV32_BNE, `RV32_BLT, `RV32_BGE,
				`RV32_BLTU, `RV32_BGEU: begin
					predecode.cond_branch = `TRUE;
                    predecode.cond_npc = `RV32_signext_Bimm(inst) + pc;
				end
                default: begin
                    predecode.jal = 0;
                    predecode.jalr = 0;
                    predecode.cond_branch = 0;
                    predecode.jal_npc = 0;
                    predecode.cond_npc = 0;
                end
            endcase
        end
    end
endmodule 

`endif
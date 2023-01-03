module branch_stack(
    input clock,
    input reset,
    input FU_OUT_BRANCH_ENTRY cond_branch, // Conditional branch output from FU
    input FU_OUT_BRANCH_ENTRY [2:0] uncond_branch, // Unconditional branch output from FU
    input MAPTABLE_STATE maptable_state_in,
    input MAPTABLE_IN_PACKET_RENAME maptable_in_packet,
    input FREELIST_STATE_PACKET freelist_state_in,
    input ROB_OUT_PACKET [2:0] rob_packet, 
    input ROB_TAIL_SNAP_PACKET rob_tail_packet,
    input INST_BUF_PACKET inst_buf_out,
    input [1:0] inst_taken,
    input CDB_PACKET [2:0] cdb_in,
    input [$clog2(`LSQ_SIZE):0] lq_tail,
    input [$clog2(`LSQ_SIZE):0] sq_tail,

    output logic mispredict,
    output logic correct_predict,
    output logic [3:0] resolved_branch,
    output MAPTABLE_IN_PACKET_RECOVERY maptable_recovery,
    output FREELIST_STATE_PACKET freelist_recovery,
    output logic [$clog2(`ROB_SIZE):0] rob_tail_recovery,
    output BS_2_IF bs_2_if,
    output logic [$clog2(`LSQ_SIZE):0] lq_tail_recovery,
    output logic [$clog2(`LSQ_SIZE):0] sq_tail_recovery
);

    logic [3:0] snapshot; // Make one stack entry to make snapshot
    logic [3:0] free_stack; // Free the resolved stack entry
    MAPTABLE_STATE [3:0] maptable_recovery_stack;
    FREELIST_STATE_PACKET [3:0] freelist_recovery_stack;
    logic [3:0] [$clog2(`ROB_SIZE):0] rob_tail_recovery_stack;
    logic [3:0] bs_valid;
    logic [3:0] [3:0] branch_stack_mask, branch_stack_mask_comb; // Branch mask for each stack

    logic [3:0] resolved_stack;
    logic [3:0] [31:0] bs_pc_out;
    logic [3:0] [$clog2(`LSQ_SIZE):0] lq_tail_recovery_stack;
    logic [3:0] [$clog2(`LSQ_SIZE):0] sq_tail_recovery_stack;

    assign resolved_stack = cond_branch.valid? cond_branch.branch_stack: 0;

    always_comb begin
        bs_2_if = '0;
        if(cond_branch.valid) begin
            bs_2_if.valid = 1;
            bs_2_if.is_uncond = 0;
            bs_2_if.pc = cond_branch.PC;
            bs_2_if.jump_pc = cond_branch.branch_result? cond_branch.branch_address: cond_branch.PC+4;
            bs_2_if.branch_mask = (resolved_stack == 1)? branch_stack_mask[0]:
                                  (resolved_stack == 2)? branch_stack_mask[1]:
                                  (resolved_stack == 4)? branch_stack_mask[2]:
                                  (resolved_stack == 8)? branch_stack_mask[3]: 0;
            bs_2_if.branch_stack = resolved_stack;
            bs_2_if.mispredict = mispredict;
            bs_2_if.take_branch = cond_branch.branch_result;
        end
        if((!mispredict & cond_branch.valid) | !cond_branch.valid) begin
            if(uncond_branch[0].valid & uncond_branch[0].is_jalr) begin
                bs_2_if.valid = 1;
                bs_2_if.jalr_pc = uncond_branch[0].branch_address;
                bs_2_if.jalr_complete = 1;
            end
            else if(uncond_branch[1].valid & uncond_branch[1].is_jalr) begin
                bs_2_if.valid = 1;
                bs_2_if.jalr_pc = uncond_branch[1].branch_address;
                bs_2_if.jalr_complete = 1;
            end
            else if(uncond_branch[2].valid & uncond_branch[2].is_jalr) begin
                bs_2_if.valid = 1;
                bs_2_if.jalr_pc = uncond_branch[2].branch_address;
                bs_2_if.jalr_complete = 1;
            end
        end
    end

    // Take snapshot
    always_comb begin
        snapshot = 4'b0;
        if(inst_taken != 0) begin
            snapshot = inst_buf_out.branch_stack;
        end
    end

    // Branch mask for each stack
    always_comb begin
        branch_stack_mask_comb = branch_stack_mask;
        if(inst_buf_out.branch_stack == 4'b0001) begin
            branch_stack_mask_comb[0] = inst_buf_out.branch_mask;
        end
        else if(inst_buf_out.branch_stack == 4'b0010) begin
            branch_stack_mask_comb[1] = inst_buf_out.branch_mask;
        end
        else if(inst_buf_out.branch_stack == 4'b0100) begin
            branch_stack_mask_comb[2] = inst_buf_out.branch_mask;
        end
        else if(inst_buf_out.branch_stack == 4'b1000) begin
            branch_stack_mask_comb[3] = inst_buf_out.branch_mask;
        end
        if(correct_predict) begin
            branch_stack_mask_comb[0] = branch_stack_mask_comb[0] & !resolved_branch;
            branch_stack_mask_comb[1] = branch_stack_mask_comb[1] & !resolved_branch;
            branch_stack_mask_comb[2] = branch_stack_mask_comb[2] & !resolved_branch;
            branch_stack_mask_comb[3] = branch_stack_mask_comb[3] & !resolved_branch;
        end
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            branch_stack_mask <= '0;
        end
        else branch_stack_mask <= branch_stack_mask_comb;
    end

    // Branch resolve
    always_comb begin
        correct_predict = 0;
        mispredict = 0;
        resolved_branch = 0;
        maptable_recovery = '0;
        freelist_recovery = '0;
        rob_tail_recovery = '0;
        lq_tail_recovery = 0;
        sq_tail_recovery = 0;
        if(cond_branch.valid) begin
            case(cond_branch.branch_stack)
            4'b0001: begin
                correct_predict = cond_branch.branch_result? (cond_branch.branch_address == cond_branch.NPC) : (bs_pc_out[0] + 4 == cond_branch.NPC);
                mispredict = cond_branch.branch_result? (cond_branch.branch_address != cond_branch.NPC) : (bs_pc_out[0] + 4 != cond_branch.NPC);
                resolved_branch = 4'b0001;
                maptable_recovery.maptable_branchstack = maptable_recovery_stack[0];
                maptable_recovery.branch_recover = mispredict;
                freelist_recovery = freelist_recovery_stack[0];
                rob_tail_recovery = rob_tail_recovery_stack[0];
                lq_tail_recovery = lq_tail_recovery_stack[0];
                sq_tail_recovery = sq_tail_recovery_stack[0];
            end
            4'b0010: begin
                correct_predict = cond_branch.branch_result? (cond_branch.branch_address == cond_branch.NPC) : (bs_pc_out[1] + 4 == cond_branch.NPC);
                mispredict = cond_branch.branch_result? (cond_branch.branch_address != cond_branch.NPC) : (bs_pc_out[1] + 4 != cond_branch.NPC);
                resolved_branch = 4'b0010;
                maptable_recovery.maptable_branchstack = maptable_recovery_stack[1];
                maptable_recovery.branch_recover = mispredict;
                freelist_recovery = freelist_recovery_stack[1];
                rob_tail_recovery = rob_tail_recovery_stack[1];
                lq_tail_recovery = lq_tail_recovery_stack[1];
                sq_tail_recovery = sq_tail_recovery_stack[1];
            end
            4'b0100: begin
                correct_predict = cond_branch.branch_result? (cond_branch.branch_address == cond_branch.NPC) : (bs_pc_out[2] + 4 == cond_branch.NPC);
                mispredict = cond_branch.branch_result? (cond_branch.branch_address != cond_branch.NPC) : (bs_pc_out[2] + 4 != cond_branch.NPC);
                resolved_branch = 4'b0100;
                maptable_recovery.maptable_branchstack = maptable_recovery_stack[2];
                maptable_recovery.branch_recover = mispredict;
                freelist_recovery = freelist_recovery_stack[2];
                rob_tail_recovery = rob_tail_recovery_stack[2];
                lq_tail_recovery = lq_tail_recovery_stack[2];
                sq_tail_recovery = sq_tail_recovery_stack[2];
            end
            4'b1000: begin
                correct_predict = cond_branch.branch_result? (cond_branch.branch_address == cond_branch.NPC) : (bs_pc_out[3] + 4 == cond_branch.NPC);
                mispredict = cond_branch.branch_result? (cond_branch.branch_address != cond_branch.NPC) : (bs_pc_out[3] + 4 != cond_branch.NPC);
                resolved_branch = 4'b1000;
                maptable_recovery.maptable_branchstack = maptable_recovery_stack[3];
                maptable_recovery.branch_recover = mispredict;
                freelist_recovery = freelist_recovery_stack[3];
                rob_tail_recovery = rob_tail_recovery_stack[3];
                lq_tail_recovery = lq_tail_recovery_stack[3];
                sq_tail_recovery = sq_tail_recovery_stack[3];
            end
            default: begin
                correct_predict = 0;
                mispredict = 0;
                resolved_branch = 4'b0000;
                maptable_recovery = '0;
                freelist_recovery = '0;
                rob_tail_recovery = '0;
            end
            endcase
        end
    end

    // Free branch stack during branch resolve
    always_comb begin
        free_stack = 0;
        if(cond_branch.valid & mispredict) begin
            free_stack[0] = bs_valid[0] & |(cond_branch.branch_stack & branch_stack_mask[0]);
            free_stack[1] = bs_valid[1] & |(cond_branch.branch_stack & branch_stack_mask[1]);
            free_stack[2] = bs_valid[2] & |(cond_branch.branch_stack & branch_stack_mask[2]);
            free_stack[3] = bs_valid[3] & |(cond_branch.branch_stack & branch_stack_mask[3]);
        end
        else if(cond_branch.valid & !mispredict) begin
            free_stack = cond_branch.branch_stack;
        end
    end

    branch_stack_entry #(.BRANCH_BIT(4'b0001)) BS_0001(
        // Input
        .clock(clock),
        .reset(reset),
        .snapshot(snapshot[0]),
        .maptable_state_in(maptable_state_in),
        .maptable_in_packet(maptable_in_packet),
        .freelist_state_in(freelist_state_in),
        .rob_packet(rob_packet),
        .rob_tail_packet(rob_tail_packet),
        .cdb_in(cdb_in),
        .free_stack(free_stack[0]),
        .pc_in(inst_buf_out.PC),
        .lq_tail(lq_tail),
        .sq_tail(sq_tail),
        // Output
        .maptable_recovery_out(maptable_recovery_stack[0]),
        .freelist_recovery(freelist_recovery_stack[0]),
        .rob_tail_recovery(rob_tail_recovery_stack[0]),
        .bs_valid(bs_valid[0]),
        .pc_out(bs_pc_out[0]),
        .lq_tail_recovery(lq_tail_recovery_stack[0]),
        .sq_tail_recovery(sq_tail_recovery_stack[0])
    );

    branch_stack_entry #(.BRANCH_BIT(4'b0010)) BS_0010(
        // Input
        .clock(clock),
        .reset(reset),
        .snapshot(snapshot[1]),
        .maptable_state_in(maptable_state_in),
        .maptable_in_packet(maptable_in_packet),
        .freelist_state_in(freelist_state_in),
        .rob_packet(rob_packet),
        .rob_tail_packet(rob_tail_packet),
        .cdb_in(cdb_in),
        .free_stack(free_stack[1]),
        .pc_in(inst_buf_out.PC),
        .lq_tail(lq_tail),
        .sq_tail(sq_tail),
        // Output
        .maptable_recovery_out(maptable_recovery_stack[1]),
        .freelist_recovery(freelist_recovery_stack[1]),
        .rob_tail_recovery(rob_tail_recovery_stack[1]),
        .bs_valid(bs_valid[1]),
        .pc_out(bs_pc_out[1]),
        .lq_tail_recovery(lq_tail_recovery_stack[1]),
        .sq_tail_recovery(sq_tail_recovery_stack[1])
    );

    branch_stack_entry #(.BRANCH_BIT(4'b0100)) BS_0100(
        // Input
        .clock(clock),
        .reset(reset),
        .snapshot(snapshot[2]),
        .maptable_state_in(maptable_state_in),
        .maptable_in_packet(maptable_in_packet),
        .freelist_state_in(freelist_state_in),
        .rob_packet(rob_packet),
        .rob_tail_packet(rob_tail_packet),
        .cdb_in(cdb_in),
        .free_stack(free_stack[2]),
        .pc_in(inst_buf_out.PC),
        .lq_tail(lq_tail),
        .sq_tail(sq_tail),
        // Output
        .maptable_recovery_out(maptable_recovery_stack[2]),
        .freelist_recovery(freelist_recovery_stack[2]),
        .rob_tail_recovery(rob_tail_recovery_stack[2]),
        .bs_valid(bs_valid[2]),
        .pc_out(bs_pc_out[2]),
        .lq_tail_recovery(lq_tail_recovery_stack[2]),
        .sq_tail_recovery(sq_tail_recovery_stack[2])
    );

    branch_stack_entry #(.BRANCH_BIT(4'b1000)) BS_1000(
        // Input
        .clock(clock),
        .reset(reset),
        .snapshot(snapshot[3]),
        .maptable_state_in(maptable_state_in),
        .maptable_in_packet(maptable_in_packet),
        .freelist_state_in(freelist_state_in),
        .rob_packet(rob_packet),
        .rob_tail_packet(rob_tail_packet),
        .cdb_in(cdb_in),
        .free_stack(free_stack[3]),
        .pc_in(inst_buf_out.PC),
        .lq_tail(lq_tail),
        .sq_tail(sq_tail),
        // Output
        .maptable_recovery_out(maptable_recovery_stack[3]),
        .freelist_recovery(freelist_recovery_stack[3]),
        .rob_tail_recovery(rob_tail_recovery_stack[3]),
        .bs_valid(bs_valid[3]),
        .pc_out(bs_pc_out[3]),
        .lq_tail_recovery(lq_tail_recovery_stack[3]),
        .sq_tail_recovery(sq_tail_recovery_stack[3])
    );

endmodule

module branch_stack_entry #(parameter BRANCH_BIT = 4'b0001) 
//synopsys template
(
    input clock,
    input reset,
    input snapshot,
    input MAPTABLE_STATE maptable_state_in,
    input MAPTABLE_IN_PACKET_RENAME maptable_in_packet,
    input FREELIST_STATE_PACKET freelist_state_in,
    input ROB_OUT_PACKET [2:0] rob_packet, 
    input ROB_TAIL_SNAP_PACKET rob_tail_packet,
    input CDB_PACKET [2:0] cdb_in,
    input free_stack, // Free this stack
    input [31:0] pc_in,
    input [$clog2(`LSQ_SIZE):0] lq_tail,
    input [$clog2(`LSQ_SIZE):0] sq_tail,

    output MAPTABLE_STATE maptable_recovery_out,
    output FREELIST_STATE_PACKET freelist_recovery,
    output logic [$clog2(`ROB_SIZE):0] rob_tail_recovery,
    output logic bs_valid,
    output logic [31:0] pc_out,
    output logic [$clog2(`LSQ_SIZE):0] lq_tail_recovery,
    output logic [$clog2(`LSQ_SIZE):0] sq_tail_recovery
);
    // parameter BRANCH_BIT = 4'b0001;
    MAPTABLE_STATE maptable_recovery, maptable_comb;
    assign maptable_recovery_out = maptable_comb;

    // State machine
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            bs_valid <= 0;
            pc_out <= 0;
        end
        else if(snapshot) begin
            bs_valid <= 1;
            pc_out <= pc_in;
        end
        else if(free_stack) begin
            bs_valid <= 0;
            pc_out <= 0;
        end
    end

    // Rob tail, load tail, store tail
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset | free_stack) begin
            rob_tail_recovery <= 0;
            lq_tail_recovery <= 0;
            sq_tail_recovery <= 0;
        end
        else if(snapshot) begin
            rob_tail_recovery <= rob_tail_packet.rob_tail[1];
            lq_tail_recovery <= lq_tail;
            sq_tail_recovery <= sq_tail;
        end
    end

    // Maptable
    always_comb begin
        if(snapshot) begin
            maptable_comb = maptable_state_in;
            if(maptable_in_packet.renaming_valid[0]) begin
                maptable_comb.lreg[maptable_in_packet.renaming_lreg[0]].renamed_preg = maptable_in_packet.renaming_preg[0];
                maptable_comb.lreg[maptable_in_packet.renaming_lreg[0]].valid = 1'b0;
            end
            for(int i = 0; i < 3; i++) begin
                if(cdb_in[i].complete_valid) begin
                    maptable_comb.lreg[cdb_in[i].complete_lreg].valid = 1'b1;
                end
            end
        end
        else begin
            maptable_comb = maptable_recovery;
            for(int i = 0; i < 3; i++) begin
                if(cdb_in[i].complete_valid) begin
                    if(!(|(cdb_in[i].branch_mask & BRANCH_BIT))) begin // Check branch mask whether the inst is before the branch
                        maptable_comb.lreg[cdb_in[i].complete_lreg].valid = 1'b1;
                    end
                end
            end
        end
    end
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            for(int i = 0; i < 32; i++) begin
                maptable_recovery.lreg[i].valid <= 1'b1;
                maptable_recovery.lreg[i].renamed_preg <= i;
            end
        end
        else maptable_recovery <= maptable_comb;
    end

    // Branch stack freelist
    FREELIST_ENTRY [`FREELIST_FIFO_SIZE-1:0] free_list; //freelist
    FREELIST_ENTRY [`FREELIST_FIFO_SIZE-1:0] free_list_comb; //comb freelist
    FREELIST_STATE_PACKET freelist_comb;
    logic [2:0][$clog2(`FL_SIZE)-1:0] preg_2b_freed;
    logic [2:0] valid_preg_in;
    logic [1:0] preg_in_num;
    logic [$clog2(`FREELIST_FIFO_SIZE):0] write_ptr, write_ptr_comb;
    logic [$clog2(`FREELIST_FIFO_SIZE):0] read_ptr, read_ptr_comb;
    assign valid_preg_in[0] = rob_packet[0].is_wb_inst & rob_packet[0].retire_valid;
    assign valid_preg_in[1] = rob_packet[1].is_wb_inst & rob_packet[1].retire_valid;
    assign valid_preg_in[2] = rob_packet[2].is_wb_inst & rob_packet[2].retire_valid;
    assign preg_in_num = valid_preg_in[0] + valid_preg_in[1] + valid_preg_in[2];

    always_comb begin
        preg_2b_freed[0] = 0;
        preg_2b_freed[1] = 0;
        preg_2b_freed[2] = 0;

        if(valid_preg_in[0]) preg_2b_freed[0] = rob_packet[0].free_preg;
        else if(valid_preg_in[1]) preg_2b_freed[0] = rob_packet[1].free_preg;
        else if(valid_preg_in[2]) preg_2b_freed[0] = rob_packet[2].free_preg;

        if(&valid_preg_in[1:0]) preg_2b_freed[1] = rob_packet[1].free_preg;
        else if (^valid_preg_in[1:0]) preg_2b_freed[1] = rob_packet[2].free_preg;

        if(preg_in_num == 3) preg_2b_freed[2] = rob_packet[2].free_preg;
    end

    always_comb begin //free regs
        free_list_comb = free_list;
        if(preg_in_num == 3) begin
            free_list_comb[write_ptr].renamed_preg = preg_2b_freed[0];
            if(write_ptr + 1 >= `FREELIST_FIFO_SIZE) free_list_comb[0].renamed_preg = preg_2b_freed[1];
            else free_list_comb[write_ptr+1].renamed_preg = preg_2b_freed[1];
            if(write_ptr + 2 >= `FREELIST_FIFO_SIZE) free_list_comb[write_ptr + 2 - `FREELIST_FIFO_SIZE].renamed_preg = preg_2b_freed[2];
            else free_list_comb[write_ptr+2].renamed_preg = preg_2b_freed[2];
        end
        else if(preg_in_num == 2) begin
            free_list_comb[write_ptr].renamed_preg = preg_2b_freed[0];
            if(write_ptr + 1 >= `FREELIST_FIFO_SIZE) free_list_comb[0].renamed_preg = preg_2b_freed[1];
            else free_list_comb[write_ptr+1].renamed_preg = preg_2b_freed[1];
        end
        else if(preg_in_num == 1) begin
            free_list_comb[write_ptr].renamed_preg = preg_2b_freed[0];
        end
    end

    assign write_ptr_comb = write_ptr + preg_in_num >= `FREELIST_FIFO_SIZE ? write_ptr + preg_in_num - `FREELIST_FIFO_SIZE 
                                                                            : write_ptr + preg_in_num;
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset | free_stack) begin
            write_ptr <= '0;
            read_ptr <= '0;
            for(integer unsigned i = 0; i < `FREELIST_FIFO_SIZE; i=i+1)begin
                free_list[i].renamed_preg <= i + 32;
                free_list[i].valid <= 1;
            end
        end
        else if(snapshot) begin
            free_list <= freelist_state_in.free_list;
            write_ptr <= freelist_state_in.write_ptr;
            read_ptr <= freelist_state_in.read_ptr;
        end
        else if(bs_valid) begin
            free_list <= free_list_comb;
            write_ptr <= write_ptr_comb;
        end
    end

    assign freelist_recovery.free_list = free_list_comb;
    assign freelist_recovery.read_ptr = read_ptr;
    assign freelist_recovery.write_ptr = write_ptr_comb;
endmodule
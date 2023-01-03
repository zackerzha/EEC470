`timescale 1ns/100ps
module FU_allocate(
    // output from RS
    input RS_OUT_PACKET rs_out,
    // get operand value which used by FU from physical register file
    input PRF_READOUT_PACKET prf_value,

    input branch_recovery,
    input branch_correct,
    input [`BRANCH_STACK_SIZE-1:0] branch_stack,

    // output ro physical register file to get the value
    output PRF_READIN_PACKET prf_idx,
    // write to physical register file
    output FU_IN_PACKET fu_in
    
);  
    logic [3:0] inst_valid;
    logic [3:0] is_inst_mult;
    logic [3:0] is_inst_cond_branch;
    // the location of mult instruction in rs_out
    logic [1:0] inst_mult_idx;
    // the location of branch instruction in rs_out
    logic [1:0] inst_branch_idx;

    logic [2:0] squash_after_branch;

    assign inst_valid[0] = rs_out.inst_valid[0];
    assign inst_valid[1] = rs_out.inst_valid[1];
    assign inst_valid[2] = rs_out.inst_valid[2];
    assign inst_valid[3] = 0;

    // is_mult_inst only has one hot bit
    assign is_inst_mult[0] = inst_valid[0] && rs_out.rs_out_packet[0].is_mult_inst;
    assign is_inst_mult[1] = inst_valid[1] && rs_out.rs_out_packet[1].is_mult_inst;
    assign is_inst_mult[2] = inst_valid[2] && rs_out.rs_out_packet[2].is_mult_inst;
    assign is_inst_mult[3] = 0;
    // is_inst_cond_branch only has one hot bit
    assign is_inst_cond_branch[0] = inst_valid[0] && rs_out.rs_out_packet[0].is_cond_branch_inst;
    assign is_inst_cond_branch[1] = inst_valid[1] && rs_out.rs_out_packet[1].is_cond_branch_inst;
    assign is_inst_cond_branch[2] = inst_valid[2] && rs_out.rs_out_packet[2].is_cond_branch_inst;
    assign is_inst_cond_branch[3] = 0;
    // read the physical register file
    // send preg idx to physical register file
    generate
        genvar j;
        for(j = 0; j < 3; j=j+1) begin:read_prf
            assign prf_idx.prf_readin_packet[j].inst_source1_preg = rs_out.rs_out_packet[j].source1_preg.renamed_preg;
            assign prf_idx.prf_readin_packet[j].inst_source2_preg = rs_out.rs_out_packet[j].source2_preg.renamed_preg;
        end
    endgenerate

    assign squash_after_branch[0] = branch_recovery & (|(branch_stack & rs_out.rs_out_packet[0].branch_mask)) & inst_valid[0];
    assign squash_after_branch[1] = branch_recovery & (|(branch_stack & rs_out.rs_out_packet[1].branch_mask)) & inst_valid[1];
    assign squash_after_branch[2] = branch_recovery & (|(branch_stack & rs_out.rs_out_packet[2].branch_mask)) & inst_valid[2];

    // get the index of condition branch in three issued instruction
    pe #(.IN_WIDTH(4)) encoder_branch  (.gnt(is_inst_cond_branch), .enc(inst_branch_idx)); //inst_branch_idx can only be 0,1,2
    assign fu_in.branch_valid = |is_inst_cond_branch & !squash_after_branch[inst_branch_idx];
    assign fu_in.inst_branch_idx = inst_branch_idx;


    // generate the input to three alu function unit, valid represent whether the specific alu function unit will be used
    generate
        genvar i;
        for(i = 0; i < 3; i = i+1) begin:alu_packet
            assign fu_in.fu_in_packet[i].valid = inst_valid[i] & !is_inst_mult[i] & !squash_after_branch[i];
            assign fu_in.fu_in_packet[i].is_mult_inst = is_inst_mult[i];
            assign fu_in.fu_in_packet[i].is_store_inst = rs_out.rs_out_packet[i].is_store_inst;
            assign fu_in.fu_in_packet[i].is_load_inst = rs_out.rs_out_packet[i].is_load_inst;
            assign fu_in.fu_in_packet[i].is_cond_branch_inst = rs_out.rs_out_packet[i].is_cond_branch_inst;
            assign fu_in.fu_in_packet[i].is_uncond_branch_inst = rs_out.rs_out_packet[i].is_uncond_branch_inst;
            assign fu_in.fu_in_packet[i].is_wb_inst = rs_out.rs_out_packet[i].is_wb_inst;
            assign fu_in.fu_in_packet[i].renamed_preg = rs_out.rs_out_packet[i].renamed_preg;
            assign fu_in.fu_in_packet[i].rob_tail = rs_out.rs_out_packet[i].rob_tail;
            assign fu_in.fu_in_packet[i].sq_idx = rs_out.rs_out_packet[i].sq_idx;
            assign fu_in.fu_in_packet[i].lq_idx = rs_out.rs_out_packet[i].lq_idx;
            assign fu_in.fu_in_packet[i].rs1_idx = rs_out.rs_out_packet[i].source1_preg.renamed_preg;
            assign fu_in.fu_in_packet[i].rs2_idx = rs_out.rs_out_packet[i].source2_preg.renamed_preg;
            assign fu_in.fu_in_packet[i].rs1_value = prf_value.prf_readout_packet[i].inst_source1_value;
            assign fu_in.fu_in_packet[i].rs2_value = prf_value.prf_readout_packet[i].inst_source2_value;
            assign fu_in.fu_in_packet[i].branch_mask = branch_correct ? rs_out.rs_out_packet[i].branch_mask & ~branch_stack : rs_out.rs_out_packet[i].branch_mask;
            assign fu_in.fu_in_packet[i].branch_stack = rs_out.rs_out_packet[i].branch_stack;
            assign fu_in.fu_in_packet[i].alu_function = rs_out.rs_out_packet[i].alu_function;
            assign fu_in.fu_in_packet[i].opa_select = rs_out.rs_out_packet[i].opa_select;
            assign fu_in.fu_in_packet[i].opb_select = rs_out.rs_out_packet[i].opb_select;
            assign fu_in.fu_in_packet[i].inst = rs_out.rs_out_packet[i].inst;
            assign fu_in.fu_in_packet[i].NPC = rs_out.rs_out_packet[i].NPC;
            assign fu_in.fu_in_packet[i].PC = rs_out.rs_out_packet[i].PC;
            assign fu_in.fu_in_packet[i].pred_pc = rs_out.rs_out_packet[i].pred_pc;
            assign fu_in.fu_in_packet[i].halt = rs_out.rs_out_packet[i].halt;
            assign fu_in.fu_in_packet[i].illegal = rs_out.rs_out_packet[i].illegal;
        end
    endgenerate

    // generate the input to multiply FU
    pe #(.IN_WIDTH(4)) encoder_mult    (.gnt(is_inst_mult), .enc(inst_mult_idx));
    assign fu_in.fu_in_packet[3].valid = inst_valid[inst_mult_idx] & is_inst_mult[inst_mult_idx] & !squash_after_branch[inst_mult_idx];
    assign fu_in.fu_in_packet[3].is_mult_inst = is_inst_mult[inst_mult_idx];
    assign fu_in.fu_in_packet[3].is_store_inst = rs_out.rs_out_packet[inst_mult_idx].is_store_inst;
    assign fu_in.fu_in_packet[3].is_load_inst = rs_out.rs_out_packet[inst_mult_idx].is_load_inst;
    assign fu_in.fu_in_packet[3].is_cond_branch_inst = rs_out.rs_out_packet[inst_mult_idx].is_cond_branch_inst;
    assign fu_in.fu_in_packet[3].is_uncond_branch_inst = rs_out.rs_out_packet[inst_mult_idx].is_uncond_branch_inst;
    assign fu_in.fu_in_packet[3].is_wb_inst = rs_out.rs_out_packet[inst_mult_idx].is_wb_inst;
    assign fu_in.fu_in_packet[3].renamed_preg = rs_out.rs_out_packet[inst_mult_idx].renamed_preg;
    assign fu_in.fu_in_packet[3].rob_tail = rs_out.rs_out_packet[inst_mult_idx].rob_tail;
    assign fu_in.fu_in_packet[3].sq_idx = rs_out.rs_out_packet[inst_mult_idx].sq_idx;
    assign fu_in.fu_in_packet[3].lq_idx = rs_out.rs_out_packet[inst_mult_idx].lq_idx;
    assign fu_in.fu_in_packet[3].branch_mask = branch_correct ? rs_out.rs_out_packet[inst_mult_idx].branch_mask & ~branch_stack : rs_out.rs_out_packet[inst_mult_idx].branch_mask;
    assign fu_in.fu_in_packet[3].branch_stack = rs_out.rs_out_packet[inst_mult_idx].branch_stack;
    assign fu_in.fu_in_packet[3].alu_function = rs_out.rs_out_packet[inst_mult_idx].alu_function;
    assign fu_in.fu_in_packet[3].rs1_idx = rs_out.rs_out_packet[inst_mult_idx].source1_preg.renamed_preg;
    assign fu_in.fu_in_packet[3].rs2_idx = rs_out.rs_out_packet[inst_mult_idx].source2_preg.renamed_preg;
    assign fu_in.fu_in_packet[3].rs1_value = prf_value.prf_readout_packet[inst_mult_idx].inst_source1_value;
    assign fu_in.fu_in_packet[3].rs2_value = prf_value.prf_readout_packet[inst_mult_idx].inst_source2_value;
    assign fu_in.fu_in_packet[3].opa_select = rs_out.rs_out_packet[inst_mult_idx].opa_select;
    assign fu_in.fu_in_packet[3].opb_select = rs_out.rs_out_packet[inst_mult_idx].opb_select;
    assign fu_in.fu_in_packet[3].inst = rs_out.rs_out_packet[inst_mult_idx].inst;
    assign fu_in.fu_in_packet[3].NPC = rs_out.rs_out_packet[inst_mult_idx].NPC;
    assign fu_in.fu_in_packet[3].PC = rs_out.rs_out_packet[inst_mult_idx].PC;
    assign fu_in.fu_in_packet[3].pred_pc = rs_out.rs_out_packet[inst_mult_idx].pred_pc;
    assign fu_in.fu_in_packet[3].halt = rs_out.rs_out_packet[inst_mult_idx].halt;
    assign fu_in.fu_in_packet[3].illegal = rs_out.rs_out_packet[inst_mult_idx].illegal;

endmodule
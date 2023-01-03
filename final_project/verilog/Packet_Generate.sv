`timescale 1ns/100ps
module Packet_Generate(
    input clock,
    input reset,
    input branch_recovery,
    input ID_PACKET [2:0] id_packet,
    input MAPTABLE_OUT_PACKET maptable_out_packet,
    input FREELIST_OUT_PACKET freelist_out_packet,
    input ROB_TAIL_PACKET rob_tail_packet,
    input logic [1:0] rob_entry_available,
    input logic [1:0] rs_entry_available,
    input logic [1:0] lq_entry_available,
    input logic [1:0] sq_entry_available,
    input logic [$clog2(`LSQ_SIZE):0] sq_tail,
    input logic [$clog2(`LSQ_SIZE):0] lq_tail,
    //input detected_wfi,

    output ROB_IN_PACKET [2:0] rob_in_packet,
    output RS_IN_PACKET rs_in,
    output logic [5:0][$clog2(`LOGIC_REG_SIZE)-1:0] lreg_read, // the source logic register of inst which used to search physical register in Map Table
    output MAPTABLE_IN_PACKET_RENAME maptable_in_packet,
    output SQ_RESERVE_PACKET sq_reserve_packet,
    output LQ_RESERVE_PACKET lq_reserve_packet,
    output logic [1:0] freelist_head_move,
    output logic [1:0] inst_buffer_head_move
);

    logic [2:0] inst_valid;//The valid bit for instruction which will be send to pipeline; 
                           //1. it is valid inst in instruction buffer 2. it will not cause structural hazard
    logic [2:0] is_inst_wb;// Whether inst need to write back
    logic [2:0] is_inst_mult;// whether inst is mult instruction
    logic [1:0] inst_is_wb_count [2:0];
    logic [2:0] is_inst_load;
    logic [1:0] inst_is_load_count [2:0];
    logic [2:0] is_inst_store;
    logic [1:0] inst_is_store_count [2:0];
    logic [1:0] inst_valid_count;// the number of valid instruction from instruction buffer
    logic [1:0] structural_capacity;// the maximum insturction which can get into pipeline while not causing structural hazard
    logic [1:0] structural_capacity_temp;
    logic [1:0] structural_capacity_temp1;
    logic [1:0] structural_capacity_temp2;
    logic [1:0] inst_to_pipeline; // the number of instruction which can be send to pipeline in this cycle


    // these two variable decide whether the input at most three valid instruction will use source1 or source2
    logic [2:0] inst_source1_not_used;
    logic [2:0] inst_source2_not_used;

    logic [1:0] fl_entry_available;
    logic [1:0] inst_under_fl_structural_count; //the number of instruction can be issued under the restriction of freelist structural
    logic [1:0] inst_under_lq_structural_count;
    logic [1:0] inst_under_sq_structural_count;
    logic [5:0][$clog2(`LOGIC_REG_SIZE)-1:0] source_reg_idx;
    logic [2:0][$clog2(`FL_SIZE)-1:0]old_renamed_preg_from_mt;

    //for lsq packet
    logic [2:0] store_issue;
    logic [1:0] store_count [2:0];
    logic [2:0] [1:0] store_location;
    logic [2:0] load_issue;
    logic [1:0] load_count [2:0];
    logic [2:0] [1:0] load_location;
    logic [2:0] [$clog2(`LSQ_SIZE)-1:0] sq_idx;
    logic [2:0] [$clog2(`LSQ_SIZE)-1:0] lq_idx;

    MAPTABLE_ENTRY [5:0] lreg_read_out;
    MAPTABLE_ENTRY preg_of_source_lreg [5:0]; // the physical register and ready bit for all six logic register

    assign is_inst_wb[0] = id_packet[0].dest_reg_idx == `ZERO_REG ? 1'b0 : 1'b1;
    assign is_inst_wb[1] = id_packet[1].dest_reg_idx == `ZERO_REG ? 1'b0 : 1'b1;
    assign is_inst_wb[2] = id_packet[2].dest_reg_idx == `ZERO_REG ? 1'b0 : 1'b1;
    assign inst_is_wb_count[0] = is_inst_wb[0];
    assign inst_is_wb_count[1] = is_inst_wb[0] + is_inst_wb[1];
    assign inst_is_wb_count[2] = is_inst_wb[0] + is_inst_wb[1] + is_inst_wb[2];

    assign is_inst_load[0] = id_packet[0].rd_mem;
    assign is_inst_load[1] = id_packet[1].rd_mem;
    assign is_inst_load[2] = id_packet[2].rd_mem;
    assign inst_is_load_count[0] = is_inst_load[0];
    assign inst_is_load_count[1] = is_inst_load[0] + is_inst_load[1];
    assign inst_is_load_count[2] = is_inst_load[0] + is_inst_load[1] + is_inst_load[2];

    assign is_inst_store[0] = id_packet[0].wr_mem;
    assign is_inst_store[1] = id_packet[1].wr_mem;
    assign is_inst_store[2] = id_packet[2].wr_mem;
    assign inst_is_store_count[0] = is_inst_store[0];
    assign inst_is_store_count[1] = is_inst_store[0] + is_inst_store[1];
    assign inst_is_store_count[2] = is_inst_store[0] + is_inst_store[1] + is_inst_store[2];


    assign fl_entry_available = freelist_out_packet.freelist_out[0].valid + freelist_out_packet.freelist_out[1].valid + freelist_out_packet.freelist_out[2].valid;
    
    // consider that the instruction from instruction buffer do not write back
    assign inst_under_fl_structural_count = inst_is_wb_count[2] <= fl_entry_available ? 2'b11 :
                                            inst_is_wb_count[1] <= fl_entry_available ? 2'b10 :
                                            inst_is_wb_count[0] <= fl_entry_available ? 2'b01 :
                                            2'b0;

    assign inst_under_lq_structural_count = inst_is_load_count[2] <= lq_entry_available ? 2'b11 :
                                            inst_is_load_count[1] <= lq_entry_available ? 2'b10 :
                                            inst_is_load_count[0] <= lq_entry_available ? 2'b01 :
                                            2'b0;
    
    assign inst_under_sq_structural_count = inst_is_store_count[2] <= sq_entry_available ? 2'b11 :
                                            inst_is_store_count[1] <= sq_entry_available ? 2'b10 :
                                            inst_is_store_count[0] <= sq_entry_available ? 2'b01 :
                                            2'b0;

    logic wfi_state;
    logic [2:0] is_wfi;

    // if there is a wfi in dispatch instruction, invalid later instruction
    assign is_wfi[0] = id_packet[0].valid & id_packet[0].halt;
    assign is_wfi[1] = is_wfi[0] | (id_packet[1].valid & id_packet[1].halt);
    assign is_wfi[2] = is_wfi[0] | is_wfi[1] |  (id_packet[2].valid & id_packet[2].halt);

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset | branch_recovery) begin
            wfi_state <= 0;
        end
        else if(is_wfi[2]) begin
            wfi_state <= 1;
        end
    end

    assign inst_valid_count              = wfi_state ? 2'b0 : (id_packet[0].valid + (id_packet[1].valid & !is_wfi[0]) + (id_packet[2].valid & !is_wfi[1]));
    assign structural_capacity_temp      = rs_entry_available < rob_entry_available ? rs_entry_available : rob_entry_available; // not take freelist structural hazard into account
    assign structural_capacity_temp1     = structural_capacity_temp < inst_under_lq_structural_count ? structural_capacity_temp : inst_under_lq_structural_count;
    assign structural_capacity_temp2     = structural_capacity_temp1 < inst_under_sq_structural_count ? structural_capacity_temp1 : inst_under_sq_structural_count;
    assign structural_capacity           = structural_capacity_temp2 < inst_under_fl_structural_count ? structural_capacity_temp2 : inst_under_fl_structural_count; // take freelist structural hazard into account
    assign inst_to_pipeline              = inst_valid_count < structural_capacity ? inst_valid_count : structural_capacity;
    assign inst_buffer_head_move         = inst_to_pipeline;

    assign is_inst_mult[0] = id_packet[0].alu_func == ALU_MUL || id_packet[0].alu_func == ALU_MULH || id_packet[0].alu_func == ALU_MULHSU || id_packet[0].alu_func == ALU_MULHU;
    assign is_inst_mult[1] = id_packet[1].alu_func == ALU_MUL || id_packet[1].alu_func == ALU_MULH || id_packet[1].alu_func == ALU_MULHSU || id_packet[1].alu_func == ALU_MULHU;
    assign is_inst_mult[2] = id_packet[2].alu_func == ALU_MUL || id_packet[2].alu_func == ALU_MULH || id_packet[2].alu_func == ALU_MULHSU || id_packet[2].alu_func == ALU_MULHU;

    assign inst_source1_not_used[0] = id_packet[0].opa_select != OPA_IS_RS1 && !id_packet[0].cond_branch;
    assign inst_source1_not_used[1] = id_packet[1].opa_select != OPA_IS_RS1 && !id_packet[1].cond_branch;
    assign inst_source1_not_used[2] = id_packet[2].opa_select != OPA_IS_RS1 && !id_packet[2].cond_branch;
    assign inst_source2_not_used[0] = id_packet[0].opb_select != OPB_IS_RS2 && !id_packet[0].cond_branch && !id_packet[0].wr_mem;
    assign inst_source2_not_used[1] = id_packet[1].opb_select != OPB_IS_RS2 && !id_packet[1].cond_branch && !id_packet[1].wr_mem;
    assign inst_source2_not_used[2] = id_packet[2].opb_select != OPB_IS_RS2 && !id_packet[2].cond_branch && !id_packet[2].wr_mem;

    always_comb begin
        case (inst_to_pipeline)
            2'b0    : inst_valid = 3'b000;
            2'b1    : inst_valid = 3'b001;
            2'b10   : inst_valid = 3'b011;
            2'b11   : inst_valid = 3'b111;
            default : inst_valid = 3'b000;
        endcase
    end


    // get the maptable output, including the old T and physical register corresponding to source logic register
    assign old_renamed_preg_from_mt = maptable_out_packet.old_renamed_preg; // get the maptable output

    // output to maptable, to update the entry in maptable with renamed physical register, considering the WAW hazard
    assign maptable_in_packet.renaming_valid[0] =  inst_valid[0] && is_inst_wb[0];
    assign maptable_in_packet.renaming_valid[1] =  inst_valid[1] && is_inst_wb[1];
    assign maptable_in_packet.renaming_valid[2] =  inst_valid[2] && is_inst_wb[2];

        // considering waw for maptable
        // assign maptable_in_packet.renaming_valid[0] =  !(id_packet[0].dest_reg_idx == id_packet[1].dest_reg_idx  ||  id_packet[0].dest_reg_idx == id_packet[2].dest_reg_idx) && inst_valid[0] && is_inst_wb[0];
        // assign maptable_in_packet.renaming_valid[1] =  !(id_packet[1].dest_reg_idx == id_packet[2].dest_reg_idx) && inst_valid[1] && is_inst_wb[1];
        // assign maptable_in_packet.renaming_valid[2] =  inst_valid[2] && is_inst_wb[2];



    assign maptable_in_packet.renaming_preg[0] = freelist_out_packet.freelist_out[0].renamed_preg;
    assign maptable_in_packet.renaming_preg[1] = !is_inst_wb[0] ? maptable_in_packet.renaming_preg[0] : freelist_out_packet.freelist_out[1].renamed_preg; 
    assign maptable_in_packet.renaming_preg[2] = !is_inst_wb[1] ? maptable_in_packet.renaming_preg[1] : 
                                                 !is_inst_wb[0] ? freelist_out_packet.freelist_out[1].renamed_preg :
                                                                  freelist_out_packet.freelist_out[2].renamed_preg;

    assign maptable_in_packet.renaming_lreg[0] = id_packet[0].dest_reg_idx;
    assign maptable_in_packet.renaming_lreg[1] = id_packet[1].dest_reg_idx;
    assign maptable_in_packet.renaming_lreg[2] = id_packet[2].dest_reg_idx;

    // get the physical register corresponding to source logic register, considering RAW
    assign source_reg_idx[0] = id_packet[0].source_rs1_idx;
    assign source_reg_idx[1] = id_packet[0].source_rs2_idx;
    assign source_reg_idx[2] = id_packet[1].source_rs1_idx;
    assign source_reg_idx[3] = id_packet[1].source_rs2_idx;
    assign source_reg_idx[4] = id_packet[2].source_rs1_idx;
    assign source_reg_idx[5] = id_packet[2].source_rs2_idx;

    // assign the input to maptable, which is the source logic register of instruction
    assign lreg_read      = source_reg_idx; // send source logic register to maptable to get physical register
    assign lreg_read_out  = maptable_out_packet.lreg_read_out; // the physical register of lreg_read from maptable
    
    
    // physical register for two source register of first inst
    assign preg_of_source_lreg[0] = lreg_read_out[0];
    assign preg_of_source_lreg[1] = lreg_read_out[1];

    // physical register for two source register of second inst
    assign preg_of_source_lreg[2] = lreg_read_out[2];
    assign preg_of_source_lreg[3] = lreg_read_out[3];
    
        // consider RAW for maptable
        // assign preg_of_source_lreg[2] = source_reg_idx[2] == id_packet[0].dest_reg_idx && is_inst_wb[0] ?  {maptable_in_packet.renaming_preg[0], 1'b0} : lreg_read_out[2] ; 
        // assign preg_of_source_lreg[3] = source_reg_idx[3] == id_packet[0].dest_reg_idx && is_inst_wb[0] ?  {maptable_in_packet.renaming_preg[0], 1'b0} : lreg_read_out[3] ;

    // physical register for two source register of third inst
    assign preg_of_source_lreg[4] = lreg_read_out[4];
    assign preg_of_source_lreg[5] = lreg_read_out[5];

        // consider RAW for maptable
        // assign preg_of_source_lreg[4] = source_reg_idx[4] == id_packet[1].dest_reg_idx && is_inst_wb[1] ?  {maptable_in_packet.renaming_preg[1], 1'b0} : 
        //                                 source_reg_idx[4] == id_packet[0].dest_reg_idx && is_inst_wb[0] ?  {maptable_in_packet.renaming_preg[0], 1'b0} :
        //                                 lreg_read_out[4];
        // assign preg_of_source_lreg[5] = source_reg_idx[5] == id_packet[1].dest_reg_idx && is_inst_wb[1] ?  {maptable_in_packet.renaming_preg[1], 1'b0} : 
        //                                 source_reg_idx[5] == id_packet[0].dest_reg_idx && is_inst_wb[0] ?  {maptable_in_packet.renaming_preg[0], 1'b0} :
        //                                 lreg_read_out[5];


    // generate the input packet to ROB
    generate
        genvar i;
        for(i = 0; i < 3; i = i+1) begin : rob_packet_generator
            assign rob_in_packet[i].inst_valid        = inst_valid[i];
            assign rob_in_packet[i].is_store_inst     = id_packet[i].wr_mem;
            assign rob_in_packet[i].is_load_inst      = id_packet[i].rd_mem;
            assign rob_in_packet[i].is_branch_inst    = id_packet[i].cond_branch || id_packet[i].uncond_branch;
            assign rob_in_packet[i].is_wb_inst        = is_inst_wb[i];
            assign rob_in_packet[i].is_wfi_inst       = id_packet[i].halt;
            assign rob_in_packet[i].rename_preg       = is_inst_wb[i] ? maptable_in_packet.renaming_preg[i] : 0;// assign the renamed preg of not write back rob entry to zero
            assign rob_in_packet[i].dest_reg          = id_packet[i].dest_reg_idx;
            assign rob_in_packet[i].sq_idx            = sq_idx[i];
            assign rob_in_packet[i].lq_idx            = lq_idx[i];
            assign rob_in_packet[i].rename_preg_old   = old_renamed_preg_from_mt[i];
            assign rob_in_packet[i].PC                = id_packet[i].PC;
            assign rob_in_packet[i].branch_stack      = id_packet[i].branch_stack; // only for branch instruction, 0 if not for branch instruction
            assign rob_in_packet[i].branch_mask       = id_packet[i].branch_mask;
        end
    endgenerate

        // consider RAW in maptable
        // assign rob_in_packet[0].rename_preg_old = old_renamed_preg_from_mt[0];
        // assign rob_in_packet[1].rename_preg_old = (id_packet[1].dest_reg_idx == id_packet[0].dest_reg_idx && is_inst_wb[0]) ? maptable_in_packet.renaming_preg[0] : old_renamed_preg_from_mt[1];
        // assign rob_in_packet[2].rename_preg_old = (id_packet[2].dest_reg_idx == id_packet[1].dest_reg_idx && is_inst_wb[1]) ? maptable_in_packet.renaming_preg[1] : 
        //                                           (id_packet[2].dest_reg_idx == id_packet[0].dest_reg_idx && is_inst_wb[0]) ? maptable_in_packet.renaming_preg[0] :
        //                                                                                                                       old_renamed_preg_from_mt[2];

                                    

    // the input to freelist, represent the tail movement of freelist after renaming
    always_comb begin
        case (inst_to_pipeline)
            2'b0    : freelist_head_move = 0;
            2'b1    : freelist_head_move = inst_is_wb_count[0];
            2'b10   : freelist_head_move = inst_is_wb_count[1];
            2'b11   : freelist_head_move = inst_is_wb_count[2];
            default : freelist_head_move = 0;
        endcase
    end

    // the input to RS
    generate 
        genvar j;
        for(j = 0; j < 3; j=j+1) begin: rs_packet_generator
            assign rs_in.rs_in_packet[j].valid                         =  inst_valid[j];
            assign rs_in.rs_in_packet[j].is_mult_inst                  =  is_inst_mult[j];
            assign rs_in.rs_in_packet[j].is_store_inst                 =  id_packet[j].wr_mem;
            assign rs_in.rs_in_packet[j].is_load_inst                  =  id_packet[j].rd_mem;
            assign rs_in.rs_in_packet[j].is_cond_branch_inst           =  id_packet[j].cond_branch;
            assign rs_in.rs_in_packet[j].is_uncond_branch_inst         =  id_packet[j].uncond_branch;
            assign rs_in.rs_in_packet[j].is_wb_inst                    =  is_inst_wb[j];
            assign rs_in.rs_in_packet[j].sq_idx                        =  sq_idx[j];
            assign rs_in.rs_in_packet[j].lq_idx                        =  lq_idx[j];
            assign rs_in.rs_in_packet[j].renamed_preg                  =  is_inst_wb[j] ? maptable_in_packet.renaming_preg[j] : 0;
            assign rs_in.rs_in_packet[j].rob_tail                      =  rob_tail_packet.rob_tail[j];
            assign rs_in.rs_in_packet[j].source1_preg.renamed_preg     =  preg_of_source_lreg[2*j].renamed_preg;
            assign rs_in.rs_in_packet[j].source2_preg.renamed_preg     =  preg_of_source_lreg[2*j+1].renamed_preg;
            assign rs_in.rs_in_packet[j].source1_preg.valid            =  inst_source1_not_used[j] | preg_of_source_lreg[2*j].valid;
            assign rs_in.rs_in_packet[j].source2_preg.valid            =  inst_source2_not_used[j] | preg_of_source_lreg[2*j+1].valid;
            assign rs_in.rs_in_packet[j].opa_select                    =  id_packet[j].opa_select;
            assign rs_in.rs_in_packet[j].opb_select                    =  id_packet[j].opb_select;
            assign rs_in.rs_in_packet[j].inst                          =  id_packet[j].inst;
            assign rs_in.rs_in_packet[j].NPC                           =  id_packet[j].NPC;
            assign rs_in.rs_in_packet[j].PC                            =  id_packet[j].PC;
            assign rs_in.rs_in_packet[j].pred_pc                       =  id_packet[j].pred_pc;
            assign rs_in.rs_in_packet[j].ready                         =  1'b0;
            assign rs_in.rs_in_packet[j].branch_mask                   =  id_packet[j].branch_mask;
            assign rs_in.rs_in_packet[j].branch_stack                  =  id_packet[j].branch_stack; // only for branch instruction, 0 if not for branch instruction
            assign rs_in.rs_in_packet[j].alu_function                  =  id_packet[j].alu_func;
            assign rs_in.rs_in_packet[j].halt                          =  id_packet[j].halt;
            assign rs_in.rs_in_packet[j].illegal                       =  id_packet[j].illegal;
        end
    endgenerate

    // generate the packet to lsq
    // in order compress valid output to store queue
    assign store_issue[0] = is_inst_store[0] & inst_valid[0];
    assign store_issue[1] = is_inst_store[1] & inst_valid[1];
    assign store_issue[2] = is_inst_store[2] & inst_valid[2];
    assign store_count[0] = 0;
    assign store_count[1] = store_issue[0];
    assign store_count[2] = store_issue[0] + store_issue[1];
    always_comb begin
        store_location = '0;
        sq_reserve_packet = '0;
        for(integer unsigned i = 0; i < 3 ; i=i+1) begin
            sq_reserve_packet.sq_reserve_entry[store_count[i]].inst         = id_packet[i].inst;
            sq_reserve_packet.sq_reserve_entry[store_count[i]].PC           = id_packet[i].PC;
            sq_reserve_packet.sq_reserve_entry[store_count[i]].branch_mask  = id_packet[i].branch_mask;
            sq_reserve_packet.sq_reserve_entry[store_count[i]].valid        = store_issue[i];
            store_location[store_count[i]]                                  = i; 
        end
    end

    // in order to compress valid output to load queue
    assign load_issue[0] = is_inst_load[0] & inst_valid[0];
    assign load_issue[1] = is_inst_load[1] & inst_valid[1];
    assign load_issue[2] = is_inst_load[2] & inst_valid[2];
    assign load_count[0] = 0;
    assign load_count[1] = load_issue[0];
    assign load_count[2] = load_issue[0] + load_issue[1];
    always_comb begin
        load_location = '0;
        lq_reserve_packet.lq_reserve_entry[0] = '0;
        lq_reserve_packet.lq_reserve_entry[1] = '0;
        lq_reserve_packet.lq_reserve_entry[2] = '0;
        for(integer unsigned i = 0; i < 3 ; i=i+1) begin
            lq_reserve_packet.lq_reserve_entry[load_count[i]].inst              = id_packet[i].inst;
            lq_reserve_packet.lq_reserve_entry[load_count[i]].PC                = id_packet[i].PC;
            lq_reserve_packet.lq_reserve_entry[load_count[i]].branch_mask       = id_packet[i].branch_mask;
            lq_reserve_packet.lq_reserve_entry[load_count[i]].rob_tail          = rob_tail_packet.rob_tail[i];
            lq_reserve_packet.lq_reserve_entry[load_count[i]].preg              = is_inst_wb[i] ? maptable_in_packet.renaming_preg[i] : 0;
            lq_reserve_packet.lq_reserve_entry[load_count[i]].valid             = load_issue[i];
            //remember the origin location of load instruction in the instruction to pipeline, for each compressed load instruction in lq_reserve_packet
            load_location[load_count[i]]                                        = i; 
        end
    end

    assign lq_reserve_packet.sq_tail[0] = sq_tail + store_count[load_location[0]];
    assign lq_reserve_packet.sq_tail[1] = sq_tail + store_count[load_location[1]];
    assign lq_reserve_packet.sq_tail[2] = sq_tail + store_count[load_location[2]];


    always_comb begin
        lq_idx = '0;
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            if(lq_reserve_packet.lq_reserve_entry[i].valid)
                lq_idx[load_location[i]] = lq_tail + i;
        end
    end

    always_comb begin
        sq_idx = '0;
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            if(sq_reserve_packet.sq_reserve_entry[i].valid) 
                sq_idx[store_location[i]] = sq_tail + i;
        end
    end



endmodule
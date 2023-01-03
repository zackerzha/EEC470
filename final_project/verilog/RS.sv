`timescale 1ns/100ps
module RS(
    input clock,
    input reset,
    input RS_IN_PACKET rs_in,
    input CDB_PACKET [2:0] cdb_in_packet,
    //BRANCH_STACK_PACKET branch_stack,
    input branch_recovery,
    input branch_correct,
    input [`BRANCH_STACK_SIZE-1:0] branch_stack,
    input stall, // if cdb buffer is going to full

    output RS_OUT_PACKET rs_out,
    output logic [1:0] available_rs_entry
    
    `ifdef DEBUG
    ,output RS_ENTRY[`RS_SIZE-1:0] rs_data
    ,output RS_ENTRY[`RS_SIZE-1:0] rs_data_after_reserve_comb
    ,output RS_ENTRY[`RS_SIZE-1:0] rs_data_after_compress_comb
    ,output RS_ENTRY[`RS_SIZE-1:0] rs_data_squash_comb
    ,output logic [$clog2(`RS_SIZE):0] tail
    // do the wakeup after the old instruction has been issued and new instruction has been reserved
    ,output logic [$clog2(`RS_SIZE):0] tail_after_reserve_comb
    ,output logic [$clog2(`RS_SIZE):0] tail_after_compress_comb
    ,output logic [$clog2(`RS_SIZE):0] tail_squash_comb
    // how many instruction is ready before instruction in current RS entry
    ,output logic [`RS_SIZE-1:0][1:0] inst_ready_before

    ,output logic [2:0][`RS_SIZE-1:0] mask_source1_cdb
    ,output logic [2:0][`RS_SIZE-1:0] mask_source2_cdb
    ,output logic [2:0][`RS_SIZE-1:0] mask_source1_forwarding
    ,output logic [2:0][`RS_SIZE-1:0] mask_source2_forwarding
    ,output logic [`RS_SIZE-1:0] mask_source1
    ,output logic [`RS_SIZE-1:0] mask_source2

    ,output logic [`RS_SIZE-1:0] mult_ready// current ready mult instruction
    ,output logic [`RS_SIZE-1:0] branch_ready// current ready mult instruction
    ,output logic [`RS_SIZE-1:0] inst_issue_reverse// current instruction which is ready to issue, only consider the first ready mult, mask the other ready mult
    ,output logic [`RS_SIZE-1:0] inst_issue_reverse_1// instruction which is ready to issue besides first issued inst
    ,output logic [`RS_SIZE-1:0] inst_issue_reverse_2// instruction which is ready to issue besides first and second issued inst
    ,output logic [$clog2(`RS_SIZE)-1:0] first_mult_position_reverse// current ready mult instruction
    ,output logic [$clog2(`RS_SIZE)-1:0] first_mult_position// current ready mult instruction
    ,output logic [$clog2(`RS_SIZE)-1:0] first_branch_position_reverse// current ready branch instruction
    ,output logic [$clog2(`RS_SIZE)-1:0] first_branch_position// current ready branch instruction
    ,output logic [2:0] issue_valid
    ,output logic [`RS_SIZE-1:0][$clog2(`RS_SIZE):0] tail_squash_move
    ,output logic [`RS_SIZE-1:0] rs_squash_entry

    `endif
);

    `ifndef DEBUG
    RS_ENTRY[`RS_SIZE-1:0] rs_data;
    RS_ENTRY[`RS_SIZE-1:0] rs_data_after_reserve_comb;
    RS_ENTRY[`RS_SIZE-1:0] rs_data_after_compress_comb;
    RS_ENTRY[`RS_SIZE-1:0] rs_data_after_forward_comb;
    RS_ENTRY[`RS_SIZE-1:0] rs_data_after_correct_branch_comb;
    RS_ENTRY[`RS_SIZE-1:0] rs_data_squash_comb;
    logic [$clog2(`RS_SIZE):0] tail;
    // do the wakeup after the old instruction has been issued and new instruction has been reserved
    logic [$clog2(`RS_SIZE):0] tail_after_reserve_comb;
    logic [$clog2(`RS_SIZE):0] tail_after_compress_comb;
    logic [$clog2(`RS_SIZE):0] tail_squash_comb;
    // how many instruction is ready before instruction in current RS entry
    logic [`RS_SIZE-1:0][1:0] inst_ready_before;
    logic [1:0] num_inst_issued;

    logic [`RS_SIZE-1:0] mask_source1_cdb [2:0];
    logic [`RS_SIZE-1:0] mask_source2_cdb [2:0];
    logic [`RS_SIZE-1:0] mask_source1_forwarding [2:0];
    logic [`RS_SIZE-1:0] mask_source2_forwarding [2:0];
    logic [`RS_SIZE-1:0] mask_source1;
    logic [`RS_SIZE-1:0] mask_source2;

    logic [`RS_SIZE-1:0] mult_ready;// current ready mult instruction
    logic [`RS_SIZE-1:0] branch_ready;// current ready branch instruction
    logic [`RS_SIZE-1:0]inst_issue_reverse;// current instruction which is ready to issue, only consider the first ready mult, mask the other ready mult
    logic [`RS_SIZE-1:0]inst_issue_reverse_1;// instruction which is ready to issue besides first issued inst
    logic [`RS_SIZE-1:0]inst_issue_reverse_2;// instruction which is ready to issue besides first and second issued inst
    logic [$clog2(`RS_SIZE)-1:0] first_mult_position_reverse;// current ready mult instruction
    logic [$clog2(`RS_SIZE)-1:0] first_mult_position;// current ready mult instruction
    logic [$clog2(`RS_SIZE)-1:0] first_branch_position_reverse;// current ready branch instruction
    logic [$clog2(`RS_SIZE)-1:0] first_branch_position;// current ready branch instruction
    logic [2:0] issue_valid;
    logic [`RS_SIZE-1:0][$clog2(`RS_SIZE):0] tail_squash_move;
    logic [`RS_SIZE-1:0] rs_squash_entry;
    `endif 

    logic [$clog2(`RS_SIZE)-1:0] inst_issue_idx_reverse [2:0];
    logic [$clog2(`RS_SIZE)-1:0] inst_issue_idx [2:0];

 
    logic [`RS_SIZE-1:0] mask_source1_forwarding_reg [2:0];
    logic [`RS_SIZE-1:0] mask_source2_forwarding_reg [2:0];

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            mask_source1_forwarding_reg[0] <= 0;
            mask_source1_forwarding_reg[1] <= 0;
            mask_source1_forwarding_reg[2] <= 0;
            mask_source2_forwarding_reg[0] <= 0;
            mask_source2_forwarding_reg[1] <= 0;
            mask_source2_forwarding_reg[2] <= 0;
        end
        else begin
            mask_source1_forwarding_reg[0] <= mask_source1_forwarding[0];
            mask_source1_forwarding_reg[1] <= mask_source1_forwarding[1];
            mask_source1_forwarding_reg[2] <= mask_source1_forwarding[2];
            mask_source2_forwarding_reg[0] <= mask_source2_forwarding[0];
            mask_source2_forwarding_reg[1] <= mask_source2_forwarding[1];
            mask_source2_forwarding_reg[2] <= mask_source2_forwarding[2];
        end
    end

    logic [`RS_SIZE-1:0] rs_issued;

    generate
        genvar a;
        for(a = 0; a < `RS_SIZE; a=a+1) begin : Fowarding_not_issued
            assign rs_issued[a] = (a == inst_issue_idx[0] & rs_out.inst_valid[0]) | (a == inst_issue_idx[1] & rs_out.inst_valid[1]) | (a == inst_issue_idx[2] & rs_out.inst_valid[2]);
        end
    endgenerate



    always_comb begin
        rs_data_after_forward_comb = rs_data;
        for(integer unsigned i = 0; i < `RS_SIZE ; i = i+1) begin
            if(mask_source1_forwarding_reg[0][i] & (rs_data[i].valid) & !rs_issued[i]) begin
                rs_data_after_forward_comb[i].source1_preg.valid = 1'b0;
            end
            if(mask_source1_forwarding_reg[1][i] & (rs_data[i].valid) & !rs_issued[i]) begin
                rs_data_after_forward_comb[i].source1_preg.valid = 1'b0;
            end
            if(mask_source1_forwarding_reg[2][i] & (rs_data[i].valid) & !rs_issued[i]) begin
                rs_data_after_forward_comb[i].source1_preg.valid = 1'b0;
            end
        end
        for(integer unsigned i = 0; i < `RS_SIZE ; i = i+1) begin
            if(mask_source2_forwarding_reg[0][i] & (rs_data[i].valid) & !rs_issued[i]) begin
                rs_data_after_forward_comb[i].source2_preg.valid = 1'b0;
            end
            if(mask_source2_forwarding_reg[1][i] & (rs_data[i].valid) & !rs_issued[i]) begin
                rs_data_after_forward_comb[i].source2_preg.valid = 1'b0;
            end
            if(mask_source2_forwarding_reg[2][i] & (rs_data[i].valid) & !rs_issued[i]) begin
                rs_data_after_forward_comb[i].source2_preg.valid = 1'b0;
            end
        end
        for(integer unsigned i = 0; i < `RS_SIZE ; i = i+1) begin
            rs_data_after_forward_comb[i].ready = rs_data_after_forward_comb[i].source1_preg.valid & rs_data_after_forward_comb[i].source2_preg.valid;
        end
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            rs_data <= '0;
            tail <= 0;
        end
        else begin
            if(!branch_recovery) begin
                // rs_data <= rs_data_after_reserve_comb;
                rs_data <= rs_data_after_correct_branch_comb;
                tail    <= tail_after_reserve_comb;
            end
            else begin
                rs_data <= rs_data_squash_comb;
                tail    <= tail_squash_comb;
            end
        end
    end

    // assign tail_after_compress_comb = stall ? tail : tail - inst_ready_before[`RS_SIZE-1];
    assign tail_after_compress_comb = stall ? tail : tail - num_inst_issued;
    assign tail_after_reserve_comb  = tail_after_compress_comb + rs_in.rs_in_packet[0].valid + rs_in.rs_in_packet[1].valid + rs_in.rs_in_packet[2].valid;



    always_comb begin
        case(tail_after_compress_comb)
            `RS_SIZE   :  available_rs_entry = 0;
            `RS_SIZE-1 :  available_rs_entry = 1;
            `RS_SIZE-2 :  available_rs_entry = 2;
            default    :  available_rs_entry = 3;
        endcase
    end


    
    // compress RS
    // select the position where the first mult instruction is ready, if no ready mult instruction, first_mult_position = `RS_SIZE
    generate
        genvar l;
        for(l = 0; l < `RS_SIZE; l=l+1) begin:multready
            assign mult_ready[`RS_SIZE-l-1] = rs_data[l].ready && rs_data[l].is_mult_inst;
        end
    endgenerate
    priority_encoder #(.IN_WIDTH(`RS_SIZE)) pe (.req(mult_ready),.enc(first_mult_position_reverse));
    assign first_mult_position = `RS_SIZE-first_mult_position_reverse-1;

    // select the position where the first branch instruction is ready, if no ready branch instruction, first_branch_position = `RS_SIZE
    generate
        genvar n;
        for(n = 0; n < `RS_SIZE; n=n+1) begin:branchready
            assign branch_ready[`RS_SIZE-n-1] = rs_data[n].ready && rs_data[n].is_cond_branch_inst;
        end
    endgenerate
    priority_encoder #(.IN_WIDTH(`RS_SIZE)) pe_branch (.req(branch_ready),.enc(first_branch_position_reverse));
    assign first_branch_position = `RS_SIZE-first_branch_position_reverse-1;


    // determine how the instruction in RS entry can move, after the instruction have been issued
    assign inst_ready_before[0] = 0;
    generate
        genvar i;
        for(i = 1; i < `RS_SIZE; i=i+1) begin:inst_ready
            assign inst_ready_before[i] = inst_ready_before[i-1] == 2'b11 ? 2'b11 : 
                                        i > first_mult_position+1       ?   (i > first_branch_position+1 ?  inst_ready_before[i-1] + (rs_data_after_forward_comb[i-1].ready && !rs_data_after_forward_comb[i-1].is_mult_inst && !rs_data_after_forward_comb[i-1].is_cond_branch_inst)  :  inst_ready_before[i-1] + (rs_data_after_forward_comb[i-1].ready && !rs_data_after_forward_comb[i-1].is_mult_inst)) :
                                        i > first_branch_position+1     ?   inst_ready_before[i-1] + (rs_data_after_forward_comb[i-1].ready && !rs_data_after_forward_comb[i-1].is_cond_branch_inst) :  inst_ready_before[i-1] + rs_data_after_forward_comb[i-1].ready;
        end
    endgenerate

    always_comb begin
        rs_data_after_compress_comb = rs_data_after_forward_comb;
        num_inst_issued = inst_ready_before[`RS_SIZE-1];  
        if(!stall) begin
            for(integer unsigned i = 0; i <`RS_SIZE; i=i+1) begin
                rs_data_after_compress_comb[i-inst_ready_before[i]] = rs_data_after_forward_comb[i];
                rs_data_after_compress_comb[i].valid = inst_ready_before[i]!=0 ? 1'b0 : rs_data_after_forward_comb[i].valid;
                rs_data_after_compress_comb[i].ready = inst_ready_before[i]!=0 ? 1'b0 : rs_data_after_forward_comb[i].ready;
            end
            // dealing with whether the last instruction issue or not when RS is full
            // the last instrution is issued when it is the top three ready instruction
            // and it is not the second ready mult instruction
            if(     
                    ( (mult_ready[0] && first_mult_position == `RS_SIZE-1) ||  (branch_ready[0] && first_branch_position == `RS_SIZE-1) || !rs_data_after_forward_comb[`RS_SIZE-1].is_mult_inst)   //ensure that last instruction is first ready mult or other ready instruction
                    && rs_data_after_forward_comb[`RS_SIZE-1].ready 
                    && rs_data_after_forward_comb[`RS_SIZE-1].valid
                    && (inst_ready_before[`RS_SIZE-1] < 3)
            ) begin     
                //if(!branch_recovery) begin        
                    num_inst_issued = inst_ready_before[`RS_SIZE-1] + 1'b1;          
                //end
                rs_data_after_compress_comb[`RS_SIZE-1-inst_ready_before[`RS_SIZE-1]].valid = 1'b0;
                rs_data_after_compress_comb[`RS_SIZE-1-inst_ready_before[`RS_SIZE-1]].ready = 1'b0;
            end
        end
    end

    // always_comb begin
    //     have_one_mult_1 = 0;
    //     inst_ready_before = '0;
    //     for (integer unsigned i = 1; i < `RS_SIZE; i = i+1) begin
    //         if(have_one_mult_1 == 1) begin
    //             inst_ready_before[i] = inst_ready_before[i-1] == 2'b11 ? 2'b11 : inst_ready_before[i-1]+rs_data[i-1].ready && !rs_data[i-1].is_mult_inst;
    //         end
    //         else begin
    //             inst_ready_before[i] = inst_ready_before[i-1] == 2'b11 ? 2'b11 : inst_ready_before[i-1]+rs_data[i-1].ready;
    //             have_one_mult_1      = rs_data[i-1].ready && rs_data[i-1].is_mult_inst;
    //         end
    //     end
    // end


    // reserve new entry in RS
    always_comb begin
        for (integer unsigned j = 0; j < `RS_SIZE; j = j+1) begin
            rs_data_after_reserve_comb[j].valid                     = rs_data_after_compress_comb[j].valid;
            rs_data_after_reserve_comb[j].is_mult_inst              = rs_data_after_compress_comb[j].is_mult_inst;
            rs_data_after_reserve_comb[j].is_store_inst             = rs_data_after_compress_comb[j].is_store_inst;
            rs_data_after_reserve_comb[j].is_load_inst              = rs_data_after_compress_comb[j].is_load_inst;
            rs_data_after_reserve_comb[j].is_cond_branch_inst       = rs_data_after_compress_comb[j].is_cond_branch_inst;
            rs_data_after_reserve_comb[j].is_uncond_branch_inst     = rs_data_after_compress_comb[j].is_uncond_branch_inst;
            rs_data_after_reserve_comb[j].is_wb_inst                = rs_data_after_compress_comb[j].is_wb_inst;
            rs_data_after_reserve_comb[j].sq_idx                    = rs_data_after_compress_comb[j].sq_idx;
            rs_data_after_reserve_comb[j].lq_idx                    = rs_data_after_compress_comb[j].lq_idx;
            rs_data_after_reserve_comb[j].renamed_preg              = rs_data_after_compress_comb[j].renamed_preg;
            rs_data_after_reserve_comb[j].rob_tail                  = rs_data_after_compress_comb[j].rob_tail;
            rs_data_after_reserve_comb[j].source1_preg.renamed_preg = rs_data_after_compress_comb[j].source1_preg.renamed_preg;
            rs_data_after_reserve_comb[j].source2_preg.renamed_preg = rs_data_after_compress_comb[j].source2_preg.renamed_preg;
            rs_data_after_reserve_comb[j].opa_select                = rs_data_after_compress_comb[j].opa_select;
            rs_data_after_reserve_comb[j].opb_select                = rs_data_after_compress_comb[j].opb_select;
            rs_data_after_reserve_comb[j].inst                      = rs_data_after_compress_comb[j].inst;
            rs_data_after_reserve_comb[j].NPC                       = rs_data_after_compress_comb[j].NPC;
            rs_data_after_reserve_comb[j].PC                        = rs_data_after_compress_comb[j].PC;
            rs_data_after_reserve_comb[j].pred_pc                   = rs_data_after_compress_comb[j].pred_pc;
            rs_data_after_reserve_comb[j].branch_mask               = rs_data_after_compress_comb[j].branch_mask;
            rs_data_after_reserve_comb[j].branch_stack              = rs_data_after_compress_comb[j].branch_stack;
            rs_data_after_reserve_comb[j].alu_function              = rs_data_after_compress_comb[j].alu_function;
            rs_data_after_reserve_comb[j].halt                      = rs_data_after_compress_comb[j].halt;
            rs_data_after_reserve_comb[j].illegal                   = rs_data_after_compress_comb[j].illegal;
        end
        for (integer unsigned i = 0; i < 3; i = i+1) begin
            if(tail_after_compress_comb+i < `RS_SIZE) begin
                rs_data_after_reserve_comb[tail_after_compress_comb+i].valid                        = rs_in.rs_in_packet[i].valid;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].is_mult_inst                 = rs_in.rs_in_packet[i].is_mult_inst;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].is_store_inst                = rs_in.rs_in_packet[i].is_store_inst;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].is_load_inst                 = rs_in.rs_in_packet[i].is_load_inst;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].is_cond_branch_inst          = rs_in.rs_in_packet[i].is_cond_branch_inst;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].is_uncond_branch_inst        = rs_in.rs_in_packet[i].is_uncond_branch_inst;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].is_wb_inst                   = rs_in.rs_in_packet[i].is_wb_inst;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].sq_idx                       = rs_in.rs_in_packet[i].sq_idx;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].lq_idx                       = rs_in.rs_in_packet[i].lq_idx;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].renamed_preg                 = rs_in.rs_in_packet[i].renamed_preg;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].rob_tail                     = rs_in.rs_in_packet[i].rob_tail;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].source1_preg.renamed_preg    = rs_in.rs_in_packet[i].source1_preg.renamed_preg;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].source2_preg.renamed_preg    = rs_in.rs_in_packet[i].source2_preg.renamed_preg;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].opa_select                   = rs_in.rs_in_packet[i].opa_select;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].opb_select                   = rs_in.rs_in_packet[i].opb_select;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].inst                         = rs_in.rs_in_packet[i].inst;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].NPC                          = rs_in.rs_in_packet[i].NPC;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].pred_pc                      = rs_in.rs_in_packet[i].pred_pc;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].PC                           = rs_in.rs_in_packet[i].PC;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].branch_mask                  = rs_in.rs_in_packet[i].branch_mask;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].branch_stack                 = rs_in.rs_in_packet[i].branch_stack;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].alu_function                 = rs_in.rs_in_packet[i].alu_function;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].halt                         = rs_in.rs_in_packet[i].halt;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].illegal                      = rs_in.rs_in_packet[i].illegal;
            end
        end
    end


    // the part for wake up instruction after new instructions have been reserved
    // receive the input from cdb to wakeup
    generate 
    genvar j;
        for (j = 0; j < 3; j = j+1) begin : mask_cdb
            genvar i;
            for (i = 0; i <`RS_SIZE; i = i+1) begin : mask_cdb_element
                assign mask_source1_cdb[j][i] = (rs_data_after_reserve_comb[i].source1_preg.renamed_preg == cdb_in_packet[j].complete_preg) && rs_data_after_reserve_comb[i].valid && cdb_in_packet[j].complete_valid;
                assign mask_source2_cdb[j][i] = (rs_data_after_reserve_comb[i].source2_preg.renamed_preg == cdb_in_packet[j].complete_preg) && rs_data_after_reserve_comb[i].valid && cdb_in_packet[j].complete_valid; 
            end
        end
    endgenerate

    //fowarding the issue instrution, for only issued instruction which need to writeback and not include mult instruction and load instruction
    generate 
    genvar k;
        for (k = 0; k < 3; k = k+1) begin : mask_foorwarding
            genvar h;
            for (h = 0; h <`RS_SIZE; h = h+1) begin : mask_forwarding_element
                assign mask_source1_forwarding[k][h] = (rs_data_after_reserve_comb[h].source1_preg.renamed_preg == rs_out.rs_out_packet[k].renamed_preg) 
                                                    && rs_data_after_reserve_comb[h].valid && rs_out.inst_valid[k] && rs_out.rs_out_packet[k].is_wb_inst && !rs_out.rs_out_packet[k].is_mult_inst && !rs_out.rs_out_packet[k].is_load_inst;
                assign mask_source2_forwarding[k][h] = (rs_data_after_reserve_comb[h].source2_preg.renamed_preg == rs_out.rs_out_packet[k].renamed_preg) 
                                                    && rs_data_after_reserve_comb[h].valid && rs_out.inst_valid[k] && rs_out.rs_out_packet[k].is_wb_inst && !rs_out.rs_out_packet[k].is_mult_inst && !rs_out.rs_out_packet[k].is_load_inst; 
            end
        end
    endgenerate

    assign mask_source1 = mask_source1_cdb[0] | mask_source1_cdb[1] | mask_source1_cdb[2] | mask_source1_forwarding[0] | mask_source1_forwarding[1] | mask_source1_forwarding[2];
    assign mask_source2 = mask_source2_cdb[0] | mask_source2_cdb[1] | mask_source2_cdb[2] | mask_source2_forwarding[0] | mask_source2_forwarding[1] | mask_source2_forwarding[2];

    // assign mask_source1 = mask_source1_cdb[0] | mask_source1_cdb[1] | mask_source1_cdb[2];
    // assign mask_source2 = mask_source2_cdb[0] | mask_source2_cdb[1] | mask_source2_cdb[2];

    // update the ready bit 

    
    always_comb begin
        for (integer unsigned j = 0; j < `RS_SIZE; j = j+1) begin
            rs_data_after_reserve_comb[j].source1_preg.valid = (mask_source1[j] | rs_data_after_compress_comb[j].source1_preg.valid) & rs_data_after_compress_comb[j].valid;
            rs_data_after_reserve_comb[j].source2_preg.valid = (mask_source2[j] | rs_data_after_compress_comb[j].source2_preg.valid) & rs_data_after_compress_comb[j].valid;
            rs_data_after_reserve_comb[j].ready              = rs_data_after_reserve_comb[j].source1_preg.valid & rs_data_after_reserve_comb[j].source2_preg.valid;
        end

        for (integer unsigned i = 0; i < 3; i = i+1) begin
            if(tail_after_compress_comb+i < `RS_SIZE) begin
                // rs_data_after_reserve_comb[tail_after_compress_comb+i].source1_preg.valid  = (rs_in.rs_in_packet[i].source1_preg.valid | mask_source1[tail_after_compress_comb+i]) & rs_data_after_reserve_comb[tail_after_compress_comb+i].valid;
                // rs_data_after_reserve_comb[tail_after_compress_comb+i].source2_preg.valid  = (rs_in.rs_in_packet[i].source2_preg.valid | mask_source2[tail_after_compress_comb+i]) & rs_data_after_reserve_comb[tail_after_compress_comb+i].valid;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].source1_preg.valid  = (rs_in.rs_in_packet[i].source1_preg.valid | mask_source1[tail_after_compress_comb+i]) & rs_in.rs_in_packet[i].valid;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].source2_preg.valid  = (rs_in.rs_in_packet[i].source2_preg.valid | mask_source2[tail_after_compress_comb+i]) & rs_in.rs_in_packet[i].valid;
                rs_data_after_reserve_comb[tail_after_compress_comb+i].ready               = rs_data_after_reserve_comb[tail_after_compress_comb+i].source1_preg.valid & rs_data_after_reserve_comb[tail_after_compress_comb+i].source2_preg.valid;
            end
        end
    end

    // if branch is correctly predicted, clear branch mask bit for instruction in RS
    always_comb begin
        rs_data_after_correct_branch_comb = rs_data_after_reserve_comb;
        if(branch_correct) begin
            for(integer unsigned i = 0; i < `RS_SIZE; i=i+1) begin
                rs_data_after_correct_branch_comb[i].branch_mask = rs_data_after_reserve_comb[i].branch_mask & ~branch_stack;
            end
        end
    end

    
    // generate the output to FU
    // dealing with the structural hazard for mult instruction, one cycle can issue only one mult instruction

    //inst_issue_reverse is the instruction in RS can be issued which only contain at most one ready mult instruction and one ready branch instruction
    generate
    genvar m;
        for( m = 0; m < `RS_SIZE; m = m+1) begin: instruction_issue
            assign inst_issue_reverse[`RS_SIZE-m-1] = m > first_mult_position ?  (m > first_branch_position ? (!rs_data[m].is_mult_inst) && (!rs_data[m].is_cond_branch_inst) && rs_data[m].ready :  (!rs_data[m].is_mult_inst) && rs_data[m].ready) :
                                                                                 (m > first_branch_position ? (!rs_data[m].is_cond_branch_inst) && rs_data[m].ready : rs_data[m].ready);
        end
    endgenerate

    // update the instruction can be issued when the first and second instruction has been issued
    always_comb begin
        inst_issue_reverse_1 = inst_issue_reverse;
        inst_issue_reverse_1[inst_issue_idx_reverse[0]] = 1'b0;
        inst_issue_reverse_2 = inst_issue_reverse_1;
        inst_issue_reverse_2[inst_issue_idx_reverse[1]] = 1'b0;
    end

    priority_encoder #(.IN_WIDTH(`RS_SIZE)) pe_issue_1 (.req(inst_issue_reverse)  , .enc(inst_issue_idx_reverse[0]));
    priority_encoder #(.IN_WIDTH(`RS_SIZE)) pe_issue_2 (.req(inst_issue_reverse_1), .enc(inst_issue_idx_reverse[1]));
    priority_encoder #(.IN_WIDTH(`RS_SIZE)) pe_issue_3 (.req(inst_issue_reverse_2), .enc(inst_issue_idx_reverse[2]));

    assign inst_issue_idx[0] =  `RS_SIZE-inst_issue_idx_reverse[0]-1;
    assign inst_issue_idx[1] =  `RS_SIZE-inst_issue_idx_reverse[1]-1;
    assign inst_issue_idx[2] =  `RS_SIZE-inst_issue_idx_reverse[2]-1;
    // if there is no instruction can be issued or only the last instruction can be issued, the inst_issue_idx[i] == `RS_SIZE-1
    assign issue_valid[0]  =  inst_issue_idx[0] == `RS_SIZE-1 && !inst_issue_reverse[0] ? 1'b0 : 1'b1;
    // if issue_inst[0] has issued the last instruction of RS, then issue_inst[1][2] can not issue last instruction again
    assign issue_valid[1]  =  (inst_issue_idx[1] == `RS_SIZE-1 && !inst_issue_reverse_1[0]) ? 1'b0 : 1'b1;
    assign issue_valid[2]  =  (inst_issue_idx[2] == `RS_SIZE-1 && !inst_issue_reverse_2[0]) ? 1'b0 : 1'b1;

    assign rs_out.rs_out_packet[0] = rs_data[inst_issue_idx[0]];
    assign rs_out.rs_out_packet[1] = rs_data[inst_issue_idx[1]];
    assign rs_out.rs_out_packet[2] = rs_data[inst_issue_idx[2]];
    assign rs_out.inst_valid[0]    = stall ? 1'b0 : issue_valid[0];
    assign rs_out.inst_valid[1]    = stall ? 1'b0 : issue_valid[1];
    assign rs_out.inst_valid[2]    = stall ? 1'b0 : issue_valid[2];


    // squash RS if branch is mispredicted
    generate
    genvar t;
        for(t = 0; t < `RS_SIZE; t=t+1) begin: rssquash
            assign rs_squash_entry[t] = rs_data_after_compress_comb[t].valid && (|(rs_data_after_compress_comb[t].branch_mask & branch_stack));
        end
    endgenerate

    always_comb begin
        // if branch recovery, no more new instruction will be reserved in RS under current cycle
        rs_data_squash_comb = rs_data_after_compress_comb;
        for(integer unsigned i = 0; i < `RS_SIZE; i = i+1) begin
            rs_data_squash_comb[i].valid =  rs_squash_entry[i]  ?  1'b0 : rs_data_after_compress_comb[i].valid;    
            rs_data_squash_comb[i].ready =  rs_squash_entry[i]  ?  1'b0 : rs_data_after_compress_comb[i].ready;    
        end
        for (integer unsigned k = 0; k < `RS_SIZE; k = k+1) begin
            if(k<tail_squash_comb) begin
                rs_data_squash_comb[k].source1_preg.valid = mask_source1[k] | rs_data_squash_comb[k].source1_preg.valid;
                rs_data_squash_comb[k].source2_preg.valid = mask_source2[k] | rs_data_squash_comb[k].source2_preg.valid;
                rs_data_squash_comb[k].ready              = rs_data_squash_comb[k].source1_preg.valid && rs_data_squash_comb[k].source2_preg.valid 
                                                            && (rs_squash_entry[k]  ?  1'b0 : rs_data_after_compress_comb[k].valid);
            end
            else begin
                rs_data_squash_comb[k] = '0;
            end
        end
    end

    always_comb begin
        tail_squash_move = '0;
        tail_squash_move[0] = rs_squash_entry[0];
        for(integer unsigned i = 1; i <`RS_SIZE; i=i+1) begin
            tail_squash_move[i] = tail_squash_move[i-1] + rs_squash_entry[i];
        end
    end

    assign tail_squash_comb = tail_after_compress_comb - tail_squash_move[ `RS_SIZE-1];

endmodule
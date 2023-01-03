
`timescale 1ns/100ps
typedef enum logic[1:0] {S_TAKEN,W_TAKEN,W_N_TAKEN,S_N_TAKEN} predict_state;

module two_bit_saturate_predictor(
    input clock,
    input reset,
    input branch_resolved_result, // for updating two bit prediction after branch resolved, 1 represent taken while 0 represent not taken
    input update_valid,
    output predict_result // output the prediction direction result
);

    predict_state current_state,next_state;

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            current_state <= W_TAKEN;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;
        if(update_valid) begin
            case(current_state) 
                S_TAKEN   : next_state = branch_resolved_result ? S_TAKEN   : W_TAKEN;
                W_TAKEN   : next_state = branch_resolved_result ? S_TAKEN   : W_N_TAKEN;
                W_N_TAKEN : next_state = branch_resolved_result ? W_TAKEN   : S_N_TAKEN;
                S_N_TAKEN : next_state = branch_resolved_result ? W_N_TAKEN : S_N_TAKEN;
            endcase
        end
    end

    assign predict_result = ((current_state == S_TAKEN) | (current_state == W_TAKEN)) ? 1'b1 : 1'b0;

endmodule


module local_history_predictor(
    input clock,
    input reset,
    input [`XLEN-1:0] branch_prediction_pc,
    input [`XLEN-1:0] branch_resolved_pc,
    input branch_prediction_valid,
    input branch_resolved_valid, // bht and pht will only be updated after a valid branch has been resolved
    input [`BRANCH_STACK_SIZE-1:0] branch_stack_predict,
    input [`BRANCH_STACK_SIZE-1:0] branch_stack_resolved, // the pht entry which should be updated when branch has been resolved
    input branch_resolved_result,
    output branch_prediction_result
);

    //2 ^ `BRANCH_HISTORY_SIZE = `BRANCH_PHT_SIZE
    logic [`BHT_ENTRY_NUM-1:0] [`BRANCH_HISTORY_SIZE-1:0] bht_data;
    logic [`BHT_ENTRY_NUM-1:0] [`BRANCH_HISTORY_SIZE-1:0] bht_data_comb;
    logic [$clog2(`BHT_ENTRY_NUM)-1:0] branch_prediction_bht_index;
    logic [$clog2(`BHT_ENTRY_NUM)-1:0] branch_resolved_bht_index;
    logic [$clog2(`BRANCH_PHT_SIZE)-1:0] pht_prediction_idx;
    logic [$clog2(`BRANCH_PHT_SIZE)-1:0] branch_resolved_pht_idx;
    logic [`BRANCH_PHT_SIZE-1:0] pht_updated_mask;
    logic [`BRANCH_PHT_SIZE-1:0] pht_out_array;

    // to save the corresponding pht entry of predicted branch by branch mask
    logic [`BRANCH_STACK_SIZE-1:0] [$clog2(`BRANCH_PHT_SIZE)-1:0] predicted_branch_pht_idx;
    logic [`BRANCH_STACK_SIZE-1:0] [$clog2(`BRANCH_PHT_SIZE)-1:0] predicted_branch_pht_idx_comb;
    logic [$clog2(`BRANCH_STACK_SIZE)-1:0] branch_stack_predict_idx;
    logic [$clog2(`BRANCH_STACK_SIZE)-1:0] branch_stack_resolved_idx;

    // for branch prediction
    // the bht entry corresponding to branch prediction pc
    assign branch_prediction_bht_index = branch_prediction_pc[$clog2(`BHT_ENTRY_NUM)-1:0];
    // for getting pht idx which is used for branch prediction
    assign pht_prediction_idx = bht_data[branch_prediction_bht_index];
    // assign branch_prediction_result = pht_out_array[pht_prediction_idx];
    assign branch_prediction_result = branch_prediction_valid ? pht_out_array[pht_prediction_idx] : 1'b0;


    // for branch resolved
    assign branch_resolved_bht_index =  branch_resolved_pc[$clog2(`BHT_ENTRY_NUM)-1:0];
    assign branch_resolved_pht_idx = predicted_branch_pht_idx[branch_stack_resolved_idx];
    // find which pht entry to update
    always_comb begin
        pht_updated_mask = 0;
        pht_updated_mask[branch_resolved_pht_idx] = 1'b1;
    end
    // update bht for resolved branch result
    always_comb begin
        bht_data_comb = bht_data;
        if(branch_resolved_valid)
            bht_data_comb[branch_resolved_bht_index] = {bht_data[`BRANCH_HISTORY_SIZE-2:0],branch_resolved_result};
    end


    // PHT
    generate
        genvar i;
        for(i = 0; i < `BRANCH_PHT_SIZE; i=i+1) begin:pht
            two_bit_saturate_predictor PHT(.clock(clock),.reset(reset),.branch_resolved_result(branch_resolved_result),.update_valid(pht_updated_mask[i] & branch_resolved_valid),.predict_result(pht_out_array[i]));
        end 
    endgenerate

    // to save the corresponding pht entry of predicted branch by branch mask
    pe #(.IN_WIDTH(`BRANCH_STACK_SIZE)) encoder_branch_predict  (.gnt(branch_stack_predict), .enc(branch_stack_predict_idx));
    pe #(.IN_WIDTH(`BRANCH_STACK_SIZE)) encoder_branch_resolved (.gnt(branch_stack_resolved), .enc(branch_stack_resolved_idx));

    always_comb begin
        predicted_branch_pht_idx_comb = predicted_branch_pht_idx;
        if(branch_prediction_valid)
            predicted_branch_pht_idx_comb[branch_stack_predict_idx] = pht_prediction_idx;
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            predicted_branch_pht_idx <= '0;
        end
        else begin
            predicted_branch_pht_idx <= predicted_branch_pht_idx_comb;
        end
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            bht_data <= '0;
        end
        else begin
            bht_data <= bht_data_comb;
        end
    end

endmodule

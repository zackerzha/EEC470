
module cdb_param_early_branch(
    input clock,
    input reset,
    input FU_CDB_PACKET fu_cdb_packet,

    input branch_recovery,
    input branch_correct,
    input [`BRANCH_STACK_SIZE-1:0] branch_stack,

    output CDB_PACKET [2:0] cdb_packet,
    output PRF_WRITE_PACKET prf_write,
    output rs_stall
);

    logic [`CDB_BUFFER_SIZE-1:0] cdb_buffer_valid_mask;
    logic [`CDB_BUFFER_SIZE-1:0] cdb_buffer_selected;
    logic [3*`CDB_BUFFER_SIZE-1:0] cdb_buffer_selected_bus;
    logic cdb_buffer_empty;
    logic [$clog2(`CDB_BUFFER_SIZE)-1:0] cdb_buffer_selected_idx [2:0];
    logic [2:0] cdb_buffer_selected_valid;

    logic [`CDB_BUFFER_SIZE-1:0] cdb_buffer_available_mask;
    logic [`CDB_BUFFER_SIZE-1:0] cdb_buffer_available_selected;
    logic [`FU_SIZE*`CDB_BUFFER_SIZE-1:0] cdb_buffer_available_selected_bus;
    logic cdb_buffer_available_empty;
    logic [$clog2(`CDB_BUFFER_SIZE)-1:0] cdb_buffer_available_selected_idx [`FU_SIZE-1:0];
    logic [`FU_SIZE-1:0] cdb_buffer_available_selected_valid;
    
    logic [`FU_SIZE-1:0][$clog2(`CDB_BUFFER_SIZE)-1:0] temp;
    logic [$clog2(`PE_IN_WIDTH)-1:0] num_addto_cdb_buffer;
    // the number of packet send to cdb which are from fu_cdb_packet or load_cdb_packet instead of cdb buffer 
    logic [1:0] num_from_cdb_packet;
    // the number of packet send to cdb which are from cdb buffer instead of fu_cdb_packet or load_cdb_packet
    logic [1:0] num_from_cdb_buffer;


    logic [`FU_SIZE-1:0][$clog2(`PE_IN_WIDTH)-1:0] num_cdb_packet_valid_temp;
    logic [$clog2(`PE_IN_WIDTH)-1:0] num_cdb_packet_valid;

    FU_OUT_CDB_ENTRY[`CDB_BUFFER_SIZE-1:0] cdb_buffer_data;
    FU_OUT_CDB_ENTRY[`CDB_BUFFER_SIZE-1:0] cdb_buffer_data_free_comb;
    FU_OUT_CDB_ENTRY[`CDB_BUFFER_SIZE-1:0] cdb_buffer_data_reserve_comb;
    FU_OUT_CDB_ENTRY[`CDB_BUFFER_SIZE-1:0] cdb_buffer_data_comb;

    // this variable store compressed fu_cdb_packet and load_cdb_packet, which means that the data in cdb_packet_data has exclude the invalid entry in both fu_cdb_packet and load_cdb_packet
    // the sequence for data in cdb_packet_data is 
    // 7->0 : load*3 , fu_cdb_packet[3], fu_cdb_packet[2], fu_cdb_packet[1], fu_cdb_packet[0]
    FU_OUT_CDB_ENTRY[`FU_SIZE-1:0] fu_cdb_packet_compressed;
    // add the element in fu_cdb_packet_compressed which has not been issued to cdb to cdb buffer
    FU_OUT_CDB_ENTRY[`FU_SIZE-1:0] fu_cdb_packet_compressed_to_cdb_buffer;
    // the output of priority encoder, which represent the index of valid entry in cdb_packet_data
    logic [`FU_SIZE-1:0][$clog2(`PE_IN_WIDTH)-1:0] cdb_packet_entry_index;
    // it represent whether the entry of fu_cdb_packet_compressed is valid, becasue a four bit input priority encoder will output 0 for both 0001 and 0000
    logic [`FU_SIZE-1:0] fu_cdb_packet_compressed_valid;
    
    //logic [$clog2(`CDB_BUFFER_SIZE):0] occupied_entry;
    //logic [$clog2(`CDB_BUFFER_SIZE):0] available_entry;

    //logic [$clog2(`CDB_BUFFER_SIZE):0] occupied_entry_before_issue;

        // cdb_packet_valid_mask[0] represent which input cdb packet is valid
    // cdb_packet_valid which mask the first valid bit
    logic [`FU_SIZE-1:0]  cdb_packet_valid_mask [`FU_SIZE-1:0];

    logic [2:0] squash_after_branch;

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            cdb_buffer_data <= '0;
        end
        else begin
            cdb_buffer_data <= cdb_buffer_data_comb;
        end
    end

    generate
        genvar i;
        for(i = 0; i < `FU_SIZE; i=i+1) begin : cdb_packet_valid_mask0
            assign cdb_packet_valid_mask[0][i] = fu_cdb_packet.fu_cdb_packet[i].valid;
        end

        for(i = 0; i < `FU_SIZE; i=i+1) begin : PE
            priority_encoder #(.IN_WIDTH( `PE_IN_WIDTH)) pe0 (.req({{(`PE_IN_WIDTH-`FU_SIZE){1'b0}},cdb_packet_valid_mask[i]}),.enc(cdb_packet_entry_index[i]));
        end

        for(i = 0; i < `FU_SIZE; i=i+1) begin: Fu_cdb_packet_compressed
            assign fu_cdb_packet_compressed[i] = fu_cdb_packet.fu_cdb_packet[cdb_packet_entry_index[i]];
        end

        assign fu_cdb_packet_compressed_valid[0] = (cdb_packet_entry_index[0] == 0 & cdb_packet_valid_mask[0][0]==0) ? 1'b0 : 1'b1;

        for(i = 1; i < `FU_SIZE; i=i+1) begin:  Fu_cdb_packet_compressed_valid
            assign fu_cdb_packet_compressed_valid[i] = (cdb_packet_entry_index[i] == 0 & (cdb_packet_valid_mask[0][0]==0 | cdb_packet_entry_index[i-1] == 0)) ? 1'b0 : 1'b1;
        end

        assign num_cdb_packet_valid_temp[0] = cdb_packet_valid_mask[0][0];
        for(i = 1; i < `FU_SIZE; i=i+1) begin : Num_cdb_packet_valid
            assign num_cdb_packet_valid_temp[i] = num_cdb_packet_valid_temp[i-1] + cdb_packet_valid_mask[0][i];
        end

        // generate the mask which represent which entry of cdb buffer is valid
        for(i = 0; i < `CDB_BUFFER_SIZE; i=i+1) begin: cdb_buffer_valid_mask_generator
            assign cdb_buffer_valid_mask[i] = cdb_buffer_data[i].valid;
        end

        // generate the mask which represent which entry of cdb buffer is available after free
        for(i = 0; i < `CDB_BUFFER_SIZE; i=i+1) begin: cdb_buffer_available_mak_generator
            assign cdb_buffer_available_mask[i] = ~cdb_buffer_data_free_comb[i].valid;
        end
        
    endgenerate

    // mask the valid entry of cdb_packet which has already be compressed
    always_comb begin
        for(integer unsigned i = 1 ; i < `FU_SIZE ; i=i+1) begin
            cdb_packet_valid_mask[i] = cdb_packet_valid_mask[i-1] & ~(1'b1<< cdb_packet_entry_index[i-1]);
        end
    end

    // the valid entry in cdb_packet
    assign num_cdb_packet_valid = num_cdb_packet_valid_temp[`FU_SIZE-1];

    // choose three valid entry from cdb buffer
    psel_gen #(.REQS(3), .WIDTH(`CDB_BUFFER_SIZE)) cdb_buffer_selector
    ( .req(cdb_buffer_valid_mask),
      .gnt(cdb_buffer_selected),
      .gnt_bus(cdb_buffer_selected_bus),
      .empty(cdb_buffer_empty)
    );
    pe #(.IN_WIDTH(`CDB_BUFFER_SIZE)) ed_cdb_buffer0 (.gnt(cdb_buffer_selected_bus[`CDB_BUFFER_SIZE-1:0]), .enc(cdb_buffer_selected_idx[0]));
    pe #(.IN_WIDTH(`CDB_BUFFER_SIZE)) ed_cdb_buffer1 (.gnt(cdb_buffer_selected_bus[2*`CDB_BUFFER_SIZE-1:`CDB_BUFFER_SIZE]), .enc(cdb_buffer_selected_idx[1]));
    pe #(.IN_WIDTH(`CDB_BUFFER_SIZE)) ed_cdb_buffer2 (.gnt(cdb_buffer_selected_bus[3*`CDB_BUFFER_SIZE-1:2*`CDB_BUFFER_SIZE]), .enc(cdb_buffer_selected_idx[2]));
    assign cdb_buffer_selected_valid[0] = | cdb_buffer_selected_bus[`CDB_BUFFER_SIZE-1:0];
    assign cdb_buffer_selected_valid[1] = | cdb_buffer_selected_bus[2*`CDB_BUFFER_SIZE-1:`CDB_BUFFER_SIZE];
    assign cdb_buffer_selected_valid[2] = | cdb_buffer_selected_bus[3*`CDB_BUFFER_SIZE-1:2*`CDB_BUFFER_SIZE];


    // decide the source of the output of cdb module "cdb_packet"
    assign num_from_cdb_buffer =  cdb_buffer_selected_valid[0] + cdb_buffer_selected_valid[1] + cdb_buffer_selected_valid[2];
    // in "cdb_packet", if the source is from input fu_cdb_packet, the number from fu_cdb_packet is the minimum of the valid entry in fu_cdb_packet and the cdb boardcast bandwidth
    assign num_from_cdb_packet =  3 - num_from_cdb_buffer > num_cdb_packet_valid ? num_cdb_packet_valid : 3 - num_from_cdb_buffer;

    assign num_addto_cdb_buffer = num_cdb_packet_valid - num_from_cdb_packet;
    // generate the output cdb_packet
    always_comb begin
        squash_after_branch = 0;
        for(integer unsigned i = 0; i < 3; i = i+1) begin
            if(i < num_from_cdb_buffer) begin
                squash_after_branch[i] = branch_recovery & (|(cdb_buffer_data[cdb_buffer_selected_idx[i]].branch_mask & branch_stack));
                cdb_packet[i].complete_preg  =  cdb_buffer_data[cdb_buffer_selected_idx[i]].preg_to_write;
                cdb_packet[i].complete_lreg  =  cdb_buffer_data[cdb_buffer_selected_idx[i]].lreg_to_write;
                cdb_packet[i].rob_tail       =  cdb_buffer_data[cdb_buffer_selected_idx[i]].rob_tail;
                cdb_packet[i].branch_mask    =  branch_correct ? cdb_buffer_data[cdb_buffer_selected_idx[i]].branch_mask & ~branch_stack : cdb_buffer_data[cdb_buffer_selected_idx[i]].branch_mask;
                cdb_packet[i].complete_valid =  cdb_buffer_data[cdb_buffer_selected_idx[i]].is_wb_inst & ~squash_after_branch[i];
                cdb_packet[i].complete_rob_valid =  ~squash_after_branch[i];
                prf_write.prf_write_packet[i].preg_to_write = cdb_buffer_data[cdb_buffer_selected_idx[i]].preg_to_write;
                prf_write.prf_write_packet[i].preg_value    = cdb_buffer_data[cdb_buffer_selected_idx[i]].preg_value;
                prf_write.write_enable[i]                   = cdb_buffer_data[cdb_buffer_selected_idx[i]].is_wb_inst &  ~squash_after_branch[i];
            end
            else if(i >= num_from_cdb_buffer && i < num_from_cdb_buffer + num_from_cdb_packet) begin
                squash_after_branch[i] = branch_recovery & (|(fu_cdb_packet_compressed[i-num_from_cdb_buffer].branch_mask & branch_stack));
                cdb_packet[i].complete_preg  =  fu_cdb_packet_compressed[i-num_from_cdb_buffer].preg_to_write;
                cdb_packet[i].complete_lreg  =  fu_cdb_packet_compressed[i-num_from_cdb_buffer].lreg_to_write;
                cdb_packet[i].rob_tail       =  fu_cdb_packet_compressed[i-num_from_cdb_buffer].rob_tail;
                cdb_packet[i].branch_mask    =  branch_correct ? fu_cdb_packet_compressed[i-num_from_cdb_buffer].branch_mask & ~branch_stack : fu_cdb_packet_compressed[i-num_from_cdb_buffer].branch_mask;
                cdb_packet[i].complete_valid =  fu_cdb_packet_compressed[i-num_from_cdb_buffer].is_wb_inst & ~squash_after_branch[i];
                cdb_packet[i].complete_rob_valid =  ~squash_after_branch[i];
                prf_write.prf_write_packet[i].preg_to_write = fu_cdb_packet_compressed[i-num_from_cdb_buffer].preg_to_write;
                prf_write.prf_write_packet[i].preg_value    = fu_cdb_packet_compressed[i-num_from_cdb_buffer].preg_value;
                prf_write.write_enable[i]                   = fu_cdb_packet_compressed[i-num_from_cdb_buffer].is_wb_inst & ~squash_after_branch[i];
            end
            else begin
                cdb_packet[i] = '0;
                prf_write.prf_write_packet[i] = '0;
                prf_write.write_enable[i]     = 1'b0;
            end
        end
    end

    // update the data in cdb buffer
    // free the entry in cdb_buffer which has already been issed
    always_comb begin
        cdb_buffer_data_free_comb = cdb_buffer_data;
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            if(cdb_buffer_selected_valid[i]) begin
                cdb_buffer_data_free_comb[cdb_buffer_selected_idx[i]] = '0;
            end
        end
        if(branch_recovery) begin
            for(integer unsigned i = 0; i < `CDB_BUFFER_SIZE-1; i=i+1) begin
                if(|(cdb_buffer_data_free_comb[i].branch_mask & branch_stack) & cdb_buffer_data_free_comb[i].valid) begin
                    cdb_buffer_data_free_comb[i] = '0;
                end
            end
        end
    end
    
    // reserve the entry in cdb_buffer
    always_comb begin
        fu_cdb_packet_compressed_to_cdb_buffer = '0;
        for(integer unsigned i = 0; i < `FU_SIZE; i=i+1) begin
            if(i < num_addto_cdb_buffer) begin
                fu_cdb_packet_compressed_to_cdb_buffer[i] = fu_cdb_packet_compressed[num_from_cdb_packet+i];
            end
            else begin
                fu_cdb_packet_compressed_to_cdb_buffer[i] = '0;
            end
        end
    end

    psel_gen #(.REQS(`FU_SIZE), .WIDTH(`CDB_BUFFER_SIZE)) cdb_buffer_available_selector
    ( .req(cdb_buffer_available_mask),
      .gnt(cdb_buffer_available_selected),
      .gnt_bus(cdb_buffer_available_selected_bus),
      .empty(cdb_buffer_available_empty)
    ); 
    
    generate
        genvar j;
        for(j = 0; j < `FU_SIZE; j=j+1) begin: cdb_available_selector
            pe #(.IN_WIDTH(`CDB_BUFFER_SIZE)) ed_cdb_buffer_available0 (.gnt(cdb_buffer_available_selected_bus[(j+1)*`CDB_BUFFER_SIZE-1:j*`CDB_BUFFER_SIZE]), .enc(cdb_buffer_available_selected_idx[j]));
            assign cdb_buffer_available_selected_valid[j] = | cdb_buffer_available_selected_bus[(j+1)*`CDB_BUFFER_SIZE-1:j*`CDB_BUFFER_SIZE];
        end
    endgenerate

    always_comb begin
        cdb_buffer_data_reserve_comb = cdb_buffer_data_free_comb;
        for(integer unsigned i = 0 ;i < `FU_SIZE; i=i+1) begin
            // actually, cdb buffer can never be full, and it will accept all valid fu_cdb_packet
            if(fu_cdb_packet_compressed_to_cdb_buffer[i].valid & cdb_buffer_available_selected_valid[i]) begin
                cdb_buffer_data_reserve_comb[cdb_buffer_available_selected_idx[i]] = fu_cdb_packet_compressed_to_cdb_buffer[i];
            end
        end
    end

    // if branch prediction result is correct, update branch mask in cdb buffer
    always_comb begin
        cdb_buffer_data_comb = cdb_buffer_data_reserve_comb;
        if(branch_correct) begin
            for(integer unsigned i = 0; i < `CDB_BUFFER_SIZE; i=i+1) begin
                if(cdb_buffer_data_comb[i].valid) begin
                    cdb_buffer_data_comb[i].branch_mask = cdb_buffer_data_reserve_comb[i].branch_mask & ~branch_stack;
                end
            end
        end
    end

    // generate the number of available entry in cdb_buffer_data_comb
    logic [$clog2(`CDB_BUFFER_SIZE):0] cdb_available_entry_num [`CDB_BUFFER_SIZE:0];
    assign cdb_available_entry_num[0] = 0;
    generate
        genvar k;
        for(k = 0; k < `CDB_BUFFER_SIZE; k=k+1) begin: cdb_available_entry_num_generator
            assign cdb_available_entry_num[k+1] = cdb_available_entry_num[k] + ~cdb_buffer_data_comb[k].valid;
        end
    endgenerate

    assign rs_stall = cdb_available_entry_num[`CDB_BUFFER_SIZE] < 4 ? 1'b1 : 1'b0;
endmodule
module LQ (
    input clock,
    input reset,

    input LQ_RESERVE_PACKET lq_reserve_packet,
    input FU_OUT_LQ_ENTRY [2:0] lq_address_packet,
    input ROB_TO_LQ_PACKET rob_to_lq_packet,
    input SQ_TO_LQ_PACKET sq_to_lq_packet,
    input CACHE_TO_LQ_PACKET cache_to_lq_packet,
    input [$clog2(`LSQ_SIZE):0] sq_head,
    input [`LSQ_SIZE-1:0] completed_store,

    input branch_recovery,
    input branch_correct,
    input [`BRANCH_STACK_SIZE-1:0] branch_stack,
    input [$clog2(`LSQ_SIZE):0] branch_recovery_lq_tail,

    input [`LSQ_SIZE-1:0] load_accepted_cache,
    //input cdb_stall,

    output LQ_TO_SQ_PACKET lq_to_sq_packet,
    output LQ_TO_CACHE_PACKET lq_to_cache_packet,
    output FU_OUT_CDB_ENTRY [2:0] lq_to_cdb_packet,
    output logic [1:0] entry_available,
    output logic [$clog2(`LSQ_SIZE):0] lq_tail
    
);

    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data;
    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data_comb;
    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data_freed_comb;
    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data_get_address_comb;
    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data_forward_comb;
    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data_cache_comb;
    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data_reserve_comb;
    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data_complete_comb;
    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data_issue_sq_comb;
    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data_branch_correct_comb;
    LQ_ENTRY[`LSQ_SIZE-1:0] lq_data_branch_recovery_comb;
    
    logic [`LSQ_SIZE-1:0] issued_to_sq;
    logic [`LSQ_SIZE-1:0] issued_to_dcache;
    logic [`LSQ_SIZE-1:0] issued_to_cdb;
    logic [`LSQ_SIZE-1:0] issued_to_sq_comb;
    logic [`LSQ_SIZE-1:0] issued_to_dcache_comb;
    logic [`LSQ_SIZE-1:0] issued_to_cdb_comb;

    LQ_ISSUED_PACKET lq_issued_packet;
    LQ_ISSUED_PACKET lq_issued_packet_freed_comb;
    LQ_ISSUED_PACKET lq_issued_packet_updated_comb;
    LQ_ISSUED_PACKET lq_issued_packet_reserved_comb;
    LQ_ISSUED_PACKET lq_issued_packet_branch_recovery_comb;
    LQ_ISSUED_PACKET lq_issued_packet_comb;
    
    logic [$clog2(`LSQ_SIZE):0] head;
    logic [$clog2(`LSQ_SIZE):0] tail;
    logic [$clog2(`LSQ_SIZE):0] head_rl;
    logic [$clog2(`LSQ_SIZE):0] tail_rl;
    logic [$clog2(`LSQ_SIZE):0] branch_recovery_lq_tail_rl;
    logic [$clog2(`LSQ_SIZE):0] tail_rl_1;
    logic [$clog2(`LSQ_SIZE)-1:0] tail_add [3:0];
    logic [$clog2(`LSQ_SIZE):0] head_comb;
    logic [$clog2(`LSQ_SIZE):0] tail_comb;

    logic [$clog2(`LSQ_SIZE):0] occupied_entry;

    logic [3:0] data_offset [2:0];

    logic [$clog2(`LSQ_SIZE)-1:0] squash_index;
    logic [$clog2(`LSQ_SIZE)-1:0] squash_index_issue;

    logic [`LSQ_SIZE-1:0] previous_store_mask [2:0];

    logic [`LSQ_SIZE-1:0] sq_to_issue;
    logic [`LSQ_SIZE-1:0] sq_issue_selected;
    logic [3*`LSQ_SIZE-1:0] sq_issue_selected_bus;
    logic [$clog2(`LSQ_SIZE)-1:0] sq_issued_index [2:0];
    logic [2:0] sq_issued_valid;
    logic sq_to_issue_empty;

    logic [`LSQ_SIZE-1:0] cache_to_issue;
    logic [`LSQ_SIZE-1:0] cache_issue_selected;
    logic [3*`LSQ_SIZE-1:0] cache_issue_selected_bus;
    logic [$clog2(`LSQ_SIZE)-1:0] cache_issued_index [2:0];
    logic [2:0] cache_issued_valid;
    logic cache_to_issue_empty;

    logic [`LSQ_SIZE-1:0] cdb_to_issue;
    logic [`LSQ_SIZE-1:0] cdb_issue_selected;
    logic [3*`LSQ_SIZE-1:0] cdb_issue_selected_bus;
    logic [$clog2(`LSQ_SIZE)-1:0] cdb_issued_index [2:0];
    logic [2:0] cdb_issued_valid;
    logic cdb_to_issue_empty;
    logic [`XLEN-1:0] cdb_data [2:0];

    logic [$clog2(`LSQ_SIZE):0] num_to_squash;



    assign head_rl = {1'b0, head[$clog2(`LSQ_SIZE)-1:0]};
    assign tail_rl = head[$clog2(`LSQ_SIZE)] != tail[$clog2(`LSQ_SIZE)] ? {1'b1,tail[$clog2(`LSQ_SIZE)-1:0]} : {1'b0,tail[$clog2(`LSQ_SIZE)-1:0]};

    assign branch_recovery_lq_tail_rl = {1'b0, branch_recovery_lq_tail[$clog2(`LSQ_SIZE)-1:0]};
    assign tail_rl_1 = branch_recovery_lq_tail[$clog2(`LSQ_SIZE)] != tail[$clog2(`LSQ_SIZE)] ? {1'b1,tail[$clog2(`LSQ_SIZE)-1:0]} : {1'b0,tail[$clog2(`LSQ_SIZE)-1:0]};
    assign num_to_squash =  tail_rl_1 - branch_recovery_lq_tail_rl;

    assign occupied_entry = tail[$clog2(`LSQ_SIZE)] == head_comb[$clog2(`LSQ_SIZE)] ? tail - head_comb : {1'b1,tail[$clog2(`LSQ_SIZE)-1:0]} - {1'b0,head_comb[$clog2(`LSQ_SIZE)-1:0]};

    assign lq_tail = tail;

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            lq_data <= '0;
            lq_issued_packet <= '0;
            head <= 0;
            tail <= 0;
        end
        else begin
            lq_data <= lq_data_comb;
            lq_issued_packet <= lq_issued_packet_comb;
            head <= head_comb;
            tail <= tail_comb;
        end
    end

    assign tail_add[0] = tail;
    assign tail_add[1] = tail + 1;
    assign tail_add[2] = tail + 2;
    assign tail_add[3] = tail + 3;

    assign head_comb = head + rob_to_lq_packet.valid[0]  + rob_to_lq_packet.valid[1] + rob_to_lq_packet.valid[2];
    assign tail_comb = branch_recovery ? branch_recovery_lq_tail : tail + lq_reserve_packet.lq_reserve_entry[0].valid + lq_reserve_packet.lq_reserve_entry[1].valid + lq_reserve_packet.lq_reserve_entry[2].valid;

    always_comb begin
        case(occupied_entry)
            `LSQ_SIZE   : entry_available = 2'b0;
            `LSQ_SIZE-1 : entry_available = 2'b1;
            `LSQ_SIZE-2 : entry_available = 2'b10;
            default     : entry_available = 2'b11;
        endcase
    end

    /////////////////////////////////////////      Update lq_data    ////////////////////////////////////////////////
    // free lq entry
    always_comb begin
        lq_data_freed_comb = lq_data;
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            if(rob_to_lq_packet.valid[i]) begin
                lq_data_freed_comb[rob_to_lq_packet.lq_idx[i]] = '0;
            end
        end
    end

    // if address has been calculated for load
    always_comb begin
        lq_data_get_address_comb = lq_data_freed_comb;
        for(integer unsigned i = 0; i < 3 ;i=i+1) begin
            if(lq_address_packet[i].valid) begin
                lq_data_get_address_comb[lq_address_packet[i].lq_idx].address_ready = 1'b1;
                lq_data_get_address_comb[lq_address_packet[i].lq_idx].address  = lq_address_packet[i].load_address;
                lq_data_get_address_comb[lq_address_packet[i].lq_idx].data_offset   = data_offset[i];
            end
        end
    end

    // if data has been forwarded from sq to lq
    always_comb begin
        lq_data_forward_comb = lq_data_get_address_comb;
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            if(sq_to_lq_packet.sq_to_lq_entry[i].valid) begin
                lq_data_forward_comb[sq_to_lq_packet.sq_to_lq_entry[i].lq_idx].data                = sq_to_lq_packet.sq_to_lq_entry[i].data;
                lq_data_forward_comb[sq_to_lq_packet.sq_to_lq_entry[i].lq_idx].forward_data_offset = sq_to_lq_packet.sq_to_lq_entry[i].offset;
                lq_data_forward_comb[sq_to_lq_packet.sq_to_lq_entry[i].lq_idx].forwarded           = 1'b1;
                lq_data_forward_comb[sq_to_lq_packet.sq_to_lq_entry[i].lq_idx].complete            = sq_to_lq_packet.sq_to_lq_entry[i].complete;
            end
        end
    end

    // if data has been returned from cache
    always_comb begin
        lq_data_cache_comb = lq_data_forward_comb;
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            if(cache_to_lq_packet.cache_hit_packet[i].valid) begin
                lq_data_cache_comb[cache_to_lq_packet.cache_hit_packet[i].lq_idx].data      = cache_to_lq_packet.cache_hit_packet[i].data;
                lq_data_cache_comb[cache_to_lq_packet.cache_hit_packet[i].lq_idx].complete  = 1'b1;
            end
        end

        for(integer unsigned i = 0; i < `LOAD_STORE_TABLE_SIZE; i=i+1) begin
            if(cache_to_lq_packet.cache_miss_packet[i].valid) begin
                lq_data_cache_comb[cache_to_lq_packet.cache_miss_packet[i].lq_idx].data      = cache_to_lq_packet.cache_miss_packet[i].data;
                lq_data_cache_comb[cache_to_lq_packet.cache_miss_packet[i].lq_idx].complete  = 1'b1;
            end
        end
    end

    // if new load has been reserved in lq
    always_comb begin
        lq_data_reserve_comb = lq_data_cache_comb;
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            if(lq_reserve_packet.lq_reserve_entry[i].valid) begin
                lq_data_reserve_comb[tail_add[i]] = '0;
                lq_data_reserve_comb[tail_add[i]].valid = 1'b1;
                lq_data_reserve_comb[tail_add[i]].branch_mask = lq_reserve_packet.lq_reserve_entry[i].branch_mask;
                lq_data_reserve_comb[tail_add[i]].sq_complete = previous_store_mask[i]; // update the completed store for new reserved lq entry in the same cycle that this lq entry is reserved
                lq_data_reserve_comb[tail_add[i]].PC          = lq_reserve_packet.lq_reserve_entry[i].PC;
                lq_data_reserve_comb[tail_add[i]].sq_tail     = lq_reserve_packet.sq_tail[i];
                lq_data_reserve_comb[tail_add[i]].rob_tail    = lq_reserve_packet.lq_reserve_entry[i].rob_tail;
                lq_data_reserve_comb[tail_add[i]].preg        = lq_reserve_packet.lq_reserve_entry[i].preg;
                lq_data_reserve_comb[tail_add[i]].inst        = lq_reserve_packet.lq_reserve_entry[i].inst;
            end
        end
    end

    // if previous store has been completed, lq has to update
    always_comb begin
        lq_data_complete_comb = lq_data_reserve_comb;
        for(integer unsigned i = 0; i < `LSQ_SIZE; i=i+1) begin
            lq_data_complete_comb[i].sq_complete        = lq_data_reserve_comb[i].sq_complete | completed_store;
        end
    end

    always_comb begin
        lq_data_issue_sq_comb = lq_data_complete_comb;
        for(integer unsigned i = 0; i < `LSQ_SIZE; i=i+1) begin
            lq_data_issue_sq_comb[i].ready_to_search_sq = lq_data_complete_comb[i].address_ready & (&lq_data_complete_comb[i].sq_complete);
        end
    end

    always_comb begin
        lq_data_branch_correct_comb = lq_data_issue_sq_comb;
        if(branch_correct) begin
            for(integer unsigned i = 0; i < `LSQ_SIZE; i=i+1) begin
                lq_data_branch_correct_comb[i].branch_mask = lq_data_issue_sq_comb[i].branch_mask & ~branch_stack;
            end
        end
    end

    // if need to early branch recovery
    always_comb begin
        lq_data_branch_recovery_comb = lq_data_issue_sq_comb;
        squash_index = 0;
        for(integer unsigned i = 0; i < `LSQ_SIZE; i=i+1) begin
            squash_index = branch_recovery_lq_tail + i;
            if(i < num_to_squash) begin
                lq_data_branch_recovery_comb[squash_index] = '0;
            end
        end
    end

    assign lq_data_comb = branch_recovery ? lq_data_branch_recovery_comb : lq_data_branch_correct_comb;
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////


    ////////////////////////////////      Update lq_issued packet      ////////////////////////////////////////////////
    // issued_to_sq, issued_to_dcache and issued_to_cdb have to be updated when lq freed or lq reserve or branch recovery

    // when lq freed, clear specific bit of lq_issued_data
    always_comb begin
        lq_issued_packet_freed_comb = lq_issued_packet;
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            if(rob_to_lq_packet.valid[i]) begin
                lq_issued_packet_freed_comb.issued_to_sq[rob_to_lq_packet.lq_idx[i]]        = 1'b0;
                lq_issued_packet_freed_comb.issued_to_dcache[rob_to_lq_packet.lq_idx[i]]    = 1'b0;
                lq_issued_packet_freed_comb.issued_to_cdb[rob_to_lq_packet.lq_idx[i]]       = 1'b0;
            end
        end
    end

    // after issued to sq, d-cache and cdb, the bit in issued_to_sq, issued_to_dcache and issued_to_cdb which has been issued should be set 1
    always_comb begin
        lq_issued_packet_updated_comb = lq_issued_packet_freed_comb;
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            lq_issued_packet_updated_comb.issued_to_sq       = lq_issued_packet_freed_comb.issued_to_sq     | sq_issue_selected;
            lq_issued_packet_updated_comb.issued_to_dcache   = lq_issued_packet_freed_comb.issued_to_dcache | load_accepted_cache;//cache_issue_selected;//修改成d-cache返回的issued_accepted
            lq_issued_packet_updated_comb.issued_to_cdb      = lq_issued_packet_freed_comb.issued_to_cdb    | cdb_issue_selected;
        end
    end

    // when lq reserve, clear specific bit of lq_issued_data
    always_comb begin
        lq_issued_packet_reserved_comb = lq_issued_packet_updated_comb;
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            if(lq_reserve_packet.lq_reserve_entry[i].valid) begin
                lq_issued_packet_reserved_comb.issued_to_sq[tail_add[i]]      = 1'b0;
                lq_issued_packet_reserved_comb.issued_to_dcache[tail_add[i]]  = 1'b0;
                lq_issued_packet_reserved_comb.issued_to_cdb[tail_add[i]]     = 1'b0;
            end
        end
    end

    // when lq branch recovery, clear specific bit of lq_issued_data
    always_comb begin
        lq_issued_packet_branch_recovery_comb = lq_issued_packet_updated_comb;
        squash_index_issue = 0;
        for(integer unsigned i = 0; i < `LSQ_SIZE; i=i+1) begin
            squash_index_issue = branch_recovery_lq_tail + i;
            if(i < num_to_squash) begin
                lq_issued_packet_branch_recovery_comb.issued_to_sq[squash_index_issue]      = 1'b0;
                lq_issued_packet_branch_recovery_comb.issued_to_dcache[squash_index_issue]  = 1'b0;
                lq_issued_packet_branch_recovery_comb.issued_to_cdb[squash_index_issue]     = 1'b0;
            end
        end
    end

    assign lq_issued_packet_comb = branch_recovery ? lq_issued_packet_branch_recovery_comb : lq_issued_packet_reserved_comb;
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // generate the mask of entry in load queue which can be issued to sq ot dcache or cdb
    always_comb begin
        for(integer unsigned i = 0; i < `LSQ_SIZE; i=i+1) begin
            // if load instruction is ready to issue and has not been issued
            sq_to_issue[i]      = (lq_data[i].ready_to_search_sq ^ lq_issued_packet.issued_to_sq[i]) & lq_data[i].valid;
            cache_to_issue[i]   = (lq_data[i].forwarded ^ lq_data[i].complete) & (!lq_issued_packet.issued_to_dcache[i]) & lq_data[i].valid;
            cdb_to_issue[i]     = (lq_data[i].complete ^ lq_issued_packet.issued_to_cdb[i]) & lq_data[i].valid;
        end
    end

    ///////////////////////////////////////    issue logic     /////////////////////////////////////////////////
    // issue to sq
    psel_gen #(.REQS(3), .WIDTH(`LSQ_SIZE)) sq_issue_unit
    ( .req(sq_to_issue),
      .gnt(sq_issue_selected),
      .gnt_bus(sq_issue_selected_bus),
      .empty(sq_to_issue_empty)
    );
    pe #(.IN_WIDTH(`LSQ_SIZE)) ed_sq0 (.gnt(sq_issue_selected_bus[`LSQ_SIZE-1:0]), .enc(sq_issued_index[0]));
    pe #(.IN_WIDTH(`LSQ_SIZE)) ed_sq1 (.gnt(sq_issue_selected_bus[2*`LSQ_SIZE-1:`LSQ_SIZE]), .enc(sq_issued_index[1]));
    pe #(.IN_WIDTH(`LSQ_SIZE)) ed_sq2 (.gnt(sq_issue_selected_bus[3*`LSQ_SIZE-1:2*`LSQ_SIZE]), .enc(sq_issued_index[2]));
    assign sq_issued_valid[0] = |sq_issue_selected_bus[`LSQ_SIZE-1:0];
    assign sq_issued_valid[1] = |sq_issue_selected_bus[2*`LSQ_SIZE-1:`LSQ_SIZE];
    assign sq_issued_valid[2] = |sq_issue_selected_bus[3*`LSQ_SIZE-1:2*`LSQ_SIZE];
     

    // issue to d-cache
    psel_gen #(.REQS(3), .WIDTH(`LSQ_SIZE)) cache_issue_unit
    ( .req(cache_to_issue),
      .gnt(cache_issue_selected),
      .gnt_bus(cache_issue_selected_bus),
      .empty(cache_to_issue_empty)
    );
    pe #(.IN_WIDTH(`LSQ_SIZE)) ed_cache0 (.gnt(cache_issue_selected_bus[`LSQ_SIZE-1:0]), .enc(cache_issued_index[0]));
    pe #(.IN_WIDTH(`LSQ_SIZE)) ed_cache1 (.gnt(cache_issue_selected_bus[2*`LSQ_SIZE-1:`LSQ_SIZE]), .enc(cache_issued_index[1]));
    pe #(.IN_WIDTH(`LSQ_SIZE)) ed_cache2 (.gnt(cache_issue_selected_bus[3*`LSQ_SIZE-1:2*`LSQ_SIZE]), .enc(cache_issued_index[2]));
    assign cache_issued_valid[0] = |cache_issue_selected_bus[`LSQ_SIZE-1:0];
    assign cache_issued_valid[1] = |cache_issue_selected_bus[2*`LSQ_SIZE-1:`LSQ_SIZE];
    assign cache_issued_valid[2] = |cache_issue_selected_bus[3*`LSQ_SIZE-1:2*`LSQ_SIZE];

    // issue to cdb
    psel_gen #(.REQS(3), .WIDTH(`LSQ_SIZE)) cdb_issue_unit
    ( .req(cdb_to_issue),
      .gnt(cdb_issue_selected),
      .gnt_bus(cdb_issue_selected_bus),
      .empty(cdb_to_issue_empty)
    );
    pe #(.IN_WIDTH(`LSQ_SIZE)) ed_cdb0 (.gnt(cdb_issue_selected_bus[`LSQ_SIZE-1:0]), .enc(cdb_issued_index[0]));
    pe #(.IN_WIDTH(`LSQ_SIZE)) ed_cdb1 (.gnt(cdb_issue_selected_bus[2*`LSQ_SIZE-1:`LSQ_SIZE]), .enc(cdb_issued_index[1]));
    pe #(.IN_WIDTH(`LSQ_SIZE)) ed_cdb2 (.gnt(cdb_issue_selected_bus[3*`LSQ_SIZE-1:2*`LSQ_SIZE]), .enc(cdb_issued_index[2]));
    assign cdb_issued_valid[0] = |cdb_issue_selected_bus[`LSQ_SIZE-1:0];
    assign cdb_issued_valid[1] = |cdb_issue_selected_bus[2*`LSQ_SIZE-1:`LSQ_SIZE];
    assign cdb_issued_valid[2] = |cdb_issue_selected_bus[3*`LSQ_SIZE-1:2*`LSQ_SIZE];
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////


    generate
        genvar i;
        // get the data_offset of load entry when address has been obtained
        for(i = 0; i < 3; i = i+1) begin: generate_offset
            lq_get_offset lgo(.inst(lq_data[lq_address_packet[i].lq_idx].inst),.address(lq_address_packet[i].load_address),.offset(data_offset[i]));
        end

        //when new load is reserved in load queue, get the previous store of load in store queue
        for(i = 0; i < 3; i = i+1) begin: previous_store
            get_previous_store gps(.head(sq_head),.tail(lq_reserve_packet.sq_tail[i]),.previous_store_mask(previous_store_mask[i]));
        end

        for(i = 0 ; i < 3; i=i+1) begin: load_data_generate
            load_data_generator ldg(.input_data(lq_data[cdb_issued_index[i]].data), 
                                    .inst(lq_data[cdb_issued_index[i]].inst), 
                                    .offset(lq_data[cdb_issued_index[i]].data_offset),
                                    .cdb_data(cdb_data[i])
                                );
        end
    endgenerate

    //////////////////////////////////////////////// assign output ///////////////////////////////////////////
    generate
        genvar j;
        //the output packet to sq
        for(j = 0; j < 3; j=j+1) begin : generate_lq_to_sq_packet
            assign lq_to_sq_packet.lq_to_sq_entry[j].valid     = sq_issued_valid[j];
            assign lq_to_sq_packet.lq_to_sq_entry[j].address   = lq_data[sq_issued_index[j]].address;
            assign lq_to_sq_packet.lq_to_sq_entry[j].sq_tail   = lq_data[sq_issued_index[j]].sq_tail;
            assign lq_to_sq_packet.lq_to_sq_entry[j].lq_idx    = sq_issued_index[j];
            assign lq_to_sq_packet.lq_to_sq_entry[j].offset    = lq_data[sq_issued_index[j]].data_offset;
        end

        // the output packet to dcache
        for(j = 0; j < 3; j=j+1) begin : generate_lq_to_dcache_packet
            assign lq_to_cache_packet.lq_to_cache_entry[j].valid        = branch_recovery ? cache_issued_valid[j] & !(|(lq_data[cache_issued_index[j]].branch_mask & branch_stack)) : cache_issued_valid[j]; // the instruction which should be flushed under branch misprediction should not be sended to d-cache to avoid d-cache pollution
            assign lq_to_cache_packet.lq_to_cache_entry[j].address      = lq_data[cache_issued_index[j]].address;
            assign lq_to_cache_packet.lq_to_cache_entry[j].offset       = lq_data[cache_issued_index[j]].forward_data_offset;
            assign lq_to_cache_packet.lq_to_cache_entry[j].data         = lq_data[cache_issued_index[j]].data;
            assign lq_to_cache_packet.lq_to_cache_entry[j].branch_mask  = branch_correct ? lq_data[cache_issued_index[j]].branch_mask & ~branch_stack : lq_data[cache_issued_index[j]].branch_mask;
            assign lq_to_cache_packet.lq_to_cache_entry[j].lq_idx       = cache_issued_index[j];
            assign lq_to_cache_packet.lq_to_cache_entry[j].inst         = lq_data[cache_issued_index[j]].inst;
            assign lq_to_cache_packet.lq_to_cache_entry[j].PC           = lq_data[cache_issued_index[j]].PC;
        end

        // the output packet to cdb
        for(j = 0; j < 3; j=j+1) begin : generate_lq_to_cdb_packet
            assign lq_to_cdb_packet[j].valid            = branch_recovery ? cdb_issued_valid[j] & !(|(lq_data[cdb_issued_index[j]].branch_mask & branch_stack)) : cdb_issued_valid[j]; // the instruction which should be flushed under branch misprediction should not be sended to d-cache to avoid d-cache pollution
            assign lq_to_cdb_packet[j].preg_to_write    = lq_data[cdb_issued_index[j]].preg;
            assign lq_to_cdb_packet[j].lreg_to_write    = lq_data[cdb_issued_index[j]].inst.r.rd;
            assign lq_to_cdb_packet[j].preg_value       = cdb_data[j];
            assign lq_to_cdb_packet[j].rob_tail         = lq_data[cdb_issued_index[j]].rob_tail;
            assign lq_to_cdb_packet[j].is_wb_inst       = 1'b1;
            assign lq_to_cdb_packet[j].branch_mask      = branch_correct ? lq_data[cdb_issued_index[j]].branch_mask & ~branch_stack : lq_data[cdb_issued_index[j]].branch_mask;
        end
    endgenerate
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

endmodule


module lq_get_offset(
    input INST inst,
    input [`XLEN-1:0] address,
    output logic [3:0] offset
);
    logic [3:0] mask;
    always_comb begin
        case(address[1:0])
            2'b00 : mask = 4'b0001;
            2'b01 : mask = 4'b0010;
            2'b10 : mask = 4'b0100;
            2'b11 : mask = 4'b1000;
        endcase
    end

    always_comb begin
        case(inst.r.funct3[1:0])
             2'b0    : offset = mask;
             2'b1    : offset = address[1] ? 4'b1100 : 4'b0011;
             2'b10   : offset = 4'b1111;
             default : offset = mask;
        endcase
    end
endmodule


module get_previous_store(
    input logic[$clog2(`LSQ_SIZE):0] head,
    input logic[$clog2(`LSQ_SIZE):0] tail,
    output logic [`LSQ_SIZE-1:0] previous_store_mask
);
    logic [$clog2(`LSQ_SIZE):0] head_rl;
    logic [$clog2(`LSQ_SIZE):0] tail_rl;
    logic [$clog2(`LSQ_SIZE)-1:0] temp_index;
    logic [$clog2(`LSQ_SIZE):0] num_previous_store;

    assign head_rl = {1'b0,head[$clog2(`LSQ_SIZE)-1:0]};
    assign tail_rl = head[$clog2(`LSQ_SIZE)] == tail[$clog2(`LSQ_SIZE)] ? {1'b0,tail[$clog2(`LSQ_SIZE)-1:0]} : {1'b1,tail[$clog2(`LSQ_SIZE)-1:0]};

    assign num_previous_store = tail_rl - head_rl;

    always_comb begin
        temp_index = 0;
        previous_store_mask = 0;
        for(integer unsigned i = 0; i < `LSQ_SIZE; i=i+1) begin
            temp_index = head + i;
            if(i < num_previous_store) begin
                previous_store_mask[temp_index] = 1'b0;
            end
            else begin
                previous_store_mask[temp_index] = 1'b1;
            end
        end
    end
endmodule


module load_data_generator(
    input [`XLEN-1:0] input_data,
    input INST inst,
    input [3:0] offset,
    output logic [`XLEN-1:0] cdb_data
);

    logic is_unsigned_extend;
    logic [`XLEN-1:0] output_data;
    assign is_unsigned_extend = inst.r.funct3[2]; 
    assign cdb_data = output_data;

    always_comb begin
        output_data = 0;
        if (inst.r.funct3[1:0] == 2'b0) begin
            if(offset[0]) begin
                output_data = is_unsigned_extend ? {{(`XLEN-8){1'b0}}, input_data[7:0]} : {{(`XLEN-8){input_data[7]}}, input_data[7:0]};
            end
            else if(offset[1]) begin
                output_data = is_unsigned_extend ? {{(`XLEN-8){1'b0}}, input_data[15:8]} : {{(`XLEN-8){input_data[15]}}, input_data[15:8]};
            end
            else if(offset[2]) begin
                output_data = is_unsigned_extend ? {{(`XLEN-8){1'b0}}, input_data[23:16]} : {{(`XLEN-8){input_data[23]}}, input_data[23:16]};
            end
            else if(offset[3]) begin
                output_data = is_unsigned_extend ? {{(`XLEN-8){1'b0}}, input_data[31:24]} : {{(`XLEN-8){input_data[31]}}, input_data[31:24]};
            end
            else begin
                output_data = 0;
            end
            // for(integer unsigned i = 0; i < 4; i=i+1) begin
            //     if(offset[i]) 
            //         output_data = is_unsigned_extend ? {{(`XLEN-8){1'b0}}, input_data[8*(i+1)-1:8*i]} : {{(`XLEN-8){input_data[8*(i+1)-1]}}, input_data[8*(i+1)-1:8*i]};
            // end
        end
        else if (inst.r.funct3[1:0] == 2'b1) begin
            if(offset == 4'b0011)
                output_data = is_unsigned_extend ? {{(`XLEN-16){1'b0}}, input_data[15:0]} : {{(`XLEN-16){input_data[15]}}, input_data[15:0]};
            else 
                output_data = is_unsigned_extend ? {{(`XLEN-16){1'b0}}, input_data[31:16]} : {{(`XLEN-16){input_data[31]}}, input_data[31:16]};
        end
        else begin
            output_data = input_data;
        end
    end
 
endmodule
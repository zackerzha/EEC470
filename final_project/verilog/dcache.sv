`timescale 1ns/100ps

module dcache(
    input clock,
    input reset,

    input SQ_TO_CACHE_ENTRY sq_to_cache_packet,
    input LQ_TO_CACHE_PACKET lq_to_cache_packet,

    input branch_recovery,
    input branch_correct,
    input [`BRANCH_STACK_SIZE-1:0] branch_stack,

    input [3:0]  mem2proc_response,
    input [63:0] mem2proc_data,
    input [3:0]  mem2proc_tag,

    output logic store_write_ptr_move,
    output logic [`LSQ_SIZE-1:0] load_accepted_cache,
    output CACHE_TO_LQ_PACKET cache_to_lq_packet,
    output CACHE_TO_SQ_PACKET cache_to_sq_packet,

    // to memory, for dcache , BUS_LOAD , BUS WRITE or BUS_NONE
    output logic [1:0] dcache2mem_command,
    output logic [`XLEN-1:0] dcache2mem_addr,
    output logic [2*`XLEN-1:0] dcache2mem_data,
    
    output DCACHE_SET [`SET-1:0] cache_data_out
);
    // the load instruction sequence is the same as lq_to_cache_packet
    logic [2:0] cache_hit_load; // valid load which is cache hit, all cache hit load can be accept by dcache
    logic [`WAY-1:0] cache_hit_load_mask [2:0];
    logic [$clog2(`WAY)-1:0] cache_hit_load_idx [2:0]; // the index of hit cache line in cache set
    logic [2*`XLEN-1:0] cache_line_data_load [2:0];
    logic [2:0] cache_miss_load; // if load is valid and cache miss, cache_miss_load = 1
    logic [2:0] cache_miss_mshr_hit_load; //  valid load which is cache miss but hit in mshr
    // logic [2:0] cache_miss_mshr_hit_load_accepted; // the cache_miss_mshr_hit load instruction which is accepted by d-cache
    logic [2:0] cache_miss_mshr_miss_load_accepted;// the cache_miss_mshr_miss load instruction which is accepted by d-cache
    logic [`CACHE_SET_BITS-1:0] load_cache_set_idx [2:0]; // the index bit of three load isntruction from load queue
    logic [12 - `CACHE_SET_BITS:0] load_cache_tag [2:0]; // the tag bit of three load isntruction from load queue
    logic [2:0] hit_in_mshr_load; // valid load miss in d-cache but hit in mshr
    logic [`MSHR_SIZE-1:0] hit_in_mshr_load_mask [2:0];
    logic [$clog2(`MSHR_SIZE)-1:0] hit_in_mshr_load_idx [2:0];
    logic [2:0] memory_data_forward_valid;
    logic [2:0] missed_in_mshr_load; // load miss in d-cache and miss in mshr,which means that load should reserve an entry in mshr
    logic [`MSHR_SIZE-1:0] mshr_to_issue;
    logic [$clog2(`MSHR_SIZE)-1:0] mshr_issue_selected;
    logic [`MSHR_SIZE-1:0] mshr_available;
    logic [`MSHR_SIZE-1:0] mshr_available_load [2:0];
    logic [$clog2(`MSHR_SIZE)-1:0] mshr_entry_selected_load [2:0];
    logic [$clog2(`MSHR_SIZE)-1:0] mshr_entry_load0; // the real mshr entry which is choosen by cache miss and mshr miss load
    logic [$clog2(`MSHR_SIZE)-1:0] mshr_entry_load1;// because the load0 and load1 may share the same mshr entry
    logic [$clog2(`MSHR_SIZE)-1:0] mshr_entry_load2;
    logic [2:0] mshr_entry_selected_load_valid;
    logic [2:0] load_memory_address_matched;
    logic [`XLEN-1:0] data_to_lq_hit [2:0];
    logic [`XLEN-1:0] data_to_lq_miss [`LOAD_STORE_TABLE_SIZE-1:0];
    logic [2:0] load_accepted;// load instruction which accepted by d-cache in lq_to_cache_packet

    logic [`CACHE_SET_BITS-1:0] store_cache_set_idx; // the index bit of three load isntruction from store queue
    logic [12 - `CACHE_SET_BITS:0] store_cache_tag; // the tag bit of three load isntruction from store queue

    logic store_accepted_cache;
    logic [`WAY-1:0] cache_hit_store_mask;
    logic [$clog2(`WAY)-1:0] cache_hit_store_idx;
    logic cache_hit_store;
    logic cache_miss_store;
    logic hit_in_mshr_store;
    logic cache_miss_mshr_hit_store;
    logic memory_data_forward_store_valid;
    logic [`MSHR_SIZE-1:0] hit_in_mshr_store_mask;
    logic [$clog2(`MSHR_SIZE)-1:0] hit_in_mshr_store_idx;
    logic store_mshr_hit_accepted;
    logic missed_in_mshr_store;
    logic [`MSHR_SIZE-1:0] mshr_available_store;
    logic [$clog2(`MSHR_SIZE)-1:0]mshr_entry_selected_store;
    logic mshr_entry_selected_store_valid;
    logic reserve_new_mshr_entry_store_valid;


    MSHR_ENTRY [`MSHR_SIZE-1:0] mshr_data;
    MSHR_ENTRY [`MSHR_SIZE-1:0] mshr_data_freed_comb;
    MSHR_ENTRY [`MSHR_SIZE-1:0] mshr_data_issued_comb;
    MSHR_ENTRY [`MSHR_SIZE-1:0] mshr_data_load_comb;
    MSHR_ENTRY [`MSHR_SIZE-1:0] mshr_data_store_comb;
    MSHR_ENTRY [`MSHR_SIZE-1:0] mshr_data_branch_recovery_comb;
    MSHR_ENTRY [`MSHR_SIZE-1:0] mshr_data_comb;
    logic mshr_issue_valid;
    logic mshr_issue_stall; // if dcache is evicted, the BUS_STORE command is prior than BUS_LOAD
    logic [`MSHR_SIZE-1:0] mem_tag_matched_mshr;// represent which mshr entry has the same tag with the mem2proc_tag
    logic [$clog2(`MSHR_SIZE)-1:0] mem_tag_matched_mshr_idx;
    logic [`XLEN-1:0] mem_return_address; // the address of data which has been returned from memory
    logic mem_return_address_valid; // whether the mem_tag_matched_mshr_idx is a valid index, just checking whether there is no matched mshr entry

    LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array;
    LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array_mshr_hit_load0_comb; // load table updated when load0 hit in mshr
    LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array_mshr_hit_load1_comb;
    LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array_mshr_hit_load2_comb;
    LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array_mshr_miss_load0_comb; // load table updated when load0 miss in mshr
    LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array_mshr_miss_load1_comb;
    LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array_mshr_miss_load2_comb;
    LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array_free_comb;
    LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array_branch_correct_comb;
    LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array_comb;
    STORE_TABLE_PACKET[`MSHR_SIZE-1:0] store_table_array;
    STORE_TABLE_PACKET[`MSHR_SIZE-1:0] store_table_array_mshr_hit_comb;
    STORE_TABLE_PACKET[`MSHR_SIZE-1:0] store_table_array_mshr_miss_comb;
    STORE_TABLE_PACKET[`MSHR_SIZE-1:0] store_table_array_comb;

    //dcache data
    DCACHE_SET [`SET-1:0] cache_data;
    DCACHE_SET [`SET-1:0] cache_data_hit_comb;
    DCACHE_SET [`SET-1:0] cache_data_comb;
    logic [`SET-1:0][$clog2(`WAY)-1:0] lru;
    logic [`SET-1:0][$clog2(`WAY)-1:0] lru_comb;
    logic [2*`XLEN-1:0] cache_line_after_store_miss_array [`LOAD_STORE_TABLE_SIZE-1:0];
    logic [2*`XLEN-1:0] cache_line_after_store_miss;
    logic [2*`XLEN-1:0] cache_line_after_store_hit;
    logic [`WAY-1:0] cache_line_available [`SET-1:0];
    logic [$clog2(`WAY)-1:0] available_cache_line_selected;
    logic available_cache_line_valid;
    logic [`CACHE_SET_BITS-1:0] memory_data_to_cache_set_idx;
    logic [12-`CACHE_SET_BITS:0] memory_data_to_cache_set_tag;
    DCACHE_LINE evicted_cache_line;// the cache line to be evicted
    DCACHE_LINE evicted_cache_line_reg;
    logic [`XLEN-1:0] evicted_cache_line_address;
    logic [`XLEN-1:0] evicted_cache_line_address_reg;
    logic evicted_dirty_cache_line_valid;
    logic evicted_dirty_cache_line_valid_reg;
    // which represent whether the mshr entry which matched tag return by memory, has store insturction which is cache misss
    // if memory_data_mshr is 0 which means there is at least a store in mshr entry
    // and the cache line which should be set to dirty because there is at least on tore will modify cache line from memory
    logic memory_data_mshr_has_store;

    assign cache_data_out = cache_data;
    
    generate
        genvar l;
        //mshr which are ready to issue to memory
        for(l = 0; l < `MSHR_SIZE; l=l+1) begin: mshr_TO_issue
            assign mshr_to_issue[l] = mshr_data[l].valid & mshr_data[l].wait_to_issue;
        end

        for(l = 0; l < `MSHR_SIZE; l=l+1) begin: mshr_Available
            assign mshr_available[l] = ~mshr_data[l].valid;
        end

        //search for the mshr entry with tag the same with input "mem2proc_tag"
        for(l = 0 ; l < `MSHR_SIZE; l=l+1) begin
            assign mem_tag_matched_mshr[l] = (mem2proc_tag == mshr_data[l].mem2proc_tag) & (mem2proc_tag != 0) & mshr_data[l].valid;
        end
    endgenerate 
    
    // find which mshr entry has the matched mem2proc_tag
    pe #(.IN_WIDTH(`MSHR_SIZE)) encoder_mshr_idx(.gnt(mem_tag_matched_mshr) ,.enc(mem_tag_matched_mshr_idx));
    assign mem_return_address = mshr_data[mem_tag_matched_mshr_idx].address; // the address which has been return
    assign mem_return_address_valid = | mem_tag_matched_mshr;

    //////////////////////////////////////////////// for load instruction////////////////////////////////////////////////
    assign load_cache_set_idx[0] = lq_to_cache_packet.lq_to_cache_entry[0].address[3+`CACHE_SET_BITS-1:3];
    assign load_cache_set_idx[1] = lq_to_cache_packet.lq_to_cache_entry[1].address[3+`CACHE_SET_BITS-1:3];
    assign load_cache_set_idx[2] = lq_to_cache_packet.lq_to_cache_entry[2].address[3+`CACHE_SET_BITS-1:3];
    assign load_cache_tag[0] = lq_to_cache_packet.lq_to_cache_entry[0].address[`XLEN-1:3+`CACHE_SET_BITS];
    assign load_cache_tag[1] = lq_to_cache_packet.lq_to_cache_entry[1].address[`XLEN-1:3+`CACHE_SET_BITS];
    assign load_cache_tag[2] = lq_to_cache_packet.lq_to_cache_entry[2].address[`XLEN-1:3+`CACHE_SET_BITS];
    //1.for load instruction which is cache hit
    generate
        genvar j;
        genvar k;
        // for valid input load isntruction, are cache hit or cache miss
        for(j = 0 ; j  < 3; j=j+1) begin:load_inst
            for(k = 0; k < `WAY ; k=k+1) begin:cache_set_cam_load
                //if 1. tag match 2.load instruction is valid 3. cache line is valid
                assign cache_hit_load_mask[j][k] = (cache_data[load_cache_set_idx[j]].cache_line[k].tag == load_cache_tag[j]) & cache_data[load_cache_set_idx[j]].cache_line[k].valid & lq_to_cache_packet.lq_to_cache_entry[j].valid;
            end
            assign cache_hit_load[j]    = | cache_hit_load_mask[j];
            assign cache_miss_load[j]   = ~cache_hit_load[j] & lq_to_cache_packet.lq_to_cache_entry[j].valid;
            pe #(.IN_WIDTH(`WAY)) load_hit_encoders(.gnt(cache_hit_load_mask[j]), .enc(cache_hit_load_idx[j]));
        end

        for(j = 0; j < 3; j=j+1) begin:data_to_lq_generator_cache_hit
            assign cache_line_data_load[j] = memory_data_forward_valid[j] ? mem2proc_data : cache_data[load_cache_set_idx[j]].cache_line[cache_hit_load_idx[j]].data;
            data_to_lq_generator dlg(.cache_line_data(cache_line_data_load[j]), 
                                     .data_from_lq(lq_to_cache_packet.lq_to_cache_entry[j].data), 
                                     .address(lq_to_cache_packet.lq_to_cache_entry[j].address), 
                                     .load_offset(lq_to_cache_packet.lq_to_cache_entry[j].offset), 
                                     .data_to_lq(data_to_lq_hit[j])
                                    );
        end

        for(j = 0; j < `WAY; j=j+1) begin:data_to_lq_generator_cache_miss
            data_to_lq_generator dlg(.cache_line_data(mem2proc_data), // return data from memory to d-cache
                                     .data_from_lq(load_table_array[mem_tag_matched_mshr_idx].load_table[j].data), // data in load table
                                     .address(load_table_array[mem_tag_matched_mshr_idx].load_table[j].address), 
                                     .load_offset(load_table_array[mem_tag_matched_mshr_idx].load_table[j].offset), 
                                     .data_to_lq(data_to_lq_miss[j])
                                    );
        end
    endgenerate


    //2.for load inatruction which is cache miss but hit in mshr

    generate
        genvar i;
        // for load 0 hit in mshr or not
        for(i = 0; i < `MSHR_SIZE; i=i+1) begin : load_0
            assign hit_in_mshr_load_mask[0][i] = lq_to_cache_packet.lq_to_cache_entry[0].valid & mshr_data[i].valid 
                                            & (mshr_data[i].address == {lq_to_cache_packet.lq_to_cache_entry[0].address[`XLEN-1:3],{3{1'b0}}});
        end
        assign hit_in_mshr_load[0] = | hit_in_mshr_load_mask[0];
        pe #(.IN_WIDTH(`MSHR_SIZE)) mshr_hit_idx_load0 (.gnt(hit_in_mshr_load_mask[0]), .enc(hit_in_mshr_load_idx[0]));

        // for load 1 hit in mshr or not
        for(i = 0; i < `MSHR_SIZE; i=i+1) begin : load_1
            assign hit_in_mshr_load_mask[1][i] = lq_to_cache_packet.lq_to_cache_entry[1].valid & mshr_data[i].valid 
                                            & (mshr_data[i].address == {lq_to_cache_packet.lq_to_cache_entry[1].address[`XLEN-1:3],{3{1'b0}}});
        end
        assign hit_in_mshr_load[1] = | hit_in_mshr_load_mask[1];
        pe #(.IN_WIDTH(`MSHR_SIZE)) mshr_hit_idx_load1 (.gnt(hit_in_mshr_load_mask[1]), .enc(hit_in_mshr_load_idx[1]));

        // for load 2 hit in mshr or not
        for(i = 0; i < `MSHR_SIZE; i=i+1) begin : load_2
            assign hit_in_mshr_load_mask[2][i] = lq_to_cache_packet.lq_to_cache_entry[2].valid & mshr_data[i].valid 
                                            & (mshr_data[i].address == {lq_to_cache_packet.lq_to_cache_entry[2].address[`XLEN-1:3],{3{1'b0}}});
        end
        assign hit_in_mshr_load[2] = | hit_in_mshr_load_mask[2];
        pe #(.IN_WIDTH(`MSHR_SIZE)) mshr_hit_idx_load2 (.gnt(hit_in_mshr_load_mask[2]), .enc(hit_in_mshr_load_idx[2]));
    endgenerate

    assign cache_miss_mshr_hit_load[0] = hit_in_mshr_load[0] & cache_miss_load[0]; // if load instruction is valid and cache miss and hit in mshr
    assign cache_miss_mshr_hit_load[1] = hit_in_mshr_load[1] & cache_miss_load[1];
    assign cache_miss_mshr_hit_load[2] = hit_in_mshr_load[2] & cache_miss_load[2];

    // if load instruction is valid and the load public address is matched with the address of data which send from memory to d-cache in the same cycle
    assign load_memory_address_matched[0] = (lq_to_cache_packet.lq_to_cache_entry[0].address[`XLEN-1:3] == mem_return_address[`XLEN-1:3]) & lq_to_cache_packet.lq_to_cache_entry[0].valid & mem_return_address_valid; 
    assign load_memory_address_matched[1] = (lq_to_cache_packet.lq_to_cache_entry[1].address[`XLEN-1:3] == mem_return_address[`XLEN-1:3]) & lq_to_cache_packet.lq_to_cache_entry[1].valid & mem_return_address_valid;
    assign load_memory_address_matched[2] = (lq_to_cache_packet.lq_to_cache_entry[2].address[`XLEN-1:3] == mem_return_address[`XLEN-1:3]) & lq_to_cache_packet.lq_to_cache_entry[2].valid & mem_return_address_valid;

    // although these load miss in d-cache, but it can get the data in the same cycle and should be added to cache-hit-packet
    assign memory_data_forward_valid[0] = cache_miss_mshr_hit_load[0] & load_memory_address_matched[0]; // if memory_data_forward = 1 means that the load can be added to cache hit packet
    assign memory_data_forward_valid[1] = cache_miss_mshr_hit_load[1] & load_memory_address_matched[1];
    assign memory_data_forward_valid[2] = cache_miss_mshr_hit_load[2] & load_memory_address_matched[2];


    logic [2:0] reserve_load_table;
    logic [2:0] reserve_load_table_load0;
    logic [2:0] reserve_load_table_load1;
    logic [2:0] reserve_load_table_load2;
    //for load which need to reserve load store table
    // which means load instruction is cache_miss_mshr_hit_load and can not be forwarded from memory return data
    assign reserve_load_table = cache_miss_mshr_hit_load & ~memory_data_forward_valid;

    // update load table for cache miss but mshr hit load instruction which need to reserve load table entry
    always_comb begin
        load_table_array_mshr_hit_load0_comb = load_table_array;
        reserve_load_table_load0 = reserve_load_table;
        if(reserve_load_table[0]) begin
            if(load_table_array[hit_in_mshr_load_idx[0]].tail == `LOAD_STORE_TABLE_SIZE) begin
                // represent this load instruction can not be accepted by d-cache due to structural hazard of load table
                reserve_load_table_load0[0] = 1'b0;
            end
            else begin
                load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[0]].tail = load_table_array[hit_in_mshr_load_idx[0]].tail + 1;
                load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[0]].load_table[load_table_array[hit_in_mshr_load_idx[0]].tail].valid = 1'b1;
                load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[0]].load_table[load_table_array[hit_in_mshr_load_idx[0]].tail].address = lq_to_cache_packet.lq_to_cache_entry[0].address;
                load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[0]].load_table[load_table_array[hit_in_mshr_load_idx[0]].tail].offset = lq_to_cache_packet.lq_to_cache_entry[0].offset;
                load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[0]].load_table[load_table_array[hit_in_mshr_load_idx[0]].tail].data = lq_to_cache_packet.lq_to_cache_entry[0].data;
                load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[0]].load_table[load_table_array[hit_in_mshr_load_idx[0]].tail].branch_mask = lq_to_cache_packet.lq_to_cache_entry[0].branch_mask;
                load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[0]].load_table[load_table_array[hit_in_mshr_load_idx[0]].tail].lsq_idx = lq_to_cache_packet.lq_to_cache_entry[0].lq_idx;
                load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[0]].load_table[load_table_array[hit_in_mshr_load_idx[0]].tail].PC = lq_to_cache_packet.lq_to_cache_entry[0].PC;
            end
        end
    end

    always_comb begin
        load_table_array_mshr_hit_load1_comb = load_table_array_mshr_hit_load0_comb;
        reserve_load_table_load1 = reserve_load_table_load0;
        if(reserve_load_table_load0[1]) begin
            if(load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[1]].tail == `LOAD_STORE_TABLE_SIZE) begin
                // represent this load instruction can not be accepted by d-cache due to structural hazard of load table
                reserve_load_table_load1[1] = 1'b0;
            end
            else begin
                load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[1]].tail = load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[1]].tail + 1;
                load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[1]].load_table[load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[1]].tail].valid = 1'b1;
                load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[1]].load_table[load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[1]].tail].address = lq_to_cache_packet.lq_to_cache_entry[1].address;
                load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[1]].load_table[load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[1]].tail].offset = lq_to_cache_packet.lq_to_cache_entry[1].offset;
                load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[1]].load_table[load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[1]].tail].data = lq_to_cache_packet.lq_to_cache_entry[1].data;
                load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[1]].load_table[load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[1]].tail].branch_mask = lq_to_cache_packet.lq_to_cache_entry[1].branch_mask;
                load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[1]].load_table[load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[1]].tail].lsq_idx = lq_to_cache_packet.lq_to_cache_entry[1].lq_idx;
                load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[1]].load_table[load_table_array_mshr_hit_load0_comb[hit_in_mshr_load_idx[1]].tail].PC = lq_to_cache_packet.lq_to_cache_entry[1].PC;
            end
        end
    end

    always_comb begin
        load_table_array_mshr_hit_load2_comb = load_table_array_mshr_hit_load1_comb;
        reserve_load_table_load2 = reserve_load_table_load1;
        if(reserve_load_table_load1[2]) begin
            if(load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[2]].tail == `LOAD_STORE_TABLE_SIZE) begin
                // represent this load instruction can not be accepted by d-cache due to structural hazard of load table
                reserve_load_table_load2[2] = 1'b0;
            end
            else begin
                load_table_array_mshr_hit_load2_comb[hit_in_mshr_load_idx[2]].tail = load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[2]].tail + 1;
                load_table_array_mshr_hit_load2_comb[hit_in_mshr_load_idx[2]].load_table[load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[2]].tail].valid = 1'b1;
                load_table_array_mshr_hit_load2_comb[hit_in_mshr_load_idx[2]].load_table[load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[2]].tail].address = lq_to_cache_packet.lq_to_cache_entry[2].address;
                load_table_array_mshr_hit_load2_comb[hit_in_mshr_load_idx[2]].load_table[load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[2]].tail].offset = lq_to_cache_packet.lq_to_cache_entry[2].offset;
                load_table_array_mshr_hit_load2_comb[hit_in_mshr_load_idx[2]].load_table[load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[2]].tail].data = lq_to_cache_packet.lq_to_cache_entry[2].data;
                load_table_array_mshr_hit_load2_comb[hit_in_mshr_load_idx[2]].load_table[load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[2]].tail].branch_mask = lq_to_cache_packet.lq_to_cache_entry[2].branch_mask;
                load_table_array_mshr_hit_load2_comb[hit_in_mshr_load_idx[2]].load_table[load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[2]].tail].lsq_idx = lq_to_cache_packet.lq_to_cache_entry[2].lq_idx;
                load_table_array_mshr_hit_load2_comb[hit_in_mshr_load_idx[2]].load_table[load_table_array_mshr_hit_load1_comb[hit_in_mshr_load_idx[2]].tail].PC = lq_to_cache_packet.lq_to_cache_entry[2].PC;
            end
        end
    end
    

    //3,for load instruction which is cache miss and miss in mshr
    priority_encoder #(.IN_WIDTH(`MSHR_SIZE)) mshr_selector_load0 (.req(mshr_available_load[0]), .enc(mshr_entry_selected_load[0]));
    priority_encoder #(.IN_WIDTH(`MSHR_SIZE)) mshr_selector_load1 (.req(mshr_available_load[1]), .enc(mshr_entry_selected_load[1]));
    priority_encoder #(.IN_WIDTH(`MSHR_SIZE)) mshr_selector_load2 (.req(mshr_available_load[2]), .enc(mshr_entry_selected_load[2]));

    // if valid cache miss load which need to reserve an entry in mshr, misssed_in_mshr_load = 1
    assign missed_in_mshr_load[0] = cache_miss_load[0] & ~hit_in_mshr_load[0];
    assign missed_in_mshr_load[1] = cache_miss_load[1] & ~hit_in_mshr_load[1] 
                                    & ((lq_to_cache_packet.lq_to_cache_entry[0].address[`XLEN-1:3] != lq_to_cache_packet.lq_to_cache_entry[1].address[`XLEN-1:3]) | ~lq_to_cache_packet.lq_to_cache_entry[0].valid);
    assign missed_in_mshr_load[2] = cache_miss_load[2] & ~hit_in_mshr_load[2]
                                    & ((lq_to_cache_packet.lq_to_cache_entry[0].address[`XLEN-1:3] != lq_to_cache_packet.lq_to_cache_entry[2].address[`XLEN-1:3]) | ~lq_to_cache_packet.lq_to_cache_entry[0].valid)
                                    & ((lq_to_cache_packet.lq_to_cache_entry[1].address[`XLEN-1:3] != lq_to_cache_packet.lq_to_cache_entry[2].address[`XLEN-1:3]) | ~lq_to_cache_packet.lq_to_cache_entry[1].valid);

    assign mshr_available_load[0] = mshr_available;
    assign mshr_available_load[1] = missed_in_mshr_load[0] ? mshr_available_load[0] & ~(1'b1<<mshr_entry_selected_load[0]) : mshr_available_load[0];
    assign mshr_available_load[2] = missed_in_mshr_load[1] ? mshr_available_load[1] & ~(1'b1<<mshr_entry_selected_load[1]) : mshr_available_load[1];

    // whether the priority selector can select a valid mshr entry for valid cache miss load which need to reserve an new entry in mshr
    assign mshr_entry_selected_load_valid[0] = | mshr_available_load[0];
    assign mshr_entry_selected_load_valid[1] = | mshr_available_load[1];
    assign mshr_entry_selected_load_valid[2] = | mshr_available_load[2];

    logic [2:0] reserve_new_mshr_entry_load_valid;
    assign reserve_new_mshr_entry_load_valid[0] = missed_in_mshr_load[0] &  mshr_entry_selected_load_valid[0];
    assign reserve_new_mshr_entry_load_valid[1] = missed_in_mshr_load[1] &  mshr_entry_selected_load_valid[1];
    assign reserve_new_mshr_entry_load_valid[2] = missed_in_mshr_load[2] &  mshr_entry_selected_load_valid[2];

    logic [2:0] share_new_mshr_entry_load_valid;
    assign share_new_mshr_entry_load_valid[0] = 1'b0;
    assign share_new_mshr_entry_load_valid[1] = (lq_to_cache_packet.lq_to_cache_entry[0].address[`XLEN-1:3] == lq_to_cache_packet.lq_to_cache_entry[1].address[`XLEN-1:3]) & reserve_new_mshr_entry_load_valid[0] & lq_to_cache_packet.lq_to_cache_entry[1].valid;
    assign share_new_mshr_entry_load_valid[2] = (lq_to_cache_packet.lq_to_cache_entry[0].address[`XLEN-1:3] == lq_to_cache_packet.lq_to_cache_entry[2].address[`XLEN-1:3]) & reserve_new_mshr_entry_load_valid[0] & lq_to_cache_packet.lq_to_cache_entry[2].valid
                                                | (lq_to_cache_packet.lq_to_cache_entry[1].address[`XLEN-1:3] == lq_to_cache_packet.lq_to_cache_entry[2].address[`XLEN-1:3]) & reserve_new_mshr_entry_load_valid[1] & lq_to_cache_packet.lq_to_cache_entry[2].valid;


    // represent the valid load instruction which is miss in cache and miss in mshr and be accept by dcache (consider mshr strutural hazard)
    assign cache_miss_mshr_miss_load_accepted[0] = reserve_new_mshr_entry_load_valid[0] | share_new_mshr_entry_load_valid[0];
    assign cache_miss_mshr_miss_load_accepted[1] = reserve_new_mshr_entry_load_valid[1] | share_new_mshr_entry_load_valid[1];
    assign cache_miss_mshr_miss_load_accepted[2] = reserve_new_mshr_entry_load_valid[2] | share_new_mshr_entry_load_valid[2];

    always_comb begin
        // for load0, get whether load0 should be accepted by d-cache
        mshr_entry_load0 = mshr_entry_selected_load[0];

        // for load1, get whether load1 should be accepted by d-cache
        if(reserve_new_mshr_entry_load_valid[1]) begin
            mshr_entry_load1 = mshr_entry_selected_load[1];
        end
        else if((lq_to_cache_packet.lq_to_cache_entry[0].address[`XLEN-1:3] == lq_to_cache_packet.lq_to_cache_entry[1].address[`XLEN-1:3]) & reserve_new_mshr_entry_load_valid[0]) begin
            mshr_entry_load1 = mshr_entry_selected_load[0];
        end
        else begin
            mshr_entry_load1 = 0;
        end
        
        // for load2, get whether load2 should be accepted by d-cache
        if(reserve_new_mshr_entry_load_valid[2]) begin
            mshr_entry_load2 = mshr_entry_selected_load[2];
        end
        else if((lq_to_cache_packet.lq_to_cache_entry[0].address[`XLEN-1:3] == lq_to_cache_packet.lq_to_cache_entry[2].address[`XLEN-1:3]) & reserve_new_mshr_entry_load_valid[0]) begin
            mshr_entry_load2 = mshr_entry_selected_load[0];
        end
        else if((lq_to_cache_packet.lq_to_cache_entry[1].address[`XLEN-1:3] == lq_to_cache_packet.lq_to_cache_entry[2].address[`XLEN-1:3]) & reserve_new_mshr_entry_load_valid[1]) begin
            mshr_entry_load2 = mshr_entry_selected_load[1];
        end
        else begin
            mshr_entry_load2 = 0;
        end
    end


    // update load table for cache miss and mshr miss
    always_comb begin
        load_table_array_mshr_miss_load0_comb = load_table_array_mshr_hit_load2_comb;
        if(cache_miss_mshr_miss_load_accepted[0]) begin
            load_table_array_mshr_miss_load0_comb[mshr_entry_load0].tail = load_table_array_mshr_hit_load2_comb[mshr_entry_load0].tail + 1;
            load_table_array_mshr_miss_load0_comb[mshr_entry_load0].load_table[load_table_array_mshr_hit_load2_comb[mshr_entry_load0].tail].valid = 1'b1;
            load_table_array_mshr_miss_load0_comb[mshr_entry_load0].load_table[load_table_array_mshr_hit_load2_comb[mshr_entry_load0].tail].address = lq_to_cache_packet.lq_to_cache_entry[0].address;
            load_table_array_mshr_miss_load0_comb[mshr_entry_load0].load_table[load_table_array_mshr_hit_load2_comb[mshr_entry_load0].tail].offset = lq_to_cache_packet.lq_to_cache_entry[0].offset;
            load_table_array_mshr_miss_load0_comb[mshr_entry_load0].load_table[load_table_array_mshr_hit_load2_comb[mshr_entry_load0].tail].data = lq_to_cache_packet.lq_to_cache_entry[0].data;
            load_table_array_mshr_miss_load0_comb[mshr_entry_load0].load_table[load_table_array_mshr_hit_load2_comb[mshr_entry_load0].tail].branch_mask = lq_to_cache_packet.lq_to_cache_entry[0].branch_mask;
            load_table_array_mshr_miss_load0_comb[mshr_entry_load0].load_table[load_table_array_mshr_hit_load2_comb[mshr_entry_load0].tail].lsq_idx = lq_to_cache_packet.lq_to_cache_entry[0].lq_idx;
            load_table_array_mshr_miss_load0_comb[mshr_entry_load0].load_table[load_table_array_mshr_hit_load2_comb[mshr_entry_load0].tail].PC = lq_to_cache_packet.lq_to_cache_entry[0].PC;
        end
    end

    always_comb begin
        load_table_array_mshr_miss_load1_comb = load_table_array_mshr_miss_load0_comb;
        if(cache_miss_mshr_miss_load_accepted[1]) begin
            load_table_array_mshr_miss_load1_comb[mshr_entry_load1].tail = load_table_array_mshr_miss_load0_comb[mshr_entry_load1].tail + 1;
            load_table_array_mshr_miss_load1_comb[mshr_entry_load1].load_table[load_table_array_mshr_miss_load0_comb[mshr_entry_load1].tail].valid = 1'b1;
            load_table_array_mshr_miss_load1_comb[mshr_entry_load1].load_table[load_table_array_mshr_miss_load0_comb[mshr_entry_load1].tail].address = lq_to_cache_packet.lq_to_cache_entry[1].address;
            load_table_array_mshr_miss_load1_comb[mshr_entry_load1].load_table[load_table_array_mshr_miss_load0_comb[mshr_entry_load1].tail].offset = lq_to_cache_packet.lq_to_cache_entry[1].offset;
            load_table_array_mshr_miss_load1_comb[mshr_entry_load1].load_table[load_table_array_mshr_miss_load0_comb[mshr_entry_load1].tail].data = lq_to_cache_packet.lq_to_cache_entry[1].data;
            load_table_array_mshr_miss_load1_comb[mshr_entry_load1].load_table[load_table_array_mshr_miss_load0_comb[mshr_entry_load1].tail].branch_mask = lq_to_cache_packet.lq_to_cache_entry[1].branch_mask;
            load_table_array_mshr_miss_load1_comb[mshr_entry_load1].load_table[load_table_array_mshr_miss_load0_comb[mshr_entry_load1].tail].lsq_idx = lq_to_cache_packet.lq_to_cache_entry[1].lq_idx;
            load_table_array_mshr_miss_load1_comb[mshr_entry_load1].load_table[load_table_array_mshr_miss_load0_comb[mshr_entry_load1].tail].PC = lq_to_cache_packet.lq_to_cache_entry[1].PC;
        end
    end

    always_comb begin
        load_table_array_mshr_miss_load2_comb = load_table_array_mshr_miss_load1_comb;
        if(cache_miss_mshr_miss_load_accepted[2]) begin
            load_table_array_mshr_miss_load2_comb[mshr_entry_load2].tail = load_table_array_mshr_miss_load1_comb[mshr_entry_load2].tail + 1;
            load_table_array_mshr_miss_load2_comb[mshr_entry_load2].load_table[load_table_array_mshr_miss_load1_comb[mshr_entry_load2].tail].valid = 1'b1;
            load_table_array_mshr_miss_load2_comb[mshr_entry_load2].load_table[load_table_array_mshr_miss_load1_comb[mshr_entry_load2].tail].address = lq_to_cache_packet.lq_to_cache_entry[2].address;
            load_table_array_mshr_miss_load2_comb[mshr_entry_load2].load_table[load_table_array_mshr_miss_load1_comb[mshr_entry_load2].tail].offset = lq_to_cache_packet.lq_to_cache_entry[2].offset;
            load_table_array_mshr_miss_load2_comb[mshr_entry_load2].load_table[load_table_array_mshr_miss_load1_comb[mshr_entry_load2].tail].data = lq_to_cache_packet.lq_to_cache_entry[2].data;
            load_table_array_mshr_miss_load2_comb[mshr_entry_load2].load_table[load_table_array_mshr_miss_load1_comb[mshr_entry_load2].tail].branch_mask = lq_to_cache_packet.lq_to_cache_entry[2].branch_mask;
            load_table_array_mshr_miss_load2_comb[mshr_entry_load2].load_table[load_table_array_mshr_miss_load1_comb[mshr_entry_load2].tail].lsq_idx = lq_to_cache_packet.lq_to_cache_entry[2].lq_idx;
            load_table_array_mshr_miss_load2_comb[mshr_entry_load2].load_table[load_table_array_mshr_miss_load1_comb[mshr_entry_load2].tail].PC = lq_to_cache_packet.lq_to_cache_entry[2].PC;
        end
    end

    // free load table if data has been returned from memory
    always_comb begin
        load_table_array_free_comb = load_table_array_mshr_miss_load2_comb;
        if(mem_return_address_valid) begin
            load_table_array_free_comb[mem_tag_matched_mshr_idx] = '0;
        end
    end

    always_comb begin
        load_table_array_branch_correct_comb = load_table_array_free_comb;
        if(branch_correct) begin
            for(integer unsigned i = 0; i < `MSHR_SIZE; i=i+1) begin
                for(integer unsigned j = 0; j < `LOAD_STORE_TABLE_SIZE; j=j+1) begin
                    if(load_table_array_free_comb[i].load_table[j].valid) begin
                        load_table_array_branch_correct_comb[i].load_table[j].branch_mask = load_table_array_free_comb[i].load_table[j].branch_mask & ~branch_stack;
                    end
                end
            end
        end
    end

    // update load table after branch recovery, if no branch recovery, keep load_table_array_comb = load_table_array_free_comb
    generate
        genvar c;
        for(c = 0 ; c < `MSHR_SIZE ; c=c+1) begin
            branch_recovery_load_table_generator BRLTG(
                .load_table(load_table_array_branch_correct_comb[c]),
                .branch_recovery(branch_recovery),
                .branch_stack(branch_stack),
                .load_table_out(load_table_array_comb[c])
            );
        end
    endgenerate
    
    


    // tell lq the instructions that are accepted by d-cache // 
    assign load_accepted = cache_hit_load | memory_data_forward_valid | reserve_load_table_load2 | cache_miss_mshr_miss_load_accepted;
    always_comb begin
        load_accepted_cache = '0;
        if(load_accepted[0]) begin
            load_accepted_cache[lq_to_cache_packet.lq_to_cache_entry[0].lq_idx] = 1'b1;
        end
        if(load_accepted[1]) begin
            load_accepted_cache[lq_to_cache_packet.lq_to_cache_entry[1].lq_idx] = 1'b1;
        end
        if(load_accepted[2]) begin
            load_accepted_cache[lq_to_cache_packet.lq_to_cache_entry[2].lq_idx] = 1'b1;
        end
    end

    assign cache_to_lq_packet.cache_hit_packet[0].valid    =  cache_hit_load[0] | memory_data_forward_valid[0]; // 1. cache hit 2. cache miss but will cache hit in the next cycle, forwarding
    assign cache_to_lq_packet.cache_hit_packet[0].lq_idx   =  lq_to_cache_packet.lq_to_cache_entry[0].lq_idx;
    assign cache_to_lq_packet.cache_hit_packet[0].data     =  data_to_lq_hit[0];
    assign cache_to_lq_packet.cache_hit_packet[1].valid    =  cache_hit_load[1] | memory_data_forward_valid[1]; // 1. cache hit 2. cache miss but will cache hit in the next cycle, forwarding
    assign cache_to_lq_packet.cache_hit_packet[1].lq_idx   =  lq_to_cache_packet.lq_to_cache_entry[1].lq_idx;
    assign cache_to_lq_packet.cache_hit_packet[1].data     =  data_to_lq_hit[1];
    assign cache_to_lq_packet.cache_hit_packet[2].valid    =  cache_hit_load[2] | memory_data_forward_valid[2]; // 1. cache hit 2. cache miss but will cache hit in the next cycle, forwarding
    assign cache_to_lq_packet.cache_hit_packet[2].lq_idx   =  lq_to_cache_packet.lq_to_cache_entry[2].lq_idx;
    assign cache_to_lq_packet.cache_hit_packet[2].data     =  data_to_lq_hit[2];

    assign cache_to_lq_packet.cache_miss_packet[0].valid    =  !mem_return_address_valid? 0: load_table_array[mem_tag_matched_mshr_idx].load_table[0].valid;
    assign cache_to_lq_packet.cache_miss_packet[0].lq_idx   =  !mem_return_address_valid? 0: load_table_array[mem_tag_matched_mshr_idx].load_table[0].lsq_idx;
    assign cache_to_lq_packet.cache_miss_packet[0].data     =  !mem_return_address_valid? 0: data_to_lq_miss[0];

    assign cache_to_lq_packet.cache_miss_packet[1].valid    =  !mem_return_address_valid? 0: load_table_array[mem_tag_matched_mshr_idx].load_table[1].valid;
    assign cache_to_lq_packet.cache_miss_packet[1].lq_idx   =  !mem_return_address_valid? 0: load_table_array[mem_tag_matched_mshr_idx].load_table[1].lsq_idx;
    assign cache_to_lq_packet.cache_miss_packet[1].data     =  !mem_return_address_valid? 0: data_to_lq_miss[1];

    assign cache_to_lq_packet.cache_miss_packet[2].valid    =  !mem_return_address_valid? 0: load_table_array[mem_tag_matched_mshr_idx].load_table[2].valid;
    assign cache_to_lq_packet.cache_miss_packet[2].lq_idx   =  !mem_return_address_valid? 0: load_table_array[mem_tag_matched_mshr_idx].load_table[2].lsq_idx;
    assign cache_to_lq_packet.cache_miss_packet[2].data     =  !mem_return_address_valid? 0: data_to_lq_miss[2];

    assign cache_to_lq_packet.cache_miss_packet[3].valid    =  !mem_return_address_valid? 0: load_table_array[mem_tag_matched_mshr_idx].load_table[3].valid;
    assign cache_to_lq_packet.cache_miss_packet[3].lq_idx   =  !mem_return_address_valid? 0: load_table_array[mem_tag_matched_mshr_idx].load_table[3].lsq_idx;
    assign cache_to_lq_packet.cache_miss_packet[3].data     =  !mem_return_address_valid? 0: data_to_lq_miss[3];
    
    // CACHE_TO_LQ_ENTRY [`LOAD_STORE_TABLE_SIZE-1:0] cache_miss_packet;
    // update cache to load packet // 
    // load cache hit packet come from two part 1. the load has cache hit 2. the load has cache miss but hit in mshr; and in the same cycle memory has return the missed data to d-cache
    /*
    always_comb begin
        cache_miss_packet = 0;
        // for(integer unsigned i = 0 ; i < 3; i=i+1) begin
        //     cache_to_lq_packet.cache_hit_packet[i].valid    =  cache_hit_load[i] | memory_data_forward_valid[i]; // 1. cache hit 2. cache miss but will cache hit in the next cycle, forwarding
        //     cache_to_lq_packet.cache_hit_packet[i].lq_idx   =  lq_to_cache_packet.lq_to_cache_entry[i].lq_idx;
        //     cache_to_lq_packet.cache_hit_packet[i].data     =  data_to_lq_hit[i];
        // end
        // cache_to_lq_packet.cache_hit_packet[0].valid    =  cache_hit_load[0] | memory_data_forward_valid[0]; // 1. cache hit 2. cache miss but will cache hit in the next cycle, forwarding
        // cache_to_lq_packet.cache_hit_packet[0].lq_idx   =  lq_to_cache_packet.lq_to_cache_entry[0].lq_idx;
        // cache_to_lq_packet.cache_hit_packet[0].data     =  data_to_lq_hit[0];
        // cache_to_lq_packet.cache_hit_packet[1].valid    =  cache_hit_load[1] | memory_data_forward_valid[1]; // 1. cache hit 2. cache miss but will cache hit in the next cycle, forwarding
        // cache_to_lq_packet.cache_hit_packet[1].lq_idx   =  lq_to_cache_packet.lq_to_cache_entry[1].lq_idx;
        // cache_to_lq_packet.cache_hit_packet[1].data     =  data_to_lq_hit[1];
        // cache_to_lq_packet.cache_hit_packet[2].valid    =  cache_hit_load[2] | memory_data_forward_valid[2]; // 1. cache hit 2. cache miss but will cache hit in the next cycle, forwarding
        // cache_to_lq_packet.cache_hit_packet[2].lq_idx   =  lq_to_cache_packet.lq_to_cache_entry[2].lq_idx;
        // cache_to_lq_packet.cache_hit_packet[2].data     =  data_to_lq_hit[2];
        if(mem_return_address_valid) begin
            for(integer unsigned i = 0 ; i < `MSHR_SIZE; i=i+1) begin
                cache_miss_packet[i].valid    =  load_table_array[mem_tag_matched_mshr_idx].load_table[i].valid; // 1. cache hit 2. cache miss but will cache hit in the next cycle, forwarding
                cache_miss_packet[i].lq_idx   =  load_table_array[mem_tag_matched_mshr_idx].load_table[i].lsq_idx;
                cache_miss_packet[i].data     =  data_to_lq_miss[i];
            end
        end
    end
    */
    // assign cache_to_lq_packet.cache_miss_packet = cache_miss_packet;
    // load cache miss packet 
    // always_comb begin
    //     cache_to_lq_packet.cache_miss_packet = '0;
    //     if(mem_return_address_valid) begin
    //         for(integer unsigned i = 0 ; i < `MSHR_SIZE; i=i+1) begin
    //             cache_to_lq_packet.cache_miss_packet[i].valid    =  load_table_array[mem_tag_matched_mshr_idx].load_table[i].valid; // 1. cache hit 2. cache miss but will cache hit in the next cycle, forwarding
    //             cache_to_lq_packet.cache_miss_packet[i].lq_idx   =  load_table_array[mem_tag_matched_mshr_idx].load_table[i].lsq_idx;
    //             cache_to_lq_packet.cache_miss_packet[i].data     =  data_to_lq_miss[i];
    //         end
    //     end
    // end

    //////////////////////////////////////////////// for store instruction ////////////////////////////////////////////////
    assign store_cache_set_idx = sq_to_cache_packet.address[3+`CACHE_SET_BITS-1:3];
    assign store_cache_tag = sq_to_cache_packet.address[`XLEN-1:3+`CACHE_SET_BITS];

    //1. store hit in cache
    generate
        genvar m;
        for(m = 0; m < `WAY ; m=m+1) begin:cache_set_cam_store
            //if 1. tag match 2.load instruction is valid 3. cache line is valid
            assign cache_hit_store_mask[m] = (cache_data[store_cache_set_idx].cache_line[m].tag == store_cache_tag) & cache_data[store_cache_set_idx].cache_line[m].valid & sq_to_cache_packet.valid;
        end
        assign cache_hit_store    = | cache_hit_store_mask;
        assign cache_miss_store   = ~cache_hit_store & sq_to_cache_packet.valid;
        pe #(.IN_WIDTH(`WAY)) store_hit_encoder(.gnt(cache_hit_store_mask), .enc(cache_hit_store_idx));
    endgenerate

    // for store, if cache hit or memory_data_forward_store_valid, write data to 

    //2. store miss in cache but hit in mshr
    // when judgeing whether store is hit in mshr entry, store address has to search in mshr_data(before mshr free)
    wor hit_in_mshr_store_before_free;
    generate 
        genvar n;
        for(n = 0; n < `MSHR_SIZE; n=n+1) begin:store_mshr_hit
            assign hit_in_mshr_store_mask[n] = sq_to_cache_packet.valid & mshr_data_load_comb[n].valid  & (mshr_data_load_comb[n].address == {sq_to_cache_packet.address[`XLEN-1:3],3'b0});
        end
        for(n = 0; n < `MSHR_SIZE; n=n+1) begin:Hit_in_mshr_store_before_free
            assign hit_in_mshr_store_before_free = sq_to_cache_packet.valid & mshr_data[n].valid  & (mshr_data[n].address == {sq_to_cache_packet.address[`XLEN-1:3],3'b0});
        end
        assign hit_in_mshr_store = | hit_in_mshr_store_mask;
        pe #(.IN_WIDTH(`MSHR_SIZE)) mshr_hit_idx_store (.gnt(hit_in_mshr_store_mask), .enc(hit_in_mshr_store_idx));
    endgenerate
    
    assign cache_miss_mshr_hit_store = hit_in_mshr_store & cache_miss_store; 
    assign memory_data_forward_store_valid = hit_in_mshr_store_before_free  & cache_miss_store & (sq_to_cache_packet.address[`XLEN-1:3] == mem_return_address[`XLEN-1:3]) & sq_to_cache_packet.valid & mem_return_address_valid;

    always_comb begin
        store_table_array_mshr_hit_comb = store_table_array;
        store_mshr_hit_accepted = cache_miss_mshr_hit_store & ~memory_data_forward_store_valid;
        if(cache_miss_mshr_hit_store & ~memory_data_forward_store_valid) begin // which means need to reserve a new entry in store table
            if(store_table_array[hit_in_mshr_store_idx].tail == `LOAD_STORE_TABLE_SIZE) begin
                store_mshr_hit_accepted = 1'b0;
            end
            else begin
                store_table_array_mshr_hit_comb[hit_in_mshr_store_idx].tail = store_table_array[hit_in_mshr_store_idx].tail + 1;
                store_table_array_mshr_hit_comb[hit_in_mshr_store_idx].store_table[store_table_array[hit_in_mshr_store_idx].tail].valid = 1'b1;
                store_table_array_mshr_hit_comb[hit_in_mshr_store_idx].store_table[store_table_array[hit_in_mshr_store_idx].tail].address = sq_to_cache_packet.address;
                store_table_array_mshr_hit_comb[hit_in_mshr_store_idx].store_table[store_table_array[hit_in_mshr_store_idx].tail].offset = sq_to_cache_packet.offset;
                store_table_array_mshr_hit_comb[hit_in_mshr_store_idx].store_table[store_table_array[hit_in_mshr_store_idx].tail].data = sq_to_cache_packet.data;
                store_table_array_mshr_hit_comb[hit_in_mshr_store_idx].store_table[store_table_array[hit_in_mshr_store_idx].tail].branch_mask = sq_to_cache_packet.branch_mask;
                store_table_array_mshr_hit_comb[hit_in_mshr_store_idx].store_table[store_table_array[hit_in_mshr_store_idx].tail].lsq_idx = sq_to_cache_packet.sq_idx;
                store_table_array_mshr_hit_comb[hit_in_mshr_store_idx].store_table[store_table_array[hit_in_mshr_store_idx].tail].PC = sq_to_cache_packet.PC;
            end
        end
    end

    //3. store miss in cahce but miss in mshr
    
    priority_encoder #(.IN_WIDTH(`MSHR_SIZE)) mshr_selector_store (.req(mshr_available_store), .enc(mshr_entry_selected_store));
    assign missed_in_mshr_store = cache_miss_store & ~hit_in_mshr_store & !memory_data_forward_store_valid;
    assign mshr_available_store = missed_in_mshr_load[2] ? mshr_available_load[2] & ~(1'b1<<mshr_entry_selected_load[2]) : mshr_available_load[2];
    assign mshr_entry_selected_store_valid = | mshr_available_store;
    assign reserve_new_mshr_entry_store_valid = missed_in_mshr_store & mshr_entry_selected_store_valid; //store need to reserve a new entry in mshr 

    always_comb begin
        store_table_array_mshr_miss_comb = store_table_array_mshr_hit_comb;
        if(reserve_new_mshr_entry_store_valid) begin
            store_table_array_mshr_miss_comb[mshr_entry_selected_store].tail = store_table_array_mshr_hit_comb[mshr_entry_selected_store].tail + 1;
            store_table_array_mshr_miss_comb[mshr_entry_selected_store].store_table[store_table_array_mshr_hit_comb[mshr_entry_selected_store].tail].valid = 1'b1;
            store_table_array_mshr_miss_comb[mshr_entry_selected_store].store_table[store_table_array_mshr_hit_comb[mshr_entry_selected_store].tail].address = sq_to_cache_packet.address;
            store_table_array_mshr_miss_comb[mshr_entry_selected_store].store_table[store_table_array_mshr_hit_comb[mshr_entry_selected_store].tail].offset = sq_to_cache_packet.offset;
            store_table_array_mshr_miss_comb[mshr_entry_selected_store].store_table[store_table_array_mshr_hit_comb[mshr_entry_selected_store].tail].data = sq_to_cache_packet.data;
            store_table_array_mshr_miss_comb[mshr_entry_selected_store].store_table[store_table_array_mshr_hit_comb[mshr_entry_selected_store].tail].branch_mask = sq_to_cache_packet.branch_mask;
            store_table_array_mshr_miss_comb[mshr_entry_selected_store].store_table[store_table_array_mshr_hit_comb[mshr_entry_selected_store].tail].lsq_idx = sq_to_cache_packet.sq_idx;
            store_table_array_mshr_miss_comb[mshr_entry_selected_store].store_table[store_table_array_mshr_hit_comb[mshr_entry_selected_store].tail].PC = sq_to_cache_packet.PC;
        end
    end

    // free store table
    always_comb begin
        store_table_array_comb = store_table_array_mshr_miss_comb;
        if(mem_return_address_valid) begin
            store_table_array_comb[mem_tag_matched_mshr_idx] = '0;
        end
    end

    // generate the cache to sq packet
    // for cache hit packet
    // assign cache_to_sq_packet.cache_hit_packet.valid = cache_hit_store | memory_data_forward_store_valid;
    // assign cache_to_sq_packet.cache_hit_packet.sq_idx = sq_to_cache_packet.sq_idx;
    // for cache miss packet
    always_comb begin
        cache_to_sq_packet = '0;
        cache_to_sq_packet.cache_hit_packet.valid = cache_hit_store | memory_data_forward_store_valid;
        cache_to_sq_packet.cache_hit_packet.sq_idx = sq_to_cache_packet.sq_idx;
        if(mem_return_address_valid) begin
            for(integer unsigned i = 0 ; i < `MSHR_SIZE; i=i+1) begin
                cache_to_sq_packet.cache_miss_packet[i].valid    =  store_table_array[mem_tag_matched_mshr_idx].store_table[i].valid; // 1. cache hit 2. cache miss but will cache hit in the next cycle, forwarding
                cache_to_sq_packet.cache_miss_packet[i].sq_idx   =  store_table_array[mem_tag_matched_mshr_idx].store_table[i].lsq_idx;
            end
        end
    end

    assign store_accepted_cache = cache_hit_store | memory_data_forward_store_valid | store_mshr_hit_accepted | reserve_new_mshr_entry_store_valid;
    assign store_write_ptr_move = store_accepted_cache & sq_to_cache_packet.valid;

    //===========================update MSHR===========================

    //update mshr after free
    always_comb begin
        mshr_data_freed_comb = mshr_data;
        // update mshr after request has been issued to memory
        for(integer unsigned i = 0 ; i < `MSHR_SIZE; i = i+1) begin
            if(mshr_data[i].mem2proc_tag == mem2proc_tag && mshr_data[i].valid && (mem2proc_tag!=0))
                mshr_data_freed_comb[i] = '0;
        end
    end


    //update mshr after issued to memory
    priority_encoder #(.IN_WIDTH(`MSHR_SIZE)) issue_selector (.req(mshr_to_issue), .enc(mshr_issue_selected));
    assign mshr_issue_valid = | mshr_to_issue;
    always_comb begin
        mshr_data_issued_comb = mshr_data_freed_comb;
        if(mshr_data_freed_comb[mshr_issue_selected].valid & mshr_data_freed_comb[mshr_issue_selected].wait_to_issue & !mshr_issue_stall) begin
            if(mem2proc_response != 0) begin
                mshr_data_issued_comb[mshr_issue_selected].wait_to_issue = 1'b0;
                mshr_data_issued_comb[mshr_issue_selected].mem2proc_tag = mem2proc_response;
            end
        end
    end

    //update mshr after load instruction cache miss and reserve new entry in mshr
    always_comb begin
        mshr_data_load_comb = mshr_data_issued_comb;
        for(integer unsigned i = 0; i < 3; i = i+1) begin
            if(reserve_new_mshr_entry_load_valid[i]) begin
                mshr_data_load_comb[mshr_entry_selected_load[i]].valid = 1'b1;
                mshr_data_load_comb[mshr_entry_selected_load[i]].wait_to_issue = 1'b1;
                mshr_data_load_comb[mshr_entry_selected_load[i]].address = {lq_to_cache_packet.lq_to_cache_entry[i].address[`XLEN-1:3],{3{1'b0}}};
                mshr_data_load_comb[mshr_entry_selected_load[i]].mem2proc_tag = 0;
                //$display(" mem2proc_response : %d",mshr_entry_selected_load[i]);
            end
        end
    end

    // update mshr after store instruction cache miss and reserve new entry in mshr
    always_comb begin
        mshr_data_store_comb = mshr_data_load_comb;
        if(reserve_new_mshr_entry_store_valid) begin
            mshr_data_store_comb[mshr_entry_selected_store].valid = 1'b1;
            mshr_data_store_comb[mshr_entry_selected_store].wait_to_issue = 1'b1;
            mshr_data_store_comb[mshr_entry_selected_store].address = {sq_to_cache_packet.address[`XLEN-1:3],{3{1'b0}}};
            mshr_data_store_comb[mshr_entry_selected_store].mem2proc_tag = 0;
        end
    end

    always_comb begin
        mshr_data_branch_recovery_comb = mshr_data_store_comb;
        for(integer unsigned i = 0; i < `MSHR_SIZE; i=i+1) begin
            if(load_table_array_comb[i].tail == 0 & store_table_array_comb[i].tail == 0) begin
                mshr_data_branch_recovery_comb[i] = '0;
            end
        end
    end

    assign mshr_data_comb = branch_recovery ? mshr_data_branch_recovery_comb : mshr_data_store_comb;

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            mshr_data <= '0;
            load_table_array <= '0;
            store_table_array <='0;
        end
        else begin
            mshr_data <= mshr_data_comb;
            load_table_array <= load_table_array_comb;
            store_table_array <= store_table_array_comb;
        end
    end

    //===========================update CACHE===========================
    //if cache hit and write in cache
    //the store has to update the d-cache line in sequence, 
    //1. first update the cache line with store table instructrion , store table save store instruction sequentially; 
    //2. update the cache line with cache hit data
    
    // generate the updated cache line after data has been stored into cache line
    generate
        genvar t;
        store_write_in_cache SDG_MISS0( .cache_line_data(mem2proc_data),
                                        .valid(store_table_array[mem_tag_matched_mshr_idx].store_table[0].valid),
                                        .data_from_sq(store_table_array[mem_tag_matched_mshr_idx].store_table[0].data),
                                        .address(store_table_array[mem_tag_matched_mshr_idx].store_table[0].address),
                                        .store_offset(store_table_array[mem_tag_matched_mshr_idx].store_table[0].offset),
                                        .cache_line_data_after_write(cache_line_after_store_miss_array[0])
                                    );
        for(t = 1; t < `LOAD_STORE_TABLE_SIZE; t=t+1) begin : store_data_generator
            store_write_in_cache SDG_MISS(  .cache_line_data(cache_line_after_store_miss_array[t-1]),
                                            .valid(store_table_array[mem_tag_matched_mshr_idx].store_table[t].valid),
                                            .data_from_sq(store_table_array[mem_tag_matched_mshr_idx].store_table[t].data),
                                            .address(store_table_array[mem_tag_matched_mshr_idx].store_table[t].address),
                                            .store_offset(store_table_array[mem_tag_matched_mshr_idx].store_table[t].offset),
                                            .cache_line_data_after_write(cache_line_after_store_miss_array[t])
                                        );
        end
        store_write_in_cache SDG_FORWARD(   .cache_line_data(cache_line_after_store_miss_array[`LOAD_STORE_TABLE_SIZE-1]),
                                            .valid(memory_data_forward_store_valid),
                                            .data_from_sq(sq_to_cache_packet.data),
                                            .address(sq_to_cache_packet.address),
                                            .store_offset(sq_to_cache_packet.offset),
                                            .cache_line_data_after_write(cache_line_after_store_miss)
                                    );

        store_write_in_cache SDG_HIT(   .cache_line_data(cache_data[store_cache_set_idx].cache_line[cache_hit_store_idx].data),
                                        .valid(cache_hit_store),
                                        .data_from_sq(sq_to_cache_packet.data),
                                        .address(sq_to_cache_packet.address),
                                        .store_offset(sq_to_cache_packet.offset),
                                        .cache_line_data_after_write(cache_line_after_store_hit)
                                    );
    endgenerate

    // update Cache
    // select the available entry in d-cache
    generate
        genvar a;
        genvar b;
        for(a = 0; a < `SET; a=a+1) begin
            for(b = 0; b < `WAY; b=b+1) begin
                assign cache_line_available[a][b] = ~cache_data[a].cache_line[b].valid;
            end
        end
    endgenerate
    assign memory_data_to_cache_set_idx = mem_return_address[2+`CACHE_SET_BITS:3];
    assign memory_data_to_cache_set_tag = mem_return_address[15:3+`CACHE_SET_BITS];
    //select the available cache line in cache set for memory return cache line
    priority_encoder #(.IN_WIDTH(`WAY)) CACHE_WAY_SELECTOR(.req(cache_line_available[memory_data_to_cache_set_idx]), .enc(available_cache_line_selected));
    assign available_cache_line_valid = | cache_line_available[memory_data_to_cache_set_idx];
    // decide whether there is a store miss to the address return by memory
    assign memory_data_mshr_has_store = (store_table_array[mem_tag_matched_mshr_idx].tail != 0) | memory_data_forward_store_valid;

    //update cache data
    always_comb begin
        cache_data_hit_comb = cache_data;
        if(cache_hit_store) begin
            cache_data_hit_comb[store_cache_set_idx].cache_line[cache_hit_store_idx].dirty = 1'b1;
            cache_data_hit_comb[store_cache_set_idx].cache_line[cache_hit_store_idx].data = cache_line_after_store_hit;
        end
    end

    always_comb begin
        cache_data_comb = cache_data_hit_comb;
        if(mem_return_address_valid) begin
            if(available_cache_line_valid) begin
                cache_data_comb[memory_data_to_cache_set_idx].cache_line[available_cache_line_selected] = '0;
                cache_data_comb[memory_data_to_cache_set_idx].cache_line[available_cache_line_selected].valid = 1'b1;
                cache_data_comb[memory_data_to_cache_set_idx].cache_line[available_cache_line_selected].dirty = memory_data_mshr_has_store ? 1'b1 : 1'b0;
                cache_data_comb[memory_data_to_cache_set_idx].cache_line[available_cache_line_selected].tag = memory_data_to_cache_set_tag;
                cache_data_comb[memory_data_to_cache_set_idx].cache_line[available_cache_line_selected].data = cache_line_after_store_miss;
            end
            else begin
                cache_data_comb[memory_data_to_cache_set_idx].cache_line[lru[memory_data_to_cache_set_idx]] = '0;
                cache_data_comb[memory_data_to_cache_set_idx].cache_line[lru[memory_data_to_cache_set_idx]].valid = 1'b1;
                cache_data_comb[memory_data_to_cache_set_idx].cache_line[lru[memory_data_to_cache_set_idx]].dirty = memory_data_mshr_has_store ? 1'b1 : 1'b0;
                cache_data_comb[memory_data_to_cache_set_idx].cache_line[lru[memory_data_to_cache_set_idx]].tag = memory_data_to_cache_set_tag;
                cache_data_comb[memory_data_to_cache_set_idx].cache_line[lru[memory_data_to_cache_set_idx]].data = cache_line_after_store_miss;
            end
        end
    end

    //update LRU
    always_comb begin
        lru_comb = lru;
        // if store hit in cache
        if(cache_hit_store) begin
            lru_comb[store_cache_set_idx] = ~cache_hit_store_idx;
        end

        // if load hit in cache
        for(integer unsigned i = 0 ; i < 3; i=i+1) begin
            if(cache_hit_load[i]) begin
                lru_comb[load_cache_set_idx[i]] =  ~cache_hit_load_idx[i];
            end
        end

        // if there is valid memory data return from cache to memory
        if(mem_return_address_valid) begin
            lru_comb[memory_data_to_cache_set_idx] = available_cache_line_valid ? ~available_cache_line_selected : ~lru[memory_data_to_cache_set_idx];
        end
    end

    // if a dirty line has been evicted, it has to be store to memory immediately
    assign evicted_dirty_cache_line_valid = mem_return_address_valid & ~(|cache_line_available[memory_data_to_cache_set_idx]) & cache_data_hit_comb[memory_data_to_cache_set_idx].cache_line[lru[memory_data_to_cache_set_idx]].dirty;
    assign evicted_cache_line = cache_data_hit_comb[memory_data_to_cache_set_idx].cache_line[lru[memory_data_to_cache_set_idx]];
    assign evicted_cache_line_address = {16'b0,evicted_cache_line.tag,memory_data_to_cache_set_idx,3'b0};
    assign mshr_issue_stall = evicted_dirty_cache_line_valid_reg;
    // buffer to store evicted dirty data if there is no available mem tag
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            evicted_cache_line_reg <= 0;
            evicted_cache_line_address_reg <= 0;
            evicted_dirty_cache_line_valid_reg <= 0;
        end
        else begin
            evicted_cache_line_reg <= evicted_cache_line;
            evicted_cache_line_address_reg <= evicted_cache_line_address;
            // if in previous cycle, if dirty cache line should be evicted and the write request to cache can not be responded by memory
            evicted_dirty_cache_line_valid_reg <= evicted_dirty_cache_line_valid;
        end
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            cache_data <= '0;
            lru <= '0;
        end
        else begin
            cache_data <= cache_data_comb;
            lru <= lru_comb;
        end
    end

    // assign the read and store request to memory
    always_comb begin
        dcache2mem_addr = 0;
        dcache2mem_data = 0;
        if(evicted_dirty_cache_line_valid_reg) begin
            dcache2mem_command = BUS_STORE;
            dcache2mem_addr = evicted_cache_line_address_reg;
            dcache2mem_data = evicted_cache_line_reg.data;
        end
        else if(mshr_issue_valid) begin
            dcache2mem_command = BUS_LOAD;
            dcache2mem_addr = mshr_data[mshr_issue_selected].address;
        end
        else begin
            dcache2mem_command = BUS_NONE;
        end
    end

endmodule 


module data_to_lq_generator(
    input [2*`XLEN-1:0] cache_line_data,
    input [`XLEN-1:0] data_from_lq,
    input [`XLEN-1:0] address,
    input [3:0] load_offset, // the remaining byte which should be forwarded from d-cache
    output [`XLEN-1:0] data_to_lq
);
    logic [`XLEN-1:0] output_data;
    logic [`XLEN-1:0] cache_line_data_selected;
    assign data_to_lq = output_data; 
    assign cache_line_data_selected = address[2] ? cache_line_data[2*`XLEN-1:`XLEN] : cache_line_data[`XLEN-1:0];
    always_comb begin
        output_data = data_from_lq;
        if(load_offset[0]) begin
            output_data[7:0] = cache_line_data_selected[7:0];
        end
        if(load_offset[1]) begin
            output_data[15:8] = cache_line_data_selected[15:8];
        end
        if(load_offset[2]) begin
            output_data[23:16] = cache_line_data_selected[23:16];
        end
        if(load_offset[3]) begin
            output_data[31:24] = cache_line_data_selected[31:24];
        end
    end
endmodule

// which is used for generate the cache line after store
module store_write_in_cache(
    input [2*`XLEN-1:0] cache_line_data,
    input valid,
    input [`XLEN-1:0] data_from_sq,
    input [`XLEN-1:0] address,
    input [3:0] store_offset,
    output [2*`XLEN-1:0] cache_line_data_after_write
);
    logic [`XLEN-1:0] word_to_store;
    logic [2*`XLEN-1:0] cache_line_write;
    
    always_comb begin
        word_to_store = address[2] ? cache_line_data[63:32] : cache_line_data[31:0];
        if(store_offset[0]) begin
            word_to_store[7:0] = data_from_sq[7:0];
        end
        if(store_offset[1]) begin
                word_to_store[15:8] = data_from_sq[15:8];
        end
        if(store_offset[2]) begin
                word_to_store[23:16] = data_from_sq[23:16];
        end
        if(store_offset[3]) begin
                word_to_store[31:24] = data_from_sq[31:24];
        end
        // for(integer unsigned i = 0; i < 4; i=i+1) begin
        //     if(store_offset[i]) begin
        //         word_to_store[(i+1)*8-1:i*8] = data_from_sq[(i+1)*8-1:i*8];
        //     end
        // end
    end
    assign cache_line_write = address[2] ? {word_to_store,cache_line_data[31:0]} : {cache_line_data[63:32],word_to_store};
    assign cache_line_data_after_write = valid ? cache_line_write : cache_line_data;
endmodule


// which is ussed to flush load instruction when branch stack hit in branch mask
module branch_recovery_load_table_generator(
    input LOAD_TABLE_PACKET load_table,
    input branch_recovery,
    input[`BRANCH_STACK_SIZE-1:0] branch_stack,
    output LOAD_TABLE_PACKET load_table_out
);
    LOAD_TABLE_PACKET load_table_after_branch_recovery;
    LOAD_TABLE_PACKET load_table_after_branch_compress;
    // if the load table entry need to be flushed
    logic [`LOAD_STORE_TABLE_SIZE-1:0] branch_recovery_valid;
    logic [$clog2(`LOAD_STORE_TABLE_SIZE)-1:0] load_table_entry_valid_count [`LOAD_STORE_TABLE_SIZE-1:0];

    generate
        genvar i;
        for(i = 0; i < `LOAD_STORE_TABLE_SIZE; i=i+1) begin: Branch_recovery_valid
            assign branch_recovery_valid[i] = (|(load_table.load_table[i].branch_mask & branch_stack)) & load_table.load_table[i].valid;
        end
    endgenerate

    always_comb begin
        load_table_after_branch_recovery = load_table;
        for(integer unsigned i = 0; i < `LOAD_STORE_TABLE_SIZE; i=i+1) begin
            if(branch_recovery & branch_recovery_valid[i]) begin
                load_table_after_branch_recovery.load_table[i] = '0;
            end
        end
        load_table_after_branch_recovery.tail = load_table_after_branch_recovery.load_table[0].valid + load_table_after_branch_recovery.load_table[1].valid + load_table_after_branch_recovery.load_table[2].valid + load_table_after_branch_recovery.load_table[3].valid;
    end

    assign load_table_entry_valid_count[0] = 0;
    assign load_table_entry_valid_count[1] = load_table_after_branch_recovery.load_table[0].valid;
    assign load_table_entry_valid_count[2] = load_table_after_branch_recovery.load_table[0].valid + load_table_after_branch_recovery.load_table[1].valid;
    assign load_table_entry_valid_count[3] = load_table_after_branch_recovery.load_table[0].valid + load_table_after_branch_recovery.load_table[1].valid + load_table_after_branch_recovery.load_table[2].valid;

    always_comb begin
        load_table_after_branch_compress = '0;
        for(integer unsigned i = 0; i < `LOAD_STORE_TABLE_SIZE; i=i+1) begin
            load_table_after_branch_compress.load_table[load_table_entry_valid_count[i]] = load_table_after_branch_recovery.load_table[i];
        end
        load_table_after_branch_compress.tail = load_table_after_branch_recovery.tail;
    end
    assign load_table_out = branch_recovery ? load_table_after_branch_compress : load_table;
endmodule
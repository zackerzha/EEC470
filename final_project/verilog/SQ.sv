module SQ (
    input clock,
    input reset,
    input SQ_RESERVE_PACKET sq_reserve_packet,
    input FU_OUT_SQ_ENTRY [2:0] sq_complete_packet,
    input LQ_TO_SQ_PACKET lq_to_sq_packet,
    input ROB_TO_SQ_PACKET rob_to_sq_packet,
    input CACHE_TO_SQ_PACKET cache_to_sq_packet,
    // input [1:0] write_cache_ptr_move,
    input write_cache_ptr_move, // 0 or 1
    input branch_recovery,
    input [`BRANCH_STACK_SIZE-1:0] branch_stack,
    input [$clog2(`LSQ_SIZE):0] branch_recovery_sq_tail,
    output logic[$clog2(`LSQ_SIZE):0] sq_head,
    output logic[$clog2(`LSQ_SIZE):0] sq_tail,
    output SQ_TO_LQ_PACKET sq_to_lq_packet,
    output SQ_TO_CACHE_ENTRY sq_to_cache_packet,
    output logic [1:0] entry_available,
    output logic [`LSQ_SIZE-1:0] sq_complete,
    output logic empty
);

    SQ_ENTRY [`LSQ_SIZE-1:0] sq_data_comb;
    SQ_ENTRY [`LSQ_SIZE-1:0] sq_data;

    logic [$clog2(`LSQ_SIZE):0] head;
    logic [$clog2(`LSQ_SIZE):0] tail;
    logic [$clog2(`LSQ_SIZE):0] head_rl;
    logic [$clog2(`LSQ_SIZE):0] tail_rl;
    logic [$clog2(`LSQ_SIZE)-1:0] head_add [2:0];
    logic [$clog2(`LSQ_SIZE)-1:0] tail_add [2:0];
    logic [$clog2(`LSQ_SIZE):0] head_comb;
    logic [$clog2(`LSQ_SIZE):0] tail_comb;
    logic [$clog2(`LSQ_SIZE):0] occupied_entry;
    logic [`LSQ_SIZE:0] mask_free;
    logic [`LSQ_SIZE:0] [$clog2(`LSQ_SIZE)-1:0] temp_free;

    logic [3:0] data_offset [2:0];
    logic [`XLEN-1:0] store_data [2:0];
    logic [`XLEN-1:0] forward_data [2:0];
    logic [3:0] forward_offset [2:0];
    logic [2:0] forward_complete;
    logic [$clog2(`LSQ_SIZE):0] write_cache_ptr;
    logic [$clog2(`LSQ_SIZE):0] write_cache_ptr_comb;
    logic [$clog2(`LSQ_SIZE)-1:0] write_cache_ptr_add [2:0];

    logic [`LSQ_SIZE-1:0] sq_complete_mask;
        // for the entries which are not between head and tail, just give 0 for those bits
    logic [`LSQ_SIZE-1:0] sq_complete_mask_comb;

    assign sq_complete = sq_complete_mask_comb;
    assign occupied_entry = tail[$clog2(`LSQ_SIZE)] == head_comb[$clog2(`LSQ_SIZE)] ? tail - head_comb : {1'b1,tail[$clog2(`LSQ_SIZE)-1:0]} -  {1'b0,head_comb[$clog2(`LSQ_SIZE)-1:0]};
    assign tail_add[0] = tail;
    assign tail_add[1] = tail+1;
    assign tail_add[2] = tail+2;

    assign write_cache_ptr_add[0] = write_cache_ptr;
    assign write_cache_ptr_add[1] = write_cache_ptr+1;
    assign write_cache_ptr_add[2] = write_cache_ptr+2;

    assign write_cache_ptr_comb = write_cache_ptr + write_cache_ptr_move;// 

    assign tail_comb = branch_recovery ? branch_recovery_sq_tail : tail + sq_reserve_packet.sq_reserve_entry[0].valid + sq_reserve_packet.sq_reserve_entry[1].valid + sq_reserve_packet.sq_reserve_entry[2].valid;

    assign head_rl = {1'b0,head[$clog2(`LSQ_SIZE)-1:0]};
    assign tail_rl = head[$clog2(`LSQ_SIZE)] != tail[$clog2(`LSQ_SIZE)] ? {1'b1,tail[$clog2(`LSQ_SIZE)-1:0]} : {1'b0,tail[$clog2(`LSQ_SIZE)-1:0]};

    // sq_head is output to load queue
    assign sq_head = head_comb;
    assign sq_tail = tail;
    
    assign empty = occupied_entry == 0;

    always_comb begin
        case(occupied_entry) 
            `LSQ_SIZE-2 : entry_available = 2'b10;
            `LSQ_SIZE-1 : entry_available = 2'b1;
            `LSQ_SIZE   : entry_available = 2'b0; 
            default : entry_available = 2'b11;
        endcase
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            sq_data <= '0;
            write_cache_ptr <= 0;
            sq_complete_mask <= 0;
            head <= 0;
            tail <= 0;
        end
        else begin
            head <= head_comb;
            tail <= tail_comb;
            write_cache_ptr <= write_cache_ptr_comb;
            sq_data <= sq_data_comb;
            sq_complete_mask <= sq_complete_mask_comb;
        end
    end

    
    always_comb begin
        sq_data_comb = sq_data;
        head_comb = head;
        sq_complete_mask_comb = sq_complete_mask;
        temp_free = '0;
        mask_free = 0;
       
        // free
        mask_free[0] = 1'b1;
        for(integer unsigned i = 0 ; i < `LSQ_SIZE; i = i+1) begin
            if(head_rl+i < tail_rl) begin
                temp_free[i+1] = head+i;
                mask_free[i+1] = sq_data[temp_free[i+1]].cache_valid & mask_free[i];
                if(mask_free[i+1]) begin
                    sq_data_comb[temp_free[i+1]] = '0;
                    sq_complete_mask_comb[temp_free[i+1]] = 0;
                    head_comb = head+i+1;
                end
            end
        end

            // complete
        for(integer unsigned i = 0; i < 3 ; i = i+1) begin
            if(sq_complete_packet[i].valid) begin
                sq_data_comb[sq_complete_packet[i].sq_idx].complete       = 1'b1;
                sq_data_comb[sq_complete_packet[i].sq_idx].address        = sq_complete_packet[i].store_address;
                sq_data_comb[sq_complete_packet[i].sq_idx].data           = store_data[i];
                sq_data_comb[sq_complete_packet[i].sq_idx].data_offset    = data_offset[i];
                sq_complete_mask_comb[sq_complete_packet[i].sq_idx]       = 1'b1;
            end
        end

            // rob retire
        for(integer unsigned i = 0 ; i < 3; i = i+1) begin
            if(rob_to_sq_packet.valid[i]) begin
                sq_data_comb[rob_to_sq_packet.sq_idx[i]].retire = 1'b1;
            end
        end

            // cache hit
        // for(integer unsigned i = 0; i < 3; i = i+1) begin
        //     if(cache_to_sq_packet.cache_hit_packet[i].valid) begin
        //         sq_data_comb[cache_to_sq_packet.cache_hit_packet[i].sq_idx].cache_valid = 1'b1;
        //     end
        // end

        if(cache_to_sq_packet.cache_hit_packet.valid) begin
            sq_data_comb[cache_to_sq_packet.cache_hit_packet.sq_idx].cache_valid = 1'b1;
        end

            // cache miss
        for(integer unsigned i = 0; i < `LOAD_STORE_TABLE_SIZE; i = i+1) begin
            if(cache_to_sq_packet.cache_miss_packet[i].valid) begin
                sq_data_comb[cache_to_sq_packet.cache_miss_packet[i].sq_idx].cache_valid = 1'b1;
            end
        end

        // reserve entry, if branch is mis-predicted, should not reserve new entry in sq
        for(integer unsigned i = 0 ; i < 3; i = i+1) begin
            if(sq_reserve_packet.sq_reserve_entry[i].valid & (!branch_recovery)) begin
                sq_data_comb[tail_add[i]]                = '0;
                sq_data_comb[tail_add[i]].valid          = 1'b1;
                sq_data_comb[tail_add[i]].branch_mask    = sq_reserve_packet.sq_reserve_entry[i].branch_mask;
                sq_data_comb[tail_add[i]].PC             = sq_reserve_packet.sq_reserve_entry[i].PC;
                sq_data_comb[tail_add[i]].inst           = sq_reserve_packet.sq_reserve_entry[i].inst;
                sq_complete_mask_comb[tail_add[i]]       = 1'b0;
            end
        end

    end


    generate
        genvar i;
        for(i = 0; i < 3; i = i+1) begin: generate_offset
            get_offset go(.inst(sq_data[sq_complete_packet[i].sq_idx].inst),
                          .address(sq_complete_packet[i].store_address),
                          .input_data(sq_complete_packet[i].store_data),
                          .offset(data_offset[i]),
                          .output_data(store_data[i])
                        );
        end

        for(i = 0; i < 3; i = i+1) begin: generate_forward_data
            forward_data_generator fdg( .sq_data(sq_data), 
                                        .address(lq_to_sq_packet.lq_to_sq_entry[i].address), 
                                        .sq_tail(lq_to_sq_packet.lq_to_sq_entry[i].sq_tail),
                                        .lq_offset(lq_to_sq_packet.lq_to_sq_entry[i].offset),
                                        .sq_head(head),
                                        .forward_data(forward_data[i]),
                                        .forward_offset(forward_offset[i]),
                                        .forward_complete(forward_complete[i])
                                    );
        end
    endgenerate

    // generate output packet
    generate
        genvar j;

        for(j = 0; j < 3; j=j+1) begin: sq_to_lq_packet_generate 
            assign sq_to_lq_packet.sq_to_lq_entry[j].valid      = lq_to_sq_packet.lq_to_sq_entry[j].valid;
            assign sq_to_lq_packet.sq_to_lq_entry[j].data       = forward_data[j];
            assign sq_to_lq_packet.sq_to_lq_entry[j].lq_idx     = lq_to_sq_packet.lq_to_sq_entry[j].lq_idx;
            assign sq_to_lq_packet.sq_to_lq_entry[j].offset     = forward_offset[j];
            assign sq_to_lq_packet.sq_to_lq_entry[j].complete   = forward_complete[j];
        end

        // for(j = 0; j < 3; j=j+1) begin: sq_to_cache_packet_generate // how many store is issue to cache,load/store all occupied cache port
        //     assign sq_to_cache_packet.sq_to_cache_entry[j].valid        = branch_recovery ? sq_data[write_cache_ptr_add[j]].retire & !(|(sq_data[write_cache_ptr_add[j]].branch_mask & branch_stack))  :  sq_data[write_cache_ptr_add[j]].retire;
        //     assign sq_to_cache_packet.sq_to_cache_entry[j].address      = sq_data[write_cache_ptr_add[j]].address;
        //     assign sq_to_cache_packet.sq_to_cache_entry[j].offset       = sq_data[write_cache_ptr_add[j]].data_offset;
        //     assign sq_to_cache_packet.sq_to_cache_entry[j].data         = sq_data[write_cache_ptr_add[j]].data;
        //     assign sq_to_cache_packet.sq_to_cache_entry[j].branch_mask  = sq_data[write_cache_ptr_add[j]].branch_mask;
        //     assign sq_to_cache_packet.sq_to_cache_entry[j].sq_idx       = write_cache_ptr_add[j];
        //     assign sq_to_cache_packet.sq_to_cache_entry[j].inst         = sq_data[write_cache_ptr_add[j]].inst;
        // end
    endgenerate

    logic write_cache_ptr_move_valid;

    assign write_cache_ptr_move_valid = !(write_cache_ptr == tail);

    assign sq_to_cache_packet.valid        = sq_data[write_cache_ptr_add[0]].retire & write_cache_ptr_move_valid;
    assign sq_to_cache_packet.address      = sq_data[write_cache_ptr_add[0]].address;
    assign sq_to_cache_packet.offset       = sq_data[write_cache_ptr_add[0]].data_offset;
    assign sq_to_cache_packet.data         = sq_data[write_cache_ptr_add[0]].data;
    assign sq_to_cache_packet.branch_mask  = sq_data[write_cache_ptr_add[0]].branch_mask;
    assign sq_to_cache_packet.sq_idx       = write_cache_ptr_add[0];
    assign sq_to_cache_packet.inst         = sq_data[write_cache_ptr_add[0]].inst;
    assign sq_to_cache_packet.PC           = sq_data[write_cache_ptr_add[0]].PC;


endmodule


module get_offset(
    input INST inst,
    input [`XLEN-1:0] address,
    input [`XLEN-1:0] input_data,
    output logic [3:0] offset,
    output logic [`XLEN-1:0] output_data //the data should be saved in to the entry of store queue
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

    always_comb begin
        case(inst.r.funct3[1:0])
             2'b0    : output_data = {4{input_data[7:0]}};
             2'b1    : output_data = {2{input_data[15:0]}};
             2'b10   : output_data = input_data;
             default : output_data = input_data;
        endcase
    end

endmodule

module forward_data_generator(
    input SQ_ENTRY[`LSQ_SIZE-1:0] sq_data,
    input [`XLEN-1:0] address,
    input [$clog2(`LSQ_SIZE):0] sq_tail,
    input [3:0] lq_offset,
    input [$clog2(`LSQ_SIZE):0] sq_head,
    output logic [`XLEN-1:0] forward_data,
    output logic [3:0] forward_offset, // the byte which have not been forward which should be read from D-cache
    output logic forward_complete
);
    logic [3:0] mask [`LSQ_SIZE:0];
    logic [`XLEN-1:0] forward_data_array [`LSQ_SIZE:0];
    logic [$clog2(`LSQ_SIZE)-1:0] head_add [`LSQ_SIZE-1:0];
    logic [$clog2(`LSQ_SIZE):0] head;
    logic [$clog2(`LSQ_SIZE):0] tail;
    logic flag;

    assign flag = sq_tail[$clog2(`LSQ_SIZE)] != sq_head[$clog2(`LSQ_SIZE)];
    assign head = {1'b0, sq_head[$clog2(`LSQ_SIZE)-1:0]};
    assign tail = flag ? {1'b1, sq_tail[$clog2(`LSQ_SIZE)-1:0]} : {1'b0, sq_tail[$clog2(`LSQ_SIZE)-1:0]};

    always_comb begin
        mask[0] = 0;
        forward_data_array[0] = 0;
        for(integer unsigned i = 0; i < `LSQ_SIZE; i = i+1) begin
            head_add[i] = head + i;
            if(sq_data[head_add[i]].address[`XLEN-1:2] == address[`XLEN-1:2] && head + i < tail) begin
                mask[i+1] = {lq_offset[3] & sq_data[head_add[i]].data_offset[3], lq_offset[2] & sq_data[head_add[i]].data_offset[2], lq_offset[1] & sq_data[head_add[i]].data_offset[1], lq_offset[0] & sq_data[head_add[i]].data_offset[0]} | mask[i];
                forward_data_array[i+1][7:0]   = (lq_offset[0] & sq_data[head_add[i]].data_offset[0]) ? sq_data[head_add[i]].data[7:0]   : forward_data_array[i][7:0];
                forward_data_array[i+1][15:8]  = (lq_offset[1] & sq_data[head_add[i]].data_offset[1]) ? sq_data[head_add[i]].data[15:8]  : forward_data_array[i][15:8];
                forward_data_array[i+1][23:16] = (lq_offset[2] & sq_data[head_add[i]].data_offset[2]) ? sq_data[head_add[i]].data[23:16] : forward_data_array[i][23:16];
                forward_data_array[i+1][31:24] = (lq_offset[3] & sq_data[head_add[i]].data_offset[3]) ? sq_data[head_add[i]].data[31:24] : forward_data_array[i][31:24];
            end
            else begin
                mask[i+1] = mask[i];
                forward_data_array[i+1] = forward_data_array[i];
            end
        end
    end

    assign forward_data     = forward_data_array[`LSQ_SIZE];
    assign forward_offset   = (~mask[`LSQ_SIZE]) & lq_offset; // the remaining byte which can not be forwarded from sq, and should be read from D-cache
    assign forward_complete = mask[`LSQ_SIZE] == lq_offset;
endmodule
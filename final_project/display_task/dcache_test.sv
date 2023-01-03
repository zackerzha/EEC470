`define DEBUG
`timescale 1ns/100ps

class cache_request;
  rand bit [3:0] data_offset;
  rand bit [`XLEN-1:0] address;
  rand bit [`XLEN-1:0] data;
  rand bit [`BRANCH_STACK_SIZE-1:0] branch_mask;
  rand bit [$clog2(`LSQ_SIZE)-1:0] lsq_idx;

  constraint c_data_ofset { data_offset inside {4'b0001,4'b0010,4'b0100,4'b1000,4'b1100,4'b0011,4'b1111}; }
  constraint c_address { address  > 0; address < 32'hF;}
endclass


module testbench_dcache();

    logic clock;
    logic reset;
    SQ_TO_CACHE_ENTRY sq_to_cache_packet;
    LQ_TO_CACHE_PACKET lq_to_cache_packet;

    logic branch_recovery;
    logic branch_correct;
    logic [`BRANCH_STACK_SIZE-1:0] branch_stack;

    logic [3:0]  mem2proc_response;
    logic [63:0] mem2proc_data;
    logic [3:0]  mem2proc_tag;

    logic [1:0] store_write_ptr_move;
    logic [`LSQ_SIZE-1:0] load_accepted_cache;
    CACHE_TO_LQ_PACKET cache_to_lq_packet;
    CACHE_TO_SQ_PACKET cache_to_sq_packet;

    // to memory, for dcache , BUS_LOAD , BUS WRITE or BUS_NONE
    logic [1:0] dcache2mem_command;
    logic [`XLEN-1:0] dcache2mem_addr;
    logic [2*`XLEN-1:0] dcache2mem_data;

    logic [63:0]  unified_memory_truth [`MEM_64BIT_LINES - 1:0];

    logic [3:0] data_offset;
    logic [`XLEN-1:0] word_to_store;


    mem MEM(
        .clk(clock),
        .proc2mem_addr(dcache2mem_addr),
        .proc2mem_data(dcache2mem_data),
        .proc2mem_command(dcache2mem_command),
        .mem2proc_response(mem2proc_response),
        .mem2proc_data(mem2proc_data),
        .mem2proc_tag(mem2proc_tag)
    );
    
    `DUT(dcache) DUT(
        .clock(clock),
        .reset(reset),
        
        .sq_to_cache_packet(sq_to_cache_packet),
        .lq_to_cache_packet(lq_to_cache_packet),

        .branch_recovery(branch_recovery),
        .branch_correct(branch_correct),
        .branch_stack(branch_stack),

        .mem2proc_response(mem2proc_response),
        .mem2proc_data(mem2proc_data),
        .mem2proc_tag(mem2proc_tag),

        .store_write_ptr_move(store_write_ptr_move),
        .load_accepted_cache(load_accepted_cache),
        .cache_to_lq_packet(cache_to_lq_packet),
        .cache_to_sq_packet(cache_to_sq_packet),

        .dcache2mem_command(dcache2mem_command),
        .dcache2mem_addr(dcache2mem_addr),
        .dcache2mem_data(dcache2mem_data)
    );

    function automatic SQ_TO_CACHE_ENTRY generate_sq_to_cache_packet();
        cache_request c_req = new();
        c_req.randomize();
        generate_sq_to_cache_packet.valid = 1'b1;
        generate_sq_to_cache_packet.address = c_req.address;
        generate_sq_to_cache_packet.data = c_req.data;
        generate_sq_to_cache_packet.branch_mask = c_req.branch_mask;
        generate_sq_to_cache_packet.sq_idx = c_req.lsq_idx;
        generate_sq_to_cache_packet.offset = c_req.data_offset;
        generate_sq_to_cache_packet.inst = 0;
    endfunction

    function automatic SQ_TO_CACHE_ENTRY generate_sq_to_cache_packet_invalid();
        generate_sq_to_cache_packet_invalid = '0;
    endfunction

    function automatic SQ_TO_CACHE_ENTRY generate_sq_to_cache_packet_address(logic [`XLEN-1:0] address);
        cache_request c_req = new();
        c_req.randomize();
        generate_sq_to_cache_packet_address.valid = 1'b1;
        generate_sq_to_cache_packet_address.address = address;
        generate_sq_to_cache_packet_address.data = c_req.data;
        generate_sq_to_cache_packet_address.branch_mask = c_req.branch_mask;
        generate_sq_to_cache_packet_address.sq_idx = c_req.lsq_idx;
        generate_sq_to_cache_packet_address.offset = c_req.data_offset;
        generate_sq_to_cache_packet_address.inst = 0;
    endfunction

    function automatic LQ_TO_CACHE_ENTRY generate_lq_to_cache_packet();
        cache_request c_req = new();
        c_req.randomize();
        generate_lq_to_cache_packet.valid = 1'b1;
        generate_lq_to_cache_packet.address = c_req.address;
        generate_lq_to_cache_packet.data = c_req.data;
        generate_lq_to_cache_packet.branch_mask = c_req.branch_mask;
        generate_lq_to_cache_packet.lq_idx = c_req.lsq_idx;
        generate_lq_to_cache_packet.offset = c_req.data_offset;
        generate_lq_to_cache_packet.inst = 0;
    endfunction

    function automatic LQ_TO_CACHE_ENTRY generate_lq_to_cache_packet_invalid();
        generate_lq_to_cache_packet_invalid = '0;
    endfunction

    function automatic LQ_TO_CACHE_ENTRY generate_lq_to_cache_packet_address(logic [`XLEN-1:0] address);
        cache_request c_req = new();
        c_req.randomize();
        generate_lq_to_cache_packet_address.valid = 1'b1;
        generate_lq_to_cache_packet_address.address = address;
        generate_lq_to_cache_packet_address.data = c_req.data;
        generate_lq_to_cache_packet_address.branch_mask = c_req.branch_mask;
        generate_lq_to_cache_packet_address.lq_idx = c_req.lsq_idx;
        generate_lq_to_cache_packet_address.offset = c_req.data_offset;
        generate_lq_to_cache_packet_address.inst = 0;
    endfunction

    task update_unified_memory(logic [`XLEN-1:0] address, logic [`XLEN-1:0] data, logic [3:0] store_offset);
        logic [13:0] index;
        index = address[15:3];
        unified_memory_truth[index] = write_in_data(unified_memory_truth[index], data, address, store_offset);
    endtask

    function automatic logic[2*`XLEN-1:0] write_in_data (logic [2*`XLEN-1:0] cache_line_data, logic [`XLEN-1:0] data, logic [`XLEN-1:0] address, logic [3:0] store_offset);
        write_in_data = cache_line_data;
        word_to_store = address[2] ? cache_line_data[63:32] : cache_line_data[31:0];
        if(store_offset[0]) begin
            word_to_store[7:0] = data[7:0];
        end
        if(store_offset[1]) begin
            word_to_store[15:8] = data[15:8];
        end
        if(store_offset[2]) begin
            word_to_store[23:16] = data[23:16];
        end
        if(store_offset[3]) begin
            word_to_store[31:24] = data[31:24];
        end
        write_in_data = address[2] ? {word_to_store,write_in_data[31:0]} : {write_in_data[63:32],word_to_store};
    endfunction

    task display_dcache;
        foreach (DUT.cache_data[i]) begin
            $display("dcache_set: %d" , i);
            foreach(DUT.cache_data[i].cache_line[j]) begin
                logic[16:0] addr;
                addr = {DUT.cache_data[i].cache_line[j].tag, i[2:0], 3'b0};
                $display("dcache line: %-2d, valid: %-1d, addr: 0x%-4h, 0x%h", j, DUT.cache_data[i].cache_line[j].valid, addr, DUT.cache_data[i].cache_line[j].data);
            end
        end
    endtask

    task display_mshr;
        input MSHR_ENTRY [`MSHR_SIZE-1:0] mshr_data;
        $display("============================================ MSHR data ============================================");
        foreach (mshr_data[i]) begin
            $display("MSHR entry: %-2d, valid: %-1d, addr: 0x%-4h, wait_to_issue: %-1d, mem_tag: %-3d", i, mshr_data[i].valid, mshr_data[i].address,  mshr_data[i].wait_to_issue, mshr_data[i].mem2proc_tag);
        end
    endtask

    task display_load_table_array;
        input LOAD_TABLE_PACKET [`MSHR_SIZE-1:0] load_table_array;
        $display("============================================ Load Table data ============================================");
        for(int j = 0; j <  `MSHR_SIZE; j++) begin
            $display("load_table num : %d",j);
            display_one_load_table(load_table_array[j]);
        end
        $display("");
    endtask

    task display_one_load_table;
        input LOAD_TABLE_PACKET load_table;
        foreach (load_table.load_table[i]) begin
            $display("Load table entry: %-2d, valid: %-1d, addr: 0x%-4h, branch_mask: %-1d", i, DUT.load_table.load_table[i].valid, DUT.load_table.load_table[i].address,  DUT.load_table.load_table[i].branch_mask);
        end
        $display("tail: %-3d", load_table.tail);
    endtask

    task display_store_table_array;
        input STORE_TABLE_PACKET [`MSHR_SIZE-1:0] store_table_array;
        $display("============================================ Store Table data ============================================");
        for(int j = 0; j <  `MSHR_SIZE; j++) begin
            $display("store_table num : %d",j);
            display_one_store_table(store_table_array[j]);
        end
        $display("");
    endtask

    task display_one_store_table;
        input STORE_TABLE_PACKET store_table;
        foreach (store_table.store_table[i]) begin
            $display("Store table entry: %-2d, valid: %-1d, addr: 0x%-4h, branch_mask: %-1d", i, store_table.store_table[i].valid, store_table.store_table[i].address,  store_table.store_table[i].branch_mask);
        end
        $display("tail: %-3d", store_table.tail);
    endtask

    task display_load_table;
        input integer index;
        $display("============================================ Load Table data ============================================");
        foreach (DUT.load_table_array_comb[index].load_table[i]) begin
            $display("Load table entry: %-2d, valid: %-1d, addr: 0x%-4h, branch_mask: %-1d", i, DUT.load_table_array_comb[index].load_table[i].valid, DUT.load_table_array_comb[index].load_table[i].address,  DUT.load_table_array_comb[index].load_table[i].branch_mask);
        end
        $display("tail: %-3d", DUT.load_table_array_comb[index].tail);
    endtask

    task display_store_table;
        input integer index;
        input STORE_TABLE_PACKET[`MSHR_SIZE-1:0] Store_table_array_comb;
        $display("============================================ Store Table data ============================================");
        foreach (Store_table_array_comb[index].store_table[i]) begin
            $display("Store table entry: %-2d, valid: %-1d, addr: 0x%-4h, branch_mask: %-1d", i, Store_table_array_comb[index].store_table[i].valid, Store_table_array_comb[index].store_table[i].address,  Store_table_array_comb[index].store_table[i].branch_mask);
        end
        $display("tail: %-3d", Store_table_array_comb[index].tail);
    endtask

    task display_memory;
        foreach (MEM.unified_memory[i]) begin
            $display("display memory 0x%h as 0x%h", i, unified_memory_truth[i]);
        end
    endtask

    task check_data_from_cache;
        logic [12:0] index;
        index = DUT.mem_return_address[15:3];
        if(DUT.mem_return_address_valid) begin
            index = DUT.memory_data_to_cache_set_idx;
            if(DUT.cache_line_after_store_miss != unified_memory_truth[index]) begin
                $display("Data_out wrong!!! addr: 0x%-4h, get: 0x%h, supposed to be: 0x%h", DUT.mem_return_address, DUT.cache_line_after_store_miss , unified_memory_truth[index]);
                $finish();
            end
        end
    endtask

    task load_only;
        reset = 1'b1;
        branch_recovery = 1'b0;
        branch_correct = 1'b0;
        @(posedge clock);
        @(posedge clock);
        $readmemh("program.mem", MEM.unified_memory);
        unified_memory_truth = MEM.unified_memory;
        
        @(posedge clock);
        reset = 1'b0;
        lq_to_cache_packet.lq_to_cache_entry[0] = generate_lq_to_cache_packet_address(32'h4);
        lq_to_cache_packet.lq_to_cache_entry[1] = generate_lq_to_cache_packet_address(32'h4);
        lq_to_cache_packet.lq_to_cache_entry[2] = generate_lq_to_cache_packet_address(32'h4);
        sq_to_cache_packet = generate_sq_to_cache_packet_invalid();
        #1
        display_load_table(`MSHR_SIZE-1);
        display_mshr();
        @(posedge clock);
        lq_to_cache_packet.lq_to_cache_entry[0] = generate_lq_to_cache_packet_address(32'hC);
        lq_to_cache_packet.lq_to_cache_entry[1] = generate_lq_to_cache_packet_address(32'hD);
        lq_to_cache_packet.lq_to_cache_entry[2] = generate_lq_to_cache_packet_address(32'hE);
        #1
        display_load_table(`MSHR_SIZE-1);
        display_mshr();

        @(posedge clock);
        lq_to_cache_packet.lq_to_cache_entry[0] = generate_lq_to_cache_packet_address(32'h1);
        lq_to_cache_packet.lq_to_cache_entry[1] = generate_lq_to_cache_packet_address(32'h17);
        lq_to_cache_packet.lq_to_cache_entry[2] = 0;
        sq_to_cache_packet = generate_sq_to_cache_packet_invalid();
        #1
        display_mshr();
        display_load_table(`MSHR_SIZE-1);

        @(posedge clock);
        #1
        display_mshr();

        while(!DUT.mem_return_address_valid) begin
            @(posedge clock);
        end
        check_data_from_cache();

        while(!DUT.mem_return_address_valid) begin
            @(posedge clock);
        end
        check_data_from_cache();
        @(posedge clock)
        display_mshr();
        display_load_table(`MSHR_SIZE-1);

        @(posedge clock);
        

    endtask

    task store;
        reset = 1'b1;
        branch_recovery = 1'b0;
        branch_correct = 1'b0;
        @(posedge clock);
        @(posedge clock);
        $readmemh("program.mem", MEM.unified_memory);
        unified_memory_truth = MEM.unified_memory;
        lq_to_cache_packet.lq_to_cache_entry[0] = '0;
        lq_to_cache_packet.lq_to_cache_entry[1] = '0;
        lq_to_cache_packet.lq_to_cache_entry[2] = '0;
        sq_to_cache_packet = '0;
        
        @(posedge clock);
        reset = 0;
        sq_to_cache_packet = generate_sq_to_cache_packet();
        $display("address:%h, data:%d, offset:%d", sq_to_cache_packet.address,sq_to_cache_packet.data,sq_to_cache_packet.offset);
        update_unified_memory(sq_to_cache_packet.address, sq_to_cache_packet.data, sq_to_cache_packet.offset);
        display_mshr();
        $display(" missed_in_mshr_store : %b", DUT.hit_in_mshr_store);
         #1 display_store_table(`MSHR_SIZE-1,DUT.store_table_array_mshr_miss_comb);
        @(posedge clock);
        sq_to_cache_packet = generate_sq_to_cache_packet();
        $display("address:%h, data:%d, offset:%d", sq_to_cache_packet.address,sq_to_cache_packet.data,sq_to_cache_packet.offset);
        update_unified_memory(sq_to_cache_packet.address, sq_to_cache_packet.data, sq_to_cache_packet.offset);
        #1
        display_mshr();
        @(posedge clock);
        sq_to_cache_packet = generate_sq_to_cache_packet();
        #1
        $display("address:%h, data:%d, offset:%d", sq_to_cache_packet.address,sq_to_cache_packet.data,sq_to_cache_packet.offset);
        update_unified_memory(sq_to_cache_packet.address, sq_to_cache_packet.data, sq_to_cache_packet.offset);
        $display("%h",DUT.hit_in_mshr_store);
        $display("%h",DUT.memory_data_forward_store_valid);
        #1
        display_mshr();
        #1 display_store_table(`MSHR_SIZE-1,DUT.store_table_array_mshr_hit_comb);
        @(posedge clock);
    
        reset = 1'b0;
        sq_to_cache_packet = generate_sq_to_cache_packet();
        update_unified_memory(sq_to_cache_packet.address, sq_to_cache_packet.data, sq_to_cache_packet.offset);
        check_data_from_cache();
        @(posedge clock);
        reset = 1'b0;
        sq_to_cache_packet = generate_sq_to_cache_packet();
        update_unified_memory(sq_to_cache_packet.address, sq_to_cache_packet.data, sq_to_cache_packet.offset);
        check_data_from_cache();
        @(posedge clock);
        reset = 1'b0;
        sq_to_cache_packet = generate_sq_to_cache_packet();
        update_unified_memory(sq_to_cache_packet.address, sq_to_cache_packet.data, sq_to_cache_packet.offset);
        check_data_from_cache();
        @(posedge clock);
        reset = 1'b0;
        sq_to_cache_packet = generate_sq_to_cache_packet();
        update_unified_memory(sq_to_cache_packet.address, sq_to_cache_packet.data, sq_to_cache_packet.offset);
        check_data_from_cache();

        while(!DUT.mem_return_address_valid) begin
                @(posedge clock);
            end
            check_data_from_cache();
        while(!DUT.mem_return_address_valid) begin
                @(posedge clock);
            end
            check_data_from_cache();
        while(!DUT.mem_return_address_valid) begin
                @(posedge clock);
            end
            check_data_from_cache();
        while(!DUT.mem_return_address_valid) begin
                @(posedge clock);
            end
            check_data_from_cache();
        while(!DUT.mem_return_address_valid) begin
                @(posedge clock);
            end
            check_data_from_cache();
        while(!DUT.mem_return_address_valid) begin
                @(posedge clock);
            end
            check_data_from_cache();
        @(posedge clock);

    endtask

    
    

    always begin
        #10
        clock = ~clock;
    end
    
    initial begin
    $dumpvars;
    clock = 1'b0;
    load_only();
    store();
    
    $finish;
    end


endmodule
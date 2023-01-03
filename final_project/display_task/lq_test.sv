`define DEBUG

module testbench_lq();

    logic clock;
    logic reset;

    LQ_RESERVE_PACKET lq_reserve_packet;
    FU_OUT_LQ_ENTRY [2:0] lq_address_packet;
    ROB_TO_LQ_PACKET rob_to_lq_packet;
    SQ_TO_LQ_PACKET sq_to_lq_packet;
    CACHE_TO_LQ_PACKET cache_to_lq_packet;
    logic [$clog2(`LSQ_SIZE):0] sq_head;
    logic [`LSQ_SIZE-1:0] completed_store;
    logic branch_recovery;
    logic [`BRANCH_STACK_SIZE-1:0] branch_stack;
    logic [$clog2(`LSQ_SIZE):0] branch_recovery_sq_tail;
    logic [`LSQ_SIZE-1:0] load_accepted_cache;
    logic cdb_stall;

    LQ_TO_SQ_PACKET lq_to_sq_packet;
    LQ_TO_CACHE_PACKET lq_to_cache_packet;
    FU_OUT_CDB_ENTRY [2:0] lq_to_cdb_packet;
    logic [1:0] entry_available;
    logic [$clog2(`LSQ_SIZE):0] lq_tail;
    
    // LQ lq(
    //     .clock(clock),
    //     .reset(reset),

    //     .lq_reserve_packet(lq_reserve_packet),
    //     .lq_address_packet(lq_address_packet),
    //     .rob_to_lq_packet(rob_to_lq_packet),
    //     .sq_to_lq_packet(sq_to_lq_packet),
    //     .cache_to_lq_packet(cache_to_lq_packet),
    //     .sq_head(sq_head),
    //     .completed_store(completed_store),
    //     .branch_recovery(branch_recovery),
    //     .branch_stack(branch_stack),
    //     .branch_recovery_sq_tail(branch_recovery_sq_tail),
    //     .load_accepted_cache(load_accepted_cache),
    //     .cdb_stall(cdb_stall),

    //     .lq_to_sq_packet(lq_to_sq_packet),
    //     .lq_to_cache_packet(lq_to_cache_packet),
    //     .lq_to_cdb_packet(lq_to_cdb_packet),
    //     .entry_available(entry_available),
    //     .lq_tail(lq_tail)
    // );

    always begin
        #10
        clock = ~clock;
    end

    initial begin
    $dumpvars;
    clock = 1'b0;
    reset = 1'b0;

    @(negedge clock);
    
    $finish;
    end


endmodule

    task display_fetch_data;
        // input items
        input LQ_RESERVE_PACKET lq_reserve_packet;
        input FU_OUT_LQ_ENTRY [2:0] lq_address_packet;
        input ROB_TO_LQ_PACKET rob_to_lq_packet;
        input SQ_TO_LQ_PACKET sq_to_lq_packet;
        input CACHE_TO_LQ_PACKET cache_to_lq_packet;
        input [$clog2(`LSQ_SIZE):0] sq_head;
        input [`LSQ_SIZE-1:0] completed_store;
        input branch_recovery;
        input branch_correct;
        input [`BRANCH_STACK_SIZE-1:0] branch_stack;
        input [$clog2(`LSQ_SIZE):0] branch_recovery_sq_tail;
        input [`LSQ_SIZE-1:0] load_accepted_cache;
        input cdb_stall;
        // output items
        input LQ_TO_SQ_PACKET lq_to_sq_packet;
        input LQ_TO_CACHE_PACKET lq_to_cache_packet;
        input FU_OUT_CDB_ENTRY [2:0] lq_to_cdb_packet;
        input [1:0] entry_available;
        input [$clog2(`LSQ_SIZE)-1:0] lq_tail;
        // lq_data
        input LQ_ENTRY[`LSQ_SIZE-1:0] lq_data;
        input [`LSQ_SIZE-1:0] issued_to_sq;
        input [`LSQ_SIZE-1:0] issued_to_dcache;
        input [`LSQ_SIZE-1:0] issued_to_cdb;
        input [$clog2(`LSQ_SIZE):0] head;
        input [$clog2(`LSQ_SIZE):0] tail;
        //
        $write("\n");
        $display("================================================ LQ_input ================================================");
        $display("lq_reserve_packet:");
        $display(" instruction | pc       | branch_mask |   preg   | rob_tail | sq_tail | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-11h |", lq_reserve_packet.lq_reserve_entry[i].inst);
        $write(" %-8h |", lq_reserve_packet.lq_reserve_entry[i].PC);
        $write(" %-11b |", lq_reserve_packet.lq_reserve_entry[i].branch_mask);
        $write(" %-8d |", lq_reserve_packet.lq_reserve_entry[i].preg);
        $write(" %-8d |", lq_reserve_packet.lq_reserve_entry[i].rob_tail);
        $write(" %-7b |", lq_reserve_packet.sq_tail[i]);
        $write(" %-5b ", lq_reserve_packet.lq_reserve_entry[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("lq_address_packet:");
        $display(" lq_idx | load_address | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-6d |", lq_address_packet[i].lq_idx);
        $write(" %-12h |", lq_address_packet[i].load_address);
        $write(" %-5b ", lq_address_packet[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("rob_to_lq_packet:");
        $display(" lq_idx | valid");
        $write(" %-6d |", rob_to_lq_packet.lq_idx);
        $write(" %-5b ", rob_to_lq_packet.valid);
        //
        $write("\n");
        $display("sq_to_lq_packet:");
        $display(" data     | lq_idx | offset | complete | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-8h |", sq_to_lq_packet.sq_to_lq_entry[i].data);
        $write(" %-6d |", sq_to_lq_packet.sq_to_lq_entry[i].lq_idx);
        $write(" %-6b |", sq_to_lq_packet.sq_to_lq_entry[i].offset);
        $write(" %-8b |", sq_to_lq_packet.sq_to_lq_entry[i].complete);
        $write(" %-5b ", sq_to_lq_packet.sq_to_lq_entry[i].valid);
        $write("\n");
        end
        //111need change
        $write("\n");
        $display("cache_to_lq_packet.cache_hit:");
        $display(" Entry | lq_idx | data      | valid ");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |", i);
        $write(" %-6d |", cache_to_lq_packet.cache_hit_packet[i].lq_idx);
        $write(" %-9h |", cache_to_lq_packet.cache_hit_packet[i].data);
        $write(" %-5b ", cache_to_lq_packet.cache_hit_packet[i].valid);
        $write("\n");
        end
        $display("cache_to_lq_packet.cache_miss:");
        $display(" Entry | lq_idx | data      | valid ");
        for (integer i = 0; i < 4; i ++) begin
        $write(" %-5d |", i);
        $write(" %-6d |", cache_to_lq_packet.cache_miss_packet[i].lq_idx);
        $write(" %-9h |", cache_to_lq_packet.cache_miss_packet[i].data);
        $write(" %-5b ", cache_to_lq_packet.cache_miss_packet[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("sq_head: %d" , sq_head);
        $display("completed_store: %b", completed_store);
        $display("branch_recovery: %b", branch_recovery);
        $display("branch stack: %d" , branch_stack);
        $display("branch_recovery_sq_tail: %d",branch_recovery_sq_tail );
        $display("load_accepted_cache: %b", load_accepted_cache);
        $display("cdb_stall: %b", cdb_stall);
        //
        $write("\n");
        $display("===============================================output_data================================================");
        $write("\n");
        $display("lq_to_sq_packet:");
        $display(" Entry |  address  | sq_idx | lq_idx | offset | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |", i);
        $write(" %-9h |", lq_to_sq_packet.lq_to_sq_entry[i].address);
        $write(" %-6d |", lq_to_sq_packet.lq_to_sq_entry[i].sq_tail);
        $write(" %-6d |", lq_to_sq_packet.lq_to_sq_entry[i].lq_idx);
        $write(" %-6b |", lq_to_sq_packet.lq_to_sq_entry[i].offset);
        $write(" %-5b ", lq_to_sq_packet.lq_to_sq_entry[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("lq_to_cache_packet:");
        $display(" Entry | instuction |  address  |   data   | branch_mask | lq_idx | offset | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |", i);
        $write(" %-10h |", lq_to_cache_packet.lq_to_cache_entry[i].inst);
        $write(" %-9h |", lq_to_cache_packet.lq_to_cache_entry[i].address);
        $write(" %-8h |", lq_to_cache_packet.lq_to_cache_entry[i].data);
        $write(" %-11b |", lq_to_cache_packet.lq_to_cache_entry[i].branch_mask);
        $write(" %-6d |", lq_to_cache_packet.lq_to_cache_entry[i].lq_idx);
        $write(" %-6b |", lq_to_cache_packet.lq_to_cache_entry[i].offset);
        $write(" %-5b", lq_to_cache_packet.lq_to_cache_entry[i].valid);
        $write("\n");
        end
        //FU_OUT_CDB_ENTRY
        $write("\n");
        $display("lq_to_cdb_packet:");
        $display(" Entry | preg_value | preg_to_write | 1reg_to_write | branch_mask | rob_tail | is_wb | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |", i);
        $write(" %-10h |", lq_to_cdb_packet[i].preg_value);
        $write(" %-12d |", lq_to_cdb_packet[i].preg_to_write);
        $write(" %-13d |", lq_to_cdb_packet[i].lreg_to_write);
        $write(" %-11b |", lq_to_cdb_packet[i].branch_mask);
        $write(" %-8d |", lq_to_cdb_packet[i].rob_tail);
        $write(" %-5b |", lq_to_cdb_packet[i].is_wb_inst);
        $write(" %-5b |", lq_to_cdb_packet[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("entry_available: %d", entry_available);
        $display("lq_tail: %d", lq_tail);
        //
        // $write("\n");
        // $display("==============================================lq_data=====================================================");
        // $display(" Entry | Head | trail | valid | address_ready | ready_to_search_sq | forward | complete | branch_mask | address  |  data    | sq_complete | data_offset | forward_data_offset | pc       | sq_tail | rob_tail | preg   | instruction | issued to sq | issued to dache | issued to cdb ");
        // for (integer i = 0; i < `LSQ_SIZE; i ++) begin
        // $write(" %-5d |", i);
        // $write(" %-4d |", head);
        // $write(" %-4d |", tail);
        // $write(" %-5b |", lq_data[i].valid);
        // $write(" %-13b |", lq_data[i].address_ready);
        // $write(" %-18b |", lq_data[i].ready_to_search_sq);
        // $write(" %-6b |", lq_data[i].forward);
        // $write(" %-7b |", lq_data[i].complete);
        // $write(" %-11b |", lq_data[i].branch_mask);
        // $write(" %-8h |", lq_data[i].address);
        // $write(" %-8h |", lq_data[i].data);
        // $write(" %-10b |", lq_data[i].sq_complete);
        // $write(" %-11d |", lq_data[i].data_offset);
        // $write(" %-19b |", lq_data[i].forward_data_offset);
        // $write(" %-8h |", lq_data[i].pc);
        // $write(" %-7d |", lq_data[i].sq_tail);
        // $write(" %-8d |", lq_data[i].rob_tail);
        // $write(" %-6d |", lq_data[i].preg);
        // $write(" %-13b |", lq_data[i].address_ready);
        // $write(" %-11h |", lq_data[i].inst);
        // $write(" %-13b |", lq_data[i].address_ready);
        // $write(" %-12b |", issued_to_sq[i]);
        // $write(" %-15b |", issued_to_dcache[i]);
        // $write(" %-13d ", issued_to_cdb[i]);

        // $write("\n");
        // end
        // $display("==========================================================================================================");
        // $write("\n");
    endtask

    task display_lq_data_in;
        input LQ_RESERVE_PACKET lq_reserve_packet;
        input FU_OUT_LQ_ENTRY [2:0] lq_address_packet;
        input ROB_TO_LQ_PACKET rob_to_lq_packet;
        input SQ_TO_LQ_PACKET sq_to_lq_packet;
        input CACHE_TO_LQ_PACKET cache_to_lq_packet;
        input [$clog2(`LSQ_SIZE):0] sq_head;
        input [`LSQ_SIZE-1:0] completed_store;
        input branch_recovery;
        input [`BRANCH_STACK_SIZE-1:0] branch_stack;
        input [$clog2(`LSQ_SIZE):0] branch_recovery_sq_tail;
        input [`LSQ_SIZE-1:0] load_accepted_cache;
        input cdb_stall;
        $write("\n");
        $display("================================================ LQ_input ================================================");
        $display("lq_reserve_packet:");
        $display(" instruction | pc       | branch_mask |   preg   | rob_tail | sq_tail | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-11h |", lq_reserve_packet.lq_reserve_entry[i].inst);
        $write(" %-8h |", lq_reserve_packet.lq_reserve_entry[i].PC);
        $write(" %-11b |", lq_reserve_packet.lq_reserve_entry[i].branch_mask);
        $write(" %-8d |", lq_reserve_packet.lq_reserve_entry[i].preg);
        $write(" %-8d |", lq_reserve_packet.lq_reserve_entry[i].rob_tail);
        $write(" %-7b |", lq_reserve_packet.sq_tail[i]);
        $write(" %-5b ", lq_reserve_packet.lq_reserve_entry[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("lq_address_packet:");
        $display(" lq_idx | load_address | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-6d |", lq_address_packet[i].lq_idx);
        $write(" %-12h |", lq_address_packet[i].load_address);
        $write(" %-5b ", lq_address_packet[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("rob_to_lq_packet:");
        $display(" lq_idx | valid");
        $write(" %-6d |", rob_to_lq_packet.lq_idx);
        $write(" %-5b ", rob_to_lq_packet.valid);
        //
        $write("\n");
        $display("sq_to_lq_packet:");
        $display(" data     | lq_idx | offset | complete | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-8h |", sq_to_lq_packet.sq_to_lq_entry[i].data);
        $write(" %-6d |", sq_to_lq_packet.sq_to_lq_entry[i].lq_idx);
        $write(" %-6b |", sq_to_lq_packet.sq_to_lq_entry[i].offset);
        $write(" %-8b |", sq_to_lq_packet.sq_to_lq_entry[i].complete);
        $write(" %-5b ", sq_to_lq_packet.sq_to_lq_entry[i].valid);
        $write("\n");
        end
        //111need change
        $write("\n");
        $display("cache_to_lq_packet.cache_hit:");
        $display(" Entry | lq_idx | data      | valid ");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |", i);
        $write(" %-6d |", cache_to_lq_packet.cache_hit_packet[i].lq_idx);
        $write(" %-9h |", cache_to_lq_packet.cache_hit_packet[i].data);
        $write(" %-5b ", cache_to_lq_packet.cache_hit_packet[i].valid);
        $write("\n");
        end
        $display("cache_to_lq_packet.cache_miss:");
        $display(" Entry | lq_idx | data      | valid ");
        for (integer i = 0; i < 4; i ++) begin
        $write(" %-5d |", i);
        $write(" %-6d |", cache_to_lq_packet.cache_miss_packet[i].lq_idx);
        $write(" %-9h |", cache_to_lq_packet.cache_miss_packet[i].data);
        $write(" %-5b ", cache_to_lq_packet.cache_miss_packet[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("sq_head: %d" , sq_head);
        $display("completed_store: %b", completed_store);
        $display("branch_recovery: %b", branch_recovery);
        // $display("branch_correct: %b", branch_correct);
        $display("branch stack: %d" , branch_stack);
        $display("branch_recovery_sq_tail: %d",branch_recovery_sq_tail );
        $display("load_accepted_cache: %b", load_accepted_cache);
        $display("cdb_stall: %b", cdb_stall);
    endtask

    task display_lq_data_out;
        input LQ_TO_SQ_PACKET lq_to_sq_packet;
        input LQ_TO_CACHE_PACKET lq_to_cache_packet;
        input FU_OUT_CDB_ENTRY [2:0] lq_to_cdb_packet;
        input [1:0] entry_available;
        input [$clog2(`LSQ_SIZE)-1:0] lq_tail;
        $write("\n");
        $display("===============================================output_data================================================");
        $write("\n");
        $display("lq_to_sq_packet:");
        $display(" Entry |  address  | sq_idx | lq_idx | offset | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |", i);
        $write(" %-9h |", lq_to_sq_packet.lq_to_sq_entry[i].address);
        $write(" %-6d |", lq_to_sq_packet.lq_to_sq_entry[i].sq_tail);
        $write(" %-6d |", lq_to_sq_packet.lq_to_sq_entry[i].lq_idx);
        $write(" %-6b |", lq_to_sq_packet.lq_to_sq_entry[i].offset);
        $write(" %-5b ", lq_to_sq_packet.lq_to_sq_entry[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("lq_to_cache_packet:");
        $display(" Entry | instuction |  address  |   data   | branch_mask | lq_idx | offset | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |", i);
        $write(" %-10h |", lq_to_cache_packet.lq_to_cache_entry[i].inst);
        $write(" %-9h |", lq_to_cache_packet.lq_to_cache_entry[i].address);
        $write(" %-8h |", lq_to_cache_packet.lq_to_cache_entry[i].data);
        $write(" %-11b |", lq_to_cache_packet.lq_to_cache_entry[i].branch_mask);
        $write(" %-6d |", lq_to_cache_packet.lq_to_cache_entry[i].lq_idx);
        $write(" %-6b |", lq_to_cache_packet.lq_to_cache_entry[i].offset);
        $write(" %-5b", lq_to_cache_packet.lq_to_cache_entry[i].valid);
        $write("\n");
        end
        //FU_OUT_CDB_ENTRY
        $write("\n");
        $display("lq_to_cdb_packet:");
        $display(" Entry | preg_value | preg_to_write | 1reg_to_write | branch_mask | rob_tail | is_wb | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |", i);
        $write(" %-10h |", lq_to_cdb_packet[i].preg_value);
        $write(" %-12d |", lq_to_cdb_packet[i].preg_to_write);
        $write(" %-13d |", lq_to_cdb_packet[i].lreg_to_write);
        $write(" %-11b |", lq_to_cdb_packet[i].branch_mask);
        $write(" %-8d |", lq_to_cdb_packet[i].rob_tail);
        $write(" %-5b |", lq_to_cdb_packet[i].is_wb_inst);
        $write(" %-5b |", lq_to_cdb_packet[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("entry_available: %d", entry_available);
        $display("lq_tail: %d", lq_tail);
        //

    endtask

    task display_lq_data;
    // lq_data
        input LQ_ENTRY[`LSQ_SIZE-1:0] lq_data;
        input [`LSQ_SIZE-1:0] issued_to_sq;
        input [`LSQ_SIZE-1:0] issued_to_dcache;
        input [`LSQ_SIZE-1:0] issued_to_cdb;
        input [$clog2(`LSQ_SIZE)-1:0] head;
        input [$clog2(`LSQ_SIZE)-1:0] tail;

        $write("\n");
        
        $display("==============================================lq_data=====================================================");
        $display(" Entry | valid | address_ready | ready_to_search_sq | forward | complete | branch_mask | address  |  data    | sq_complete | data_offset | forward_data_offset | pc       | sq_tail | rob_tail | preg   | instruction | issued to sq | issued to dache | issued to cdb ");
        for (integer i = 0; i < `LSQ_SIZE; i ++) begin
        $write(" %-5d |", i);
        $write(" %-5b |", lq_data[i].valid);
        $write(" %-13b |", lq_data[i].address_ready);
        $write(" %-18b |", lq_data[i].ready_to_search_sq);
        $write(" %-6b |", lq_data[i].forwarded);
        $write(" %-7b |", lq_data[i].complete);
        $write(" %-11b |", lq_data[i].branch_mask);
        $write(" %-8h |", lq_data[i].address);
        $write(" %-8h |", lq_data[i].data);
        $write(" %-10b |", lq_data[i].sq_complete);
        $write(" %-11d |", lq_data[i].data_offset);
        $write(" %-19b |", lq_data[i].forward_data_offset);
        $write(" %-8h |", lq_data[i].PC);
        $write(" %-7d |", lq_data[i].sq_tail);
        $write(" %-8d |", lq_data[i].rob_tail);
        $write(" %-6d |", lq_data[i].preg);
        $write(" %-13b |", lq_data[i].address_ready);
        $write(" %-11h |", lq_data[i].inst);
        $write(" %-13b |", lq_data[i].address_ready);
        $write(" %-12b |", issued_to_sq[i]);
        $write(" %-15b |", issued_to_dcache[i]);
        $write(" %-13d ", issued_to_cdb[i]);
        $write("\n");
        end
        $display("head = %d, tail = %d",head,tail);
        $display("==========================================================================================================");
        $write("\n");

    endtask
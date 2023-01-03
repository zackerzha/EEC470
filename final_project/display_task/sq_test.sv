`define DEBUG

module testbench_sq();

    logic clock;
    logic reset;
    SQ_RESERVE_PACKET sq_reserve_packet;
    FU_OUT_SQ_ENTRY [2:0] sq_complete_packet;
    LQ_TO_SQ_PACKET lq_to_sq_packet;
    ROB_TO_SQ_PACKET rob_to_sq_packet;
    CACHE_TO_SQ_PACKET cache_to_sq_packet;
    // input [1:0] write_cache_ptr_move,
    logic write_cache_ptr_move; // 0 or 1
    logic branch_recovery;
    logic [`BRANCH_STACK_SIZE-1:0] branch_stack;
    logic [$clog2(`LSQ_SIZE):0] branch_recovery_sq_tail;
    logic [$clog2(`LSQ_SIZE):0] sq_head;
    logic [$clog2(`LSQ_SIZE):0] sq_tail;
    SQ_TO_LQ_PACKET sq_to_lq_packet;
    SQ_TO_CACHE_ENTRY sq_to_cache_packet;
    logic [1:0] entry_available;
    logic [`LSQ_SIZE-1:0] sq_complete;
    
    // SQ sq(
    //     .clock(clock),
    //     .reset(reset),
    //     .sq_reserve_packet(sq_reserve_packet),
    //     .sq_complete_packet(sq_complete_packet),
    //     .lq_to_sq_packet(lq_to_sq_packet),
    //     .rob_to_sq_packet(rob_to_sq_packet),
    //     .cache_to_sq_packet(cache_to_sq_packet),
    // // input [1:0] write_cache_ptr_move,
    //     .write_cache_ptr_move(write_cache_ptr_move), // 0 or 1
    //     .branch_recovery(branch_recovery),
    //     .branch_stack(branch_stack),
    //     .branch_recovery_sq_tail(branch_recovery_sq_tail),
    //     .sq_head(sq_head),
    //     .sq_tail(sq_tail),
    //     .sq_to_lq_packet(sq_to_lq_packet),
    //     .sq_to_cache_packet(sq_to_cache_packet),
    //     .entry_available(entry_available),
    //     .sq_complete(sq_complete)
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
    task display_sq_input;
        // input items
        input SQ_RESERVE_PACKET sq_reserve_packet;
        input FU_OUT_SQ_ENTRY [2:0] sq_complete_packet;
        input LQ_TO_SQ_PACKET lq_to_sq_packet;
        input ROB_TO_SQ_PACKET rob_to_sq_packet;
        input CACHE_TO_SQ_PACKET cache_to_sq_packet;
        input write_cache_ptr_move; // 0 or 1
        input branch_recovery;
        input [`BRANCH_STACK_SIZE-1:0] branch_stack;
        input [$clog2(`LSQ_SIZE):0] branch_recovery_sq_tail;

        //
        $write("\n");
        $display("================================================ LQ_input ================================================");
        $display("sq_reserve_packet:");
        $display(" Entry | instruction | PC       | branch_mask | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |",i );
        $write(" %-11h |", sq_reserve_packet.sq_reserve_entry[i].inst);
        $write(" %-8h |", sq_reserve_packet.sq_reserve_entry[i].PC);
        $write(" %-11b |", sq_reserve_packet.sq_reserve_entry[i].branch_mask);
        $write(" %-5b ", sq_reserve_packet.sq_reserve_entry[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("sq_complete_packet:");
        $display(" Entry | sq_idx | store_address | store_data | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |",i );
        $write(" %-6d |", sq_complete_packet[i].sq_idx);
        $write(" %-13h |", sq_complete_packet[i].store_address);
        $write(" %-10h |", sq_complete_packet[i].store_data);
        $write(" %-5b ", sq_complete_packet[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("lq_to_sq_packet:");
        $display(" Entry | address  | sq_idx | lq_idx | offset |valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |",i );
        $write(" %-8h |", lq_to_sq_packet.lq_to_sq_entry[i].address);
        $write(" %-6d |", lq_to_sq_packet.lq_to_sq_entry[i].sq_tail);
        $write(" %-6d | ", lq_to_sq_packet.lq_to_sq_entry[i].lq_idx);
        $write(" %-6d |", lq_to_sq_packet.lq_to_sq_entry[i].offset);
        $write(" %-5b ", lq_to_sq_packet.lq_to_sq_entry[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("rob_to_sq_packet:");
        $display(" Entry | sq_idx | valid ");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |",i );
        $write(" %-6d |", rob_to_sq_packet.sq_idx[i]);
        $write(" %-5b ", rob_to_sq_packet.valid[i]);
        $write("\n");
        end
        //
        $write("\n");
        $display("cache_to_sq_packet.cache_hit:");
        $display(" sq_idx | valid");
        $write(" %-6d |", cache_to_sq_packet.cache_hit_packet.sq_idx);
        $write(" %-5b ", cache_to_sq_packet.cache_hit_packet.valid);
        $write("\n");
        $display("cache_to_sq_packet.cache_miss:");
        $display(" Entry | sq_idx | valid");
        for (integer i = 0; i < 4; i ++) begin
        $write(" %-5d |",i );
        $write(" %-6d |", cache_to_sq_packet.cache_miss_packet[i].sq_idx);
        $write(" %-5b ", cache_to_sq_packet.cache_miss_packet[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("write_cache_ptr_move: %b" , write_cache_ptr_move);
        $display("branch_recovery: %b", branch_recovery);
        $display("branch_stack: %d", branch_stack);
        $display("branch_recovery_sq_tail: %d" , branch_recovery_sq_tail);
        $display("==========================================================================================================");
        $write("\n");
    endtask
 
        //

    task display_sq_output;
            // output items
        input logic[$clog2(`LSQ_SIZE):0] sq_head;
        input logic[$clog2(`LSQ_SIZE):0] sq_tail;
        input SQ_TO_LQ_PACKET sq_to_lq_packet;
        input SQ_TO_CACHE_ENTRY sq_to_cache_packet;
        input logic [1:0] entry_available;
        input logic [`LSQ_SIZE-1:0] sq_complete;
        $write("\n");
        $display("===============================================output_data================================================");
        $write("\n");
        $display("sq_to_lq_packet:");
        $display(" Entry |  data    | lq_idx | offset | complete | valid");
        for (integer i = 0; i < 3; i ++) begin
        $write(" %-5d |", i);
        $write(" %-9h |", sq_to_lq_packet.sq_to_lq_entry[i].data);
        $write(" %-6d |", sq_to_lq_packet.sq_to_lq_entry[i].lq_idx);
        $write(" %-6d |", sq_to_lq_packet.sq_to_lq_entry[i].offset);
        $write(" %-8b |", sq_to_lq_packet.sq_to_lq_entry[i].complete);
        $write(" %-5b ", sq_to_lq_packet.sq_to_lq_entry[i].valid);
        $write("\n");
        end
        //
        $write("\n");
        $display("sq_to_cache_packe:");
        $display(" instuction |  address  |   data   | branch_mask | sq_idx | offset | valid");
        $write(" %-10h |", sq_to_cache_packet.inst);
        $write(" %-9h |", sq_to_cache_packet.address);
        $write(" %-8h |", sq_to_cache_packet.data);
        $write(" %-11b |", sq_to_cache_packet.branch_mask);
        $write(" %-6d |", sq_to_cache_packet.sq_idx);
        $write(" %-6b |", sq_to_cache_packet.offset);
        $write(" %-5b", sq_to_cache_packet.valid);
        $write("\n");

        $write("\n");
        $display(" sq_head | sq_tail | entry available | sq_complete ");
        $write(" %-7d |", sq_head);
        $write(" %-7d |", sq_tail);
        $write(" %-15d |", entry_available);
        $write(" %-11b", sq_complete);
        $display("==========================================================================================================");
        $write("\n");
    endtask
        //
        task display_sq_data;
            // sq_data
            input SQ_ENTRY [`LSQ_SIZE-1:0] sq_data;
            input [$clog2(`LSQ_SIZE):0] head;
            input [$clog2(`LSQ_SIZE):0] tail;
            //
            $write("\n");
            $display("==============================================sq_data=====================================================");
            $display(" Entry | Head | trail | valid | complete | retire | cache_valid | branch_mask | address  |  data    | data_offset | PC       | instruction |  ");
            for (integer i = 0; i < 3; i ++) begin
            $write(" %-5d |", i);
            $write(" %-4d |", head);
            $write(" %-4d |", tail);
            $write(" %-5b |", sq_data[i].valid);
            $write(" %-8b |", sq_data[i].complete);
            $write(" %-6b |", sq_data[i].retire);
            $write(" %-11b |", sq_data[i].cache_valid);
            $write(" %-11b |", sq_data[i].branch_mask);
            $write(" %-8h |", sq_data[i].address);
            $write(" %-8h |", sq_data[i].data);
            $write(" %-11d |", sq_data[i].data_offset);
            $write(" %-8h |", sq_data[i].PC);
            $write(" %-11h ", sq_data[i].inst);

            $write("\n");
            end
            $display("==========================================================================================================");
            $write("\n");
        endtask
endmodule
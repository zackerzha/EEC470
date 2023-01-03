`timescale 1ns/100ps

module freelist(
    input clock,
    input reset,
    input ROB_OUT_PACKET [2:0] rob_packet,
    input logic [2:0] preg_out_num, //number of regs to be used
    input FREELIST_STATE_PACKET branch_stack_state,
    input logic squash,
    output FREELIST_OUT_PACKET fl_out,
    output FREELIST_STATE_PACKET current_state_out
    `ifdef DEBUG
    ,output logic [$clog2(`FREELIST_FIFO_SIZE):0] counto
    ,output FREELIST_ENTRY [`FREELIST_FIFO_SIZE-1:0] fl_data
    ,output logic [$clog2(`FREELIST_FIFO_SIZE):0] wrt_out
    ,output logic [$clog2(`FREELIST_FIFO_SIZE):0] rd_out
    `endif
);
    /*USAGE
    Moore machine:
    Will output the first three regs every cycle if available, if not available, valid is 0
    if preg_in_num is passed in at cycle x, preg_in_num regs will be added into the fifo at the same cycle
    if preg_out_num is passed in at cycle x, the writeptr will move at the same cycle, output regs will be updated in the next cycle
     */

    FREELIST_ENTRY [`FREELIST_FIFO_SIZE-1:0] free_list; //freelist
    FREELIST_ENTRY [`FREELIST_FIFO_SIZE-1:0] free_list_comb; //comb freelist

    logic [$clog2(`FL_SIZE)-1:0] preg_2b_freed_1;//add 1 bit to avoid saturation
    logic [$clog2(`FL_SIZE)-1:0] preg_2b_freed_2;
    logic [$clog2(`FL_SIZE)-1:0] preg_2b_freed_3;
    logic [$clog2(`FREELIST_FIFO_SIZE):0] write_ptr;
    logic [$clog2(`FREELIST_FIFO_SIZE):0] read_ptr;
    logic [$clog2(`FREELIST_FIFO_SIZE):0] write_ptr_comb;
    logic [$clog2(`FREELIST_FIFO_SIZE):0] read_ptr_comb;


    logic full;
    logic empty;
    logic [$clog2(`FREELIST_FIFO_SIZE):0] count;
    logic [1:0] preg_in_num;
    logic [2:0] valid_preg_in;

    assign full = count == `FREELIST_FIFO_SIZE;
    assign empty = count == 0;

    `ifdef DEBUG
    assign counto = count;
    assign fl_data = free_list;
    assign rd_out = read_ptr;
    assign wrt_out = write_ptr;
    `endif
    //output current state
    assign current_state_out.free_list = free_list_comb;
    assign current_state_out.write_ptr = write_ptr_comb;
    assign current_state_out.read_ptr = read_ptr;

    assign valid_preg_in[0] = rob_packet[0].is_wb_inst & rob_packet[0].retire_valid;
    assign valid_preg_in[1] = rob_packet[1].is_wb_inst & rob_packet[1].retire_valid;
    assign valid_preg_in[2] = rob_packet[2].is_wb_inst & rob_packet[2].retire_valid;
    assign preg_in_num = valid_preg_in[0] + valid_preg_in[1] + valid_preg_in[2];
     /*
    assign preg_2b_freed_1 = rob_packet[0].free_preg;
    assign preg_2b_freed_2 = rob_packet[1].free_preg;
    assign preg_2b_freed_3 = rob_packet[2].free_preg;
    */
    always_comb begin
        preg_2b_freed_1 = 0;
        preg_2b_freed_2 = 0;
        preg_2b_freed_3 = 0;

        if(valid_preg_in[0]) preg_2b_freed_1 = rob_packet[0].free_preg;
        else if(valid_preg_in[1]) preg_2b_freed_1 = rob_packet[1].free_preg;
        else if(valid_preg_in[2]) preg_2b_freed_1 = rob_packet[2].free_preg;

        if(&valid_preg_in[1:0]) preg_2b_freed_2 = rob_packet[1].free_preg;
        else if (^valid_preg_in[1:0]) preg_2b_freed_2 = rob_packet[2].free_preg;

        if(preg_in_num == 3) preg_2b_freed_3 = rob_packet[2].free_preg;
    end

    always_comb begin //free regs
        free_list_comb = free_list;
        if(preg_in_num == 3) begin
            free_list_comb[write_ptr].renamed_preg = preg_2b_freed_1;
            if(write_ptr + 1 >= `FREELIST_FIFO_SIZE) free_list_comb[0].renamed_preg = preg_2b_freed_2;
            else free_list_comb[write_ptr+1].renamed_preg = preg_2b_freed_2;
            if(write_ptr + 2 >= `FREELIST_FIFO_SIZE) free_list_comb[write_ptr + 2 - `FREELIST_FIFO_SIZE].renamed_preg = preg_2b_freed_3;
            else free_list_comb[write_ptr+2].renamed_preg = preg_2b_freed_3;
        end
        else if(preg_in_num == 2) begin
            free_list_comb[write_ptr].renamed_preg = preg_2b_freed_1;
            if(write_ptr + 1 >= `FREELIST_FIFO_SIZE) free_list_comb[0].renamed_preg = preg_2b_freed_2;
            else free_list_comb[write_ptr+1].renamed_preg = preg_2b_freed_2;
        end
        else if(preg_in_num == 1) begin
            free_list_comb[write_ptr].renamed_preg = preg_2b_freed_1;
        end
    end
    // Satuating read ptr
    logic [$clog2(`FREELIST_FIFO_SIZE)-1:0] read_ptr_plus_0;
    logic [$clog2(`FREELIST_FIFO_SIZE)-1:0] read_ptr_plus_1;
    logic [$clog2(`FREELIST_FIFO_SIZE)-1:0] read_ptr_plus_2;

    assign read_ptr_plus_0 = read_ptr[$clog2(`FREELIST_FIFO_SIZE)-1:0];
    assign read_ptr_plus_1 = read_ptr + 1 == `FREELIST_FIFO_SIZE? '0: read_ptr[$clog2(`FREELIST_FIFO_SIZE)-1:0] + 1;
    assign read_ptr_plus_2 = read_ptr + 2 == `FREELIST_FIFO_SIZE + 0? '0:
                             read_ptr + 2 == `FREELIST_FIFO_SIZE + 1? 1 : read_ptr[$clog2(`FREELIST_FIFO_SIZE)-1:0] + 2;


    //forwarding if we have less than 3 regs but some regs are freed
    assign fl_out.freelist_out[0].renamed_preg = (count == 0 && preg_in_num >=1) ? preg_2b_freed_1 : free_list[read_ptr_plus_0].renamed_preg;
    assign fl_out.freelist_out[1].renamed_preg = (count == 0 && preg_in_num >=2) ? preg_2b_freed_2 :
                                    (count == 1 && preg_in_num >=1) ? preg_2b_freed_1 :
                                    free_list[read_ptr_plus_1].renamed_preg;
    assign fl_out.freelist_out[2].renamed_preg = (count == 0 && preg_in_num ==3) ? preg_2b_freed_3 :
                                    (count == 1 && preg_in_num >=2) ? preg_2b_freed_2 :
                                    (count == 2 && preg_in_num >=1) ? preg_2b_freed_1 :
                                    free_list[read_ptr_plus_2].renamed_preg;
    //assign valid bit
    assign fl_out.freelist_out[0].valid = (count == 0 && preg_in_num == 0) ? 0 : 1;
    assign fl_out.freelist_out[1].valid = ((count == 0 && preg_in_num <= 1) || (count == 1 && preg_in_num == 0)) ? 0 : 1;
    assign fl_out.freelist_out[2].valid = ((count == 0 && preg_in_num <= 2) || 
                              (count == 1 && preg_in_num <= 1) ||
                              (count == 2 && preg_in_num == 0)) ? 0 : 1;
    //calculate next ptrs
    assign read_ptr_comb = read_ptr + preg_out_num >= `FREELIST_FIFO_SIZE ? read_ptr + preg_out_num - `FREELIST_FIFO_SIZE : read_ptr + preg_out_num;
    assign write_ptr_comb = write_ptr + preg_in_num >= `FREELIST_FIFO_SIZE ? write_ptr + preg_in_num - `FREELIST_FIFO_SIZE : write_ptr + preg_in_num;

    always_comb begin
        if(write_ptr == read_ptr) count = 32;
        else if(write_ptr > read_ptr) count = write_ptr - read_ptr;
        else count = 32 - (read_ptr - write_ptr);
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            // count <= `FREELIST_FIFO_SIZE;
            write_ptr <= '0;
            read_ptr <= '0;
            for(integer unsigned i = 0; i < `FREELIST_FIFO_SIZE; i=i+1)begin
                free_list[i].renamed_preg <= i + 32;
                free_list[i].valid <= 1;
            end
        end
        else if(squash) begin
            write_ptr <= branch_stack_state.write_ptr;
            read_ptr <= branch_stack_state.read_ptr;
            free_list <= branch_stack_state.free_list;
        end
        else begin
            free_list <= free_list_comb;
            read_ptr <= read_ptr_comb;
            write_ptr <= write_ptr_comb;
            // count <= count + preg_in_num - preg_out_num;
        end
    end

endmodule
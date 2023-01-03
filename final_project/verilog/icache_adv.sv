//////////////////////////////////////////////////////////
// Module: icache                                       //
// Description: instruction cache with stream buffer    //
//////////////////////////////////////////////////////////
`timescale 1ns/100ps
`define CACHE_LINES 32
`define CACHE_LINE_BITS $clog2(`CACHE_LINES)

typedef struct packed {
	logic [63:0]                     data;
    logic [12 - `CACHE_LINE_BITS:0]  tags;
    logic                            valids;
} ICACHE_PACKET;

module icache(
    input clock,
    input reset,

    // Processor
    input [31:0] proc2Icache_addr,
    input fetch_valid, // Fetching address is valid
    output logic [1:0] [63:0] icache_data_out,
    output logic [1:0] data_valid,

    // Memory
    input [63:0] mem2proc_data,
    input [3:0] mem2proc_response,
    input [3:0] mem2proc_tag,
    output logic [31:0] icache2mem_addr,
    output logic icache2mem_read
);

    logic [`CACHE_LINE_BITS - 1:0] current_index, next_index;
    logic [12 - `CACHE_LINE_BITS:0] current_tag, next_tag;
    logic [31:0] next_addr;
    logic cache_miss;
    wor fetched; // The required addr has been fetched but not hear back from memory yet
    wor prefetch_fetched; // The potential prefetch addr has been fetched

    ICACHE_PACKET [`CACHE_LINES-1:0] icache_data;

    // Addr for next cache line
    assign next_addr = proc2Icache_addr + 8;
    // Calculate cache tag and index for current and next address
    assign {current_tag, current_index} = proc2Icache_addr[15:3];
    assign {next_tag, next_index} = next_addr[15:3];

    /*
        Cache reading to output
    */
    // Cache output
    assign icache_data_out[0] = icache_data[current_index].data;
    assign icache_data_out[1] = icache_data[next_index].data;
    // Second line will not be valid unless first line is valid
    assign data_valid[0] = icache_data[current_index].valids && (icache_data[current_index].tags == current_tag);
    assign data_valid[1] = data_valid[0] && icache_data[next_index].valids && (icache_data[next_index].tags == next_tag);

    /*
        Stream buffer, prefetch cache line in advance
    */
    logic [31:0] fetching_addr; // Current fetching address
    logic [31:0] prefetch_addr; // Address for prefetching
    logic prefetch_stall; // Prefetch stall for already fetching enough
    logic [`NUM_MEM_TAGS:0] [31:0] fetched_addr, fetched_addr_comb; // Addr that has been fetched and get that tag
    logic [`NUM_MEM_TAGS:0] fetched_valid, fetched_valid_comb; // Addr with this tag has been fetched in progress
    logic [31:0] last_read_addr; // Last valid read address from processor

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) last_read_addr <= 0;
        else if(fetch_valid) last_read_addr <= proc2Icache_addr;
        // Check alignment
        assert(!(|proc2Icache_addr[2:0]));
    end

    assign cache_miss = !data_valid[0] & fetch_valid;

    generate
        genvar i;
        for(i = 1; i <= `NUM_MEM_TAGS; i++) begin :foo
            assign fetched = cache_miss & (proc2Icache_addr == fetched_addr[i]) & fetched_valid[i];
            assign prefetch_fetched = (prefetch_addr == fetched_addr[i]) & fetched_valid[i];
        end
    endgenerate

    // Fetching addr
    // if cache miss and the miss address request has not been recorded in fetched_addr, fetching_addr = cache request addr, it will be recorded next cycle
    // if the request finishes, wr_addr get the address, next cycle written to icache: cache miss = 0, fetched_addr[tag] = 0, fetched = 0
    // other time: prefetch (current cache miss has been recorded in fetched_addr, request sent)
    always_comb begin
        fetching_addr = 0;
        icache2mem_read = 0;
        if(cache_miss & !fetched) begin
            fetching_addr = proc2Icache_addr;
            icache2mem_read = 1;
        end
        else if(!prefetch_stall & !prefetch_fetched) begin
            fetching_addr = prefetch_addr;
            icache2mem_read = 1;
        end
        // Not fetch when data is available in cache or fetched list
        if(icache_data[fetching_addr[7:3]].valids & (icache_data[fetching_addr[7:3]].tags == fetching_addr[15:8]))
            icache2mem_read = 0;
    end
    assign icache2mem_addr = fetching_addr;
    // Prefetch addr
    assign prefetch_stall = prefetch_addr > (last_read_addr + 16*8);
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) prefetch_addr <= 0;
        // everytime for a cache miss, prefetch the next addr
        else if(cache_miss & !fetched) prefetch_addr <= proc2Icache_addr + 8;
        // memory can still accept requests, keep prefetching next 
        else if(|mem2proc_response) prefetch_addr <= prefetch_addr + 8;
    end

    always_comb begin
        fetched_addr_comb = fetched_addr;
        fetched_valid_comb = fetched_valid;
        if(mem2proc_tag != 0) begin
            fetched_addr_comb[mem2proc_tag] = 0;
            fetched_valid_comb[mem2proc_tag] = 0;
        end
        if(mem2proc_response != 0) begin
            fetched_addr_comb[mem2proc_response] = fetching_addr;
            fetched_valid_comb[mem2proc_response] = 1;
        end
    end
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            fetched_addr <= '0;
            fetched_valid <= '0;
        end
        else begin
            fetched_addr <= fetched_addr_comb;
            fetched_valid <= fetched_valid_comb;
        end
    end

    /* 
        Writting Cache when memory return valid data
    */
    logic [31:0] wrt_addr;
    logic [`CACHE_LINE_BITS - 1:0] wrt_index;
    logic [12 - `CACHE_LINE_BITS:0] wrt_tag;
    logic mem_return_valid; // Memory return is valid for icache
    assign mem_return_valid = (|mem2proc_tag) & fetched_valid[mem2proc_tag];
    assign wrt_addr = fetched_addr[mem2proc_tag];
    assign {wrt_tag, wrt_index} = wrt_addr[15:3]; 

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            icache_data <= '0;
        end
        else if(mem_return_valid) begin
            icache_data[wrt_index].data     <=  mem2proc_data;
            icache_data[wrt_index].tags     <=  wrt_tag;
            icache_data[wrt_index].valids   <=  1'b1;
        end
        // assert(!(|wrt_addr ^ mem_return_valid)); // Wrt addr and mem_return_valid must be asserted together
    end
endmodule
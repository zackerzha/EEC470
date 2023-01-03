// Memory bus
/*
    Assign memory port to i-cache or d-cache
    D-cache get more priority over i-cache
*/
module membus(
    input clock,
    input reset,
    input [31:0] icache2mem_addr,
    input [31:0] dcache2mem_addr,
    input [1:0] dcache2mem_command,
    input icache2mem_read,
    input [3:0] mem2proc_response,

    output logic [3:0] bus2dcache_response,
    output logic [3:0] bus2icache_response,
    output logic [1:0] bus2mem_command,
    output logic [31:0] bus2mem_addr
);
    logic [1:0] counter;

    //always_ff @(posedge clock) begin
    //    if(reset) counter <= 0;
    //    else counter <= counter + 1;
    //end
    assign counter = 1;
    
    always_comb begin
        bus2dcache_response = 0;
        bus2icache_response = 0;
        bus2mem_command = BUS_NONE;
        bus2mem_addr = 0;
        // I-cache get priority when counter == 0
        if(!(|counter)) begin
            if(icache2mem_read) begin
                bus2mem_command = BUS_LOAD;
                bus2mem_addr = icache2mem_addr;
                bus2icache_response = mem2proc_response;
            end
            else if(dcache2mem_command != BUS_NONE) begin
                bus2mem_command = dcache2mem_command;
                bus2mem_addr = dcache2mem_addr;
                bus2dcache_response = mem2proc_response;
            end
        end
        // D-cache get priority in all other case
        else begin
            if(dcache2mem_command != BUS_NONE) begin
                bus2mem_command = dcache2mem_command;
                bus2mem_addr = dcache2mem_addr;
                bus2dcache_response = mem2proc_response;
            end
            else if(icache2mem_read) begin
                bus2mem_command = BUS_LOAD;
                bus2mem_addr = icache2mem_addr;
                bus2icache_response = mem2proc_response;
            end
        end
    end

endmodule
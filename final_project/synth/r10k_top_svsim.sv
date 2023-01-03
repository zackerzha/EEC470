`ifndef SYNTHESIS

//
// This is an automatically generated file from 
// dc_shell Version T-2022.03-SP3 -- Jul 12, 2022
//

// For simulation only. Do not modify.

module r10k_top_svsim(
    input         clock,                    	input         reset,                        
    	input [3:0]   mem2proc_response,        	input [63:0]  mem2proc_data,            	input [3:0]   mem2proc_tag,              	output logic [1:0]  proc2mem_command,    	output logic [32-1:0] proc2mem_addr,      	output logic [63:0] proc2mem_data,          
        output EXCEPTION_CODE   error_status,

        output ROB_OUT_PACKET [2:0] rob_out_packet_out,
    output DCACHE_SET [7:0] cache_data_out,
    output [64-1:0] [32-1:0] preg_out,
    output branch_correct_out,
    output branch_flush_out
);  

        

  r10k_top r10k_top( {>>{ clock }}, {>>{ reset }}, {>>{ mem2proc_response }}, 
        {>>{ mem2proc_data }}, {>>{ mem2proc_tag }}, {>>{ proc2mem_command }}, 
        {>>{ proc2mem_addr }}, {>>{ proc2mem_data }}, {>>{ error_status }}, 
        {>>{ rob_out_packet_out }}, {>>{ cache_data_out }}, {>>{ preg_out }}, 
        {>>{ branch_correct_out }}, {>>{ branch_flush_out }} );
endmodule
`endif

/////////////////////////////////////////////////////////////
// Module name: instruction buffer                         //
// Dependency:                                             //
// Description: fetch and output instructions.             //
/////////////////////////////////////////////////////////////
`ifndef __INSNBUFFER_V__
`define __INSNBUFFER_V__
`timescale 1ns/100ps


module insnbuffer(
    input clock,
    input reset,
    input flush, // flush all insn in buffer (branch)
    input branch_correct,
    input [3:0] branch_stack,
    input INST_BUF_PACKET [3:0] insnbuffer_input,
    input logic [1:0] headmove, // only used to calculate the next available space
    input [3:0][3:0] branch_stack_in,
    // input logic [2:0] tailmove, // determined in the insnbuffer
    // output INSN_BUFFER_ENTRY [2:0] insnbuffer_output, // just output next 3 insn
    output INST_BUF_PACKET [2:0] insnbuffer_output,
    output logic [2:0] available_entry,
    output logic [2:0] tailmove
    `ifdef DEBUG
    , output logic [$clog2(`INSN_BUFFER_SIZE)-1:0] tail_add [3:0]
    , output logic [$clog2(`INSN_BUFFER_SIZE)-1:0] head_add [2:0]
    , output INSN_BUFFER_STATE instruction_buffer
    , output INSN_BUFFER_STATE instruction_buffer_comb
    , output logic [$clog2(`INSN_BUFFER_SIZE):0] occupied_entry
    `endif
);

// define for synthesis in for loop
`ifndef DEBUG
// logic [2:0] tailmove;
INSN_BUFFER_STATE instruction_buffer;
INSN_BUFFER_STATE instruction_buffer_comb;
logic [$clog2(`INSN_BUFFER_SIZE):0] occupied_entry;
logic [$clog2(`INSN_BUFFER_SIZE)-1:0] tail_add [3:0];
logic [$clog2(`INSN_BUFFER_SIZE)-1:0] head_add [2:0];
`endif
// logic [1:0] internal_fwd;

// determine available entry with current head and tail
// allocate insn according to available entry
//if tail invalid - no valid insn inside
//assign occupied_entry = (instruction_buffer.insn_buffer_content[instruction_buffer.tail].insn_valid == 0) ? 0 : 
//                        (instruction_buffer.tail >= instruction_buffer.head) ? (instruction_buffer.tail - instruction_buffer.head + 1) :
//                        (instruction_buffer.tail + 8 - instruction_buffer.head + 1);
assign occupied_entry = (instruction_buffer.insn_buffer_content[instruction_buffer.head].valid == 0) ? 0 : 
                        (instruction_buffer.tail > instruction_buffer.head) ? (instruction_buffer.tail - instruction_buffer.head) :
                        (instruction_buffer.tail + 8 - instruction_buffer.head);
// assign headmove_real = (headmove > occupied_entry) ? occupied_entry : headmove;
// if branch met, insn_valid might equal to 0 if stall (not fetch insn after branch)
// assign tailmove = insnbuffer_input[0].insn_valid + insnbuffer_input[1].insn_valid + insnbuffer_input[2].insn_valid + insnbuffer_input[3].insn_valid;
// if tailmove smaller than available entry
// assign tailmove_real = (available_entry + headmove_real >= tailmove) ? tailmove : (available_entry + headmove_real);
logic detect_branch;
// assign output packet (from head)
always_comb begin
    detect_branch = 0;
    for (integer unsigned j = 0; j < 3; j = j+1) begin
        detect_branch = detect_branch | (|(instruction_buffer.insn_buffer_content[head_add[j]].branch_stack));
        if(!detect_branch | j == 0) begin
            insnbuffer_output[j].valid              = instruction_buffer.insn_buffer_content[head_add[j]].valid & !flush;
            insnbuffer_output[j].inst               = instruction_buffer.insn_buffer_content[head_add[j]].inst; 
            insnbuffer_output[j].PC                 = instruction_buffer.insn_buffer_content[head_add[j]].PC;
            insnbuffer_output[j].NPC                = instruction_buffer.insn_buffer_content[head_add[j]].NPC;
            insnbuffer_output[j].pred_pc            = instruction_buffer.insn_buffer_content[head_add[j]].pred_pc;
            insnbuffer_output[j].branch_mask        = branch_correct? instruction_buffer.insn_buffer_content[head_add[j]].branch_mask & ~branch_stack: instruction_buffer.insn_buffer_content[head_add[j]].branch_mask;
            insnbuffer_output[j].branch_stack       = instruction_buffer.insn_buffer_content[head_add[j]].branch_stack;
        end
        else begin
            insnbuffer_output[j].valid              = '0;
            insnbuffer_output[j].inst               = '0;
            insnbuffer_output[j].PC                 = '0;
            insnbuffer_output[j].NPC                = '0;
            insnbuffer_output[j].pred_pc            = '0;
            insnbuffer_output[j].branch_mask        = '0;
            insnbuffer_output[j].branch_stack       = '0;
        end
    end
end

// head move have been counted, based on this, decide how many insn in 4 can enter 
always_comb begin
    case(occupied_entry)
        `INSN_BUFFER_SIZE-3 : available_entry = 3'b011;
        `INSN_BUFFER_SIZE-2 : available_entry = 3'b010;
        `INSN_BUFFER_SIZE-1 : available_entry = 3'b001;
        `INSN_BUFFER_SIZE   : available_entry = 3'b0;
        default : available_entry = 3'b100;
    endcase
end
assign tailmove = (reset || flush) ? 0 : 
                    (available_entry < (insnbuffer_input[0].valid + insnbuffer_input[1].valid + insnbuffer_input[2].valid + insnbuffer_input[3].valid)) ? available_entry :
                    (insnbuffer_input[0].valid + insnbuffer_input[1].valid + insnbuffer_input[2].valid + insnbuffer_input[3].valid);

// headmove must be generated correctly, including the following two cases:
// if head is invalid, headmove must be zero
// if head = tail && valid, headmove must be one
//assign instruction_buffer_comb.head = ((instruction_buffer.insn_buffer_content[instruction_buffer.head].insn_valid == 0) || (instruction_buffer.head == instruction_buffer.tail)) ? 
//                                        ((headmove == 0) ? instruction_buffer.head : (instruction_buffer.head + headmove - 1)) :
//                                        instruction_buffer.head + headmove;
//assign instruction_buffer_comb.tail = (instruction_buffer.insn_buffer_content[instruction_buffer.tail].insn_valid == 0) ? 
//                                        ((tailmove == 0) ? instruction_buffer.tail : (instruction_buffer.tail + tailmove - 1)) :
//                                        instruction_buffer.tail + tailmove;
// if invalid, headmove must be zero, no need for if statement
assign instruction_buffer_comb.head = instruction_buffer.head + headmove; 
assign instruction_buffer_comb.tail = instruction_buffer.tail + tailmove;

// max headmove = 3, max tail move = 4(add tail)
// move head and tail accordingly
// case: like headmove = 3 while occuppied entry only 2?  (whether this could happen)
// assign tail_add[0] = (instruction_buffer.insn_buffer_content[instruction_buffer.tail].insn_valid == 0) ? instruction_buffer.tail : (instruction_buffer.tail + 1);
// assign tail_add[1] = (instruction_buffer.insn_buffer_content[instruction_buffer.tail].insn_valid == 0) ? (instruction_buffer.tail + 1) : (instruction_buffer.tail + 2);
// assign tail_add[2] = (instruction_buffer.insn_buffer_content[instruction_buffer.tail].insn_valid == 0) ? (instruction_buffer.tail + 2) : (instruction_buffer.tail + 3);
// assign tail_add[3] = (instruction_buffer.insn_buffer_content[instruction_buffer.tail].insn_valid == 0) ? (instruction_buffer.tail + 3) : (instruction_buffer.tail + 4);
assign tail_add[0] = instruction_buffer.tail;
assign tail_add[1] = instruction_buffer.tail + 1;
assign tail_add[2] = instruction_buffer.tail + 2;
assign tail_add[3] = instruction_buffer.tail + 3;

assign head_add[0] = instruction_buffer.head;
assign head_add[1] = instruction_buffer.head + 1;
assign head_add[2] = instruction_buffer.head + 2;

// update the instruction buffer
always_comb begin
    for (integer unsigned k = 0; k < `INSN_BUFFER_SIZE; k = k+1) begin
        instruction_buffer_comb.insn_buffer_content[k].valid = instruction_buffer.insn_buffer_content[k].valid;
        instruction_buffer_comb.insn_buffer_content[k].inst = instruction_buffer.insn_buffer_content[k].inst;
        instruction_buffer_comb.insn_buffer_content[k].PC = instruction_buffer.insn_buffer_content[k].PC;
        instruction_buffer_comb.insn_buffer_content[k].NPC = instruction_buffer.insn_buffer_content[k].NPC;
        instruction_buffer_comb.insn_buffer_content[k].pred_pc = instruction_buffer.insn_buffer_content[k].pred_pc;
        instruction_buffer_comb.insn_buffer_content[k].branch_mask = instruction_buffer.insn_buffer_content[k].branch_mask;
    end
    for (integer unsigned j = 0; j < 3; j = j+1) begin
        instruction_buffer_comb.insn_buffer_content[head_add[j]].valid = (headmove > j) ?  1'b0 : instruction_buffer.insn_buffer_content[head_add[j]].valid;
    end
    for (integer unsigned j = 0; j < 4; j = j+1) begin
        instruction_buffer_comb.insn_buffer_content[tail_add[j]].valid = (tailmove > j) ?  1'b1 : instruction_buffer_comb.insn_buffer_content[tail_add[j]].valid;
        instruction_buffer_comb.insn_buffer_content[tail_add[j]].inst = (tailmove > j) ?  insnbuffer_input[j].inst : instruction_buffer.insn_buffer_content[tail_add[j]].inst;
        instruction_buffer_comb.insn_buffer_content[tail_add[j]].PC = (tailmove > j) ?  insnbuffer_input[j].PC : instruction_buffer.insn_buffer_content[tail_add[j]].PC;
        instruction_buffer_comb.insn_buffer_content[tail_add[j]].NPC = (tailmove > j) ?  insnbuffer_input[j].NPC : instruction_buffer.insn_buffer_content[tail_add[j]].NPC;
        instruction_buffer_comb.insn_buffer_content[tail_add[j]].pred_pc = (tailmove > j) ?  insnbuffer_input[j].pred_pc : instruction_buffer.insn_buffer_content[tail_add[j]].pred_pc;
        instruction_buffer_comb.insn_buffer_content[tail_add[j]].branch_mask = (tailmove > j) ?  insnbuffer_input[j].branch_mask : instruction_buffer.insn_buffer_content[tail_add[j]].branch_mask;
        // instruction_buffer_comb.insn_buffer_content[tail_add[j]].branch_stack = (tailmove > j) ?  insnbuffer_input[j].branch_stack : instruction_buffer.insn_buffer_content[tail_add[j]].branch_stack;
    end
    for (integer unsigned k = 0; k < `INSN_BUFFER_SIZE; k = k+1) begin
        instruction_buffer_comb.insn_buffer_content[k].branch_mask = branch_correct? instruction_buffer_comb.insn_buffer_content[k].branch_mask & ~branch_stack: instruction_buffer_comb.insn_buffer_content[k].branch_mask;
    end
end

always_comb begin
    for (integer unsigned k = 0; k < `INSN_BUFFER_SIZE; k = k+1) begin
        instruction_buffer_comb.insn_buffer_content[k].branch_stack = instruction_buffer.insn_buffer_content[k].branch_stack;
    end
    for (integer unsigned j = 0; j < 4; j = j+1) begin
        instruction_buffer_comb.insn_buffer_content[tail_add[j]].branch_stack = (tailmove > j) ?  branch_stack_in[j] : instruction_buffer.insn_buffer_content[tail_add[j]].branch_stack;
    end
end

//synopsys sync_set_reset "reset"
always_ff @(posedge clock) begin
    if (reset || flush) begin
        instruction_buffer.insn_buffer_content <= '0;
        instruction_buffer.head <= '0;
        instruction_buffer.tail <= '0;
    end
    else begin
        instruction_buffer.insn_buffer_content <= instruction_buffer_comb.insn_buffer_content;
        instruction_buffer.head <= instruction_buffer_comb.head;
        instruction_buffer.tail <= instruction_buffer_comb.tail;
    end
end

endmodule

`endif // __INSNBUFFER_V__
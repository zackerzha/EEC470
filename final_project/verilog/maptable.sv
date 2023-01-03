/////////////////////////////////////////////////////////////
// Module name: maptable                                   //
// Dependency:                                             //
// Description: maptable can store the register renaming.  //
/////////////////////////////////////////////////////////////
`ifndef __MAPTABLE_V__
`define __MAPTABLE_V__
`timescale 1ns/100ps

module maptable(
    input clock,
    input reset,
    input MAPTABLE_IN_PACKET_RENAME maptable_in_packet_rename,
    input MAPTABLE_IN_PACKET_RECOVERY maptable_in_packet_recovery,
    input [5:0][$clog2(`LOGIC_REG_SIZE)-1:0] lreg_read_in , // 6 registers that try to read the maptable
    input CDB_PACKET [2:0] cdb_in,
    output MAPTABLE_OUT_PACKET maptable_out_packet,
    output MAPTABLE_STATE current_state_out // Current maptable state that can be checked out by branch stack
);
    MAPTABLE_STATE maptable, maptable_comb;

    assign current_state_out = maptable;

    // Maptable register
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            // Fill maptable with default value during reset
            for(int i = 0; i < `LOGIC_REG_SIZE; i++) begin
                maptable.lreg[i].valid <= 1'b1;
                maptable.lreg[i].renamed_preg <= i;
            end
        end
        else if(maptable_in_packet_recovery.branch_recover) begin
            maptable <= maptable_in_packet_recovery.maptable_branchstack;
        end
        else begin
            maptable <= maptable_comb;
        end
    end

    // Unpack input
    //logic [$clog2(`LOGIC_REG_SIZE)-1:0] [2:0] renaming_lreg ;
    logic [2:0] [$clog2(`LOGIC_REG_SIZE)-1:0] renaming_lreg ;
    //logic [$clog2(`FL_SIZE)-1:0] [2:0] renaming_preg;
    logic [2:0] [$clog2(`FL_SIZE)-1:0] renaming_preg;
    logic [2:0] renaming_valid;
    logic [5:0][$clog2(`LOGIC_REG_SIZE)-1:0] lreg_read;
    assign renaming_lreg = maptable_in_packet_rename.renaming_lreg;
    assign renaming_preg = maptable_in_packet_rename.renaming_preg;
    assign renaming_valid = maptable_in_packet_rename.renaming_valid;
    assign lreg_read = lreg_read_in;

    // Updated maptable
    always_comb begin
        maptable_comb = maptable;
        // Update maptable for renaming reg
        if(renaming_valid[0]) begin
            maptable_comb.lreg[renaming_lreg[0]].renamed_preg = renaming_preg[0];
            maptable_comb.lreg[renaming_lreg[0]].valid = 1'b0;
        end
        if(renaming_valid[1]) begin
            maptable_comb.lreg[renaming_lreg[1]].renamed_preg = renaming_preg[1];
            maptable_comb.lreg[renaming_lreg[1]].valid = 1'b0;
        end
        if(renaming_valid[2]) begin
            maptable_comb.lreg[renaming_lreg[2]].renamed_preg = renaming_preg[2];
            maptable_comb.lreg[renaming_lreg[2]].valid = 1'b0;
        end
        // Update valid bit according to CDB
        // Update only when CDB preg match preg in maptable entry
        if(cdb_in[0].complete_valid) begin
            if(cdb_in[0].complete_preg == maptable_comb.lreg[cdb_in[0].complete_lreg].renamed_preg)
            maptable_comb.lreg[cdb_in[0].complete_lreg].valid = 1'b1;
        end
        if(cdb_in[1].complete_valid) begin
            if(cdb_in[1].complete_preg == maptable_comb.lreg[cdb_in[1].complete_lreg].renamed_preg)
            maptable_comb.lreg[cdb_in[1].complete_lreg].valid = 1'b1;
        end
        if(cdb_in[2].complete_valid) begin
            if(cdb_in[2].complete_preg == maptable_comb.lreg[cdb_in[2].complete_lreg].renamed_preg)
            maptable_comb.lreg[cdb_in[2].complete_lreg].valid = 1'b1;
        end
    end
    
    // Assign output
    logic [2:0][$clog2(`FL_SIZE)-1:0] old_renamed_preg;
    MAPTABLE_ENTRY [5:0] lreg_read_out;
    assign maptable_out_packet.old_renamed_preg = old_renamed_preg;
    assign maptable_out_packet.lreg_read_out = lreg_read_out;
    always_comb begin
        old_renamed_preg[0] = '0;
        old_renamed_preg[1] = '0;
        old_renamed_preg[2] = '0;

        if(renaming_valid[0]) begin
            old_renamed_preg[0] = maptable.lreg[renaming_lreg[0]].renamed_preg;
        end

        if(renaming_valid[1]) begin
            if(renaming_valid[0] & renaming_lreg[0] == renaming_lreg[1]) 
                old_renamed_preg[1] = renaming_preg[0];
            else old_renamed_preg[1] = maptable.lreg[renaming_lreg[1]].renamed_preg;
        end

        if(renaming_valid[2]) begin
            if(renaming_valid[1] & renaming_lreg[1] == renaming_lreg[2]) 
                old_renamed_preg[2] = renaming_preg[1];
            else if(renaming_valid[0] & renaming_lreg[0] == renaming_lreg[2]) 
                old_renamed_preg[2] = renaming_preg[0];
            else old_renamed_preg[2] = maptable.lreg[renaming_lreg[2]].renamed_preg;
        end
    end

    // Output for maptable read
    // Return updated preg if the lreg is renaming in current cycle
    always_comb begin
        // Instruction 1
        lreg_read_out[0] = maptable.lreg[lreg_read[0]];
        lreg_read_out[1] = maptable.lreg[lreg_read[1]];

        // Instruction 2
        if(lreg_read[2] == renaming_lreg[0] & renaming_valid[0]) begin
            lreg_read_out[2].renamed_preg = renaming_preg[0];
            lreg_read_out[2].valid = 1'b0;
        end
        else lreg_read_out[2] = maptable.lreg[lreg_read[2]];

        if(lreg_read[3] == renaming_lreg[0] & renaming_valid[0]) begin
            lreg_read_out[3].renamed_preg = renaming_preg[0];
            lreg_read_out[3].valid = 1'b0;
        end
        else lreg_read_out[3] = maptable.lreg[lreg_read[3]];

        // Instruction 3
        if(lreg_read[4] == renaming_lreg[1] & renaming_valid[1]) begin
            lreg_read_out[4].renamed_preg = renaming_preg[1];
            lreg_read_out[4].valid = 1'b0;
        end
        else if(lreg_read[4] == renaming_lreg[0] & renaming_valid[0]) begin
            lreg_read_out[4].renamed_preg = renaming_preg[0];
            lreg_read_out[4].valid = 1'b0;
        end
        else lreg_read_out[4] = maptable.lreg[lreg_read[4]];

        if(lreg_read[5] == renaming_lreg[1] & renaming_valid[1]) begin
            lreg_read_out[5].renamed_preg = renaming_preg[1];
            lreg_read_out[5].valid = 1'b0;
        end
        else if(lreg_read[5] == renaming_lreg[0] & renaming_valid[0]) begin
            lreg_read_out[5].renamed_preg = renaming_preg[0];
            lreg_read_out[5].valid = 1'b0;
        end
        else lreg_read_out[5] = maptable.lreg[lreg_read[5]];
    end

    // always_comb begin
    //     // Instruction 1
    //     lreg_read_out[0] = maptable.lreg[lreg_read[0]];
    //     lreg_read_out[1] = maptable.lreg[lreg_read[1]];

    //     // Instruction 2
    //     lreg_read_out[2] = maptable.lreg[lreg_read[2]];
    //     lreg_read_out[3] = maptable.lreg[lreg_read[3]];

    //     // Instruction 3
    //     lreg_read_out[4] = maptable.lreg[lreg_read[4]];
    //     lreg_read_out[5] = maptable.lreg[lreg_read[5]];
    // end
endmodule

`endif // __MAPTABLE_V__
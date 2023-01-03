/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  regfile.v                                           //
//                                                                     //
//  Description :  This module creates the Regfile used by the ID and  // 
//                 WB Stages of the Pipeline.                          //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __REGFILE_V__
`define __REGFILE_V__

`timescale 1ns/100ps

module regfile(
        input   PRF_READIN_PACKET rd_idx,   // 6 read idx input
	      input	  PRF_WRITE_PACKET wr_in,    		    // 3 write index
        input         wr_clk,
        input reset,

        output PRF_READOUT_PACKET readout,   // read data

        output [`FL_SIZE-1:0] [`XLEN-1:0] preg_out
      );
  
 reg    [`FL_SIZE-1:0] [`XLEN-1:0] registers;   // 32, 64-bit Registers
 assign preg_out = registers;
  wire   [`XLEN-1:0] rda_reg = registers[rd_idx.prf_readin_packet[0].inst_source1_preg];
  wire   [`XLEN-1:0] rdb_reg = registers[rd_idx.prf_readin_packet[0].inst_source2_preg];
  wire   [`XLEN-1:0] rdc_reg = registers[rd_idx.prf_readin_packet[1].inst_source1_preg];
  wire   [`XLEN-1:0] rdd_reg = registers[rd_idx.prf_readin_packet[1].inst_source2_preg];
  wire   [`XLEN-1:0] rde_reg = registers[rd_idx.prf_readin_packet[2].inst_source1_preg];
  wire   [`XLEN-1:0] rdf_reg = registers[rd_idx.prf_readin_packet[2].inst_source2_preg];

  assign readout.prf_readout_packet[0].inst_source1_value = rda_reg;
  assign readout.prf_readout_packet[0].inst_source2_value = rdb_reg;
  assign readout.prf_readout_packet[1].inst_source1_value = rdc_reg;
  assign readout.prf_readout_packet[1].inst_source2_value = rdd_reg;
  assign readout.prf_readout_packet[2].inst_source1_value = rde_reg;
  assign readout.prf_readout_packet[2].inst_source2_value = rdf_reg;
/*
  //
  // Read port A
  //
  always_comb
    if (rd_idx.prf_readin_packet[0].inst_source1_preg == `ZERO_REG)
      readout.prf_readout_packet[0].inst_source1_value = 0;
    else if (wr_in.prf_write_packet[0].write_enable && (wr_in.prf_write_packet[0].preg_to_write == rd_idx.prf_readin_packet[0].inst_source1_preg))
      readout.prf_readout_packet[0].inst_source1_value = wr_in.prf_write_packet[0].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[1].write_enable && (wr_in.prf_write_packet[1].preg_to_write == rd_idx.prf_readin_packet[0].inst_source1_preg))
      readout.prf_readout_packet[0].inst_source1_value = wr_in.prf_write_packet[1].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[2].write_enable && (wr_in.prf_write_packet[2].preg_to_write == rd_idx.prf_readin_packet[0].inst_source1_preg))
      readout.prf_readout_packet[0].inst_source1_value = wr_in.prf_write_packet[2].preg_value;  // internal forwarding
    else
      readout.prf_readout_packet[0].inst_source1_value = rda_reg;

  //
  // Read port B
  //
  always_comb
    if (rd_idx.prf_readin_packet[0].inst_source2_preg == `ZERO_REG)
      readout.prf_readout_packet[0].inst_source2_value = 0;
    else if (wr_in.prf_write_packet[0].write_enable && (wr_in.prf_write_packet[0].preg_to_write == rd_idx.prf_readin_packet[0].inst_source2_preg))
      readout.prf_readout_packet[0].inst_source2_value = wr_in.prf_write_packet[0].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[1].write_enable && (wr_in.prf_write_packet[1].preg_to_write == rd_idx.prf_readin_packet[0].inst_source2_preg))
      readout.prf_readout_packet[0].inst_source2_value = wr_in.prf_write_packet[1].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[2].write_enable && (wr_in.prf_write_packet[2].preg_to_write == rd_idx.prf_readin_packet[0].inst_source2_preg))
      readout.prf_readout_packet[0].inst_source2_value = wr_in.prf_write_packet[2].preg_value;  // internal forwarding
    else
      readout.prf_readout_packet[0].inst_source2_value = rdb_reg;
  // Read port C
  //
  always_comb
    if (rd_idx.prf_readin_packet[1].inst_source1_preg == `ZERO_REG)
      readout.prf_readout_packet[1].inst_source1_value = 0;
    else if (wr_in.prf_write_packet[0].write_enable && (wr_in.prf_write_packet[0].preg_to_write == rd_idx.prf_readin_packet[1].inst_source1_preg))
      readout.prf_readout_packet[1].inst_source1_value = wr_in.prf_write_packet[0].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[1].write_enable && (wr_in.prf_write_packet[1].preg_to_write == rd_idx.prf_readin_packet[1].inst_source1_preg))
      readout.prf_readout_packet[1].inst_source1_value = wr_in.prf_write_packet[1].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[2].write_enable && (wr_in.prf_write_packet[2].preg_to_write == rd_idx.prf_readin_packet[1].inst_source1_preg))
      readout.prf_readout_packet[1].inst_source1_value = wr_in.prf_write_packet[2].preg_value;  // internal forwarding
    else
      readout.prf_readout_packet[1].inst_source1_value = rdc_reg;
  // Read port D
  //
  always_comb
    if (rd_idx.prf_readin_packet[1].inst_source2_preg == `ZERO_REG)
      readout.prf_readout_packet[1].inst_source2_value = 0;
    else if (wr_in.prf_write_packet[0].write_enable && (wr_in.prf_write_packet[0].preg_to_write == rd_idx.prf_readin_packet[1].inst_source2_preg))
      readout.prf_readout_packet[1].inst_source2_value = wr_in.prf_write_packet[0].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[1].write_enable && (wr_in.prf_write_packet[1].preg_to_write == rd_idx.prf_readin_packet[1].inst_source2_preg))
      readout.prf_readout_packet[1].inst_source2_value = wr_in.prf_write_packet[1].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[2].write_enable && (wr_in.prf_write_packet[2].preg_to_write == rd_idx.prf_readin_packet[1].inst_source2_preg))
      readout.prf_readout_packet[1].inst_source2_value = wr_in.prf_write_packet[2].preg_value;  // internal forwarding
    else
      readout.prf_readout_packet[1].inst_source2_value = rdd_reg;
  // Read port E
  //
  always_comb
    if (rd_idx.prf_readin_packet[2].inst_source1_preg == `ZERO_REG)
      readout.prf_readout_packet[2].inst_source1_value = 0;
    else if (wr_in.prf_write_packet[0].write_enable && (wr_in.prf_write_packet[0].preg_to_write == rd_idx.prf_readin_packet[2].inst_source1_preg))
      readout.prf_readout_packet[2].inst_source1_value = wr_in.prf_write_packet[0].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[1].write_enable && (wr_in.prf_write_packet[1].preg_to_write == rd_idx.prf_readin_packet[2].inst_source1_preg))
      readout.prf_readout_packet[2].inst_source1_value = wr_in.prf_write_packet[1].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[2].write_enable && (wr_in.prf_write_packet[2].preg_to_write == rd_idx.prf_readin_packet[2].inst_source1_preg))
      readout.prf_readout_packet[2].inst_source1_value = wr_in.prf_write_packet[2].preg_value;  // internal forwarding
    else
      readout.prf_readout_packet[2].inst_source1_value = rde_reg;

  // Read port B
  //
  always_comb
    if (rd_idx.prf_readin_packet[2].inst_source2_preg == `ZERO_REG)
      readout.prf_readout_packet[2].inst_source2_value = 0;
    else if (wr_in.prf_write_packet[0].write_enable && (wr_in.prf_write_packet[0].preg_to_write == rd_idx.prf_readin_packet[2].inst_source2_preg))
      readout.prf_readout_packet[2].inst_source2_value = wr_in.prf_write_packet[0].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[2].write_enable && (wr_in.prf_write_packet[1].preg_to_write == rd_idx.prf_readin_packet[2].inst_source2_preg))
      readout.prf_readout_packet[2].inst_source2_value = wr_in.prf_write_packet[1].preg_value;  // internal forwarding
    else if (wr_in.prf_write_packet[2].write_enable && (wr_in.prf_write_packet[2].preg_to_write == rd_idx.prf_readin_packet[2].inst_source2_preg))
      readout.prf_readout_packet[2].inst_source2_value = wr_in.prf_write_packet[2].preg_value;  // internal forwarding
    else
      readout.prf_readout_packet[2].inst_source2_value = rdf_reg;
*/
  //
  // Write port
  //
  //synopsys sync_set_reset "reset"
  always_ff @(posedge wr_clk) begin
    if(reset) begin
      registers <= '0;
    end
    else begin
    if (wr_in.write_enable[0]) begin
        registers[wr_in.prf_write_packet[0].preg_to_write] <= wr_in.prf_write_packet[0].preg_value;
    end
    if (wr_in.write_enable[1]) begin  
	registers[wr_in.prf_write_packet[1].preg_to_write] <= wr_in.prf_write_packet[1].preg_value;
    end
    if (wr_in.write_enable[2]) begin 
	registers[wr_in.prf_write_packet[2].preg_to_write] <= wr_in.prf_write_packet[2].preg_value;
    end
    end
    // Assertion 
    assert(!((wr_in.write_enable[0] & wr_in.write_enable[1]) & (wr_in.prf_write_packet[0].preg_to_write == wr_in.prf_write_packet[1].preg_to_write)));
    assert(!((wr_in.write_enable[0] & wr_in.write_enable[2]) & (wr_in.prf_write_packet[0].preg_to_write == wr_in.prf_write_packet[2].preg_to_write)));
    assert(!((wr_in.write_enable[1] & wr_in.write_enable[2]) & (wr_in.prf_write_packet[1].preg_to_write == wr_in.prf_write_packet[2].preg_to_write)));
    assert(!(wr_in.write_enable[0] & wr_in.prf_write_packet[0].preg_to_write == 0));
    assert(!(wr_in.write_enable[1] & wr_in.prf_write_packet[1].preg_to_write == 0));
    assert(!(wr_in.write_enable[2] & wr_in.prf_write_packet[2].preg_to_write == 0));
end
endmodule // regfile
`endif //__REGFILE_V__

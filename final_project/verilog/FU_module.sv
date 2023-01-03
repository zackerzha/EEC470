//
// The ALU
//
// given the command code CMD and proper operands A and B, compute the
// result of the instruction
//
// This module is purely combinational
//
`timescale 1ns/100ps
module alu(
	input [`XLEN-1:0] opa,
	input [`XLEN-1:0] opb,
	ALU_FUNC     func,

	output logic [`XLEN-1:0] result
);
	wire signed [`XLEN-1:0] signed_opa, signed_opb;
	assign signed_opa = opa;
	assign signed_opb = opb;

	always_comb begin
		case (func)
			ALU_ADD:      result = opa + opb;
			ALU_SUB:      result = opa - opb;
			ALU_AND:      result = opa & opb;
			ALU_SLT:      result = signed_opa < signed_opb;
			ALU_SLTU:     result = opa < opb;
			ALU_OR:       result = opa | opb;
			ALU_XOR:      result = opa ^ opb;
			ALU_SRL:      result = opa >> opb[4:0];
			ALU_SLL:      result = opa << opb[4:0];
			ALU_SRA:      result = signed_opa >>> opb[4:0]; // arithmetic from logical shift
			default:      result = `XLEN'hfacebeec;  // here to prevent latches
		endcase
	end
endmodule // alu

//
// BrCond module
//
// Given the instruction code, compute the proper condition for the
// instruction; for branches this condition will indicate whether the
// target is taken.
//
// This module is purely combinational
//
module brcond(// Inputs
	input [`XLEN-1:0] rs1,    // Value to check against condition
	input [`XLEN-1:0] rs2,
	input  [2:0] func,  // Specifies which condition to check

	output logic cond    // 0/1 condition result (False/True)
);

	logic signed [`XLEN-1:0] signed_rs1, signed_rs2;
	assign signed_rs1 = rs1;
	assign signed_rs2 = rs2;
	always_comb begin
		cond = 0;
		case (func)
			3'b000: cond = signed_rs1 == signed_rs2;  // BEQ
			3'b001: cond = signed_rs1 != signed_rs2;  // BNE
			3'b100: cond = signed_rs1 < signed_rs2;   // BLT
			3'b101: cond = signed_rs1 >= signed_rs2;  // BGE
			3'b110: cond = rs1 < rs2;                 // BLTU
			3'b111: cond = rs1 >= rs2;                // BGEU
		endcase
	end
	
endmodule // brcond




module mult(
				input clock, reset,
				input [`XLEN-1:0] mcand, mplier,
				input start_mult,
				input ALU_FUNC func_in,
				input FU_IN_ENTRY mult_inst_data,
				input branch_recovery,
				input branch_correct,
				input [`BRANCH_STACK_SIZE-1:0] branch_stack,
			
				output FU_IN_ENTRY mult_inst_data_out,
				output [`XLEN-1:0] product,
				output done
			);
  
	logic start;
	logic [(2*`XLEN)-1:0] mcand_out, mplier_out;
	logic [`depth:0][2*`XLEN-1:0] internal_products, internal_mcands, internal_mpliers;
	logic [`depth:0] internal_dones;

	logic [(2*`XLEN-1):0] mcand_1;     // the real one that gets implemented
	logic [(2*`XLEN-1):0] mplier_1;    // the real one that gets implemented

	logic  [(2*`XLEN-1):0] signed_mcand;
	logic  [(2*`XLEN-1):0] signed_mplier;
	logic  [(2*`XLEN-1):0] unsigned_mcand;
	logic  [(2*`XLEN-1):0] unsigned_mplier;
	logic  [(2*`XLEN)-1:0] product_0;       // one level before the real product

	FU_IN_ENTRY [`depth:0] mult_data_array;


	assign start = start_mult; //& ((func_in == ALU_MUL) | (func_in == ALU_MULH) 
					//| (func_in == ALU_MULHSU) | (func_in == ALU_MULHU));

	assign signed_mcand = {{(`XLEN){mcand[(`XLEN-1)]}}, mcand};
	assign signed_mplier = {{(`XLEN){mplier[(`XLEN-1)]}}, mplier};;
	assign unsigned_mcand = {{(`XLEN){1'b0}}, mcand};
	assign unsigned_mplier = {{(`XLEN){1'b0}}, mplier};

	assign internal_mcands[0]   = mcand_1;
	assign internal_mpliers[0]  = mplier_1;
	assign internal_products[0] = 'h0;
	assign internal_dones[0]    = start;
	assign product_0 = internal_products[`depth];
	assign mult_data_array[0] = mult_inst_data;

	always_comb begin
		if (func_in == ALU_MUL || func_in == ALU_MULH) begin
			mcand_1 = signed_mcand;
			mplier_1 = signed_mplier;
		end

		else if ((func_in == ALU_MULHSU) || (func_in == ALU_MULHU)) begin
			mcand_1 = unsigned_mcand;
			mplier_1 = unsigned_mplier;
		end

		else begin
			mcand_1 = 0;
			mplier_1 = 0;
		end
	end

	generate
		genvar i;
		for (i = 0; i < `depth; ++i) begin : mstage
			mult_stage ms (
				.clock(clock),
				.reset(reset),
				.product_in(internal_products[i]),
				.mplier_in(internal_mpliers[i]),
				.mcand_in(internal_mcands[i]),
				.start(internal_dones[i]),
				.mult_inst_data(mult_data_array[i]),

				.branch_recovery(branch_recovery),
				.branch_stack(branch_stack),
				.branch_correct(branch_correct),
				
				.product_out(internal_products[i+1]),
				.mplier_out(internal_mpliers[i+1]),
				.mcand_out(internal_mcands[i+1]),
				.done(internal_dones[i+1]),
				.mult_inst_data_out(mult_data_array[i+1])
			);
		end
	endgenerate

	assign mult_inst_data_out = mult_data_array[`depth];

	assign done    = internal_dones[`depth];

	assign product = ((mult_inst_data_out.alu_function == ALU_MULH) || (mult_inst_data_out.alu_function == ALU_MULHSU) || (mult_inst_data_out.alu_function == ALU_MULHU)) ?
						product_0[(2*`XLEN-1):`XLEN] : product_0[(`XLEN-1):0];

endmodule


module mult_stage(
					input clock, reset, start,
					input [(2*`XLEN)-1:0] product_in, 
					input [(2*`XLEN)-1:0] mplier_in, mcand_in,
					input FU_IN_ENTRY mult_inst_data,

					input branch_recovery,
					input branch_correct,
					input [`BRANCH_STACK_SIZE-1:0] branch_stack,
	
					output logic done,
					output logic [(2*`XLEN)-1:0] product_out, mplier_out, mcand_out,
					output FU_IN_ENTRY mult_inst_data_out
				);
    parameter  depth = 2;
	parameter  bits_num = (2*`XLEN)>>($clog2(depth));

	FU_IN_ENTRY mult_inst_data_out_temp;

	logic complete;
	logic [(2*`XLEN)-1:0] prod_in_reg, partial_prod_reg;
	logic [(2*`XLEN)-1:0] partial_product, next_mplier, next_mcand;
	logic squash_after_branch;

	assign product_out = prod_in_reg + partial_prod_reg;
	assign partial_product = mplier_in[(bits_num-1):0] * mcand_in;
	assign next_mplier = {{bits_num{1'b0}}, mplier_in[(2*`XLEN)-1:bits_num]};
	assign next_mcand = {mcand_in[((2*`XLEN)-bits_num-1):0], {bits_num{1'b0}}};

	//synopsys sync_set_reset "reset"
	always_ff @(posedge clock) begin
		if(reset) begin
			prod_in_reg      			<= '0;
			partial_prod_reg   			<= '0;
			mplier_out       			<= '0;
			mcand_out        			<= '0;
			mult_inst_data_out_temp 	<= '0;
		end
		else begin
			prod_in_reg      			<= product_in;
			partial_prod_reg   			<= partial_product;
			mplier_out       			<= next_mplier;
			mcand_out        			<= next_mcand;
			mult_inst_data_out_temp 	<= mult_inst_data;
		end
	end

	// synopsys sync_set_reset "reset"
	always_ff @(posedge clock) begin
		if(reset) begin
			complete <= 1'b0;
		end
		else begin
			complete <= start;
		end
	end

	always_comb begin
		mult_inst_data_out = mult_inst_data_out_temp;
		mult_inst_data_out.branch_mask = branch_correct ? mult_inst_data_out_temp.branch_mask & ~branch_stack : mult_inst_data_out_temp.branch_mask;
	end

	assign squash_after_branch = branch_recovery & (|(mult_inst_data_out.branch_mask & branch_stack)) & mult_inst_data_out.valid;

	assign done = squash_after_branch ? 1'b0 : complete;
endmodule

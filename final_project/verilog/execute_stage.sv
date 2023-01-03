`timescale 1ns/100ps
module execute_stage(
    input clock,
    input reset,
    input FU_IN_PACKET fu_in,
    input branch_recovery,
    input branch_correct,
    input [`BRANCH_STACK_SIZE-1:0] branch_stack,

    // send packet to cdb (in the same cycle), including
    // 1. the data write to prf
    // 2. preg_idx
    // send packet to fetch and branch prediction
    // 1. the branch address and taken/not taken
    // send packet to lsq
    // 1. the data send to lsq, including address and store value
    output FU_OUT_PACKET fu_out_packet
);
    FU_IN_PACKET fu_in_reg;
    logic [2:0][`XLEN-1:0] opa_mux_out;
    logic [2:0][`XLEN-1:0] opb_mux_out;

    logic [2:0][`XLEN-1:0] alu_result;
    logic cond_branch_result;
    logic [`XLEN-1:0] mult_result;
    logic mult_done;

    FU_IN_ENTRY mult_inst_data_out;

    logic [`XLEN-1:0] branch_operand1;
    logic [`XLEN-1:0] branch_operand2;

    logic [`XLEN-1:0] mult_opa;
    logic [`XLEN-1:0] mult_opb;

    FU_OUT_CDB_ENTRY [3:0] fu_cdb_packet;
    FU_OUT_BRANCH_ENTRY fu_cond_branch_packet;
    FU_OUT_BRANCH_ENTRY [2:0] fu_uncond_branch_packet;
    FU_OUT_SQ_ENTRY[2:0] fu_sq_packet;
    FU_OUT_LQ_ENTRY[2:0] fu_lq_packet;
    ALU_RESULT_PACKET alu_result_packet;
    ALU_RESULT_PACKET alu_result_packet_comb;

    logic [2:0] is_opa_forward;
    logic [2:0][`XLEN-1:0] opa_forward_data;
    logic [2:0] is_opb_forward;
    logic [2:0][`XLEN-1:0] opb_forward_data;

    logic [`XLEN-1:0] mult_opa_forward_data;
    logic  is_mult_opa_forward;
    logic [`XLEN-1:0] mult_opb_forward_data;
    logic  is_mult_opb_forward;

    logic [2:0] squash_after_branch;

    // the register between issue and execute
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset)
            fu_in_reg <= '0;
        else
            fu_in_reg <= fu_in;
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset)
            alu_result_packet <= '0;
        else begin
            alu_result_packet <= alu_result_packet_comb;
        end
    end

    generate
        genvar m;
        for(m = 0; m < 3; m=m+1) begin : alu
            assign alu_result_packet_comb.preg_to_write[m] = fu_in_reg.fu_in_packet[m].renamed_preg;
            assign alu_result_packet_comb.value[m]         = alu_result[m];
            assign alu_result_packet_comb.valid[m]         = fu_in_reg.fu_in_packet[m].valid & (!fu_in_reg.fu_in_packet[m].is_cond_branch_inst) & (!fu_in_reg.fu_in_packet[m].is_store_inst) & (!fu_in_reg.fu_in_packet[m].is_load_inst) & fu_in_reg.fu_in_packet[m].is_wb_inst;
        end

        for(m = 0; m < 3; m=m+1) begin : is_operand_forward
            assign is_opa_forward[m] = (alu_result_packet.preg_to_write[0] == fu_in_reg.fu_in_packet[m].rs1_idx && alu_result_packet.valid[0]) | (alu_result_packet.preg_to_write[1] == fu_in_reg.fu_in_packet[m].rs1_idx && alu_result_packet.valid[1]) | (alu_result_packet.preg_to_write[2] == fu_in_reg.fu_in_packet[m].rs1_idx && alu_result_packet.valid[2]);
            assign is_opb_forward[m] = (alu_result_packet.preg_to_write[0] == fu_in_reg.fu_in_packet[m].rs2_idx && alu_result_packet.valid[0]) | (alu_result_packet.preg_to_write[1] == fu_in_reg.fu_in_packet[m].rs2_idx && alu_result_packet.valid[1]) | (alu_result_packet.preg_to_write[2] == fu_in_reg.fu_in_packet[m].rs2_idx && alu_result_packet.valid[2]);
        end
    endgenerate

    // set the forward data from alu for operandA
    always_comb begin
        opa_forward_data = '0;
        for (integer unsigned i = 0; i < 3; i=i+1) begin
            if (alu_result_packet.preg_to_write[0] == fu_in_reg.fu_in_packet[i].rs1_idx && alu_result_packet.valid[0])
                opa_forward_data[i] = alu_result_packet.value[0];
            else if (alu_result_packet.preg_to_write[1] == fu_in_reg.fu_in_packet[i].rs1_idx  && alu_result_packet.valid[1])
                opa_forward_data[i] = alu_result_packet.value[1];
            else if (alu_result_packet.preg_to_write[2] == fu_in_reg.fu_in_packet[i].rs1_idx  && alu_result_packet.valid[2])
                opa_forward_data[i] = alu_result_packet.value[2];
        end
    end
    // set the forward data from alu for operandB
    always_comb begin
        opb_forward_data = '0;
        for (integer unsigned i = 0; i < 3; i=i+1) begin
            if (alu_result_packet.preg_to_write[0] == fu_in_reg.fu_in_packet[i].rs2_idx && alu_result_packet.valid[0])
                opb_forward_data[i] = alu_result_packet.value[0];
            else if (alu_result_packet.preg_to_write[1] == fu_in_reg.fu_in_packet[i].rs2_idx && alu_result_packet.valid[1])
                opb_forward_data[i] = alu_result_packet.value[1];
            else if (alu_result_packet.preg_to_write[2] == fu_in_reg.fu_in_packet[i].rs2_idx && alu_result_packet.valid[2])
                opb_forward_data[i] = alu_result_packet.value[2];
        end
    end


    assign is_mult_opa_forward = (alu_result_packet_comb.preg_to_write[0] == fu_in.fu_in_packet[3].rs1_idx && alu_result_packet_comb.valid[0]) | (alu_result_packet_comb.preg_to_write[1] == fu_in.fu_in_packet[3].rs1_idx && alu_result_packet_comb.valid[1]) | (alu_result_packet_comb.preg_to_write[2] == fu_in.fu_in_packet[3].rs1_idx && alu_result_packet_comb.valid[2]);
    assign is_mult_opb_forward = (alu_result_packet_comb.preg_to_write[0] == fu_in.fu_in_packet[3].rs2_idx && alu_result_packet_comb.valid[0]) | (alu_result_packet_comb.preg_to_write[1] == fu_in.fu_in_packet[3].rs2_idx && alu_result_packet_comb.valid[1]) | (alu_result_packet_comb.preg_to_write[2] == fu_in.fu_in_packet[3].rs2_idx && alu_result_packet_comb.valid[2]);
    // set the forward data for mult operandA
    always_comb begin
        mult_opa_forward_data = '0;
        if (alu_result_packet_comb.preg_to_write[0] == fu_in.fu_in_packet[3].rs1_idx  && alu_result_packet_comb.valid[0])
            mult_opa_forward_data = alu_result_packet_comb.value[0];
        else if (alu_result_packet_comb.preg_to_write[1] == fu_in.fu_in_packet[3].rs1_idx  && alu_result_packet_comb.valid[1])
            mult_opa_forward_data = alu_result_packet_comb.value[1];
        else if (alu_result_packet_comb.preg_to_write[2] == fu_in.fu_in_packet[3].rs1_idx  && alu_result_packet_comb.valid[2])
            mult_opa_forward_data = alu_result_packet_comb.value[2];
    end
    // set the forward data for mult operandB
    always_comb begin
        mult_opb_forward_data = '0;
        if (alu_result_packet_comb.preg_to_write[0] == fu_in.fu_in_packet[3].rs2_idx)
            mult_opb_forward_data = alu_result_packet_comb.value[0];
        else if (alu_result_packet_comb.preg_to_write[1] == fu_in.fu_in_packet[3].rs2_idx)
            mult_opb_forward_data = alu_result_packet_comb.value[1];
        else if (alu_result_packet_comb.preg_to_write[2] == fu_in.fu_in_packet[3].rs2_idx)
            mult_opb_forward_data = alu_result_packet_comb.value[2];
    end

    // assign is_mult_opa_forward = (alu_result_packet.preg_to_write[0] == fu_in_reg.fu_in_packet[3].rs1_idx && alu_result_packet.valid[0]) | (alu_result_packet.preg_to_write[1] == fu_in_reg.fu_in_packet[3].rs1_idx && alu_result_packet.valid[1]) | (alu_result_packet.preg_to_write[2] == fu_in_reg.fu_in_packet[3].rs1_idx && alu_result_packet.valid[2]);
    // assign is_mult_opb_forward = (alu_result_packet.preg_to_write[0] == fu_in_reg.fu_in_packet[3].rs2_idx && alu_result_packet.valid[0]) | (alu_result_packet.preg_to_write[1] == fu_in_reg.fu_in_packet[3].rs2_idx && alu_result_packet.valid[1]) | (alu_result_packet.preg_to_write[2] == fu_in_reg.fu_in_packet[3].rs2_idx && alu_result_packet.valid[2]);
    // // set the forward data for mult operandA
    // always_comb begin
    //     mult_opa_forward_data = '0;
    //     if (alu_result_packet.preg_to_write[0] == fu_in_reg.fu_in_packet[3].rs1_idx  && alu_result_packet.valid[0])
    //         mult_opa_forward_data = alu_result_packet.value[0];
    //     else if (alu_result_packet.preg_to_write[1] == fu_in_reg.fu_in_packet[3].rs1_idx  && alu_result_packet.valid[1])
    //         mult_opa_forward_data = alu_result_packet.value[1];
    //     else if (alu_result_packet.preg_to_write[2] == fu_in_reg.fu_in_packet[3].rs1_idx  && alu_result_packet.valid[2])
    //         mult_opa_forward_data = alu_result_packet.value[2];
    // end
    // // set the forward data for mult operandB
    // always_comb begin
    //     mult_opb_forward_data = '0;
    //     if (alu_result_packet.preg_to_write[0] == fu_in_reg.fu_in_packet[3].rs2_idx)
    //         mult_opb_forward_data = alu_result_packet.value[0];
    //     else if (alu_result_packet.preg_to_write[1] == fu_in_reg.fu_in_packet[3].rs2_idx)
    //         mult_opb_forward_data = alu_result_packet.value[1];
    //     else if (alu_result_packet.preg_to_write[2] == fu_in_reg.fu_in_packet[3].rs2_idx)
    //         mult_opb_forward_data = alu_result_packet.value[2];
    // end


    always_comb begin
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            opa_mux_out[i] = `XLEN'hdeadfbac;
		    case (fu_in_reg.fu_in_packet[i].opa_select)
                OPA_IS_RS1:  opa_mux_out[i] = is_opa_forward[i] ? opa_forward_data[i] : fu_in_reg.fu_in_packet[i].rs1_value;
                OPA_IS_NPC:  opa_mux_out[i] = fu_in_reg.fu_in_packet[i].PC+4;
                OPA_IS_PC:   opa_mux_out[i] = fu_in_reg.fu_in_packet[i].PC;
                OPA_IS_ZERO: opa_mux_out[i] = 0;
		    endcase
        end
    end

    always_comb begin
        for(integer unsigned i = 0; i < 3; i=i+1) begin
            opb_mux_out[i] = `XLEN'hdeadfbac;
            case (fu_in_reg.fu_in_packet[i].opb_select)
                OPB_IS_RS2:   opb_mux_out[i] = is_opb_forward[i] ? opb_forward_data[i] : fu_in_reg.fu_in_packet[i].rs2_value;
                OPB_IS_I_IMM: opb_mux_out[i] = `RV32_signext_Iimm(fu_in_reg.fu_in_packet[i].inst);
                OPB_IS_S_IMM: opb_mux_out[i] = `RV32_signext_Simm(fu_in_reg.fu_in_packet[i].inst);
                OPB_IS_B_IMM: opb_mux_out[i] = `RV32_signext_Bimm(fu_in_reg.fu_in_packet[i].inst);
                OPB_IS_U_IMM: opb_mux_out[i] = `RV32_signext_Uimm(fu_in_reg.fu_in_packet[i].inst);
                OPB_IS_J_IMM: opb_mux_out[i] = `RV32_signext_Jimm(fu_in_reg.fu_in_packet[i].inst);
            endcase
        end
    end

    assign squash_after_branch[0] = branch_recovery & (|(branch_stack & fu_in_reg.fu_in_packet[0].branch_mask)) & fu_in_reg.fu_in_packet[0].valid;
    assign squash_after_branch[1] = branch_recovery & (|(branch_stack & fu_in_reg.fu_in_packet[1].branch_mask)) & fu_in_reg.fu_in_packet[1].valid;
    assign squash_after_branch[2] = branch_recovery & (|(branch_stack & fu_in_reg.fu_in_packet[2].branch_mask)) & fu_in_reg.fu_in_packet[2].valid;

    alu alu_0(
        .opa(opa_mux_out[0]),
        .opb(opb_mux_out[0]),
        .func(fu_in_reg.fu_in_packet[0].alu_function),

        .result(alu_result[0])
    );

    alu alu_1(
        .opa(opa_mux_out[1]),
        .opb(opb_mux_out[1]),
        .func(fu_in_reg.fu_in_packet[1].alu_function),

        .result(alu_result[1])
    );

    alu alu_2(
        .opa(opa_mux_out[2]),
        .opb(opb_mux_out[2]),
        .func(fu_in_reg.fu_in_packet[2].alu_function),

        .result(alu_result[2])
    );

    assign branch_operand1 = is_opa_forward[fu_in_reg.inst_branch_idx] ? opa_forward_data[fu_in_reg.inst_branch_idx] : fu_in_reg.fu_in_packet[fu_in_reg.inst_branch_idx].rs1_value;
    assign branch_operand2 = is_opb_forward[fu_in_reg.inst_branch_idx] ? opb_forward_data[fu_in_reg.inst_branch_idx] : fu_in_reg.fu_in_packet[fu_in_reg.inst_branch_idx].rs2_value;
    brcond brcond(
        .rs1(branch_operand1),
		.rs2(branch_operand2),
		.func(fu_in_reg.fu_in_packet[fu_in_reg.inst_branch_idx].inst.b.funct3), // inst bits to determine check

		// Output
		.cond(cond_branch_result)
    );

    // because that the mult module already has the register between issue and execute
    // so the input of mult module is pure combinational logic which is fu_in instead of fu_in_reg
    logic mult_valid;
    logic mult_valid_reg;
    logic [`XLEN-1:0] mult_opa_reg;
    logic [`XLEN-1:0] mult_opb_reg;
    FU_IN_ENTRY fu_mult_packet;

    assign mult_valid = !(branch_recovery & |(branch_stack & fu_in.fu_in_packet[3].branch_mask)) & fu_in.fu_in_packet[3].valid;
    assign mult_opa = is_mult_opa_forward ? mult_opa_forward_data : fu_in.fu_in_packet[3].rs1_value;
    assign mult_opb = is_mult_opb_forward ? mult_opb_forward_data : fu_in.fu_in_packet[3].rs2_value;
    always_comb begin
        fu_mult_packet = fu_in_reg.fu_in_packet[3];
        if(branch_correct) begin
            fu_mult_packet.branch_mask = fu_in_reg.fu_in_packet[3].branch_mask & (~branch_stack);
        end
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            mult_valid_reg <= 0;
            mult_opa_reg <= 0;
            mult_opb_reg <= 0;
        end
        else begin
            mult_valid_reg <= mult_valid;
            mult_opa_reg <= mult_opa;
            mult_opb_reg <= mult_opb;
        end
    end


    mult mult(
        .clock(clock),
        .reset(reset),
        .mcand(mult_opa_reg),
        .mplier(mult_opb_reg),
        .start_mult(mult_valid_reg  & (!(branch_recovery & |(branch_stack & fu_in_reg.fu_in_packet[3].branch_mask)))),// if there is a valid mult instruction buffer send to mult FU
        .func_in(fu_in_reg.fu_in_packet[3].alu_function),
        //.mult_inst_data(fu_in_reg.fu_in_packet[3]),
        .mult_inst_data(fu_mult_packet),
        .branch_recovery(branch_recovery),
        .branch_correct(branch_correct),
        .branch_stack(branch_stack),

        .mult_inst_data_out(mult_inst_data_out),
        .product(mult_result),
        .done(mult_done)
    );


    // generate fu_cdb_packet
    // exclude load instruction becasue load instruction can not complete at execute stage
    generate
        genvar i;
        for(i = 0; i < 3; i=i+1) begin : fu_cdb
            assign fu_cdb_packet[i].preg_to_write = fu_cdb_packet[i].valid ? fu_in_reg.fu_in_packet[i].renamed_preg : 0;
            assign fu_cdb_packet[i].lreg_to_write = fu_cdb_packet[i].valid ? fu_in_reg.fu_in_packet[i].inst.r.rd : 0;
            assign fu_cdb_packet[i].preg_value    = fu_cdb_packet[i].valid ? (fu_in_reg.fu_in_packet[i].is_uncond_branch_inst ? fu_in_reg.fu_in_packet[i].PC + 4 : alu_result[i]) : 0;
            assign fu_cdb_packet[i].rob_tail      = fu_in_reg.fu_in_packet[i].rob_tail;
            assign fu_cdb_packet[i].is_wb_inst    = fu_in_reg.fu_in_packet[i].is_wb_inst;
            assign fu_cdb_packet[i].branch_mask   = branch_correct ? fu_in_reg.fu_in_packet[i].branch_mask & ~branch_stack : fu_in_reg.fu_in_packet[i].branch_mask;
            assign fu_cdb_packet[i].valid         = fu_in_reg.fu_in_packet[i].valid & (!fu_in_reg.fu_in_packet[i].is_load_inst) & ~squash_after_branch[i];// for the valid instruction which use alu can all complete except load instruction
        end
    endgenerate
    // for mult FU
    assign fu_cdb_packet[3].preg_to_write = mult_inst_data_out.renamed_preg;
    assign fu_cdb_packet[3].lreg_to_write = mult_inst_data_out.inst.r.rd;
    assign fu_cdb_packet[3].preg_value    = mult_result;
    assign fu_cdb_packet[3].rob_tail      = mult_inst_data_out.rob_tail;
    assign fu_cdb_packet[3].is_wb_inst    = 1'b1;
    assign fu_cdb_packet[3].branch_mask   = mult_inst_data_out.branch_mask;
    assign fu_cdb_packet[3].valid         = mult_done;

    // generate fu_cond_branch_packet
    FU_OUT_BRANCH_ENTRY fu_cond_branch_packet_reg;

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            fu_cond_branch_packet_reg <= '0;
        end
        else begin
            fu_cond_branch_packet_reg <= fu_cond_branch_packet;
        end
    end

    assign fu_cond_branch_packet.branch_result  = fu_in_reg.branch_valid ? cond_branch_result : 1'b0;
    assign fu_cond_branch_packet.branch_address = alu_result[fu_in_reg.inst_branch_idx];
    assign fu_cond_branch_packet.NPC            = fu_in_reg.fu_in_packet[fu_in_reg.inst_branch_idx].pred_pc;
    assign fu_cond_branch_packet.PC             = fu_in_reg.fu_in_packet[fu_in_reg.inst_branch_idx].PC;
    assign fu_cond_branch_packet.branch_mask    = branch_correct ? fu_in_reg.fu_in_packet[fu_in_reg.inst_branch_idx].branch_mask & ~branch_stack : fu_in_reg.fu_in_packet[fu_in_reg.inst_branch_idx].branch_mask;
    assign fu_cond_branch_packet.branch_stack   = fu_in_reg.fu_in_packet[fu_in_reg.inst_branch_idx].branch_stack;
    assign fu_cond_branch_packet.is_jalr        = 1'b0;
    assign fu_cond_branch_packet.valid          = fu_in_reg.branch_valid & (!(branch_recovery & |(branch_stack & fu_in_reg.fu_in_packet[fu_in_reg.inst_branch_idx].branch_mask)));



    // generate fu_uncond_branch_packet
    generate
        genvar j;
        for(j = 0; j < 3; j=j+1) begin : fu_branch
            assign fu_uncond_branch_packet[j].branch_result    = 1'b1;
            assign fu_uncond_branch_packet[j].branch_address   = alu_result[j];
            assign fu_uncond_branch_packet[j].NPC              = fu_in_reg.fu_in_packet[j].pred_pc;
            assign fu_uncond_branch_packet[j].PC               = fu_in_reg.fu_in_packet[j].PC;
            assign fu_uncond_branch_packet[j].branch_mask      = branch_correct ? fu_in_reg.fu_in_packet[j].branch_mask & ~branch_stack : fu_in_reg.fu_in_packet[j].branch_mask;
            assign fu_uncond_branch_packet[j].branch_stack     = fu_in_reg.fu_in_packet[j].branch_stack;
            assign fu_uncond_branch_packet[j].is_jalr          = fu_in_reg.fu_in_packet[j].opa_select == OPA_IS_RS1;
            assign fu_uncond_branch_packet[j].valid            = fu_in_reg.fu_in_packet[j].valid & fu_in_reg.fu_in_packet[j].is_uncond_branch_inst & ~squash_after_branch[j];
        end
    endgenerate

    // gneerate fu_sq_packet and fu_lq_packet
    generate
        genvar k;
        for(k = 0; k < 3; k=k+1) begin : fu_sq
            assign fu_sq_packet[k].sq_idx        = fu_in_reg.fu_in_packet[k].sq_idx;
            assign fu_sq_packet[k].store_address = alu_result[k];
            // forward the alu result as rs2 value when the instruction is store and has RAW
            assign fu_sq_packet[k].store_data    = is_opb_forward[k] ? opb_forward_data[k] : fu_in_reg.fu_in_packet[k].rs2_value;
            assign fu_sq_packet[k].valid         = fu_in_reg.fu_in_packet[k].valid & fu_in_reg.fu_in_packet[k].is_store_inst & ~squash_after_branch[k];
        end
    endgenerate

    generate
        genvar l;
        for(l = 0; l < 3; l=l+1) begin : fu_lq
            assign fu_lq_packet[l].lq_idx        = fu_in_reg.fu_in_packet[l].lq_idx;
            assign fu_lq_packet[l].load_address  = alu_result[l];
            assign fu_lq_packet[l].valid         = fu_in_reg.fu_in_packet[l].valid & fu_in_reg.fu_in_packet[l].is_load_inst & ~squash_after_branch[l];
        end
    endgenerate

    assign fu_out_packet.fu_cdb_packet           = fu_cdb_packet;
    assign fu_out_packet.fu_cond_branch_packet   = fu_cond_branch_packet_reg;//fu_cond_branch_packet;
    assign fu_out_packet.fu_uncond_branch_packet = fu_uncond_branch_packet;
    assign fu_out_packet.fu_sq_packet            = fu_sq_packet;
    assign fu_out_packet.fu_lq_packet            = fu_lq_packet;


endmodule

module mini_riscv (
    input  logic clk,
    input  logic rst_n,

    // Instruction Memory Interface
    output logic [31:0] pc,
    input  logic [31:0] instr,

    // Retirement Monitor Interface (For our Python Testbench to spy on!)
    output logic        retire_valid,
    output logic [4:0]  retire_reg,
    output logic [31:0] retire_data
);

    // ========================================================================
    // 0. The Register File (32 Registers, x0 is hardwired to 0)
    // ========================================================================
    logic [31:0] regfile [0:31];
    
    // ========================================================================
    // 1. FETCH STAGE (IF)
    // ========================================================================
    logic [31:0] next_pc;
    logic stall; // Hazard stall signal

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc <= 0;
        else if (!stall) pc <= next_pc; // Only advance PC if not stalled!
    end
    assign next_pc = pc + 4;

    // IF/ID Pipeline Register
    logic [31:0] if_id_pc, if_id_instr;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc <= 0;
            if_id_instr <= 32'h00000013; // NOP (ADDI x0, x0, 0)
        end else if (!stall) begin
            if_id_pc <= pc;
            if_id_instr <= instr;
        end
    end

    // ========================================================================
    // 2. DECODE STAGE (ID) & HAZARD DETECTION
    // ========================================================================
    logic [6:0] opcode;
    logic [4:0] rs1, rs2, rd;
    logic [31:0] imm;
    logic is_add, is_sub, is_addi;

    assign opcode = if_id_instr[6:0];
    assign rd     = if_id_instr[11:7];
    assign rs1    = if_id_instr[19:15];
    assign rs2    = if_id_instr[24:20];
    
    // I-Type Immediate extraction (Sign Extended)
    assign imm = {{20{if_id_instr[31]}}, if_id_instr[31:20]};

    // Instruction Decoding
    assign is_addi = (opcode == 7'b0010011);
    assign is_add  = (opcode == 7'b0110011 && if_id_instr[31:25] == 7'b0000000);
    assign is_sub  = (opcode == 7'b0110011 && if_id_instr[31:25] == 7'b0100000);

    logic reg_write_en;
    assign reg_write_en = (is_add | is_sub | is_addi) & (rd != 0);

    // Read Data from Register File
    logic [31:0] rs1_data, rs2_data;
    // Read Data with Internal Forwarding from the Writeback Stage!
    assign rs1_data = (rs1 == 0) ? 0 : 
                      (ex_wb_reg_write_en && (ex_wb_rd == rs1)) ? ex_wb_alu_out : 
                      regfile[rs1];
                      
    assign rs2_data = (rs2 == 0) ? 0 : 
                      (ex_wb_reg_write_en && (ex_wb_rd == rs2)) ? ex_wb_alu_out : 
                      regfile[rs2];

    // --- THE HAZARD DETECTION UNIT ---
    // If the EX stage is writing to a register that we need right now, STALL!
    logic id_ex_reg_write_en;
    logic [4:0] id_ex_rd;
    
    assign stall = id_ex_reg_write_en && (id_ex_rd != 0) && 
                   ((id_ex_rd == rs1) || (id_ex_rd == rs2 && !is_addi));

    // ID/EX Pipeline Register
    logic [31:0] id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    logic id_ex_is_add, id_ex_is_sub, id_ex_is_addi;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || stall) begin 
            // If stalled, insert a BUBBLE (turn the instruction into a NOP)
            id_ex_reg_write_en <= 0;
            id_ex_rd <= 0;
        end else begin
            id_ex_rs1_data <= rs1_data;
            id_ex_rs2_data <= rs2_data;
            id_ex_imm <= imm;
            id_ex_rd <= rd;
            id_ex_reg_write_en <= reg_write_en;
            id_ex_is_add <= is_add;
            id_ex_is_sub <= is_sub;
            id_ex_is_addi <= is_addi;
        end
    end

    // ========================================================================
    // 3. EXECUTE STAGE (EX)
    // ========================================================================
    logic [31:0] alu_out;
    logic [31:0] alu_op2;

    // MUX for ALU input 2 (Register vs Immediate)
    assign alu_op2 = id_ex_is_addi ? id_ex_imm : id_ex_rs2_data;

    // The ALU
    always_comb begin
        if (id_ex_is_sub) alu_out = id_ex_rs1_data - alu_op2;
        else              alu_out = id_ex_rs1_data + alu_op2; // ADD / ADDI
    end

    // EX/WB Pipeline Register
    logic ex_wb_reg_write_en;
    logic [4:0]  ex_wb_rd;
    logic [31:0] ex_wb_alu_out;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_wb_reg_write_en <= 0;
            ex_wb_rd <= 0;
        end else begin
            ex_wb_reg_write_en <= id_ex_reg_write_en;
            ex_wb_rd <= id_ex_rd;
            ex_wb_alu_out <= alu_out;
        end
    end

    // ========================================================================
    // 4. WRITEBACK STAGE (WB) & RETIREMENT
    // ========================================================================
    always_ff @(posedge clk) begin
        if (ex_wb_reg_write_en && ex_wb_rd != 0) begin
            regfile[ex_wb_rd] <= ex_wb_alu_out;
        end
    end

    // Broadcast retirement to the Python Testbench!
    assign retire_valid = ex_wb_reg_write_en;
    assign retire_reg   = ex_wb_rd;
    assign retire_data  = ex_wb_alu_out;

endmodule

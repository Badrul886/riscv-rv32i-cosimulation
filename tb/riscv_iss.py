class RiscvISS:
    """A pure software Golden Reference Model of a RISC-V RV32I Processor."""
    
    def __init__(self):
        # 32 architectural registers initialized to 0
        self.registers = [0] * 32

    def execute_instruction(self, instr_hex):
        """
        Takes a 32-bit compiled RISC-V instruction, decodes it, 
        and updates the software register state perfectly.
        """
        # 1. Decode standard RISC-V fields using bitmasks
        opcode = instr_hex & 0x7F
        rd     = (instr_hex >> 7) & 0x1F
        rs1    = (instr_hex >> 15) & 0x1F
        rs2    = (instr_hex >> 20) & 0x1F
        func7  = (instr_hex >> 25) & 0x7F
        
        # 2. Extract 12-bit immediate and sign-extend to 32 bits (for ADDI)
        imm = (instr_hex >> 20) & 0xFFF
        if imm & 0x800: # If the sign bit is 1, handle Python negative two's complement
            imm = imm - 0x1000 

        # 3. Rule: Register x0 is hardwired to zero. Never overwrite it.
        if rd == 0:
            return 
        
        rs1_val = self.registers[rs1]
        rs2_val = self.registers[rs2]

        # 4. Execute the math!
        if opcode == 0x33: 
            # R-Type Instructions (Register to Register)
            if func7 == 0x00:
                self.registers[rd] = (rs1_val + rs2_val) & 0xFFFFFFFF # ADD
            elif func7 == 0x20:
                self.registers[rd] = (rs1_val - rs2_val) & 0xFFFFFFFF # SUB
                
        elif opcode == 0x13: 
            # I-Type Instructions (Immediate)
            self.registers[rd] = (rs1_val + imm) & 0xFFFFFFFF         # ADDI
            
        return self.registers[rd]

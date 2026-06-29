import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly
from riscv_iss import RiscvISS

# Our compiled machine code program (Hexadecimal RISC-V instructions)
PROGRAM = [
    0x00a00093, # 1. ADDI x1, x0, 10
    0x01400113, # 2. ADDI x2, x0, 20
    0x002081b3, # 3. ADD  x3, x1, x2 (HAZARD: Needs x1 and x2)
    0x40118233, # 4. SUB  x4, x3, x1 (HAZARD: Needs x3)
    0x00000013, # NOP (Keeps pipeline moving at the end)
    0x00000013, # NOP
    0x00000013, # NOP
]

@cocotb.test()
async def test_step_and_compare(dut):
    """Hardware-Software Co-Simulation of a RISC-V Pipeline."""
    
    # 1. Boot up the Hardware Clock and the Software ISS
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    iss = RiscvISS()

    # 2. Virtual Instruction Memory (RAM) Coroutine
    async def instr_memory():
        """Acts as SRAM, feeding instructions to the processor based on its PC."""
        while True:
            await FallingEdge(dut.clk) # Read on falling edge to simulate SRAM speed
            pc = dut.pc.value.integer
            idx = pc // 4  # RISC-V PC increments by 4 bytes per instruction
            
            if idx < len(PROGRAM):
                dut.instr.value = PROGRAM[idx]
            else:
                dut.instr.value = 0x00000013 # Default to NOP if out of bounds

    # Start the memory running in the background
    cocotb.start_soon(instr_memory())

    # 3. Hardware Reset Sequence
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    
    dut._log.info("--- RISC-V BOOT SEQUENCE COMPLETE ---")
    dut._log.info("Initiating Step-and-Compare Verification...")

    # 4. The Step-and-Compare Loop
    instructions_retired = 0
    
    while instructions_retired < 4: # We have 4 real instructions to check
        await RisingEdge(dut.clk)
        await ReadOnly() # Freeze the simulator and check the wires!
        
        # Did the Hardware just finish (retire) an instruction?
        if dut.retire_valid.value == 1:
            hw_reg  = dut.retire_reg.value.integer
            hw_data = dut.retire_data.value.integer
            
            # Step the Software ISS forward by ONE instruction
            instr_hex = PROGRAM[instructions_retired]
            sw_data = iss.execute_instruction(instr_hex)
            
            dut._log.info(f"Instr {instructions_retired+1} Retired -> Write x{hw_reg}")
            dut._log.info(f"    Hardware calculated: {hw_data}")
            dut._log.info(f"    Software calculated: {sw_data}")
            
            # THE GOLDEN CHECK
            assert hw_data == sw_data, f"SILICON BUG DETECTED! Reg x{hw_reg} -> HW: {hw_data} != SW: {sw_data}"
            
            instructions_retired += 1

    dut._log.info("--- VERIFICATION SUCCESS ---")
    dut._log.info("The pipelined hardware perfectly matched the software golden model!")

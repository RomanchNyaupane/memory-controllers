# Simple SDRAM Controller

⚠️ **IMPORTANT DISCLAIMER** ⚠️

**This is NOT production-ready code and contains numerous bugs and limitations. This implementation is intended for educational purposes only to understand basic SDRAM controller concepts. Do not use this code in any production system or critical application.**

## Overview

This project implements a basic SDRAM controller in Verilog, designed to demonstrate fundamental concepts of SDRAM memory management. The controller provides a simple interface for read and write operations while handling the complex timing requirements of SDRAM devices.

## Architecture

### Module Structure

```
sdram_controller
├── refresh_counter.v    (External refresh timing module)
├── RCD_timer.v         (Row-to-Column Delay timing module)
└── Main controller logic
```

### Key Components

- **Main State Machine**: 9-state FSM handling SDRAM operations
- **External Timers**: Separate modules for refresh and RCD timing
- **Simple Interface**: 8-bit data width with basic control signals

## State Machine Logic

The controller implements a 9-state finite state machine:

### States Description

1. **INITIALIZATION (1)**: 
   - Waits for 100μs (14,310 clock cycles at 50MHz)
   - Applies NOP commands during initialization period
   - Transitions to PRECHARGE_ALL after initialization complete

2. **PRECHARGE_ALL (7)**:
   - Issues precharge all banks command
   - Prepares SDRAM for refresh operations
   - Sets addr_out[10] = 1 for all-bank precharge

3. **REFRESH (8)**:
   - Performs CBR (CAS-before-RAS) auto-refresh
   - Handles both initial refresh during startup and periodic refresh
   - Command: `{cke=1, cs_=0, ras_=0, cas_=0, wr_en_=1}`

4. **SET_MODE (9)**:
   - Configures SDRAM mode register
   - Sets burst length, CAS latency, and other parameters
   - Mode register value: `9'b0_00_011_0_000`

5. **IDLE (2)**:
   - Default waiting state for incoming requests
   - Monitors refresh interrupt and read/write requests
   - Enables refresh counter operation

6. **ACTIVATE (6)**:
   - Opens a specific row in a bank for access
   - Waits for RCD (Row-to-Column Delay) timing
   - Loads row address and bank address to SDRAM

7. **READ (3)**:
   - Performs read operation with auto-precharge
   - Sets addr_out[10] = 1 for auto-precharge
   - Grants read request and transitions to data input

8. **WRITE (4)**:
   - Performs write operation with auto-precharge
   - Transfers write data to SDRAM
   - Grants write request

9. **DATA_IN (10)**:
   - Captures read data from SDRAM
   - Sets read data valid flag
   - Returns to IDLE state

10. **NOP (5)**:
    - No Operation state for timing delays
    - Provides necessary wait cycles between operations
    - Uses nop_count for delay management

### State Transition Flow

```
INITIALIZATION → PRECHARGE_ALL → REFRESH → SET_MODE → IDLE
                                    ↑         ↓
                                IDLE ←→ ACTIVATE → READ/WRITE
                                    ↑              ↓
                                    ←── DATA_IN ←──
```

## Interface Signals

### Input Signals
- `clk`: System clock (50MHz assumed)
- `reset`: Active high reset
- `rd_req`: Read request from master
- `wr_req`: Write request from master
- `in_addr[23:0]`: 24-bit address input
- `wr_data[7:0]`: 8-bit write data
- `bank_addr[1:0]`: Bank address (Note: Redundant with in_addr)
- `rd_data_o[7:0]`: Read data from SDRAM chip

### Output Signals
- `rd_data[7:0]`: Read data to master
- `wr_gnt`: Write request grant
- `rd_gnt`: Read request grant  
- `rd_data_valid`: Read data valid flag
- `wr_data_o[7:0]`: Write data to SDRAM
- `addr_out[11:0]`: Address output to SDRAM
- `bank_out[1:0]`: Bank address to SDRAM
- `cke, cas_, ras_, wr_en_, cs_`: SDRAM control signals

## Address Mapping

The 24-bit input address is mapped as follows:
- `in_addr[23:22]`: Bank address (2 bits)
- `in_addr[21:12]`: Row address (10 bits) 
- `in_addr[11:2]`: Column address (10 bits)
- `in_addr[1:0]`: Byte select (unused in 8-bit interface)

## Timing Parameters

- **Initialization Delay**: 14,310 clock cycles (100μs at 50MHz)
- **RCD Delay**: Handled by external RCD_timer module
- **Refresh Interval**: Managed by external refresh_counter module
- **NOP Delays**: 2-3 clock cycles between critical operations

## Known Issues and Limitations

### Critical Bugs
1. **Incomplete State Machine**: Several state transitions are not properly handled
2. **Timing Violations**: Hard-coded delays may not meet SDRAM specifications
3. **Address Mapping Issues**: Inconsistent address bit assignments
4. **Grant Signal Logic**: Read/write grants not properly managed
5. **Reset Handling**: Incomplete reset sequence for all registers
6. **Refresh Priority**: No proper handling of refresh during ongoing operations

### Design Limitations
1. **No Burst Support**: Only single-word read/write operations
2. **No Row Management**: Always uses auto-precharge (inefficient)
3. **Fixed Timing**: Not configurable for different SDRAM speeds
4. **Simple Interface**: No advanced features like data masking
5. **No Error Detection**: No handling of SDRAM errors or timeouts

### Missing Features
- Bank conflict detection
- Proper CAS latency handling
- Data queue management
- Advanced refresh scheduling
- Power-down modes
- Self-refresh capability

## Educational Value

This controller demonstrates:
- Basic SDRAM command sequences
- State machine design for memory controllers
- Timing relationship between SDRAM operations
- Integration of external timing modules
- Address decoding and mapping concepts

## Usage Note

This code is provided solely for educational purposes to understand SDRAM controller fundamentals. For any practical application, use a thoroughly tested, production-ready SDRAM controller IP core.

## File Structure

```
├── sdram_my_version.txt    # Main controller module
├── refresh_counter.v       # Refresh timing module (not provided)
├── RCD_timer.v            # Row-to-Column delay timer (not provided)
└── README.md              # This file
```

## Contributing

Since this is educational code with known issues, contributions focusing on:
- Bug fixes and corrections
- Better documentation
- Testbench development
- Timing analysis improvements

are welcome for learning purposes.

## License

This educational code is provided as-is for learning purposes. No warranty or support is provided.

`include "refresh_counter.v"
`include "RCD_timer.v"

module sdram_controller(
    input wire clk, rd_req, wr_req, reset, 
    input wire [23:0] in_addr,
    input wire [7:0] wr_data,   //data input to controller(to be written by master)
    input wire [1:0] bank_addr, //bank address input to controller(to be written by master)
    
    output reg [7:0] rd_data,
    output reg wr_gnt, rd_gnt, rd_data_valid, //grants for write and read requests

    input wire [7:0] rd_data_o,    //data input to controller(to be read from SDRAM)
    output reg [7:0] wr_data_o,      //data output from controller(to be written to SDRAM)
    output reg [11:0] addr_out,     //address output from SDRAM       }|12 bit address + 2 bit bank address = 14 bit address
    output reg [1:0] bank_out,      //bank address output to SDRAM  }|
    output reg cke, cas_, ras_, wr_en_, cs_ // "_" indicates active low signal
    //dqm signal which is important in read and write operations is not used here
);
wire ref_int, rcd_int, cas_int;
reg rcd_start, cas_start;
reg start_ref_cnt;

reg [20:0] x;

parameter INITIALIZATION = 1, IDLE = 2, READ = 3, WRITE = 4, NOP=5, ACTIVATE = 6;
parameter PRECHARGE_ALL = 7, REFRESH = 8, SET_MODE = 9, DATA_IN = 10;
reg [3:0] state, next_state, return_state;

reg[13:0] initialization_count;
reg [11:0] refresh_count;
reg initial_refresh, set_mode_register;
reg [1:0] initial_refresh_count;
reg [7:0] data_in; //data read from SDRAM

reg [1:0] nop_count; //count for NOP command

reg rd_active, wr_active; //indicates whether read or write operation is active
reg rcd_ack;
/*
Device deselect (DESL) cke=1, cs_=0, ras_= x, cas_= x, wr_en_= x, bank_out = 2'bxx, a10 = x, a9:a0 = x
No operation (NOP) cke=1, cs_=0, ras_= 1, cas_= 1, wr_en_= 1, bank_out = 2'bxx, a10 = x, a9:a0 = x
Burst stop (BST) cke=1, cs_=0, ras_= 1, cas_= 1, wr_en_= 0, bank_out = x, a10 = x, a9:a0 = x
Read cke=1, cs_=0, ras_= 1, cas_= 0, wr_en_= 1, bank_out = validdata, a10 = 0, a9:a0 = validdata
Read with auto precharge cke=1, cs_=0, ras_= 1, cas_= 0, wr_en_= 1, bank_out = validdata, a10 = 1, a9:a0 = validdata
Write cke=1, cs_=0, ras_= 1, cas_= 0, wr_en_= 0, bank_out = validdata, a10 = 0, a9:a0 = validdata
Write with auto precharge cke=1, cs_=0, ras_= 1, cas_= 0, wr_en_= 0, bank_out = validdata, a10 = 1, a9:a0 = validdata
Bank activate (ACT) cke=1, cs_=0, ras_= 0, cas_= 1, wr_en_= 1, bank_out = validdata, a10 = validdata, a9:a0 = validdata
Precharge select bank (PRE) cke=1, cs_=0, ras_= 0, cas_= 1, wr_en_= 0, bank_out = validdata, a10 = 0, a9:a0 = x
Precharge all banks (PALL) cke=1, cs_=0, ras_= 0, cas_= 1, wr_en_= 0, bank_out = x, a10 = 1, a9:a0 = x
CBR Auto-Refresh (REF) cke=1, cs_=0, ras_= 0, cas_= 0, wr_en_= 1, bank_out = x, a10 = x, a9:a0 = x
Self-Refresh (SELF) cke=1, cs_=0, ras_= 0, cas_= 0, wr_en_= 1, bank_out = x, a10 = x, a9:a0 = x
Mode register set (MRS) cke=1, cs_=0, ras_= 0, cas_= 0, wr_en_= 0, bank_out = 0, a10 = 0, a9:a0 = x
*/
//assign rd_gnt = (state == READ)? 
refresh_counter refresh_counter_inst (
    .clk(clk),
    .reset(reset),
    .ref_int(ref_int), //refresh interrupt
    .start_ref_cnt(start_ref_cnt)
);
RCD_timer rcd_timer(
    .clk(clk),
    .reset(reset),
    .start(rcd_start),
    .interrupt(rcd_int),
    .rcd_ack(rcd_ack)
);
RCD_timer cas_timer(
    .clk(clk),
    .reset(reset),
    .start(cas_start),
    .interrupt(cas_int)
);


always @ (posedge clk) begin
    if(reset) begin 
        state <= INITIALIZATION; 
        return_state <= INITIALIZATION; 
        initialization_count <= 0;
        nop_count <= 0;
        x<=0;
    end else begin
        state <= next_state;
        //update NOP count
        if(state == NOP) begin
            if(nop_count > 0) nop_count <= nop_count - 1;
            else nop_count <= 0;
        end
        // Handle initialization counting
        if (state == INITIALIZATION ) begin
            initialization_count <= initialization_count + 1;
        end else begin
            initialization_count <= 0; //reset count when not in INITIALIZATION
        end
    end
end
 
/*
questions left for future analysis:
1. the self refresh command is implemented in idle state. if interrupt is generated in another state, what
   should be done in that case?
*/

always @(nop_count, state, rd_req, wr_req, rd_gnt, wr_gnt, rd_data, in_addr, reset, initialization_count, ref_int) begin
if(!reset) begin
    return_state = return_state;
    rcd_ack = 0;
    case(state)
        INITIALIZATION: begin
            if(initialization_count < 14'd14310) begin
                //apply nop command to sdram during initialization (for 100us)
                set_mode_register = 0;
                start_ref_cnt = 0;
                cke = 1; cs_ = 0; ras_ = 1;
                cas_ = 1; wr_en_ = 1;
                next_state = INITIALIZATION;
                nop_count = 2'b00;
            end else begin
                next_state = PRECHARGE_ALL; //go to precharge all state after initialization
                initial_refresh = 1;
                initialization_count = 0; //reset the initialization count
            end
            
        end
        NOP: begin
            cke = 1; cs_ = 0; ras_ = 1;
            cas_ = 1; wr_en_ = 1;
            
            if(nop_count == 2'b00) next_state = return_state;
            else next_state = NOP;
        end
        IDLE: begin
            initial_refresh = 0;
            start_ref_cnt = 1;
            wr_gnt = 0;
            // the idle state is only for waiting for requests. the chip needs NOP command explicitly if no request is present
            cke = 1; cs_ = 0; ras_ = 1;
            cas_ = 1; wr_en_ = 1;

            if(ref_int) begin
                next_state = REFRESH;
                x=3;
            end else begin
            if(rd_req | wr_req) begin
                next_state = ACTIVATE;
                rcd_start = 1; //start the RCD timer
            end else begin
                next_state = NOP; //do not start the RCD timer
                nop_count = 2'b00;
                return_state = IDLE; //stay in idle state
            end
            end
        end
        REFRESH: begin      //CBR auto refresh
            cke = 1; cs_ = 0; ras_ = 0;
            cas_ = 0; wr_en_ = 1;
            if(initial_refresh) begin 
                next_state = NOP;
                nop_count = 0;
                return_state = REFRESH;
                initial_refresh = 0;
                x=1;
                set_mode_register = 1;
            end
            else if(set_mode_register) begin
                x=2;
                next_state = NOP;
                nop_count = 0;
                return_state = SET_MODE;
                set_mode_register = 0;
                end else next_state = IDLE;//go back to idle after refresh
        end
        ACTIVATE: begin     //activate a row in a bank
            cke = 1; cs_ = 0; ras_ = 0;
            cas_ = 1; wr_en_ = 1;

            addr_out[11:0] = in_addr[11:0]; //use the row address from read request
            bank_out = in_addr[23:22]; //use the bank address from read request
            next_state = NOP; //do not start the RCD timer
            nop_count = 2'b10; //wait in NOP state for 2 cycles 
            return_state = rd_req ? READ :  WRITE; 
        end
        READ: begin //read with auto precharge
            cke = 1; cs_ = 0; ras_ = 1;
            cas_ = 0; wr_en_ = 1;
            addr_out[10] = 1;
            rd_gnt = 1;
            rcd_ack = 0;
            
            next_state = NOP; 
            return_state = DATA_IN;
            nop_count = 2'b10; //wait in NOP state for  2 cycles to allow data to be read from SDRAM
        end
        WRITE: begin
            cke = 1; cs_ = 0; ras_ = 1;
            cas_ = 0; wr_en_ = 0;
            wr_gnt = 1;
            rcd_ack = 0;
            addr_out[10] = 1; //write with auto precharge
            wr_data_o = wr_data; //write data to SDRAM

            next_state = IDLE; //go to write precharge state after write operation
            return_state = IDLE;
        end

        PRECHARGE_ALL: begin
            cke = 1; cs_ = 0; ras_ = 0;
            cas_ = 1; wr_en_ = 0;
            addr_out[10] = 1; //precharge all banks
            if(initial_refresh) next_state = REFRESH;
            else next_state = IDLE; //go back to idle after precharge
        end

        SET_MODE: begin
            //set mode register
            addr_out[8:0] = 9'b0_00_011_0_000;
            cke = 1; cs_ = 0; ras_ = 0;
            cas_ = 0; wr_en_ = 0; bank_out = 2'b00;
            next_state = IDLE; //go back to idle after setting mode register
            return_state = IDLE;
        end
        DATA_IN: begin
            rd_gnt = 0;
            rd_data = rd_data_o; //read data from SDRAM
            rd_data_valid = 1;
            next_state = IDLE; //go back to idle after reading data
            return_state = IDLE;
        end

    endcase
end
end
endmodule
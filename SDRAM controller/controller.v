`include "refresh_counter.v"

module sdram_controller(
    input wire clk, rd_req, wr_req, reset, 
    input wire [23:0] wr_addr,
    input wire [23:0] rd_addr,
    input wire [7:0] wr_data,   //data input to controller(to be written by master)
    input wire [1:0] bank_addr, //bank address input to controller(to be written by master)

    output reg wr_gnt, rd_gnt, rd_data_valid, //grants for write and read requests


    input wire [7:0] rd_data,    //data input to controller(to be read from SDRAM)
    output reg [7:0] wr_data,      //data output from controller(to be written to SDRAM)
    output reg [11:0] addr_out,     //address output to SDRAM       }|12 bit address + 2 bit bank address = 14 bit address
    output reg [1:0] bank_out,      //bank address output to SDRAM  }|
    output reg cke, cas_, ras_, wr_en_, cs_ // "_" indicates active low signal
    //dqm signal which is important in read and write operations is not used here
);
wire ref_int, rcd_start, rcd_int, cas_int;
wire cas_start;

reg [7:0] data_in; //data read from SDRAM

parameter INITIALIZATION = 1, IDLE = 2, READ = 3, WRITE = 4;
parameter READ_PRECHARGE = 5, WRITE_PRECHARGE = 6, ACTIVATE = 7;
parameter PRECHARGE_ALL = 8, REFRESH = 9, SELF_REFRESH = 10, MODE_REGISTER_SET = 11;
reg [3:0] state, next_state, return_state;

reg[13:0] initialization_count;
reg [11:0] refresh_count;

reg rd_active, wr_active; //indicates whether read or write operation is active
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
.refresh_counter refresh_counter_inst (
    .clk(clk),
    .reset(reset),
    .ref_int(ref_int) //refresh interrupt
);
.RCD_timer rcd_timer(
    .clk(clk),
    .reset(reset),
    .start(rcd_start),
    .interrupt(rcd_int)
);
.RCD_timer cas_timer(
    .clk(clk),
    .reset(reset),
    .start(cas_start),
    .interrupt(cas_int)
);


always @ posedge(clk) begin
if(reset) begin state <= INITIALIZATION; return_state <= INITIALIZATION end else state <= next_state;
end

/*
questions left for future analysis:
1. the self refresh command is implemented in idle state. if interrupt is generated in another state, what
   should be done in that case?
*/

always @(state, rd_req, rd_gnt, wr_gnt, rd_data) begin
    count = 0;
    case(state)
        INITIALIZATION: begin
            count = count + 1;
            if(count < 14'd14310) begin
                //apply nop command to sdram during initialization (for 100us)
            next_state = NOP;
            return_state = INITIALIZATION; //stay in initialization state
            end
            else begin
                next_state = PRECHARGE_ALL; //go to precharge all state after initialization
                //set mode register
                addr_out[8:0] = 9'b0_00_011_0_000;
                cke = 1; cs_ = 0; ras_ = 0;
                cas_ = 0; wr_en_ = 0; bank_out = 2'b00;
            end
        end
        NOP: begin
            cke = 1; cs_ = 0; ras_ = 1;
            cas_ = 1; wr_en_ = 1;
            next_state = return_state;
        end
        IDLE: begin
            if(ref_int) begin    
                next_state = REFRESH;
            end
            if(rd_req | wr_req) begin
                next_state = ACTIVATE;
                rcd_start = 1; //start the RCD timer
            end else begin
                next_state = NOP; //do not start the RCD timer
                return_state = IDLE; //stay in idle state
            end

        end
        REFRESH: begin      //CBR auto refresh
            cke = 1; cs_ = 0; ras_ = 0;
            cas_ = 0; wr_en_ = 1;

            next_state = IDLE; //go back to idle after refresh
        end
        ACTIVATE: begin     //activate a row in a bank
            cke = 1; cs_ = 0; ras_ = 0;
            cas_ = 1; wr_en_ = 1;

            if(rcd_int) begin
                addr_out[9:0] = rd_addr[11:2]; //set the column address
                next_state = rd_req ? READ :  WRITE; //go to read or write state after activating row
                cas_start = 1; //start the CAS timer
            end else begin
                addr_out[11:0] = rd_addr[11:0]; //use the row address from read request
                bank_out = rd_addr[23:22]; //use the bank address from read request
                next_state = NOP; //do not start the RCD timer
                return_state = ACTIVATE; //stay in idle state
            end
        end
        READ: begin //read with auto precharge
            cke = 1; cs_ = 0; ras_ = 1;
            cas_ = 0; wr_en_ = 1;
            addr_out[10] = 1;
            if(cas_int) begin
                data_in = rd_data; //read data from SDRAM
            end
            next_state = IDLE; //go to read precharge state after read operation
        end
        WRITE: begin
            cke = 1; cs_ = 0; ras_ = 1;
            cas_ = 0; wr_en_ = 0;
            addr_out[10] = 1; //write with auto precharge
            if(cas_int) begin
                wr_data = wr_data; //write data to SDRAM
            end
            next_state = IDLE; //go to write precharge state after write operation
        end


        PRECHARGE_ALL: begin
            cke = 1; cs_ = 0; ras_ = 0;
            cas_ = 1; wr_en_ = 0;
            addr_out[10] = 1; //precharge all banks
            next_state = IDLE; //go back to idle after precharge
        end
    endcase
end
endmodule
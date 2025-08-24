`timescale 1ns/1ps

module tb_sdram_controller();
    // Inputs
    reg clk;
    reg reset;
    reg rd_req;
    reg wr_req;
    reg [23:0] in_addr;
    reg [7:0] wr_data;
    reg [1:0] bank_addr;
    reg [7:0] rd_data_o;
    
    // Outputs
    wire [7:0] rd_data;
    wire wr_gnt;
    wire rd_gnt;
    wire rd_data_valid;
    wire [7:0] wr_data_o;
    wire [11:0] addr_out;
    wire [1:0] bank_out;
    wire cke;
    wire cas_;
    wire ras_;
    wire wr_en_;
    wire cs_;
    
    // Instantiate the SDRAM controller
    sdram_controller dut (
        .clk(clk),
        .reset(reset),
        .rd_req(rd_req),
        .wr_req(wr_req),
        .in_addr(in_addr),
        .wr_data(wr_data),
        .bank_addr(bank_addr),
        .rd_data(rd_data),
        .wr_gnt(wr_gnt),
        .rd_gnt(rd_gnt),
        .rd_data_valid(rd_data_valid),
        .rd_data_o(rd_data_o),
        .wr_data_o(wr_data_o),
        .addr_out(addr_out),
        .bank_out(bank_out),
        .cke(cke),
        .cas_(cas_),
        .ras_(ras_),
        .wr_en_(wr_en_),
        .cs_(cs_)
    );
    
    // 143MHz clock generation (period = 6.993ns)
    always #3.4965 clk = ~clk;
    
    // Test sequence
    initial begin
        // Initialize signals
        clk = 0;
        reset = 1;
        rd_req = 0;
        wr_req = 0;
        in_addr = 24'h0;
        wr_data = 8'h0;
        bank_addr = 2'b00;
        rd_data_o = 8'hAA;
        
        // Apply reset for 20 clock cycles
        #200 reset = 0;
        
        $display("Starting 100us initialization period...");
        
        // Wait for 100us initialization to complete (14300 clock cycles at 143MHz)
        // 100us = 100,000ns, at 6.993ns/cycle = ~14300 cycles
        #100100;
        
        $display("Initialization complete. Starting test operations...");
        
        #100;
        // Test Case 1: Write operation
        @(posedge clk);
        wr_req = 1;
        in_addr = 24'h123456;  // Row: 0x456, Column: 0x123, Bank: 0x1
        wr_data = 8'h55;
        bank_addr = 2'b01;
        
        // Wait for write grant
        wait(wr_gnt);
        @(posedge clk);
        wr_req = 0;
        
        // Wait for write to complete
        #500;
        
        // Test Case 2: Read operation
        @(posedge clk);
        rd_req = 1;
        in_addr = 24'h789ABC;  // Row: 0xABC, Column: 0x789, Bank: 0x2
        bank_addr = 2'b10;
        rd_data_o = 8'hDE;     // Simulate SDRAM returning data
        
        // Wait for read grant
        wait(rd_gnt);
        @(posedge clk);
        rd_req = 0;
        
        // Wait for read to complete and data to be valid
        wait(rd_data_valid);
        #100;
        
        // Test Case 3: Another write operation
        @(posedge clk);
        wr_req = 1;
        in_addr = 24'hDEF123;  // Row: 0x123, Column: 0xDEF, Bank: 0x3
        wr_data = 8'hFF;
        bank_addr = 2'b11;
        
        wait(wr_gnt);
        @(posedge clk);
        wr_req = 0;
        
        #500;
        
        // Test Case 4: Back-to-back operations
        @(posedge clk);
        wr_req = 1;
        in_addr = 24'h111111;
        wr_data = 8'h11;
        bank_addr = 2'b00;
        
        wait(wr_gnt);
        @(posedge clk);
        wr_req = 0;
        
        // Wait a bit then issue read
        #200;
        @(posedge clk);
        rd_req = 1;
        in_addr = 24'h222222;
        bank_addr = 2'b01;
        rd_data_o = 8'h22;
        
        wait(rd_gnt);
        @(posedge clk);
        rd_req = 0;
        
        wait(rd_data_valid);
        #100;
        
        // Test refresh functionality by waiting longer
        $display("Waiting to observe refresh cycles...");
        #20000;  // 20us wait to see refresh cycles
        
        // Final test case
        @(posedge clk);
        wr_req = 1;
        in_addr = 24'h333333;
        wr_data = 8'h33;
        bank_addr = 2'b10;
        
        wait(wr_gnt);
        @(posedge clk);
        wr_req = 0;
        
        #1000;
        
        $display("Test completed successfully!");
        $finish;
    end
    
    // Monitor key signals
    always @(posedge clk) begin
        if (!reset) begin
            $display("Time: %0t ns | State: %d | rd_req: %b | wr_req: %b | rd_gnt: %b | wr_gnt: %b", 
                     $time, dut.state, rd_req, wr_req, rd_gnt, wr_gnt);
            $display("  addr_out: %03h | bank_out: %b | wr_data_o: %02h | rd_data: %02h", 
                     addr_out, bank_out, wr_data_o, rd_data);
            $display("  Control: cke: %b | cs_: %b | ras_: %b | cas_: %b | wr_en_: %b", 
                     cke, cs_, ras_, cas_, wr_en_);
            $display("----------------------------------------");
        end
    end
    
    // Check for refresh cycles
    always @(posedge clk) begin
        if (dut.state == 8) begin  // REFRESH state
            $display("REFRESH cycle detected at time %0t ns", $time);
        end
    end
    
    // VCD dump for waveform viewing
    initial begin
        $dumpfile("sdram_controller.vcd");
        $dumpvars(0, tb_sdram_controller);
        // Add specific signals for better waveform viewing
        $dumpvars(1, dut.state);
        $dumpvars(1, dut.initialization_count);
        $dumpvars(1, dut.refresh_count);
    end
    
endmodule

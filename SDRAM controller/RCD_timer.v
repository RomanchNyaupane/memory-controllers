module RCD_timer(
    input wire clk,
    input wire reset,

    input wire start, //start signal to initiate the timer
    output reg interrupt //refresh interrupt signal
);
reg [1:0] count;
always @(posedge clk ) begin
    if (start) count <= count + 1;
    if(count == 2'b10) begin
        rcd_int <=1;
        count <= 0; //reset count after generating interrupt
    end else rcd_int <= 0; //clear interrupt if not in the right count
    
end

endmodule
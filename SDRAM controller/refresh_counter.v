module refresh_counter(
    input wire clk, reset,
    output reg ref_int //refresh interrupt
);
reg [11:0] refresh_count;
always @(posedge clk) begin
    if (reset) begin
        refresh_count <= 12'b0;
        ref_int <= 1'b0;
    end else begin
        if (refresh_count < 12'd2235) begin
            refresh_count <= refresh_count + 1;
            ref_int <= 1'b0; // No interrupt until count reaches limit
        end else begin
            refresh_count <= 12'b0; // Reset count after reaching limit
            ref_int <= 1'b1; // Trigger refresh interrupt
        end
    end
end
endmodule
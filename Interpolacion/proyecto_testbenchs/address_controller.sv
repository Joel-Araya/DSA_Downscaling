module address_controller (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        key_inc,      // Active low KEY[1]
    input  logic        key_dec,      // Active low KEY[3]
    output logic [15:0] address
);

    // Synchronize inputs (2-stage synchronizer)
    logic key_inc_sync1, key_inc_sync2;
    logic key_dec_sync1, key_dec_sync2;
    
    // Debounce counters and state
    logic [19:0] debounce_cnt_inc, debounce_cnt_dec;
    logic key_inc_stable, key_dec_stable;
    logic key_inc_prev, key_dec_prev;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Synchronizers
            key_inc_sync1 <= 1'b1;
            key_inc_sync2 <= 1'b1;
            key_dec_sync1 <= 1'b1;
            key_dec_sync2 <= 1'b1;
            
            // Debounce
            debounce_cnt_inc <= 20'd0;
            debounce_cnt_dec <= 20'd0;
            key_inc_stable <= 1'b1;
            key_dec_stable <= 1'b1;
            key_inc_prev <= 1'b1;
            key_dec_prev <= 1'b1;
            
            // Address
            address <= 16'h0000;
        end else begin
            // 2-stage synchronization
            key_inc_sync1 <= key_inc;
            key_inc_sync2 <= key_inc_sync1;
            key_dec_sync1 <= key_dec;
            key_dec_sync2 <= key_dec_sync1;
            
            // Debounce increment key
            if (key_inc_sync2 == key_inc_stable) begin
                debounce_cnt_inc <= 20'd0;
            end else begin
                if (debounce_cnt_inc < 20'd500000) begin  // 10ms at 50MHz
                    debounce_cnt_inc <= debounce_cnt_inc + 1;
                end else begin
                    key_inc_stable <= key_inc_sync2;
                    debounce_cnt_inc <= 20'd0;
                end
            end
            
            // Debounce decrement key
            if (key_dec_sync2 == key_dec_stable) begin
                debounce_cnt_dec <= 20'd0;
            end else begin
                if (debounce_cnt_dec < 20'd500000) begin  // 10ms at 50MHz
                    debounce_cnt_dec <= debounce_cnt_dec + 1;
                end else begin
                    key_dec_stable <= key_dec_sync2;
                    debounce_cnt_dec <= 20'd0;
                end
            end
            
            // Update previous state
            key_inc_prev <= key_inc_stable;
            key_dec_prev <= key_dec_stable;
            
            // Detect falling edge (button press) and update address
            if (!key_inc_stable && key_inc_prev) begin
                address <= address + 16'd4;
            end else if (!key_dec_stable && key_dec_prev) begin
                address <= address - 16'd4;
            end
        end
    end

endmodule

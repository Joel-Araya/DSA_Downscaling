module instruction_handler (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [1:0]  ir_in,
    input  logic [31:0] instruction, 
    
    output logic        i_mode_select,
    output logic        debug_mode,
    output logic [8:0]  img_width,
    output logic [8:0]  img_height,
    output logic [2:0]  N_simd,
    output logic [7:0]  scale_factor,

	input  logic [31:0] i_mem_rdata,
	output logic        o_mem_we,
	output logic [3:0]  o_mem_byte_en,
    output logic [15:0] o_mem_addr,
	output logic [31:0] o_mem_wdata,

    output logic [31:0] response_data,
    output logic        start,
    output logic        waiting_command,
    output logic        debug_signal
    );

logic is_ready_to_start;
logic reciving_img_data;
logic i_write_enable;
logic write_done;
logic [31:0] img_data_lenght;
logic [31:0] img_data_counter;
logic [31:0] clk_counter;
logic [15:0] write_mem_addr;
logic [15:0] read_addr_counter;
logic config_received;
logic ir_in_prev;

// Unified state machine on main clock
always_ff @(posedge clk or negedge reset_n) begin

    if (~reset_n) begin
        i_mode_select <= 1'b0;
        debug_mode <= 1'b0;
        img_width <= 9'd0;
        img_height <= 9'd0;
        N_simd <= 3'd0;
        scale_factor <= 8'd0;
        img_data_counter <= 32'd0;
        img_data_lenght <= 32'd0;
        reciving_img_data <= 1'b0;
        waiting_command <= 1'b1;
        i_write_enable <= 1'b0;
        is_ready_to_start <= 1'b0;
        start <= 1'b0;
        response_data <= 32'd0;
        clk_counter <= 32'd0;
        write_done <= 1'b0;
        read_addr_counter <= 16'h0000;
        debug_signal <= 1'b0;
        config_received <= 1'b0;
        ir_in_prev <= 1'b0;
    end else begin
        // Store previous ir_in[0] state to detect rising edge
        ir_in_prev <= ir_in[0];

        // Handle write completion timer
        if (write_done) begin
            clk_counter <= clk_counter + 1;
            if (clk_counter == 2) begin
                reciving_img_data <= 1'b0;
                is_ready_to_start <= 1'b1;
                waiting_command <= 1'b1;
                i_write_enable <= 1'b0;
                write_done <= 1'b0;
                clk_counter <= 32'd0;
            end
        end
        // Handle instruction reception on ir_in[0] rising edge
        else if (ir_in[0] && !ir_in_prev) begin
            if (waiting_command) begin
                if (instruction[31] == 1'b0) begin
                    // Read command: bit[31]=0, bit[30]=img/reg, bit[29]=org/res, bit[7:0]=reg_code
                    if (instruction[30] == 1'b0) begin
                        // Read image data
                        if (instruction[29] == 1'b0) begin
                            // Read from original image
                            read_addr_counter <= 16'h0000;
                        end else begin
                            // Read from result image (placeholder address)
                            read_addr_counter <= 16'h8000;
                        end
                        response_data <= i_mem_rdata;
                    end else begin
                        // Read register based on reg_code [7:0]
                        case (instruction[7:0])
                            8'd0: response_data <= {23'd0, img_width};
                            8'd1: response_data <= {23'd0, img_height};
                            8'd2: response_data <= {29'd0, N_simd};
                            8'd3: response_data <= {24'd0, scale_factor};
                            8'd4: response_data <= {31'd0, i_mode_select};
                            8'd5: response_data <= {31'd0, debug_mode};
                            8'd6: response_data <= {31'd0, start};
                            8'd7: response_data <= img_data_lenght;
                            8'd8: response_data <= img_data_counter;
                            default: response_data <= 32'hDEADC0DE; // Invalid register
                        endcase
                    end
                end
                else if (instruction[31] == 1'b1 && |instruction[30:0]) begin
                    // Configuration instruction - don't write this to memory
                    i_mode_select <= instruction[30];
                    debug_mode <= instruction[29];
                    img_width <= instruction[28:20];
                    img_height <= instruction[19:11];
                    N_simd <= instruction[10:8];
                    scale_factor <= instruction[7:0];

                    img_data_lenght <= instruction[28:20] * instruction[19:11];
                    img_data_counter <= 32'd0;
                    config_received <= 1'b1;
                    waiting_command <= 1'b0;
                
                end else if (is_ready_to_start && instruction[31] == 1'b1 && ~|instruction[30:0]) begin
                    // Start processing
                    start <= 1'b1;
                    is_ready_to_start <= 1'b0;
                    waiting_command <= 1'b0;
                end
            end 
            else if (config_received) begin
                // First data after config - start receiving
                config_received <= 1'b0;
                reciving_img_data <= 1'b1;
                i_write_enable <= 1'b1;
                img_data_counter <= img_data_counter + 4;
                debug_signal <= 1'b1;
            end
            else if (reciving_img_data) begin
                // Continue receiving image data
                if (img_data_counter >= img_data_lenght) begin
                    debug_signal <= 1'b0;
                    write_done <= 1'b1;
                    i_write_enable <= 1'b0;
                end else begin
                    debug_signal <= 1'b1;
                    i_write_enable <= 1'b1;
                    img_data_counter <= img_data_counter + 4;
                end
            end
        end else begin
            // Deassert write enable when ir_in[0] goes low
            if (i_write_enable) begin
                i_write_enable <= 1'b0;
            end
        end
    end
end
img_writer img_reciver (
                .clk(clk),
                .rst_n(reset_n),
                .recived_pixel(ir_in[0]),
                .i_write_enable(i_write_enable),
                .i_pixel_data(instruction),
                .img_data_length(img_data_lenght),
                .img_data_counter(img_data_counter),
                .o_mem_we(o_mem_we),
                .o_mem_byte_en(o_mem_byte_en),
                .o_mem_addr(write_mem_addr),
                .o_mem_wdata(o_mem_wdata),
                .o_write_done()
            );

// Handle read requests on ir_in[1] - advance to next pixel
// always_ff @(posedge ir_in[1] or negedge reset_n) begin
//     if (~reset_n) begin
//         // Reset handled in main block
//     end else begin
//         // Advance read address to next pixel (4 bytes)
//         read_addr_counter <= read_addr_counter + 16'd4;
//         response_data <= i_mem_rdata;
//     end
// end

// Connect read address to memory when not writing
assign o_mem_addr = i_write_enable ? write_mem_addr : read_addr_counter;
    


endmodule
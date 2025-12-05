module img_writer (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        recived_pixel,      // Signal indicating a pixel has been received
    
    // Control signals
    input  logic        i_write_enable,     // Enable writing
    input  logic [31:0] i_pixel_data,       // 4 pixels (bytes) to write
    
    // Image size tracking
    input  logic [31:0] img_data_length,    // Total number of pixels in image
    input  logic [31:0] img_data_counter,   // Current pixel count written
    
    // Memory interface
    output logic        o_mem_we,
    output logic [3:0]  o_mem_byte_en,
    output logic [15:0] o_mem_addr,
    output logic [31:0] o_mem_wdata,
    
    // Status
    output logic        o_write_done        // Indicates write is complete
); 

    // Calculate remaining pixels to write
    logic [31:0] remaining_pixels;
    logic [3:0]  bytes_to_write;

    assign remaining_pixels = img_data_length - img_data_counter;
    
    // Determine how many bytes to enable based on remaining pixels (combinational)
    always_comb begin
        if (remaining_pixels >= 4) begin
            bytes_to_write = 4'b1111;  // Write all 4 bytes
        end else if (remaining_pixels == 3) begin
            bytes_to_write = 4'b0111;  // Write 3 bytes
        end else if (remaining_pixels == 2) begin
            bytes_to_write = 4'b0011;  // Write 2 bytes
        end else if (remaining_pixels == 1) begin
            bytes_to_write = 4'b0001;  // Write 1 byte
        end else begin
            bytes_to_write = 4'b0000;  // No bytes to write
        end
    end
    
    // Memory write logic (combinational)
    always_comb begin
        if (i_write_enable && (img_data_counter < img_data_length)) begin
            o_mem_we      = 1'b1;
            o_mem_byte_en = bytes_to_write;
            o_mem_wdata   = i_pixel_data;
        end else begin
            o_mem_we      = 1'b0;
            o_mem_byte_en = 4'b0000;
            o_mem_wdata   = 32'h0;
        end
    end
    
    // Address generation (increments by 4 bytes per write)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_mem_addr <= 16'h0000;
        end else if (i_write_enable && o_mem_we) begin
            o_mem_addr <= o_mem_addr + 16'd4;
        end
    end
    
    // Write done signal
    assign o_write_done = (img_data_counter >= img_data_length);

endmodule

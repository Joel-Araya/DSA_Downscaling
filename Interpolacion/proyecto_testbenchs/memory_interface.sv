module memory_interface (
    input  logic        clk,
    input  logic        rst_n,
    
    // Memory interface signals
    input  logic        o_mem_we,
    input  logic [3:0]  o_mem_byte_en,
    input  logic [15:0] o_mem_addr,
    input  logic [31:0] o_mem_wdata,
    output logic [31:0] i_mem_rdata
);

    // Instantiate Intel FPGA RAM module
    // ram.v is a 1MB (262144 words x 32 bits) single-port RAM with byte enables
    // Address is 18-bit word address (we use lower 16 bits from o_mem_addr)
    logic [17:0] ram_address;
    
    // Convert byte address to word address (divide by 4)
    assign ram_address = {2'b00, o_mem_addr[15:2]};
    
    ram ram_inst (
        .address  (ram_address),      // 18-bit word address
        .byteena  (o_mem_byte_en),    // 4-bit byte enable
        .clock    (clk),              // Clock
        .data     (o_mem_wdata),      // 32-bit write data
        .wren     (o_mem_we),         // Write enable
        .q        (i_mem_rdata)       // 32-bit read data
    );

endmodule

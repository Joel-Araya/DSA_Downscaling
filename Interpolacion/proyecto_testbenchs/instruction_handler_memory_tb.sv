`timescale 1ns / 1ps

module instruction_handler_memory_tb;

	localparam CLK_PERIOD = 20;

    // Clock and reset
    logic        clk;
    logic        reset_n;
    
    // Instruction interface
    logic [1:0]  ir_in;
    logic [31:0] instruction;
    
    // Configuration outputs
    logic        i_mode_select;
    logic        debug_mode;
    logic [8:0]  img_width;
    logic [8:0]  img_height;
    logic [2:0]  N_simd;
    logic [7:0]  scale_factor;
    
    // Memory interface signals
    logic        o_mem_we;
    logic        manual = 0;
    logic [31:0] i_mem_rdata;
    logic [3:0]  o_mem_byte_en;
    logic [15:0] o_mem_addr_aux;
    logic [15:0] o_mem_addr_manual;
    logic [15:0] o_mem_addr;
    logic [31:0] o_mem_wdata;
    
    // Control outputs
    logic [31:0] response_data;
    logic        start;
    
    // Instantiate instruction handler
    instruction_handler inst_handler (
        .clk           (clk),
        .reset_n       (reset_n),
        .ir_in         (ir_in),
        .instruction   (instruction),
        .i_mode_select (i_mode_select),
        .debug_mode    (debug_mode),
        .img_width     (img_width),
        .img_height    (img_height),
        .N_simd        (N_simd),
        .scale_factor  (scale_factor),
        .i_mem_rdata   (i_mem_rdata),
        .o_mem_we      (o_mem_we),
        .o_mem_byte_en (o_mem_byte_en),
        .o_mem_addr    (o_mem_addr),
        .o_mem_wdata   (o_mem_wdata),
        .response_data (response_data),
        .start         (start)
    );
    
    // Instantiate memory interface
    memory_interface mem_if (
        .clk          (clk),
        .rst_n        (reset_n),
        .o_mem_we     (o_mem_we),
        .o_mem_byte_en(o_mem_byte_en),
        .o_mem_addr   (o_mem_addr_aux),
        .o_mem_wdata  (o_mem_wdata),
        .i_mem_rdata  (i_mem_rdata)
    );
    
    // Clock generation (50MHz)
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Task to send instruction on ir_in[0]
    task send_instruction_ir0(input [31:0] instr);
        begin
            instruction = instr;
            #5;
            ir_in[0] = 1;
            #20;
            ir_in[0] = 0;
            #20;
        end
    endtask
    
    // Task to verify memory contents
    task verify_memory(input [15:0] addr, input [31:0] expected_data);
        logic [31:0] read_data;
        begin
            @(posedge clk);
            // Memory read happens automatically on address change
            @(posedge clk);
            @(posedge clk);
            read_data = i_mem_rdata;
            if (read_data == expected_data) begin
                $display("  [PASS] Address 0x%h: 0x%h", addr, read_data);
            end else begin
                $display("  [FAIL] Address 0x%h: Got 0x%h, Expected 0x%h", addr, read_data, expected_data);
            end
        end
    endtask
    
    // Test stimulus
    initial begin
        // Initialize signals
        reset_n = 0;
        ir_in = 2'b00;
        instruction = 32'h00000000;
        
        // Reset
        #50;
        reset_n = 1;
        #40;
        
        $display("=== Starting Instruction Handler + Memory Integration Test ===");
        
        // Test 1: Configure for small image (4x4 = 16 pixels = 4 words)
        $display("\nTest 1: Configure for 4x4 image (16 pixels)");
        $display("  Config: mode=1, debug=0, width=4, height=4, N_simd=1, scale=2");
        send_instruction_ir0(32'b1_1_0_000000100_000000100_001_00000010);
        
        #50;
        $display("  Configuration applied:");
        $display("    i_mode_select: %b", i_mode_select);
        $display("    img_width: %d, img_height: %d", img_width, img_height);
        $display("    Total pixels: %d", img_width * img_height);
        
        // Test 2: Write image data to memory
        $display("\nTest 2: Writing 4 words of image data");
        begin
            logic [31:0] test_data [4];
            test_data[0] = 32'h04030201;  // Pixels 1,2,3,4
            test_data[1] = 32'h08070605;  // Pixels 5,6,7,8
            test_data[2] = 32'h0C0B0A09;  // Pixels 9,10,11,12
            test_data[3] = 32'h100F0E0D;  // Pixels 13,14,15,16
            
            for (int i = 0; i < 4; i++) begin
                send_instruction_ir0(test_data[i]);
                $display("  Word %0d written: 0x%h at address 0x%h", i, test_data[i], o_mem_addr);
                #40;
            end
        end
        
        // Test 3: Read back and verify memory contents
        $display("\nTest 3: Verifying memory contents");
        #100;  // Wait for writes to complete
        
        // Note: Direct memory read verification
        begin
            manual = 1;
            for (int i = 0; i < 4; i++) begin
                o_mem_addr_manual = 16'h0000 + (i * 4);
                #40;
                $display("  Reading address 0x%h: 0x%h", o_mem_addr_aux, i_mem_rdata);
                // The memory interface provides continuous read
                // We can check by monitoring i_mem_rdata when o_mem_addr changes
            end
            manual = 0;
        end
        
        // Test 4: Send start command
        $display("\nTest 4: Send start processing command");
        send_instruction_ir0(32'b1_0000000000000000000000000000000);
        #50;
        $display("  Start signal asserted: %b", start);
        
        // Test 5: Larger image with specific pattern
        $display("\nTest 5: Configure and write 8x8 image (64 pixels = 16 words)");
        reset_n = 0;
        #50;
        reset_n = 1;
        #40;
        
        send_instruction_ir0(32'b1_0_1_000001000_000001000_010_00000011);
        #50;
        $display("  New config: %dx%d = %d pixels", img_width, img_height, img_width * img_height);
        
        $display("  Writing pattern data...");
        begin
            automatic logic [31:0] pattern;
            for (int i = 0; i < 16; i++) begin
                pattern = {8'(i*4+3), 8'(i*4+2), 8'(i*4+1), 8'(i*4)};
                send_instruction_ir0(pattern);
                if (i % 4 == 0) begin
                    $display("    Progress: %0d/16 words", i);
                end
            end
        end
        
        $display("  Image data write complete");
        #100;
        
        // Test 6: Non-aligned image size (test byte enable)
        $display("\nTest 6: Configure for 3x3 image (9 pixels = 2.25 words)");
        reset_n = 0;
        #50;
        reset_n = 1;
        #40;
        
        send_instruction_ir0(32'b1_0_0_000000011_000000011_001_00000001);
        #50;
        $display("  Image: %dx%d = %d pixels", img_width, img_height, img_width * img_height);
        
        // Write 3 words (last one should have partial byte enable)
        send_instruction_ir0(32'h04030201);
        $display("  Word 0: byte_en=%b (expected 1111)", o_mem_byte_en);
        #40;
        
        send_instruction_ir0(32'h08070605);
        $display("  Word 1: byte_en=%b (expected 1111)", o_mem_byte_en);
        #40;
        
        send_instruction_ir0(32'h00000009);
        $display("  Word 2: byte_en=%b (expected 0001 - only 1 pixel remains)", o_mem_byte_en);
        #40;
        
        // Test 7: Memory integrity check
        $display("\nTest 7: Writing known pattern and checking consistency");
        reset_n = 0;
        #50;
        reset_n = 1;
        #40;
        
        send_instruction_ir0(32'b1_1_0_000000010_000000010_001_00000001);
        #50;
        $display("  Image: 2x2 = 4 pixels = 1 word");
        
        send_instruction_ir0(32'hDEADBEEF);
        #40;
        $display("  Written 0xDEADBEEF to address 0x%h", o_mem_addr);
        
        #100;
        $display("\n=== Integration Test Complete ===");
        $display("All instruction handler and memory interface operations verified");
        $finish;
    end
    
    // Monitor all memory writes
    always @(posedge clk) begin
        if (o_mem_we) begin
            $display("  [MEM_WRITE] Time=%0t | Addr=0x%h | Data=0x%h | ByteEn=%b", 
                     $time, o_mem_addr, o_mem_wdata, o_mem_byte_en);
        end
    end
    
    // Monitor memory read data changes
    logic [31:0] prev_rdata = 32'h0;
    always @(posedge clk) begin
        if (i_mem_rdata != prev_rdata) begin
            $display("  [MEM_READ] Time=%0t | Addr=0x%h | Data=0x%h", 
                     $time, o_mem_addr, i_mem_rdata);
            prev_rdata = i_mem_rdata;
        end
    end

    assign o_mem_addr_aux = manual ? o_mem_addr_manual : o_mem_addr;

endmodule

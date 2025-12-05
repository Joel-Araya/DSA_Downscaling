`timescale 1ns / 1ps

module instruction_handler_tb;

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
    
    // Memory interface
    logic [31:0] i_mem_rdata;
    logic        o_mem_we;
    logic [3:0]  o_mem_byte_en;
    logic [15:0] o_mem_addr;
    logic [31:0] o_mem_wdata;
    
    // Control outputs
    logic [31:0] response_data;
    logic        start;
    
    // Instantiate DUT
    instruction_handler dut (
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
    
    // Clock generation (50MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end
    
    // Task to send instruction on ir_in[0]
    task send_instruction_ir0(input [31:0] instr);
        begin
            instruction = instr;
            #5;
            ir_in[0] = 1;
            #5;
            $display("  Word: addr=0x%h, data=0x%h, byte_en=%b", 
                      o_mem_addr, o_mem_wdata, o_mem_byte_en);
            #20;
            ir_in[0] = 0;
            #20;
        end
    endtask
    
    // Task to send instruction on ir_in[1]
    task send_instruction_ir1(input [31:0] instr);
        begin
            instruction = instr;
            #5;
            ir_in[1] = 1;
            #20;
            ir_in[1] = 0;
            #20;
        end
    endtask
    
    // Test stimulus
    initial begin
        // Initialize signals
        reset_n = 0;
        ir_in = 2'b00;
        instruction = 32'h00000000;
        i_mem_rdata = 32'h00000000;
        
        // Reset
        #50;
        reset_n = 1;
        #40;
        
        $display("=== Starting Instruction Handler Test ===");
        
        // Test 1: Send configuration instruction
        $display("\nTest 1: Configuration Instruction");
        $display("  Config: mode=1, debug=0, width=64, height=32, N_simd=2, scale=3");
        // Build configuration instruction:
        // bit[31]=1 (config), bit[30]=i_mode_select, bit[29]=debug_mode
        // bits[28:20]=img_width, bits[19:11]=img_height
        // bits[10:8]=N_simd, bits[7:0]=scale_factor
        send_instruction_ir0(32'b1_1_0_001000000_000100000_010_00000011);
        
        #50;
        $display("  Output - i_mode_select: %b", i_mode_select);
        $display("  Output - debug_mode: %b", debug_mode);
        $display("  Output - img_width: %d", img_width);
        $display("  Output - img_height: %d", img_height);
        $display("  Output - N_simd: %d", N_simd);
        $display("  Output - scale_factor: %d", scale_factor);
        
        // Test 2: Send image data (4 pixels at a time)
        $display("\nTest 2: Sending Image Data (64x32 = 2048 pixels = 512 words)");
        $display("  Sending first 8 words of image data...");
        
        for (int i = 0; i < 8; i++) begin
            send_instruction_ir0(32'h11111111 * (i + 1));
            $display("  Word %0d: addr=0x%h, data=0x%h, we=%b, byte_en=%b", 
                     i, o_mem_addr, o_mem_wdata, o_mem_we, o_mem_byte_en);
            #20;
        end
        
        // Test 3: Send remaining image data (simulate full image)
        $display("\nTest 3: Fast-forward remaining image data...");
        for (int i = 8; i < 512; i++) begin
            send_instruction_ir0(32'hAAAAAAAA);
            if (i % 100 == 0) begin
                $display("  Progress: %0d/512 words written", i);
            end
        end
        
        $display("  Image data transfer complete");
        #100;
        
        // Test 4: Send start processing command
        $display("\nTest 4: Start Processing Command");
        send_instruction_ir0(32'b1_0000000000000000000000000000000);
        #50;
        $display("  Start signal: %b (expected: 1)", start);
        
        // Test 5: Configuration with different parameters
        $display("\nTest 5: New Configuration");
        $display("  Config: mode=0, debug=1, width=128, height=64, N_simd=4, scale=5");
        reset_n = 0;
        #50;
        reset_n = 1;
        #40;
        
        send_instruction_ir0(32'b1_0_1_010000000_001000000_100_00000101);
        #50;
        $display("  Output - i_mode_select: %b", i_mode_select);
        $display("  Output - debug_mode: %b", debug_mode);
        $display("  Output - img_width: %d", img_width);
        $display("  Output - img_height: %d", img_height);
        $display("  Output - N_simd: %d", N_simd);
        $display("  Output - scale_factor: %d", scale_factor);
        
        // Test 6: Partial image data (test boundary condition)
        $display("\nTest 6: Small Image (3x3 = 9 pixels = 3 words)");
        reset_n = 0;
        #50;
        reset_n = 1;
        #40;
        
        send_instruction_ir0(32'b1_0_0_000000011_000000011_001_00000001);
        #50;
        $display("  Image size: %dx%d = %d pixels", img_width, img_height, img_width * img_height);
        
        for (int i = 0; i < 3; i++) begin
            send_instruction_ir0(32'hFF000000 | (i << 16));
            // $display("  Word %0d: addr=0x%h, data=0x%h, byte_en=%b", 
            //          i, o_mem_addr, o_mem_wdata, o_mem_byte_en);
                     
            #20;
        end
        
        $display("  Checking last write byte enable (should handle 1 remaining pixel)");
        
        #100;
        $display("\n=== Test Complete ===");
        $finish;
    end
    
    // Monitor memory writes
    always @(posedge o_mem_we) begin
        $display("  [MEM WRITE] Time=%0t addr=0x%h data=0x%h byte_en=%b", 
                 $time, o_mem_addr, o_mem_wdata, o_mem_byte_en);
    end

endmodule

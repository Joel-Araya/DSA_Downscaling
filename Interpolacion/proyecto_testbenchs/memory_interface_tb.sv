`timescale 1ns / 1ps

module memory_interface_tb;

    // Clock and reset
    logic        clk;
    logic        rst_n;
    
    // Memory interface signals
    logic        o_mem_we;
    logic [3:0]  o_mem_byte_en;
    logic [15:0] o_mem_addr;
    logic [31:0] o_mem_wdata;
    logic [31:0] i_mem_rdata;
    
    // Instantiate DUT
    memory_interface dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .o_mem_we     (o_mem_we),
        .o_mem_byte_en(o_mem_byte_en),
        .o_mem_addr   (o_mem_addr),
        .o_mem_wdata  (o_mem_wdata),
        .i_mem_rdata  (i_mem_rdata)
    );
    
    // Clock generation (50MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end
    
    // Test stimulus
    initial begin
        // Initialize signals
        rst_n = 0;
        o_mem_we = 0;
        o_mem_byte_en = 4'b0000;
        o_mem_addr = 16'h0000;
        o_mem_wdata = 32'h00000000;
        
        // Reset
        #50;
        rst_n = 1;
        #20;
        
        $display("=== Starting Memory Interface Test ===");
        
        // Test 1: Write full 32-bit word at address 0x100
        $display("\nTest 1: Write full word 0xDEADBEEF at 0x100");
        @(posedge clk);
        o_mem_addr = 16'h0100;
        o_mem_wdata = 32'hDEADBEEF;
        o_mem_byte_en = 4'b1111;
        o_mem_we = 1;
        @(posedge clk);
        o_mem_we = 0;
        
        // Read back
        @(posedge clk);
        o_mem_addr = 16'h0100;
        @(posedge clk);
        @(posedge clk);
        $display("Read data: 0x%h (expected: 0xDEADBEEF)", i_mem_rdata);
        
        // Test 2: Write only byte 0 at address 0x104
        $display("\nTest 2: Write byte 0 only (0xAA) at 0x104");
        @(posedge clk);
        o_mem_addr = 16'h0104;
        o_mem_wdata = 32'h000000AA;
        o_mem_byte_en = 4'b0001;
        o_mem_we = 1;
        @(posedge clk);
        o_mem_we = 0;
        
        @(posedge clk);
        o_mem_addr = 16'h0104;
        @(posedge clk);
        @(posedge clk);
        $display("Read data: 0x%h (expected: 0x000000AA)", i_mem_rdata);
        
        // Test 3: Write bytes 0 and 1 at address 0x108
        $display("\nTest 3: Write bytes 0,1 (0xCCBB) at 0x108");
        @(posedge clk);
        o_mem_addr = 16'h0108;
        o_mem_wdata = 32'h0000CCBB;
        o_mem_byte_en = 4'b0011;
        o_mem_we = 1;
        @(posedge clk);
        o_mem_we = 0;
        
        @(posedge clk);
        o_mem_addr = 16'h0108;
        @(posedge clk);
        @(posedge clk);
        $display("Read data: 0x%h (expected: 0x0000CCBB)", i_mem_rdata);
        
        // Test 4: Write bytes 0,1,2 at address 0x10C
        $display("\nTest 4: Write bytes 0,1,2 (0xFFEEDD) at 0x10C");
        @(posedge clk);
        o_mem_addr = 16'h010C;
        o_mem_wdata = 32'h00FFEEDD;
        o_mem_byte_en = 4'b0111;
        o_mem_we = 1;
        @(posedge clk);
        o_mem_we = 0;
        
        @(posedge clk);
        o_mem_addr = 16'h010C;
        @(posedge clk);
        @(posedge clk);
        $display("Read data: 0x%h (expected: 0x00FFEEDD)", i_mem_rdata);
        
        // Test 5: Sequential write (like image writing)
        $display("\nTest 5: Sequential writes (simulating image data)");
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            o_mem_addr = 16'h0200 + (i * 4);
            o_mem_wdata = 32'h11111111 * (i + 1);
            o_mem_byte_en = 4'b1111;
            o_mem_we = 1;
            @(posedge clk);
            o_mem_we = 0;
            $display("  Written 0x%h to address 0x%h", o_mem_wdata, o_mem_addr);
        end
        
        // Read back sequential data
        $display("\nReading back sequential data:");
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            o_mem_addr = 16'h0200 + (i * 4);
            @(posedge clk);
            @(posedge clk);
            $display("  Address 0x%h: 0x%h", o_mem_addr, i_mem_rdata);
        end
        
        // Test 6: Partial write at end (simulating image boundary)
        $display("\nTest 6: Partial write with 3 bytes enabled at 0x0300");
        @(posedge clk);
        o_mem_addr = 16'h0300;
        o_mem_wdata = 32'hAABBCCDD;
        o_mem_byte_en = 4'b0111;  // Only write 3 bytes
        o_mem_we = 1;
        @(posedge clk);
        o_mem_we = 0;
        
        @(posedge clk);
        o_mem_addr = 16'h0300;
        @(posedge clk);
        @(posedge clk);
        $display("Read data: 0x%h (expected: 0x00BBCCDD)", i_mem_rdata);
        
        #100;
        $display("\n=== Test Complete ===");
        $finish;
    end
    
    // Monitor for debugging
    initial begin
        $monitor("Time=%0t clk=%b rst_n=%b we=%b addr=0x%h wdata=0x%h rdata=0x%h byte_en=%b", 
                 $time, clk, rst_n, o_mem_we, o_mem_addr, o_mem_wdata, i_mem_rdata, o_mem_byte_en);
    end

endmodule

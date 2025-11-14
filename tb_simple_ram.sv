// Nombre de archivo: tb_simple_ram.sv
// Testbench CORREGIDO con retardos de lectura

`timescale 1ns / 1ps

module tb_simple_ram;

    // --- Parámetros ---
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 8;
    parameter CLK_PERIOD = 10;

    // --- Señales ---
    logic                      clk;
    logic                      we;
    logic [ADDR_WIDTH-1:0]     addr;
    logic [DATA_WIDTH-1:0]     data_in;
    logic [DATA_WIDTH-1:0]     data_out;

    // --- Instanciación del DUT ---
    simple_ram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) UUT (
        .clk(clk),
        .we(we),
        .addr(addr),
        .data_in(data_in),
        .data_out(data_out)
    );

    // --- Generador de Reloj ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    logic [ADDR_WIDTH-1:0] ADDR_1 = 8'd5;
    logic [DATA_WIDTH-1:0] DATA_1 = 32'hAAAAAAAA;
    
    logic [ADDR_WIDTH-1:0] ADDR_2 = 8'd10;
    logic [DATA_WIDTH-1:0] DATA_2 = 32'hDEADBEEF;
    logic [DATA_WIDTH-1:0] DATA_3 = 32'hC0FFEE12;
    // --- Proceso de Estímulo ---
    initial begin
        $dumpfile("simple_ram.vcd");
        $dumpvars(0, tb_simple_ram);

        $display("--- Inicio del Testbench para simple_ram ---");

        we = 0;
        addr = 0;
        data_in = 0;
        @(posedge clk);
        @(posedge clk);

        // --- Prueba 1: Escribir DATA_1 en ADDR_1 ---
        $display("Prueba 1: Escribiendo %h en la direccion %d", DATA_1, ADDR_1);
        we = 1;
        addr = ADDR_1;
        data_in = DATA_1;
        @(posedge clk);

        // --- Prueba 2: Leer DATA_1 de ADDR_1 ---
        $display("Prueba 2: Leyendo de la direccion %d", ADDR_1);
        we = 0;
        addr = ADDR_1; 
        @(posedge clk); // Ciclo N: Dirección se registra
        @(posedge clk); // Ciclo N+1: Salida 'data_out' se actualiza
        
        $display("Dato leido: %h", data_out);
        if (data_out !== DATA_1) begin
            $display("ERROR de Lectura 1: Se esperaba %h pero se obtuvo %h", DATA_1, data_out);
            $finish;
        end

        // --- Prueba 3: Escribir DATA_2 en ADDR_2 ---
        $display("Prueba 3: Escribiendo %h en la direccion %d", DATA_2, ADDR_2);
        we = 1;
        addr = ADDR_2;
        data_in = DATA_2;
        @(posedge clk);

        // --- Prueba 4: Prueba de "Read-First" ---
        $display("Prueba 4: 'Read-First'. Escribiendo %h y leyendo de %d simultaneamente.", DATA_3, ADDR_2);
        we = 1;
        addr = ADDR_2;
        data_in = DATA_3;
        @(posedge clk); // Ciclo N: Escribe DATA_3 y lee valor antiguo (DATA_2)
        
        $display("Dato leido (Read-First): %h", data_out);
        if (data_out !== DATA_2) begin
            $display("ERROR de Read-First: Se esperaba el dato antiguo %h pero se obtuvo %h", DATA_2, data_out);
            $finish;
        end

        // --- Prueba 5: Verificar la escritura de la Prueba 4 ---
        $display("Prueba 5: Verificando que la escritura de %h fue exitosa.", DATA_3);
        we = 0; 
        addr = ADDR_2; 
        @(posedge clk); // Ciclo N: Lee ADDR_2
        @(posedge clk); // Ciclo N+1: El nuevo valor (DATA_3) aparece en 'data_out'
        
        #1; // <--- CORRECCIÓN 3: Esperar 1ps
        
        $display("Dato leido: %h", data_out);
        if (data_out !== DATA_3) begin
            $display("ERROR de Lectura 2: Se esperaba el dato nuevo %h pero se obtuvo %h", DATA_3, data_out);
            $finish;
        end

        $display("--- Testbench completado exitosamente ---");
        $finish; 

    end

endmodule
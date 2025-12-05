`timescale 1ns/1ps

module tb_bilinear_interp;

	// Parametros del Test
	localparam CLK_PERIOD = 10; // 100MHz
	
	// Señales del Testbench
	logic clk;
	logic rst_n;
	logic i_start;
	logic [7:0] i_p1, i_p2, i_p3, i_p4;
   logic [15:0] i_wx, i_wy;
   logic [7:0] o_pixel_out;
   logic       o_valid;
	
	// Instancia del DUT (Device Under Test)
	bilinear_interp dut (.*);
	
	// Generador de Reloj
	always begin
		clk = 1'b0; #(CLK_PERIOD / 2);
		clk = 1'b1; #(CLK_PERIOD / 2);
	end
	
	// Proceso Principal del Test
	initial begin
		$display("Iniciando Testbench...");
		
		// 1. Reset
		rst_n = 1'b1;
		i_start = 1'b0;
		i_p1 = '0; i_p2 = '0; i_p3 = '0; i_p4 = '0;
		i_wx = '0; i_wy = '0;
		repeat (2) @(posedge clk);
		rst_n = 1'b0;
		
		repeat (5) @(posedge clk);
		rst_n = 1'b1;
		@(posedge clk);
		
		// 2. Vector de Prueba 1 (Caso: 0.5, 0.5)
		$display("Aplicando Vector de Prueba 1 (Resultado esperado: 25)");
		i_p1 = 8'd10;
		i_p2 = 8'd20;
		i_p3 = 8'd30;
		i_p4 = 8'd40;
		i_wx = 16'h0080; // 0.5 Q8.8
		i_wy = 16'h0080; // 0.5 Q8.8
		
		i_start = 1'b1;
		@(posedge clk);
		i_start = 1'b0; // i_start es solo un pulso
		
		// 3. Esperar la salida valida
		while (!o_valid) begin
			@(posedge clk);
		end
		
		// 4. Verificar el resultado
		if (o_pixel_out == 8'd25) begin
			$display("PASO: Vector 1. Resultado = %d", o_pixel_out);
		end else begin
			$error("FALLO: Vector 1. Resultado = %d, Esperado = 25", o_pixel_out);
		end
		
		@(posedge clk);
		
		$display("Testbench completado.");
		$finish;
	end

endmodule
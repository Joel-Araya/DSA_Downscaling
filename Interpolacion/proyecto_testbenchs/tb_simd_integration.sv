`timescale 1ns/1ps

module tb_simd_integration;

	localparam CLK_PERIOD = 10;
	
	// Señales
	logic clk, rst_n, i_start, i_load_en;
   logic [15:0] i_wx, i_wy;
   logic o_valid;
	
	// Datos de entrada para registros (Ventana 5x2)
	logic [4:0][7:0] row0_in;
	logic [4:0][7:0] row1_in;
	
	// Salidas del SIMD
	logic [3:0][7:0] pixel_out;
	
	// Cables internos entre Registros y SIMD Core
	logic [3:0][7:0] w_p1, w_p2, w_p3, w_p4;
	
	// --- Instancia: Registros SIMD ---
	simd_registers u_regs (
		.clk(clk), .rst_n(rst_n), .i_load_enable(i_load_en),
		.i_row0_data(row0_in), .i_row1_data(row1_in),
		.o_p1_vec(w_p1), .o_p2_vec(w_p2), .o_p3_vec(w_p3), .o_p4_vec(w_p4)
	);

	// --- Instancia: Nucleo SIMD ---
	bilinear_interp_simd u_simd_core (
		.clk(clk), .rst_n(rst_n), .i_start(i_start),
		.i_p1_vec(w_p1), .i_p2_vec(w_p2), .i_p3_vec(w_p3), .i_p4_vec(w_p4),
		.i_wx(i_wx), .i_wy(i_wy),
		.o_pixel_out_vec(pixel_out), .o_valid(o_valid)
	);
	
	// Generador de Reloj
	always #(CLK_PERIOD/2) clk = ~clk;
	
	initial begin
		// Inicializacion
		clk = 0; rst_n = 1; i_start = 0; i_load_en = 0;
		i_wx = 16'h0080; i_wy = 16'h0080;	// (0.5, 0.5)
		
		//Reset
		#20 rst_n = 0; #20 rst_n = 1; #10;
		
		$display("--- Iniciando Test SIMD (N=4) ---");
		
		// Cargar Datos en Registros SIMD
		// Row 0: 10, 20, 30, 40, 50
		// Row 1: 10, 20, 30, 40, 50
		// Lane 0 (entre 10 y 20) -> 15
		// Lane 1 (entre 30 y 40) -> 25
		
		row0_in = '{8'd50, 8'd40, 8'd30, 8'd20, 8'd10};
		row1_in = '{8'd50, 8'd40, 8'd30, 8'd20, 8'd10};
		
		i_load_en = 1;
		@(posedge clk);
		i_load_en = 0;
		
		// Iniciar Procesamiento SIMD
		i_start = 1;
		@(posedge clk);
		i_start = 0;
		
		wait(o_valid);
		
		$display("Resultados SIMD: ");
		$display(" - Lane 0 (Esp:15): %d", pixel_out[0]);
		$display(" - Lane 1 (Esp:25): %d", pixel_out[1]);
		$display(" - Lane 2 (Esp:35): %d", pixel_out[2]);
		$display(" - Lane 3 (Esp:45): %d", pixel_out[3]);
		
		if(pixel_out[0] == 15 && pixel_out[3] == 45)
			$display(">> PASO: Validacion Paralela Exitosa");
		else
			$display(">> FALLO: Valores incorrectos");
		
		#50 $finish;
		
	end

endmodule 
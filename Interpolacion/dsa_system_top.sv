module dsa_system_top (
	input logic clk,
	input logic rst_n,
	// Interfaz de Control (JTAG)
	input logic i_start,
	input logic i_mode_select, // 0 = SEQ, 1 = SIMD
	output logic o_busy,
	output logic o_done,
	input logic [8:0] i_img_width,
	input logic [8:0] i_img_height,
	// Interfaz de Memoria (Para conectar a la BRAM Dual-Port)
	output logic [15:0] o_mem_addr,
	output logic o_mem_we,
	output logic [3:0]  o_mem_byte_en, // Importante para escritura parcial
	output logic [31:0] o_mem_wdata,
	input logic  [31:0] i_mem_rdata
);

	// Cables internos
	logic simd_start, simd_valid;
	logic seq_start, seq_valid;
	logic [3:0][7:0] simd_r0, simd_r1, simd_res;
	logic [7:0] seq_p1, seq_p2, seq_p3, seq_p4, seq_res;
	
	// Instancia del Controlador (FSM)
	main_controller u_controller (
		.clk(clk), 
		.rst_n(rst_n),
		.i_start(i_start), 
		.i_mode(i_mode_select),
		.o_busy(o_busy), 
		.o_done(o_done),
		.i_width(i_img_width), 
		.i_height(i_img_height),
		.o_mem_addr(o_mem_addr), 
		.o_mem_we(o_mem_we),
		.o_mem_byte_en(o_mem_byte_en),
		.o_mem_wdata(o_mem_wdata), 
		.i_mem_rdata(i_mem_rdata),
		// SIMD
		.o_simd_start(simd_start),
		.o_row0_vec(simd_r0), 
		.o_row1_vec(simd_r1),
		.i_simd_result(simd_res), 
		.i_simd_valid(simd_valid),
		// Sequential
		.o_seq_start(seq_start),
		.o_seq_p1(seq_p1), 
		.o_seq_p2(seq_p2), 
		.o_seq_p3(seq_p3), 
		.o_seq_p4(seq_p4),
		.i_seq_result(seq_res), 
		.i_seq_valid(seq_valid)
);
	
	// Instancia SIMD Core
	// Nota: i_wx e i_wy estan hardcodeados a o.5 (0x0080) por ahora,
	// o deben venir de registros de configuracion.
	bilinear_interp_simd u_simd_core (
		.clk(clk), 
		.rst_n(rst_n),
		.i_start(simd_start),
		.i_p1_vec(simd_r0), 
		.i_p2_vec(simd_r0), 
		.i_p3_vec(simd_r1), 
		.i_p4_vec(simd_r1),
		.i_wx(16'h0080), // 0.5 fijo
		.i_wy(16'h0080), // 0.5 fijo
		.o_pixel_out_vec(simd_res),
		.o_valid(simd_valid)
	);
	
	// Instancia Sequential Core
	bilinear_interp u_seq_core (
		.clk(clk), .rst_n(rst_n),
		.i_start(seq_start),
		.i_p1(seq_p1), 
		.i_p2(seq_p2), 
		.i_p3(seq_p3), 
		.i_p4(seq_p4),
		.i_wx(16'h0080), 
		.i_wy(16'h0080),
		.o_pixel_out(seq_res),
		.o_valid(seq_valid)
	);

endmodule 
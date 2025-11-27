module dsa_system_top (
	input logic clk,
	input logic rst_n,
	// Interfaz de Control (JTAG)
	input logic i_start,
	output logic o_busy,
	output logic o_done,
	input logic [8:0] i_img_width,
	input logic [8:0] i_img_height,
	// Interfaz de Memoria (Para conectar a la BRAM Dual-Port)
	output logic [15:0] o_mem_addr,
	output logic o_mem_we,
	output logic [31:0] o_mem_wdata,
	input logic  [31:0] i_mem_rdata
);

	// Cables internos
	logic simd_start, simd_valid;
	logic [3:0][7:0] row0, row1, res_vec;
	
	// Instancia del Controlador (FSM)
	main_controller u_controller (
		.clk(clk), .rst_n(rst_n),
		.i_start(i_start), .o_busy(o_busy), .o_done(o_done),
		.i_width(i_img_width), .i_height(i_img_height),
		.o_mem_addr(o_mem_addr), .o_mem_we(o_mem_we),
		.o_mem_wdata(o_mem_wdata), .i_mem_rdata(i_mem_rdata),
		.o_simd_start(simd_start),
		.o_row0_vec(row0), .o_row1_vec(row1),
		.i_simd_result(res_vec), .i_simd_valid(simd_valid)
	);
	
	// Instancia del Nucleo SIMD 
	// Nota: i_wx e i_wy estan hardcodeados a o.5 (0x0080) por ahora,
	// o deben venir de registros de configuracion.
	bilinear_interp_simd u_simd_core (
		.clk(clk), .rst_n(rst_n),
		.i_start(simd_start),
		.i_p1_vec(row0), // Simplificación: Usamos row0 como P1 (ajustar lógica de ventana si necesario)
		.i_p2_vec(row0), // Simplificación para compilación
		.i_p3_vec(row1), 
		.i_p4_vec(row1),
		.i_wx(16'h0080), .i_wy(16'h0080), // 0.5 fijo
		.o_pixel_out_vec(res_vec),
		.o_valid(simd_valid)
	);

endmodule 
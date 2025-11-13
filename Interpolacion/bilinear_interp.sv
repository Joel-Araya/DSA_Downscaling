/*
 * Modulo Wrapper: Pipeline de Interpolación Modular
 * - Conecta las 3 etapas del pipeline.
 */
 
module bilinear_interp (
	input logic clk,
	input logic rst_n,

	// Interfaz de control
	input logic i_start,

	// Entradas de datos
	input logic [7:0] i_p1, i_p2, i_p3, i_p4,
	input logic [15:0] i_wx, i_wy, // Q8.8

	// Salida final
	output logic [7:0] o_pixel_out,
	output logic       o_valid
);

	// --- Cables de conexión entre etapas ---

	// Etapa 1 -> Etapa 2
	logic [15:0] w_s1_lerp1, w_s1_lerp2, w_s1_wy;
	logic        w_s1_valid;

	// Etapa 2 -> Etapa 3
	logic [15:0] w_s2_pfinal;
	logic        w_s2_valid;

	// --- Instanciación de Módulos ---

	// Instancia Etapa 1
	stage1_interp_x u_stage1 (
		.clk        (clk),
		.rst_n      (rst_n),
		.i_start    (i_start),
		.i_p1       (i_p1),
		.i_p2       (i_p2),
		.i_p3       (i_p3),
		.i_p4       (i_p4),
		.i_wx       (i_wx),
		.i_wy       (i_wy),
		.o_lerp_1_q (w_s1_lerp1),
		.o_lerp_2_q (w_s1_lerp2),
		.o_wy_q     (w_s1_wy),
		.o_valid    (w_s1_valid)
	);

	// Instancia Etapa 2
	stage2_interp_y u_stage2 (
		.clk         (clk),
		.rst_n       (rst_n),
		.i_lerp_1_q  (w_s1_lerp1),
		.i_lerp_2_q  (w_s1_lerp2),
		.i_wy_q      (w_s1_wy),
		.i_valid     (w_s1_valid),
		.o_p_final_q (w_s2_pfinal),
		.o_valid     (w_s2_valid)
	);

	// Instancia Etapa 3
	stage3_convert u_stage3 (
		.clk         (clk),
		.rst_n       (rst_n),
		.i_p_final_q (w_s2_pfinal),
		.i_valid     (w_s2_valid),
		.o_pixel_out (o_pixel_out), // Salida final
		.o_valid     (o_valid)      // Salida final
	);

endmodule
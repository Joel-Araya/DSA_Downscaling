module bilinear_interp_simd (
	input logic clk, 
	input logic rst_n,
	// Control
	input logic i_start,		
	// Vectores de Entrada
	input logic [3:0][7:0] i_p1_vec, // Vecinos Arriba-Izquierda
	input logic [3:0][7:0] i_p2_vec, // Vecinos Arriba-Derecha
	input logic [3:0][7:0] i_p3_vec, // Vecinos Abajo-Izquierda
	input logic [3:0][7:0] i_p4_vec, // Vecinos	Abajo-Derecha
	// Pesos
	input logic [15:0] i_wx,
	input logic [15:0] i_wy,
	// Salida Vectorial
	output logic [3:0][7:0] o_pixel_out_vec,
	output logic o_valid
);
	
	// Valid individual para cada lane (interna)
	logic [3:0] valid_lanes;
	
	// Generar 4 instancias (Lanes 0 a 3)
	genvar i;
	generate 
		for (i = 0; i < 4; i++) begin : sim_lanes
			bilinear_interp u_core (
				.clk (clk),
				.rst_n (rst_n),
				.i_start (i_start),
				.i_p1 (i_p1_vec[i]),
				.i_p2 (i_p2_vec[i]),
				.i_p3 (i_p3_vec[i]),
				.i_p4 (i_p4_vec[i]),
				.i_wx (i_wx),
				.i_wy (i_wy),
				.o_pixel_out (o_pixel_out_vec[i]),
				.o_valid (valid_lanes[i])
			);
		end
	endgenerate
	
	// La salida es valida si el carril 0 es valido (todos sincronizados)
	assign o_valid = valid_lanes[0];

endmodule 

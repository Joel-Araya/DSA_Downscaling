/*
 * Etapa 1 del Pipeline: Interpolacion en X
 * - Calcula lerp_1 y lerp_2 en paralelo.
 * - Registra las salidas y pasa w_y y 'valid' a la siguiente etapa.
 */
 
 module stage1_interp_x (
	input logic clk,
	input logic rst_n,
	
	// Control y datos de entrada
	input logic 			i_start,
	input logic [7:0]		i_p1, i_p2, i_p3, i_p4,
	input logic [15:0]	i_wx, // Q8.8
	input logic [15:0]	i_wy, // Q8.8
	
	// Salidas a la Etapa 2
	output logic [15:0] o_lerp_1_q, // Q8.8
	output logic [15:0] o_lerp_2_q, // Q8.8
	output logic [15:0] o_wy_q, 	  // Q8.8
	output logic 		  o_valid
 );
 
	localparam ONE_Q88 = 16'h0100; // 1.0 en Q8.8
	
	logic [15:0] p1_q, p2_q, p3_q, p4_q;
	logic [15:0] wx_inv;
	logic [31:0] mul1_x, mul2_x, mul3_x, mul4_x;
	logic [15:0] lerp_1_comb, lerp_2_comb;
	
	// Promocion de pixeles a Q8.8
	assign p1_q = {i_p1, 8'b0};
   assign p2_q = {i_p2, 8'b0};
   assign p3_q = {i_p3, 8'b0};
   assign p4_q = {i_p4, 8'b0};
	
	assign wx_inv = ONE_Q88 - i_wx;
	
	// lerp_1 = P1*(1-w_x) + P2*w_x
   assign mul1_x = p1_q * wx_inv;
   assign mul2_x = p2_q * i_wx;
   assign lerp_1_comb = (mul1_x >> 8) + (mul2_x >> 8);
	
	// lerp_2 = P3*(1-w_x) + P4*w_x
   assign mul3_x = p3_q * wx_inv;
   assign mul4_x = p4_q * i_wx;
   assign lerp_2_comb = (mul3_x >> 8) + (mul4_x >> 8);
	
	// Registros de salida de la Etapa 1
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			o_lerp_1_q <= '0;
			o_lerp_2_q <= '0;
			o_wy_q     <= '0;
			o_valid    <= '0;
		end else begin
			o_lerp_1_q <= lerp_1_comb;
			o_lerp_2_q <= lerp_2_comb;
			o_wy_q     <= i_wy; // Pasa w_y al siguiente registro
			o_valid    <= i_start;
		end
	end
 
 endmodule
 
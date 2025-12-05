/*
 * Etapa 2 del Pipeline: Interpolacion en Y
 * - Calcula el pixel final en formato Q8.8.
 * - Registra la salida y pasa 'valid'.
 */
 
module stage2_interp_y (
	input logic clk,
	input logic rst_n,

	// Entradas desde la Etapa 1
	input logic [15:0] i_lerp_1_q, // Q8.8
	input logic [15:0] i_lerp_2_q, // Q8.8
	input logic [15:0] i_wy_q,     // Q8.8
	input logic        i_valid,

	// Salidas a la Etapa 3
	output logic [15:0] o_p_final_q, // Q8.8
	output logic        o_valid
);

	localparam ONE_Q88 = 16'h0100; // 1.0 en Q8.8

	// Lógica combinacional de la Etapa 2
	logic [15:0] wy_inv;
	logic [31:0] mul1_y, mul2_y;
	logic [15:0] p_final_comb;

	assign wy_inv = ONE_Q88 - i_wy_q;

	// p_final = lerp_1*(1-w_y) + lerp_2*w_y
	assign mul1_y = i_lerp_1_q * wy_inv;
	assign mul2_y = i_lerp_2_q * i_wy_q;
	assign p_final_comb = (mul1_y >> 8) + (mul2_y >> 8);

	// Registros de salida de la Etapa 2
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			o_p_final_q <= '0;
			o_valid     <= '0;
		end else begin
			o_p_final_q <= p_final_comb;
			o_valid     <= i_valid;
		end
	end

endmodule

/*
 * Etapa 3 del Pipeline: Conversion de Formato
 * - Convierte el resultado Q8.8 a Entero de 8 bits (UInt8).
 * - Registra la salida final.
 */
 
module stage3_convert (
	input logic clk,
	input logic rst_n,

	// Entradas desde la Etapa 2
	input logic [15:0] i_p_final_q, // Q8.8
	input logic        i_valid,

	// Salidas finales del pipeline
	output logic [7:0] o_pixel_out,
	output logic       o_valid
	);

	// Logica combinacional de la Etapa 3
	// Truncamiento: toma la parte entera [15:8]
	logic [7:0] pixel_out_comb;
	assign pixel_out_comb = i_p_final_q[15:8];

	// Registros de salida de la Etapa 3
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			o_pixel_out <= '0;
			o_valid     <= '0;
		end else begin
			o_pixel_out <= pixel_out_comb;
			o_valid     <= i_valid;
		end
	end

endmodule

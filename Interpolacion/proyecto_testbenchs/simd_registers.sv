module simd_registers (
	input logic clk,
	input logic rst_n,
	input logic i_load_enable,
	// Entrada de datos desde memoria
	input logic [4:0][7:0] i_row0_data,      // Pixeles [x, x+1, x+2, x+3]
	input logic [4:0][7:0] i_row1_data,      // Pixeles [x, x+1, x+2, x+3]
	// Salidas formateadas para el nucleo SIMD
	output logic [3:0][7:0] o_p1_vec ,
	output logic [3:0][7:0] o_p2_vec,
	output logic [3:0][7:0] o_p3_vec,
	output logic [3:0][7:0] o_p4_vec
);

	// Registros internos 
	logic [4:0][7:0] r_row0;
	logic [4:0][7:0] r_row1;
	
	// Escritura de Registros
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			for (int k=0; k<5; k++) begin
				r_row0[k] <= '0;
				r_row1[k] <= '0;
			end
		end else if (i_load_enable) begin
			r_row0 <= i_row0_data;
			r_row1 <= i_row1_data;
		end
	end
	
	// Logica de Distribucion (Wiring) para los 4 lanes
	
	always_comb begin
		for (int i=0; i<4; i++) begin
			o_p1_vec[i] = r_row0[i];	// Top-Left
			o_p2_vec[i] = r_row0[i+1];	// Top-Right
			o_p3_vec[i] = r_row1[i];	// Bottom-Left
			o_p4_vec[i] = r_row1[i+1];	// Bottom-Right
		end
	end

endmodule 

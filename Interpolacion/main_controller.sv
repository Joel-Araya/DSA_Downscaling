module main_controller (
	input logic clk,
	input logic rst_n,
	// Señales de Control desde JTAG/Registros
	input logic i_start,
	output logic o_busy,
	output logic o_done,
	// Configuracion (asumimos fijos por ahora o vienen de registros)
	input logic [8:0] i_width, 	// 512
	input logic [8:0] i_height, 	// 512
	// Interfaz con Memoria
	output logic [15:0] o_mem_addr, 	// Direccion compartida read/write
	output logic o_mem_we, 				// Write Enable
	output logic [31:0] o_mem_wdata,	// Dato a escribir (4 pixeles)
	input logic [31:0] i_mem_rdata, 	// Dato leido (ancho 32 bits = 4 pixeles)
	// Interfaz con Nucleo SIMD
	output logic o_simd_start,
	output logic [3:0][7:0] o_row0_vec,	// A SIMD Registers
	output logic [3:0][7:0] o_row1_vec,	// A SIMD Registers
	input logic  [3:0][7:0] i_simd_result, // Desde SIMD Core
	input logic i_simd_valid
);
	
	// Estados de la FSM
	typedef enum logic [3:0] {
		IDLE,
		READ_R0,			// Leer Fila Superior
		WAIT_R0,			// Esperar RAM
		READ_R1,			// Leer Fila Inferior
		WAIT_R1,			// Esperar RAM
		TRIGGER_SIMD,	// Disparar calculo
		WAIT_SIMD,		// Esperar resultado valido
		WRITE_RES,		// Escribir en memoria 
		UPDATE_ADDR,	// Calcular siguiente bloque
		DONE
	} state_t;
	
	state_t state;
	
	// Contadores XY
	logic [8:0] x_cnt;
	logic [8:0] y_cnt;
	
	// Direcciones base (Offsets en memoria)
	// Asumimos:
	// - Imagen Entrada inicia en direccion 0
	// - Imagen Salida inicia en direccion 65536 (despues de 512x512 bytes si fuera byte-addressing, 
	//   pero se simplifica para el ejemplo).
	//   NOTA: ajustar segun el mapa de memoria definido
	localparam INPUT_BASE_ADDR = 16'd0;
	localparam OUTPUT_BASE_ADDR = 16'd16384;
	
	//Buffers temporales para datos leidos
	logic [31:0] row0_data;
	logic [31:0] row1_data;
	
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			state <= IDLE;
			x_cnt <= '0;
			y_cnt <= '0;
			o_done <= 1'b0;
			row0_data <= '0;
			row1_data <= '0;
		end else begin 
			case (state)
				IDLE: begin
					o_done <= 1'b0;
					x_cnt <= '0;
					y_cnt <= '0;
					if (i_start) state <= READ_R0;
				end
				
				READ_R0: state <= WAIT_R0;
				WAIT_R0: begin
					row0_data <= i_mem_rdata; // Guardar dato leido
					state <= READ_R1;
				end
				
				READ_R1: state <= WAIT_R1;
				WAIT_R1: begin
					row1_data <= i_mem_rdata; // Guardar dato leido
					state <= TRIGGER_SIMD;
				end
				
				TRIGGER_SIMD: state <= WAIT_SIMD;
				
				WAIT_SIMD : begin
					if (i_simd_valid) state <= WRITE_RES;
				end
				
				WRITE_RES: state <= UPDATE_ADDR;
				
				UPDATE_ADDR: begin
					// Logica de barrido
					if (x_cnt + 4 >= i_width) begin
						x_cnt <= '0;
						if (y_cnt + 2 >= i_height) begin
							state <= DONE; // Fin de imagen
						end else begin
							y_cnt <= y_cnt + 2; // Siguiente par de filas
							state <= READ_R0;
						end
					end else begin
						x_cnt <= x_cnt + 4;
						state <= READ_R0;
					end
				end
				
				DONE: begin
					o_done <= 1'b1;
					if (!i_start) state <= IDLE; // Reset handshake
				end
			endcase 
		end 
	end
	
	// Logica Combinacional de Salidas
	always_comb begin
		o_busy = (state != IDLE && state != DONE);
		o_mem_we = 1'b0;
		o_mem_addr = '0;
		o_simd_start = 1'b0;
		
		// Mapeo de vectores para el SIMD (Simplificado: asume alineación perfecta de 4 pixeles)
      // En una implementación real robusta, aquí va la lógica de "Ventana Deslizante"
      // combinando partes de row0_data anterior y actual.
      // Para este avance, pasamos los datos directos. 
		o_row0_vec = row0_data; // Casting implicito de 32 bits a [3:0][7:0]
		o_row1_vec = row1_data;
		
		o_mem_wdata = i_simd_result; // Escribir resultado del SIMD
		
		case (state) 
			READ_R0: begin
			// Calcular dirección lineal: (y * width + x) / 4 (palabras de 32 bits)
				o_mem_addr = INPUT_BASE_ADDR + ((y_cnt * i_width) + x_cnt) / 4;
			end
			
			READ_R1: begin
				o_mem_addr = INPUT_BASE_ADDR + (((y_cnt + 1) * i_width) + x_cnt) / 4;
			end
			
			TRIGGER_SIMD: o_simd_start = 1'b1;
			
			WRITE_RES: begin
				o_mem_we = 1'b1;
				// Dirección salida: (y_out * width_out + x_out) / 4
				// Como es downscaling 0.5, y_out = y_cnt/2, x_out = x_cnt/2
				// Esto requiere ajuste matemático, simplificado aquí:
				o_mem_addr = OUTPUT_BASE_ADDR + (((y_cnt/2) * (i_width/2)) + (x_cnt/2)) / 4;
			end
		endcase 
		
	end
	
endmodule 




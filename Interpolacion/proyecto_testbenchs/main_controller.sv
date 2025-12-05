module main_controller (
	input logic clk,
	input logic rst_n,
	// Control Global
	input logic  i_start,
	input logic  i_mode,	// 0 = Secuencial , 1 = SIMD
	output logic o_busy,
	output logic o_done,
	// Stepping
	input logic i_step_mode,	// 1 = Habilitar modo stepping
	input logic i_step_trig,	// Señal de disparo (botón "Siguiente")
	// Configuracion de Escala
	input logic [8:0]  i_width,		// 512
	input logic [8:0]  i_height, 	// 512
	input logic [15:0] i_inv_scale, // Paso de avance en Q8.8 (1/Scale)
	// Interfaz con Memoria (Lectura/Escritura 32 bits)
	output logic [15:0] o_mem_addr, 		// Direccion compartida read/write
	output logic 		  o_mem_we, 					// Write Enable
	output logic [3:0]  o_mem_byte_en,	// Habilita bytes individuales
	output logic [31:0] o_mem_wdata,		// Dato a escribir (4 pixeles)
	input logic  [31:0] i_mem_rdata, 		// Dato leido (ancho 32 bits = 4 pixeles)
	// Pesos calculados
	output logic [15:0] o_wx,
	output logic [15:0] o_wy,
	// Interfaz SIMD Core
	output logic o_simd_start,
	output logic [3:0][7:0] o_row0_vec,		// A SIMD Registers
	output logic [3:0][7:0] o_row1_vec,		// A SIMD Registers
	input logic 				i_simd_valid,
	input logic  [3:0][7:0] i_simd_result, // Desde SIMD Core
	// Interfaz Sequential Core
	output logic 		 o_seq_start,
	output logic [7:0] o_seq_p1, o_seq_p2, o_seq_p3, o_seq_p4,
	input logic 		 i_seq_valid,
	input logic [7:0]  i_seq_result
);
	
	// Estados de la FSM
	typedef enum logic [3:0] {
		IDLE,
		CALC_ADDR,		// Calcular direcciones basadas en acumuladores
		READ_R0,			// Leer Fila Superior
		WAIT_R0,			// Esperar RAM
		READ_R1,			// Leer Fila Inferior
		WAIT_R1,			// Esperar RAM
		TRIGGER_CALC,	// Disparar calculo
		WAIT_CALC,		// Esperar resultado valido
		WRITE_RES,		// Escribir en memoria 
		CHECK_STEP,		// Verificar si pausar
		PAUSED,			// Estado de pausa
		UPDATE_ACC,		// Avanzar acumuladores
		DONE
	} state_t;
	
	state_t state;
	
	// Acumuladores de Posicion 
	// Bits [16:8] = Parte Entera (Coordenada pixel) y Bits [7:0] = Parte Fraccionaria (Peso wx/wy)
	logic [16:0] x_acc;
	logic [16:0] y_acc;
	
	// Coordenadas enteras actuales
	logic [8:0] x_int;
	logic [8:0] y_int;
	
	// Detector de flanco para el boton de stepping 
	logic trig_d, trig_pulse;
	always_ff @(posedge clk) begin
		trig_d <= i_step_trig;
	end
	assign trig_pulse = i_step_trig && !trig_d; // Detecta subida 0->1
	
	//Buffers temporales para datos leidos
	logic [31:0] row0_data;
	logic [31:0] row1_data;
	
	// Direcciones base (Offsets en memoria)
	// Asumimos:
	// - Imagen Entrada inicia en direccion 0
	// - Imagen Salida inicia en direccion 65536 (despues de 512x512 bytes si fuera byte-addressing, 
	//   pero se simplifica para el ejemplo).
	//   NOTA: ajustar segun el mapa de memoria definido
	localparam INPUT_BASE_ADDR = 16'd0;
	localparam OUTPUT_BASE_ADDR = 16'd16384;
	
	// Logica Secuencial (FSM)
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			state <= IDLE;
			x_acc <= '0;
			y_acc <= '0;
			o_done <= 1'b0;
		end else begin 
			case (state)
				IDLE: begin
					o_done <= 1'b0;
					x_acc <= '0;
					y_acc <= '0;
					if (i_start) state <= CALC_ADDR;
				end
				
				CALC_ADDR: begin
					x_int <= x_acc[16:8];
					y_int <= y_acc[16:8];
					state <= READ_R0;
				end
				
				READ_R0: state <= WAIT_R0;
				WAIT_R0: begin
					row0_data <= i_mem_rdata; // Guardar dato leido
					state <= READ_R1;
				end
				
				READ_R1: state <= WAIT_R1;
				WAIT_R1: begin
					row1_data <= i_mem_rdata; // Guardar dato leido
					state <= TRIGGER_CALC;
				end
				
				TRIGGER_CALC: state <= WAIT_CALC;
				
				WAIT_CALC: begin
				// Esperar al valid del modo activo
					if ((i_mode && i_simd_valid) || (!i_mode && i_seq_valid))
						state <= WRITE_RES;
				end
				
				WRITE_RES: state <= CHECK_STEP;
				
				CHECK_STEP: begin
					if (i_step_mode) state<= PAUSED;
					else state <= UPDATE_ACC;
				end
				
				PAUSED: begin
					if (trig_pulse) state <= UPDATE_ACC;
				end
				
				UPDATE_ACC: begin
					// Logica de avance dependiente del modo
					logic [16:0] next_x;
					logic [16:0] next_y;
					if (i_mode) next_x = x_acc + (i_inv_scale << 2); 	// + 4 * paso
					else next_x = x_acc + i_inv_scale;						// + 1 * paso
					
					// Verificacion de limites (usando la parte entera)
					if (next_x[16:8] >= i_width) begin
						x_acc <= '0; // Reset X
						// Avanzar Y
						next_y = y_acc + i_inv_scale; // Siempre avanzamos fila a fila
						if (next_y[16:8] >= i_height) begin
							state <= DONE; // Fin de imagen
						end else begin
							y_acc <= next_y; // Siguiente par de filas
							state <= READ_R0;
						end
					end else begin
						x_acc <= next_x;
						state <= CALC_ADDR;
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
		// Defaults
		o_busy = (state != IDLE && state != DONE);
		o_mem_we = 1'b0;
		o_mem_addr = '0;
		o_mem_byte_en = 4'b0000;
		o_mem_wdata = 0;
		o_simd_start = 1'b0;
		o_seq_start = 1'b0;
		
		// Asginar Pesos (Parte fraccionaria del acumulador)
		o_wx = {8'b0, x_acc[7:0]};
		o_wy = {8'b0, y_acc[7:0]};
		
		// Datos para SIMD (Pasa todo el bloque)
		o_row0_vec = row0_data; // Casting implicito de 32 bits a [3:0][7:0]
		o_row1_vec = row1_data;
		
		// Datos para Sequencial
		// Simplificación: Asumimos que x_cnt está alineado a palabra para la lectura de bloque.
		// En una implementación real pixel a pixel, habría que manejar offsets dentro de row0_data.
		// Aquí asumimos x_cnt local dentro del bloque leído (bits [1:0]).
		// P1 = row0[offset], P2 = row0[offset+1]...
		// Nota: Esto requeriría un barrel shifter si leemos alineado. 
		// Para simplificar este avance, asumiremos que en modo secuencial leemos 
		// siempre alineado y usamos byte enables solo para escritura.
		o_seq_p1 = row0_data[7:0];		// Top-Left
		o_seq_p2 = row0_data[15:8];	// Top-Right
		o_seq_p3 = row1_data[7:0];		// Bottom-Left
		o_seq_p4 = row1_data[15:8];	// Bottom-Right
		
		case (state) 
			READ_R0: begin
				// Calcular dirección lineal: (y * width + x) / 4 (palabras de 32 bits)
				o_mem_addr = INPUT_BASE_ADDR + ((y_int * i_width) + x_int) / 4;
			end
			
			READ_R1: begin
				o_mem_addr = INPUT_BASE_ADDR + (((y_int + 1) * i_width) + x_int) / 4;
			end
			
			TRIGGER_CALC: begin
				if (i_mode) o_simd_start = 1'b1;
				else 			 o_seq_start = 1'b1;
			end
			
			WRITE_RES: begin
				o_mem_we = 1'b1;
				// Dirección salida: (y_out * width_out + x_out) / 4
				// Como es downscaling 0.5, y_out = y_int/2, x_out = x_int/2
				// Esto requiere ajuste matemático, simplificado aquí:
				o_mem_addr = OUTPUT_BASE_ADDR + ((y_int * (i_width/2)) + (x_int/2)) / 4;
				
				if (i_mode) begin
					// Modo SIMD: Escribe 4 bytes
					o_mem_byte_en = 4'b1111;
					o_mem_wdata = i_simd_result;
				end else begin
					// Modo SEQUENTIAL: Escribe 1 byte en la posicion correcta
					// Calculamos el offset del byte dentro de la palabra
					o_mem_byte_en = (4'b0001 << (x_int % 4));
					o_mem_wdata = {4{i_seq_result}}; // Replica el dato (el byte enable filtra)
				end
			end
		endcase 
		
	end
	
endmodule 

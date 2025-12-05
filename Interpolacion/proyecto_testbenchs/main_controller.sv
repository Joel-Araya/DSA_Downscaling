module main_controller (
	input logic clk,
	input logic rst_n,
	// Control Global
	input logic  i_start,
	input logic  i_mode,	    // 0 = Secuencial , 1 = SIMD
	output logic o_busy,
	output logic o_done,
	// Stepping
	input logic i_step_mode,	// 1 = Habilitar modo stepping
	input logic i_step_trig,	// Señal de disparo ("Siguiente")
	// Configuracion de Escala
	input logic [8:0]  i_width,
	input logic [8:0]  i_height,
	input logic [15:0] i_inv_scale, // Paso de avance en Q8.8 (1/Scale)
	// Interfaz con Memoria (Lectura/Escritura 32 bits)
	output logic [15:0] o_mem_addr, 
	output logic 		  o_mem_we,
	output logic [3:0]  o_mem_byte_en,
	output logic [31:0] o_mem_wdata,
	input logic  [31:0] i_mem_rdata,
	// Pesos calculados
	output logic [15:0] o_wx,
	output logic [15:0] o_wy,
	// Interfaz SIMD Core
	output logic o_simd_start,
	output logic [3:0][7:0] o_row0_vec,	
	output logic [3:0][7:0] o_row1_vec,	
	input logic 				i_simd_valid,
	input logic  [31:0] i_simd_result, // CORRECCION: 32 bits para SIMD
	// Interfaz Sequential Core
	output logic 		 o_seq_start,
	output logic [7:0] o_seq_p1, o_seq_p2, o_seq_p3, o_seq_p4,
	input logic 		 i_seq_valid,
	input logic [7:0]  i_seq_result
);

    // Estados de la FSM
	typedef enum logic [3:0] {
		IDLE,
		CALC_ADDR,		
		READ_R0, WAIT_R0, 
		READ_R1, WAIT_R1, 
		TRIGGER_CALC,	
		WAIT_CALC,		
		WRITE_RES,		
		PAUSED,         // Estado de pausa simple
		UPDATE_ACC,		
		DONE
	} state_t;

	state_t state;
	
	// Acumuladores de Posicion 
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
	assign trig_pulse = i_step_trig && !trig_d;
	
	//Buffers temporales para datos leidos
	logic [31:0] row0_data;
	logic [31:0] row1_data;
	
	// Direcciones base
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
                    // Si el stepping está activo, pausa aquí ANTES de leer memoria
                    if (i_step_mode) state <= PAUSED;
					else state <= READ_R0;
				end
                
                PAUSED: begin
                    // Espera el pulso de avance
                    if (trig_pulse) state <= READ_R0;
                end
				
				READ_R0: state <= WAIT_R0;
				WAIT_R0: begin
					row0_data <= i_mem_rdata; 
					state <= READ_R1;
				end
				
				READ_R1: state <= WAIT_R1;
				WAIT_R1: begin
					row1_data <= i_mem_rdata;
					state <= TRIGGER_CALC;
				end
				
				TRIGGER_CALC: state <= WAIT_CALC;
				
				WAIT_CALC: begin
					if ((i_mode && i_simd_valid) || (!i_mode && i_seq_valid))
						state <= WRITE_RES;
				end
				
				WRITE_RES: state <= UPDATE_ACC; // Simplificado: siempre avanza
				
				UPDATE_ACC: begin
					// Logica de avance dependiente del modo
					logic [16:0] next_x;
					logic [16:0] next_y;
					
					if (i_mode) next_x = x_acc + (i_inv_scale << 2);
					else next_x = x_acc + i_inv_scale;
					
					// Verificacion de limites
					if (next_x[16:8] >= i_width) begin
						x_acc <= '0;
						next_y = y_acc + i_inv_scale; 
						
						if (next_y[16:8] >= i_height) begin
							state <= DONE;
						end else begin
							y_acc <= next_y;
							state <= CALC_ADDR; // Reinicia el ciclo
						end
					end else begin
						x_acc <= next_x;
						state <= CALC_ADDR; // Reinicia el ciclo
					end
				end
				
				DONE: begin
					o_done <= 1'b1;
					if (!i_start) state <= IDLE;
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
        
        // Pausar si estamos en PAUSED
        if (state == PAUSED) o_busy = 1'b1;
		
		// Asginar Pesos (Parte fraccionaria del acumulador)
		o_wx = {8'b0, x_acc[7:0]};
		o_wy = {8'b0, y_acc[7:0]};

		// Datos para SIMD (Pasa todo el bloque)
		o_row0_vec = row0_data;
		o_row1_vec = row1_data;
		
		// Datos para Sequencial
		o_seq_p1 = row0_data[7:0];		
		o_seq_p2 = row0_data[15:8];	
		o_seq_p3 = row1_data[7:0];		
		o_seq_p4 = row1_data[15:8];
		
		case (state) 
			READ_R0: begin
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
				o_mem_addr = OUTPUT_BASE_ADDR + (((y_int/2) * (i_width/2)) + (x_int/2)) / 4;

				if (i_mode) begin
					// MODO SIMD: Escribe 4 bytes (1111)
					o_mem_byte_en = 4'b1111;
					o_mem_wdata = i_simd_result;
				end else begin
					// MODO SEQUENCIAL: Escribe 1 byte (0001 << offset)
					logic [1:0] byte_offset;
					byte_offset = (x_int/2) % 4; // x_out = x_int/2
					o_mem_byte_en = (4'b0001 << byte_offset); 
					o_mem_wdata = {4{i_seq_result}}; 
				end
			end
		endcase 
	end
endmodule
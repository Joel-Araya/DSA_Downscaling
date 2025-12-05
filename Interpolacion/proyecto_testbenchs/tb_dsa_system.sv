`timescale 1ns/1ps

module tb_dsa_system;

	// --- Configuración ---
	localparam CLK_PERIOD = 10;
	// Imagen de prueba pequeña para simulación: 8x4 píxeles
	localparam IMG_W = 8;
	localparam IMG_H = 4;

	// Mapa de Memoria (Word Addressing)
	localparam ADDR_INPUT  = 16'd0;
	localparam ADDR_OUTPUT = 16'd16384; 

	// --- Señales de Control y Configuración ---
	logic clk, rst_n;
	logic i_start, i_mode;
	logic [8:0] i_w, i_h;

	// ** NUEVAS SEÑALES: STEPPING Y ESCALA **
	logic i_step_mode;              // 1 = Activa Stepping [RF-09]
	logic i_step_trig;              // Botón "Siguiente"
	logic [15:0] i_inv_scale;       // Factor de Escala Inverso (Q8.8) [RF-03]

	logic o_busy, o_done;

	// Interfaz de Memoria
	logic [15:0] mem_addr;
	logic        mem_we;
	logic [3:0]  mem_byte_en;
	logic [31:0] mem_wdata;
	logic [31:0] mem_rdata;

	// --- Memoria Simulada (Array) ---
	logic [31:0] fake_ram [0:16384+100]; 

	// --- Instancia del TOP Actualizado ---
	dsa_system_top dut (
		.clk(clk), .rst_n(rst_n),
		.i_start(i_start), .i_mode_select(i_mode),

		// Conexión de señales nuevas
		.i_step_mode(i_step_mode), 
		.i_step_trig(i_step_trig),
		.i_inv_scale(i_inv_scale),

		.o_busy(o_busy), .o_done(o_done),
		.i_img_width(i_w), .i_img_height(i_h),
		.o_mem_addr(mem_addr), .o_mem_we(mem_we),
		.o_mem_byte_en(mem_byte_en),
		.o_mem_wdata(mem_wdata), .i_mem_rdata(mem_rdata)
	);
	
	initial begin
		clk = 0;
	end

	// --- Generación de Reloj ---
	always #(CLK_PERIOD/2) clk = ~clk;

	// --- Comportamiento de la Memoria Simulada ---
	// 1. Lectura Síncrona
	always_ff @(posedge clk) begin
		if (!mem_we) begin
			mem_rdata <= fake_ram[mem_addr];
		end
	end

	// 2. Escritura Síncrona con Byte Enable
	always_ff @(posedge clk) begin
		if (mem_we) begin
			if (mem_byte_en[0]) fake_ram[mem_addr][7:0]   <= mem_wdata[7:0];
			if (mem_byte_en[1]) fake_ram[mem_addr][15:8]  <= mem_wdata[15:8];
			if (mem_byte_en[2]) fake_ram[mem_addr][23:16] <= mem_wdata[23:16];
			if (mem_byte_en[3]) fake_ram[mem_addr][31:24] <= mem_wdata[31:24];

			$display("[MEM WRITE] Time: %t | Addr: %d | Data: %h | ByteEn: %b", 
						$time, mem_addr, mem_wdata, mem_byte_en);
		end
	end

	// --- Inicialización de Datos de Prueba (Gradiente) ---
	task init_memory();
		integer i, j;
		logic [31:0] pixel_pack;
		$display("--- Inicializando Memoria Simulada (Gradiente) ---");

		for (i = 0; i < IMG_H; i++) begin
			for (j = 0; j < IMG_W; j=j+4) begin
				// Patrón: Valor = (y * 8) + x. Ej: Fila 0 = 0, 1, 2, 3...
				pixel_pack =  {8'(i*IMG_W + j+3+32), 
									8'(i*IMG_W + j+2+32), 
									8'(i*IMG_W + j+1+32), 
									8'(i*IMG_W + j+32)}; 
				fake_ram[ADDR_INPUT + (i*IMG_W + j)/4] = pixel_pack;
			end
		end
	endtask

	// --- Tarea Auxiliar: Simular Click en "Siguiente" ---
	task click_step();
		$display("   >> [USER] Click en 'Siguiente'...");
		i_step_trig = 1;
		repeat(2) @(posedge clk); 
		i_step_trig = 0;
		repeat(2) @(posedge clk); 
	endtask

	// --- Proceso Principal de Prueba ---
initial begin
		// Valores por defecto
		clk = 0; rst_n = 0; i_start = 0;
		i_mode = 0; i_step_mode = 0; i_step_trig = 0;
		i_w = IMG_W; i_h = IMG_H;

		// ** CORRECCIÓN CRÍTICA DE ESCALA **
		// Escala 0.75 (Avance 1.333...)
		// 1/0.75 ≈ 1.3333. En Q8.8 (x 2^8) es 341.33, redondeado a 16'h0155.
		i_inv_scale = 16'h0155; // Fuerza un peso fraccionario w_x = 0.33

		init_memory(); // Volvemos al patrón 0, 1, 2, 3...

		// Reset Inicial
		#20 rst_n = 1;
		#20;
		rst_n = 0; #10 rst_n = 1;

		// ------------------------------------------------
		// PRUEBA 1: MODO SIMD (Escala 0.75 - Corrida completa)
		// ------------------------------------------------
		$display("\n>>> PRUEBA 1: INICIANDO MODO SIMD (Escala 0.75) <<<");
		i_mode = 1; i_step_mode = 0; 
		i_start = 1;
		@(posedge clk);
		i_start = 0;

		wait(o_done);
		$display(">>> FIN MODO SIMD (Done activado) <<<");
		#100;

		// ------------------------------------------------
		// PRUEBA 2: MODO SECUENCIAL con STEPPING (Validar RF-09)
		// ------------------------------------------------
		$display("\n>>> PRUEBA 2: INICIANDO MODO SECUENCIAL con STEPPING (Escala 0.75) <<<");

		// Reiniciar contadores para la nueva prueba
		rst_n = 0; #10 rst_n = 1; 

		i_mode = 0;
		i_step_mode = 1;     // HABILITAR Stepping

		i_start = 1;
		@(posedge clk);
		i_start = 0;

		// Esperar 500ns para confirmar que el sistema se PAUSA
		$display("[TEST] Esperando 500ns. El sistema DEBE pausarse después del CALC_ADDR inicial.");
		#500; 

		// El controlador ya está en PAUSED. Hacemos 4 pasos.
		$display("\n[TEST] Enviando Trigger 1 (Paso 1/4):");
		click_step();
		#50;

		$display("\n[TEST] Enviando Trigger 2 (Paso 2/4):"); 
		click_step();
		#50;

		$display("\n[TEST] Enviando Trigger 3 (Paso 3/4):");
		click_step();
		#50;

		$display("\n[TEST] Enviando Trigger 4 (Paso 4/4):");
		click_step();
		#50;

		// Desactivar Stepping y dejar que termine la imagen
		$display("\n[TEST] Desactivando Stepping y Corriendo a final...");
		i_step_mode = 0;

		wait(o_done);
		$display("\n>>> PROCESO STEPPING TERMINADO EXITOSAMENTE <<<");

		#50 $finish;
	end

endmodule
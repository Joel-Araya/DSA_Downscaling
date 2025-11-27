`timescale 1ns/1ps

module tb_dsa_system;

	// --- Configuración ---
	localparam CLK_PERIOD = 10;
	// Usaremos una imagen diminuta para probar rápido: 8x4 píxeles
	localparam IMG_W = 8;
	localparam IMG_H = 4;

	// Mapa de Memoria (Debe coincidir con main_controller)
	localparam ADDR_INPUT  = 16'd0;
	localparam ADDR_OUTPUT = 16'd16384; 

	// --- Señales ---
	logic clk, rst_n;
	logic i_start, i_mode;
	logic [8:0] i_w, i_h;
	logic o_busy, o_done;

	// Interfaz de Memoria
	logic [15:0] mem_addr;
	logic        mem_we;
	logic [3:0]  mem_byte_en;
	logic [31:0] mem_wdata;
	logic [31:0] mem_rdata;

	// --- Memoria Simulada (Array) ---
	// Simulamos una RAM de 64KB (Word Addressing para facilitar TB)
	logic [31:0] fake_ram [0:16384+100]; 

	// --- Instancia del TOP ---
	dsa_system_top dut (
		.clk(clk), .rst_n(rst_n),
		.i_start(i_start), .i_mode_select(i_mode),
		.o_busy(o_busy), .o_done(o_done),
		.i_img_width(i_w), .i_img_height(i_h),
		.o_mem_addr(mem_addr), .o_mem_we(mem_we),
		.o_mem_byte_en(mem_byte_en),
		.o_mem_wdata(mem_wdata), .i_mem_rdata(mem_rdata)
	);

	// --- Generación de Reloj ---
	always #(CLK_PERIOD/2) clk = ~clk;

	// --- Comportamiento de la Memoria Simulada ---
	// 1. Lectura Síncrona (Como la BRAM real)
	always_ff @(posedge clk) begin
		if (!mem_we) begin // Si no se está escribiendo, se puede leer
			// El controlador espera el dato 1 ciclo después de poner la dirección
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

			$display("[MEM WRITE] Addr: %d | Data: %h | ByteEn: %b | Time: %t", 
						mem_addr, mem_wdata, mem_byte_en, $time);
		end
	end

	// --- Inicialización de Datos de Prueba ---
	task init_memory();
		integer i, j;
		logic [31:0] pixel_pack;
		$display("--- Inicializando Memoria Simulada (Gradiente) ---");
		// Llenamos la RAM con un patrón conocido (Gradiente)
		// Dirección 0: Pixeles (0,0) a (3,0)
		// Valor = (y * W) + x  (Para verificar fácil)
		for (i = 0; i < IMG_H; i++) begin
			for (j = 0; j < IMG_W; j=j+4) begin
				// Empaquetar 4 píxeles en una palabra de 32 bits
				pixel_pack =  {8'(i*IMG_W + j+3), 
									8'(i*IMG_W + j+2), 
									8'(i*IMG_W + j+1), 
									8'(i*IMG_W + j)};
				fake_ram[ADDR_INPUT + (i*IMG_W + j)/4] = pixel_pack;
			end
		end
	endtask

	// --- Proceso de Prueba ---
	initial begin
		clk = 0; rst_n = 0; i_start = 0; i_mode = 0;
		i_w = IMG_W; i_h = IMG_H;

		init_memory();

		#20 rst_n = 1;
		#20;

		// ------------------------------------------------
		// PRUEBA 1: MODO SIMD (i_mode = 1)
		// ------------------------------------------------
		$display("\n>>> INICIANDO PRUEBA MODO SIMD <<<");
		i_mode = 1; 
		i_start = 1;
		@(posedge clk);
		i_start = 0;

		// Esperar a que termine
		wait(o_done);
		$display(">>> FIN MODO SIMD (Done activado) <<<");

		// Verificar un dato escrito (Opcional, visual en consola es mejor)
		#20;

		// ------------------------------------------------
		// PRUEBA 2: MODO SECUENCIAL (i_mode = 0)
		// ------------------------------------------------
		// Cambiamos la dirección de salida base en el controlador (o reseteamos memoria)
		// Para este test simple, sobrescribiremos lo mismo, observando los logs.
		$display("\n>>> INICIANDO PRUEBA MODO SECUENCIAL <<<");
		rst_n = 0; #10 rst_n = 1; // Reset para borrar contadores

		i_mode = 0;
		i_start = 1;
		@(posedge clk);
		i_start = 0;

		wait(o_done);
		$display(">>> FIN MODO SECUENCIAL (Done activado) <<<");

		#50;
	end

endmodule
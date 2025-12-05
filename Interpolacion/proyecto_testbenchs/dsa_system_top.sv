module dsa_system_top (
    input logic clk,
    input logic rst_n,

    // --- Interfaz de Control (JTAG) ---
    input logic i_start,
    input logic i_mode_select,     // 0 = SEQ, 1 = SIMD
    
    // Entradas Stepping y Escala
    input logic i_step_mode,
    input logic i_step_trig,
    input logic [15:0] i_inv_scale, 

    output logic o_busy,
    output logic o_done,
    input logic [8:0] i_img_width,
    input logic [8:0] i_img_height,

    // --- Interfaz de Memoria ---
    output logic [15:0] o_mem_addr,
    output logic        o_mem_we,
    output logic [3:0]  o_mem_byte_en,
    output logic [31:0] o_mem_wdata,
    input logic  [31:0] i_mem_rdata
);

    // Cables internos
    logic w_simd_load_start, simd_valid; // Señal combinada: Load/Start
    logic seq_start, seq_valid;
    
    logic [15:0] w_wx, w_wy;
    
    // (A) Salidas del Controlador (4 bytes)
    logic [3:0][7:0] w_ctrl_r0, w_ctrl_r1; 
    
    // (B) Salidas del Registro SIMD (4 vectores de 4 vecinos)
    logic [3:0][7:0] w_reg_p1, w_reg_p2, w_reg_p3, w_reg_p4;
    
    logic [31:0] simd_res;
    logic [7:0] seq_p1, seq_p2, seq_p3, seq_p4, seq_res;

    // 1. Instancia del Controlador (FSM)
    main_controller u_controller (
        .clk(clk), .rst_n(rst_n),
        .i_start(i_start), .i_mode(i_mode_select),
        
        .i_step_mode(i_step_mode), .i_step_trig(i_step_trig),
        
        .o_busy(o_busy), .o_done(o_done),
        .i_width(i_img_width), .i_height(i_img_height),
        
        .i_inv_scale(i_inv_scale),
        .o_wx(w_wx), .o_wy(w_wy),
        
        .o_mem_addr(o_mem_addr), .o_mem_we(o_mem_we),
        .o_mem_byte_en(o_mem_byte_en),
        .o_mem_wdata(o_mem_wdata), .i_mem_rdata(i_mem_rdata),
        
        .o_simd_start(w_simd_load_start), 
        .o_row0_vec(w_ctrl_r0), .o_row1_vec(w_ctrl_r1),
        .i_simd_result(simd_res), 
        .i_simd_valid(simd_valid),
        
        // Sequential
        .o_seq_start(seq_start),
        .o_seq_p1(seq_p1), .o_seq_p2(seq_p2), 
        .o_seq_p3(seq_p3), .o_seq_p4(seq_p4),
        .i_seq_result(seq_res), .i_seq_valid(seq_valid)
    );
    
    // 2. Instancia del Registro SIMD
    simd_registers u_simd_reg (
        .clk(clk), 
        .rst_n(rst_n),
        
        // ** Conectamos la señal de inicio del controlador como ENABLE **
        .i_load_enable(w_simd_load_start), 
        
        // ** CONEXIÓN CRÍTICA DE 5 BYTES: w_ctrl_r0/r1 son 4 bytes, se le añade un 0 **
        // El registro necesita 5 bytes ([4:0][7:0]) para el sliding window.
        .i_row0_data({8'b0, w_ctrl_r0}), 
        .i_row1_data({8'b0, w_ctrl_r1}), 
        
        // Conectamos a los cables de salida correctos (w_reg_pX)
        .o_p1_vec(w_reg_p1), 
        .o_p2_vec(w_reg_p2),
        .o_p3_vec(w_reg_p3), 
        .o_p4_vec(w_reg_p4)
    );


    // 3. Instancia Núcleo SIMD
    bilinear_interp_simd u_simd_core (
        .clk(clk), 
        .rst_n(rst_n),
        .i_start(w_simd_load_start), // Inicia la interpolación cuando los datos están cargados
        
        // ** CONEXIÓN CRÍTICA: Tomamos las 4 SALIDAS DEL REGISTRO SIMD **
        .i_p1_vec(w_reg_p1), 
        .i_p2_vec(w_reg_p2),
        .i_p3_vec(w_reg_p3), 
        .i_p4_vec(w_reg_p4),
        
        .i_wx(w_wx), .i_wy(w_wy),
        .o_pixel_out_vec(simd_res),
        .o_valid(simd_valid)
    );

    // 4. Instancia Núcleo Secuencial
    bilinear_interp u_seq_core (
        .clk(clk), .rst_n(rst_n),
        .i_start(seq_start),
        .i_p1(seq_p1), .i_p2(seq_p2), 
        .i_p3(seq_p3), .i_p4(seq_p4),
        .i_wx(w_wx), .i_wy(w_wy),
        .o_pixel_out(seq_res),
        .o_valid(seq_valid)
    );

endmodule
module jtag_tap_controller_1687 (
    // 1. Giao tiếp JTAG vật lý (5 chân chuẩn)
    input  wire tck,            // Test Clock
    input  wire tms,            // Test Mode Select
    input  wire tdi,            // Test Data In
    output reg  tdo,            // Test Data Out
    output wire trst_n_out,     // Reset hệ thống (active low)
    input  wire ext_reset,      // Reset ngoài (tùy chọn)
    // Chân mới: Nhận dữ liệu từ mạng IJTAG quay về
    input  wire node_so,

    // 2. Tín hiệu điều khiển chung cho Mạng (SIB & Wrapper)
    output wire se,             // Shift Enable (nối vào shift_dr của mạng)
    output wire ce,             // Capture Enable (nối vào capture_dr của mạng)
    output wire ue,             // Update Enable (nối vào update_dr của mạng)
    
    // 3. Tín hiệu chọn tầng (Giải mã từ IR)
    output wire selectwir,      // Bật khi nạp lệnh IEEE 1500 Instruction
    output wire selectwdr,      // Bật khi nạp lệnh IEEE 1500 Data/MBIST
    output wire ijtag_sel,      // Bật khi đang ở chế độ IJTAG nói chung
    
    // 4. Giám sát lệnh
    output reg [3:0] ir_reg     // Thanh ghi lệnh hiện tại (4-bit)
);

    // --- Định nghĩa các trạng thái JTAG FSM ---
    reg [3:0] state;
    localparam TEST_LOGIC_RESET = 4'h0, RUN_TEST_IDLE  = 4'h1,
               SELECT_DR_SCAN   = 4'h2, CAPTURE_DR     = 4'h3,
               SHIFT_DR         = 4'h4, EXIT1_DR       = 4'h5,
               PAUSE_DR         = 4'h6, EXIT2_DR       = 4'h7,
               UPDATE_DR        = 4'h8, SELECT_IR_SCAN = 4'h9,
               CAPTURE_IR       = 4'hA, SHIFT_IR       = 4'hB,
               EXIT1_IR         = 4'hC, PAUSE_IR       = 4'hD,
               EXIT2_IR         = 4'hE, UPDATE_IR      = 4'hF;

    // --- Định nghĩa mã lệnh (Ví dụ) ---
    localparam BYPASS       = 4'b1111;
    localparam IDCODE       = 4'b0001;
    localparam CMD_WIR_ACC  = 4'b1000; // Mã lệnh truy cập IEEE 1500 WIR
    localparam CMD_WDR_ACC  = 4'b1001; // Mã lệnh truy cập IEEE 1500 WDR (MBIST)

    // 1. Máy trạng thái JTAG (TAP FSM)
    always @(posedge tck or negedge trst_n_out) begin
        if (!trst_n_out) state <= TEST_LOGIC_RESET;
        else begin
            case (state)
                TEST_LOGIC_RESET: state <= (tms) ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
                RUN_TEST_IDLE:    state <= (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
                SELECT_DR_SCAN:   state <= (tms) ? SELECT_IR_SCAN   : CAPTURE_DR;
                CAPTURE_DR:       state <= (tms) ? EXIT1_DR         : SHIFT_DR;
                SHIFT_DR:         state <= (tms) ? EXIT1_DR         : SHIFT_DR;
                EXIT1_DR:         state <= (tms) ? UPDATE_DR        : PAUSE_DR;
                // ... (các trạng thái DR khác tương tự)
                UPDATE_DR:        state <= (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
                SELECT_IR_SCAN:   state <= (tms) ? TEST_LOGIC_RESET : CAPTURE_IR;
                CAPTURE_IR:       state <= (tms) ? EXIT1_IR         : SHIFT_IR;
                SHIFT_IR:         state <= (tms) ? EXIT1_IR         : SHIFT_IR;
                UPDATE_IR:        state <= (tms) ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
                default:          state <= TEST_LOGIC_RESET;
            endcase
        end
    end

    // 2. Logic Thanh ghi lệnh (IR Register)
    always @(posedge tck or negedge trst_n_out) begin
        if (!trst_n_out) ir_reg <= BYPASS;
        else if (state == SHIFT_IR) ir_reg <= {tdi, ir_reg[3:1]};
    end

    // 3. GIẢI MÃ LỆNH VÀ GỘP TÍN HIỆU (Phần quan trọng nhất)
    
    // Tạo tín hiệu chọn (Select) dựa trên mã lệnh nạp vào IR
    assign selectwir = (ir_reg == CMD_WIR_ACC);
    assign selectwdr = (ir_reg == CMD_WDR_ACC);
    assign ijtag_sel = selectwir | selectwdr; // Kích hoạt mạng IJTAG

    // Gộp các trạng thái FSM thành các chân điều khiển chung (Bus)
    // Các chân này sẽ được kéo dọc chip đến tất cả các Node mạng
    assign se = (state == SHIFT_DR);   // Shift Enable
    assign ce = (state == CAPTURE_DR); // Capture Enable
    assign ue = (state == UPDATE_DR);  // Update Enable

    // 4. Logic Reset
    assign trst_n_out = ext_reset ;

    /// 5. Logic điều khiển đầu ra TDO
    always @(*) begin
        if (state == SHIFT_IR)
            tdo = ir_reg[0]; // Xuất bit cuối của lệnh khi đang dịch IR
        else if (state == SHIFT_DR)
            tdo = node_so;   // Xuất dữ liệu từ mạng Node khi đang dịch DR
        else
            tdo = 1'b0;      // Mặc định hoặc giữ trạng thái cũ
    end

endmodule

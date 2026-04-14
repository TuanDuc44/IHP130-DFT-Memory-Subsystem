module ieee1500_wrapper_ram (
    // 1. IEEE 1500 Wrapper Serial Port (WSP) - Giữ nguyên chuẩn
    // IEEE 1500 Wrapper Serial Interface
    input  wire        wrstn,       // Wrapper reset (active low)
    input  wire        wrck,        // Wrapper clock
    input  wire        wsi,         // Wrapper serial input
    output wire        wso,         // Wrapper serial output
    input  wire        selectwir,   // Select wrapper instruction register
    input  wire        capturewir,  // Capture to wrapper instruction register
    input  wire        shiftwir,    // Shift wrapper instruction register
    input  wire        updatewir,   // Update wrapper instruction register
    input  wire        selectwdr,   // Select wrapper data register
    input  wire        capturewdr,  // Capture to wrapper data register
    input  wire        shiftwdr,    // Shift wrapper data register
    input  wire        updatewdr,   // Update wrapper data register    
    // 2. Interface kết nối với SoC
    input  wire        soc_clk,
    input  wire        soc_men, soc_wen, soc_ren,
    input  wire [7:0]  soc_addr,
    input  wire [7:0]  soc_din,
    input  wire [7:0]  soc_bm,
    output wire [7:0]  soc_dout,

    // 3. Interface kết nối trực tiếp vào Vỏ RAM (To Memory Core)
    // Cụm chân Normal của RAM
    output wire        A_CLK, A_MEN, A_WEN, A_REN,
    output wire [7:0]  A_ADDR, A_DIN, A_BM,
    input  wire [7:0]  A_DOUT,
    
    // Cụm chân BIST của RAM (Đây là chìa khóa của IEEE 1500)
    output wire        A_BIST_EN,   // Lệnh từ WIR sẽ điều khiển chân này
    output wire        A_BIST_CLK, A_BIST_MEN, A_BIST_WEN, A_BIST_REN,
    output wire [7:0]  A_BIST_ADDR, A_BIST_DIN, A_BIST_BM,
    
    // --- CỔNG GIAO TIẾP VỚI MBIST CONTROLLER (BÊN NGOÀI) ---
    output wire        mbist_start, // Wrapper ra lệnh cho MBIST chạy
    input  wire        mbist_done,  // MBIST báo đã test xong cho Wrapper
    input  wire        mbist_fail,  // MBIST báo kết quả cho Wrapper

    // Chân dữ liệu MBIST "mượn đường" đi qua Wrapper vào RAM
    input  wire        m_bist_clk, m_bist_men, m_bist_wen, m_bist_ren,
    input  wire [7:0]  m_bist_addr, m_bist_din, m_bist_bm,

    // SIB dieu khien
    input wire to_sel
);

// Nhóm 1: Wrapper Instruction Register (WIR)
    parameter BYPASS   = 3'b000;    // Bypass instruction
    parameter EXTEST   = 3'b001;    // External test instruction
    parameter INTEST   = 3'b010;    // Internal test instruction 
    parameter SAMPLE   = 3'b011;    // Sample/Preload instruction
    parameter CLAMP    = 3'b100;    // Clamp instruction
    parameter MBIST    = 3'b101;    // Memory BIST instruction
    parameter RUNBIST  = 3'b110;    // Run BIST instruction
    
    // Internal registers
    reg  [2:0]  wir;               // Instruction register
    reg  [2:0]  wir_shift;         // Shifting WIR   
    
    
     
    // WIR logic
    always @(posedge wrck or negedge wrstn) begin
        if (!wrstn) begin
            wir       <= BYPASS;    // Default to BYPASS on reset
            wir_shift <= BYPASS;
        end else if (to_sel) begin
            // Capture phase
            if (selectwir && capturewir) begin
                wir_shift <= wir;   // Capture current instruction
            end 
            // Shift phase
            else if (selectwir && shiftwir) begin
                wir_shift <= {wsi, wir_shift[2:1]}; // Shift in from WSI
            end        
            // Update phase
            if (selectwir && updatewir) begin
                wir <= wir_shift;   // Update instruction register
            end
        end
    end

    // ĐIỀU KHIỂN CHÂN CHUYỂN MẠCH VỎ RAM ---
    // A_BIST_EN là chân "gạt công tắc" nội bộ của RAM IHP
    // Nếu lệnh là MBIST (101), chân này lên 1 để ngắt CPU và mở cổng cho mạch BIST.
    //assign A_BIST_EN = (wir == MBIST);

// Nhóm 2: Dữ liệu ranh giới (WDR) - Cấu trúc 27-bit
    // [26:19]ADDR | [18:11]DIN | [10:3]BM | [2]MEN | [1]WEN | [0]REN
    reg [26:0] wdr;               
    reg [26:0] wdr_shift;         

    // Các Boundary Cells (Ô ranh giới)
    reg [7:0] wdr_addr_cell;     
    reg [7:0] wdr_din_cell;      
    reg [7:0] wdr_bm_cell;       
    reg       wdr_men_cell;      
    reg       wdr_wen_cell;
    reg       wdr_ren_cell; // Thêm chân Read Enable để đủ bộ chân RAM

    always @(posedge wrck or negedge wrstn) begin
        if (!wrstn) begin
            wdr           <= 27'h0;
            wdr_shift     <= 27'h0;
            wdr_addr_cell <= 8'h0;
            wdr_din_cell  <= 8'h0;
            wdr_bm_cell   <= 8'hFF;
            wdr_men_cell  <= 1'b0;
            wdr_wen_cell  <= 1'b0;
            wdr_ren_cell  <= 1'b0;
        end else if (to_sel && selectwdr) begin
            
            // --- Bước 7: CAPTURE ---
            if (capturewdr) begin
                case (wir)
                    INTEST, MBIST: begin
                        // Chụp kết quả từ đầu ra RAM vào chuỗi dịch
                        // [26]: done | [25]: fail | [24:8]: reserve | [7:0]: A_DOUT
                        // Tổng cộng 27 bit (khớp với khai báo reg [26:0] wdr_shift)
                        wdr_shift <= {mbist_done, mbist_fail, 17'h0, A_DOUT};
                    end
                    EXTEST, SAMPLE: begin
                        // Chụp trạng thái từ SoC để kiểm tra kết nối
                        wdr_shift <= {soc_addr, soc_din, soc_bm, soc_men, soc_wen, soc_ren};
                    end
                    default: wdr_shift <= wdr;
                endcase
            end
            
            // --- Bước 8: SHIFT ---
            else if (shiftwdr) begin
                wdr_shift <= {wsi, wdr_shift[26:1]};
            end
            
            // --- Bước 9: UPDATE ---
            if (updatewdr) begin
                wdr <= wdr_shift;
                case (wir)
                    INTEST, MBIST, EXTEST: begin
                        wdr_addr_cell <= wdr_shift[26:19];
                        wdr_din_cell  <= wdr_shift[18:11];
                        wdr_bm_cell   <= wdr_shift[10:3];
                        wdr_men_cell  <= wdr_shift[2];
                        wdr_wen_cell  <= wdr_shift[1];
                        wdr_ren_cell  <= wdr_shift[0];
                    end
                endcase
            end
        end
    end

// Nhom 3: 
    reg bypass_reg; // Bypass register
// Bypass register logic
    always @(posedge wrck or negedge wrstn) begin
        if (!wrstn) begin
            bypass_reg <= 1'b0;
        end else if (to_sel && selectwdr && shiftwdr && (wir == BYPASS)) begin
            bypass_reg <= wsi; // Shift in when in BYPASS mode
        end
    end

// Wrapper Serial Output mux
    reg wso_int; // Internal wrapper serial output
    assign wso = wso_int; // Nối tín hiệu nội bộ ra chân output
// Serial output multiplexer
    always @(*) begin
        if (to_sel) begin // CHỈ XUẤT DỮ LIỆU KHI ĐƯỢC CHỌN
            if (selectwir && shiftwir) begin
                wso_int = wir_shift[0]; 
            end else if (selectwdr && shiftwdr) begin
                if (wir == BYPASS) begin
                    wso_int = bypass_reg; 
                end else begin
                    wso_int = wdr_shift[0]; 
                end
            end else begin
                wso_int = 1'b0; 
            end
        end else begin
            wso_int = 1'b0; // Nếu SIB đóng, ngắt đường truyền của Wrapper
        end
    end

    // =========================================================
    // NHÓM 4: INTERFACE CONTROL (KẾT NỐI MBIST & THỰC THI 11-13)
    // =========================================================
    
    // 1. Điều khiển lệnh thực thi
    assign mbist_start = (wir == MBIST); // Kích hoạt MBIST khi nạp đúng lệnh

    // 2. Chuyển mạch chính cho vỏ RAM (A_BIST_EN)
    assign A_BIST_EN = (wir == MBIST); 

    // 3. ĐIỀU KHIỂN CỤM CHÂN BIST CỦA VỎ RAM
    // Khi đang ở chế độ MBIST, lấy dữ liệu trực tiếp từ MBIST Controller bên ngoài
    assign A_BIST_CLK  = m_bist_clk;
    assign A_BIST_ADDR = m_bist_addr;
    assign A_BIST_DIN  = m_bist_din;
    assign A_BIST_MEN  = m_bist_men;
    assign A_BIST_WEN  = m_bist_wen;
    assign A_BIST_REN  = m_bist_ren;
    assign A_BIST_BM   = m_bist_bm;

    // 4. ĐIỀU KHIỂN CỤM CHÂN NORMAL CỦA VỎ RAM
    // Chế độ INTEST: Lấy từ Boundary Cells (WDR)
    // Chế độ NORMAL: Lấy từ SoC (Bus hệ thống)
    assign A_ADDR = (wir == INTEST) ? wdr_addr_cell : soc_addr;
    assign A_DIN  = (wir == INTEST) ? wdr_din_cell  : soc_din;
    assign A_MEN  = (wir == INTEST) ? wdr_men_cell  : soc_men;
    assign A_WEN  = (wir == INTEST) ? wdr_wen_cell  : soc_wen;
    assign A_REN  = (wir == INTEST) ? wdr_ren_cell  : soc_ren;
    assign A_BM   = (wir == INTEST) ? wdr_bm_cell   : soc_bm;
    assign A_CLK  = (wir == INTEST) ? wrck          : soc_clk;

    // 5. QUẢN LÝ KẾT QUẢ (MONITOR & REPORT)
    assign soc_dout = A_DOUT; // Trả về cho SoC bình thường

    // Kết quả gửi về Nhóm 2 để Capture ở Bước 12
    // Nếu đang chạy MBIST thì lấy cờ fail từ MBIST, nếu không thì lấy dữ liệu RAM
    wire bist_status_to_capture;
    assign bist_status_to_capture = (wir == MBIST) ? mbist_fail : 1'b0;

endmodule

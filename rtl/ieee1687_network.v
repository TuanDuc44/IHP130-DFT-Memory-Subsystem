module ieee1687_network (
    // 1. Giao tiếp JTAG vật lý (Chân Chip)
    input  wire tck,
    input  wire tms,
    input  wire tdi,
    output wire tdo,
    input  wire ext_reset,

    // 2. Giao tiếp SoC (Chế độ hoạt động bình thường)
    input  wire        soc_clk,
    input  wire [7:0]  soc_addr, soc_din, soc_bm,
    input  wire        soc_men, soc_wen, soc_ren,
    output wire [7:0]  soc_dout
);

    // --- TÍN HIỆU ĐIỀU KHIỂN NỘI BỘ (TAP BUS) ---
    wire se, ce, ue, trst_n;
    wire ijtag_sel, swir, swdr;
    wire [3:0] ir_reg;
    wire node_so;
    wire tdo_ir;

    // =========================================================
    // KHỐI 1: TAP CONTROLLER (NHẠC TRƯỞNG)
    // Điều khiển trạng thái FSM và giải mã lệnh từ IR
    // =========================================================
    jtag_tap_controller_1687 tap_inst (
        .tck(tck),
        .tms(tms),
        .tdi(tdi),
        .tdo(tdo_ir),           // TDO nội bộ của TAP (thường dùng cho IR shift)
        .trst_n_out(trst_n),
        .ext_reset(ext_reset),
        .se(se),                // Shift Enable
        .ce(ce),                // Capture Enable
        .ue(ue),                // Update Enable
        .selectwir(swir),       // Chọn lệnh IEEE 1500 WIR
        .selectwdr(swdr),       // Chọn dữ liệu IEEE 1500 WDR
        .ijtag_sel(ijtag_sel),  // Kích hoạt mạng IJTAG
        .ir_reg(ir_reg)
    );

    // =========================================================
    // KHỐI 2: IJTAG MEMORY NODE (MẮT XÍCH MẠNG)
    // Gộp: SIB + Wrapper + MBIST + RAM Core
    // =========================================================
    // Tín hiệu MBIST nội bộ (không đưa ra ngoài Chip)
    wire mbist_start, mbist_done, mbist_fail;
    wire m_clk, m_men, m_wen, m_ren;
    wire [7:0] m_addr, m_din, m_bm;

    // Tín hiệu RAM Core nội bộ
    wire A_CLK, A_MEN, A_WEN, A_REN, A_BIST_EN;
    wire [7:0] A_ADDR, A_DIN, A_BM, A_DOUT;

    ijtag_mem_node mem_node_inst (
        .tck(tck),
        .trst_n(trst_n),
        .sel(ijtag_sel),        // Lệnh kích hoạt từ TAP
        .se(se), .ce(ce), .ue(ue),
        .tap_selectwir(swir), 
        .tap_selectwdr(swdr),
        .si(tdi),               // TDI đi thẳng vào Node đầu tiên
        .so(node_so),           // Dữ liệu sau khi quét qua Node

        // Kết nối SoC
        .soc_clk(soc_clk), .soc_addr(soc_addr), .soc_din(soc_din), 
        .soc_bm(soc_bm), .soc_men(soc_men), .soc_wen(soc_wen), 
        .soc_ren(soc_ren), .soc_dout(soc_dout)
        
        /* 
           Lưu ý: Bên trong ijtag_mem_node đã chứa sẵn các instance:
           - sib_1687
           - ieee1500_wrapper_ram
           - mbist_controller
           - RM_IHPSG13_1P_256x8_c3_bm_bist
        */
    );

    // =========================================================
    // KHỐI 3: LOGIC CHỌN TDO CUỐI CÙNG (MUX TDO)
    // =========================================================
    // Nếu đang quét IR: TDO lấy từ thanh ghi lệnh IR
    // Nếu đang quét DR (IJTAG): TDO lấy từ đầu ra của Node
    
    // Giả sử TAP FSM đang ở trạng thái SHIFT_IR (4'hB)
    wire is_shift_ir = (tap_inst.state == 4'hB); 

    //assign tdo = (is_shift_ir) ? ir_reg[0] : node_so;
    assign tdo = (is_shift_ir) ? tdo_ir : node_so;

endmodule

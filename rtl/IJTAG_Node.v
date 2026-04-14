module ijtag_mem_node (
    input  wire tck, trst_n,
    // TAP Bus Control
    input  wire sel, se, ce, ue,
    input  wire tap_selectwir, tap_selectwdr,
    // Scan Path
    input  wire si,
    output wire so,
    
    // SoC Interface (Normal Mode)
    input  wire        soc_clk,
    input  wire [7:0]  soc_addr, soc_din, soc_bm,
    input  wire        soc_men, soc_wen, soc_ren,
    output wire [7:0]  soc_dout
);

    // --- TÍN HIỆU KẾT NỐI NỘI BỘ ---
    wire node_to_sel, wrapper_wso;
    wire mbist_start, mbist_done, mbist_fail;
    wire m_clk, m_men, m_wen, m_ren;
    wire [7:0] m_addr, m_din, m_bm;
    
    // Tín hiệu từ Wrapper tới RAM Core
    wire A_CLK, A_MEN, A_WEN, A_REN, A_BIST_EN;
    wire [7:0] A_ADDR, A_DIN, A_BM;
    wire [7:0] A_DOUT;

    // 1. SIB 1687 (Cầu nối IJTAG)
    sib_1687 sib_i (
        .tck(tck), .reset(~trst_n), .sel(sel),
        .se(se), .ce(ce), .ue(ue),
        .si(si), .from_so(wrapper_wso), .so(so),
        .to_sel(node_to_sel)
    );

    // 2. MBIST CONTROLLER (Bộ tạo kịch bản kiểm tra)
    // Giả định module mbist_top thực hiện thuật toán March C-
    mbist_controller_sg13g2 mbist_i (
        .clk(soc_clk), 
        .rst_n(trst_n),
        .start(mbist_start), 
        .done(mbist_done), 
        .fail(mbist_fail),

        .A_BIST_ADDR(m_addr),
        .A_BIST_DIN(m_din), 
        .A_BIST_BM(m_bm),
        .A_BIST_MEN(m_men), 
        .A_BIST_WEN(m_wen), 
        .A_BIST_REN(m_ren), 
        .A_BIST_CLK(m_clk)
    );

    // 3. IEEE 1500 WRAPPER (Vỏ bọc tiêu chuẩn)
    ieee1500_wrapper_ram wrapper_i (
        .wrstn(trst_n), .wrck(tck), .wsi(si), .wso(wrapper_wso),
        .to_sel(node_to_sel),
        .selectwir(tap_selectwir), .capturewir(ce), .shiftwir(se), .updatewir(ue),
        .selectwdr(tap_selectwdr), .capturewdr(ce), .shiftwdr(se), .updatewdr(ue),
        
        .soc_clk(soc_clk), .soc_men(soc_men), .soc_wen(soc_wen), .soc_ren(soc_ren),
        .soc_addr(soc_addr), .soc_din(soc_din), .soc_bm(soc_bm), .soc_dout(soc_dout),
        
        .A_CLK(A_CLK), .A_MEN(A_MEN), .A_WEN(A_WEN), .A_REN(A_REN),
        .A_ADDR(A_ADDR), .A_DIN(A_DIN), .A_BM(A_BM), .A_DOUT(A_DOUT),
        .A_BIST_EN(A_BIST_EN),

        .mbist_start(mbist_start), .mbist_done(mbist_done), .mbist_fail(mbist_fail),
        .m_bist_clk(m_clk), .m_bist_men(m_men), .m_bist_wen(m_wen), .m_bist_ren(m_ren),
        .m_bist_addr(m_addr), .m_bist_din(m_din), .m_bist_bm(m_bm)
    );

    // --- 4. Vỏ RAM IHP 256x8 (Sẽ gọi Core Behavioral bên trong) ---
    RM_IHPSG13_1P_256x8_c3_bm_bist i_ram (
        // Nhóm Normal (Từ Wrapper)
        .A_CLK(A_CLK), .A_MEN(A_MEN), .A_WEN(A_WEN), .A_REN(A_REN),
        .A_ADDR(A_ADDR), .A_DIN(A_DIN), .A_BM(A_BM), .A_DLY(1'b0),
        .A_DOUT(A_DOUT),
        
        // Nhóm BIST (Từ MBIST Controller qua đường mượn của Wrapper)
        .A_BIST_EN(A_BIST_EN), .A_BIST_CLK(m_clk),
        .A_BIST_MEN(m_men), .A_BIST_WEN(m_wen), .A_BIST_REN(m_ren),
        .A_BIST_ADDR(m_addr), .A_BIST_DIN(m_din), .A_BIST_BM(m_bm)
    );

endmodule

module mbist_controller_sg13g2 (
    input  wire       clk,        // Xung nhịp hệ thống cho MBIST
    input  wire       rst_n,      // Reset tích cực thấp
    input  wire       start,      // Tín hiệu bắt đầu test
    output reg        done,       // Hoàn thành test
    output reg        fail,       // Phát hiện lỗi (1 = Hỏng)

    // Kết nối trực tiếp tới các chân BIST của SRAM
    output reg        A_BIST_CLK,
    output reg        A_BIST_EN,
    output reg        A_BIST_MEN,
    output reg        A_BIST_WEN,
    output reg        A_BIST_REN,
    output reg [7:0]  A_BIST_ADDR,
    output reg [7:0]  A_BIST_DIN,
    output reg [7:0]  A_BIST_BM,
    input  wire [7:0] A_DOUT       // Dữ liệu đọc từ SRAM để so sánh
);

    // Định nghĩa các trạng thái FSM March C-
    localparam IDLE   = 3'd0,
               M0_W0  = 3'd1, // Viết 0 toàn bộ (Tăng)
               M1_R0W1= 3'd2, // Đọc 0, Viết 1 (Tăng)
               M2_R1W0= 3'd3, // Đọc 1, Viết 0 (Tăng)
               M3_R0W1= 3'd4, // Đọc 0, Viết 1 (Giảm)
               M4_R1W0= 3'd5, // Đọc 1, Viết 0 (Giảm)
               M5_R0  = 3'd6; // Đọc 0 kiểm tra cuối (Tăng)

    reg [2:0] state;
    reg [8:0] addr_cnt; // 9 bit để kiểm tra tràn (0-255)
    reg [1:0] sub_step; // 0: Đọc, 1: Ghi (cho các bước phức hợp)

    // Điều khiển Clock BIST
    always @(*) A_BIST_CLK = clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            A_BIST_EN   <= 0;
            A_BIST_MEN  <= 0;
            A_BIST_WEN  <= 0;
            A_BIST_REN  <= 0;
            A_BIST_ADDR <= 0;
            A_BIST_DIN  <= 0;
            A_BIST_BM   <= 8'hFF; // Luôn mở mask để test toàn bộ bit
            addr_cnt    <= 0;
            sub_step    <= 0;
            done        <= 0;
            fail        <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state <= M0_W0;
                        A_BIST_EN <= 1;
                        addr_cnt <= 0;
                    end
                end

                // M0: Viết 0 (Tăng dần)
                M0_W0: begin
                    A_BIST_MEN <= 1; A_BIST_WEN <= 1; A_BIST_REN <= 0;
                    A_BIST_ADDR <= addr_cnt[7:0];
                    A_BIST_DIN  <= 8'h00;
                    if (addr_cnt == 255) begin
                        state <= M1_R0W1;
                        addr_cnt <= 0;
                    end else addr_cnt <= addr_cnt + 1;
                end

                // M1: Đọc 0, Viết 1 (Tăng dần)
                M1_R0W1: begin
                    A_BIST_ADDR <= addr_cnt[7:0];
                    if (sub_step == 0) begin // Phase Đọc
                        A_BIST_WEN <= 0; A_BIST_REN <= 1;
                        sub_step <= 1;
                    end else begin // Phase Ghi
                        if (A_DOUT != 8'h00) fail <= 1; // Kiểm tra lỗi
                        A_BIST_WEN <= 1; A_BIST_REN <= 0;
                        A_BIST_DIN <= 8'hFF;
                        sub_step <= 0;
                        if (addr_cnt == 255) begin
                            state <= M2_R1W0; addr_cnt <= 0;
                        end else addr_cnt <= addr_cnt + 1;
                    end
                end

                // M2: Đọc 1, Viết 0 (Tăng dần)
                M2_R1W0: begin
                    A_BIST_ADDR <= addr_cnt[7:0];
                    if (sub_step == 0) begin
                        A_BIST_WEN <= 0; A_BIST_REN <= 1;
                        sub_step <= 1;
                    end else begin
                        if (A_DOUT != 8'hFF) fail <= 1;
                        A_BIST_WEN <= 1; A_BIST_REN <= 0;
                        A_BIST_DIN <= 8'h00;
                        sub_step <= 0;
                        if (addr_cnt == 255) begin
                            state <= M3_R0W1; addr_cnt <= 255; // Bắt đầu giảm dần
                        end else addr_cnt <= addr_cnt + 1;
                    end
                end

                // M3: Đọc 0, Viết 1 (Giảm dần)
                M3_R0W1: begin
                    A_BIST_ADDR <= addr_cnt[7:0];
                    if (sub_step == 0) begin
                        A_BIST_WEN <= 0; A_BIST_REN <= 1;
                        sub_step <= 1;
                    end else begin
                        if (A_DOUT != 8'h00) fail <= 1;
                        A_BIST_WEN <= 1; A_BIST_REN <= 0;
                        A_BIST_DIN <= 8'hFF;
                        sub_step <= 0;
                        if (addr_cnt == 0) begin
                            state <= M4_R1W0; addr_cnt <= 255;
                        end else addr_cnt <= addr_cnt - 1;
                    end
                end

                // M4: Đọc 1, Viết 0 (Giảm dần)
                M4_R1W0: begin
                    A_BIST_ADDR <= addr_cnt[7:0];
                    if (sub_step == 0) begin
                        A_BIST_WEN <= 0; A_BIST_REN <= 1;
                        sub_step <= 1;
                    end else begin
                        if (A_DOUT != 8'hFF) fail <= 1;
                        A_BIST_WEN <= 1; A_BIST_REN <= 0;
                        A_BIST_DIN <= 8'h00;
                        sub_step <= 0;
                        if (addr_cnt == 0) begin
                            state <= M5_R0; addr_cnt <= 0;
                        end else addr_cnt <= addr_cnt - 1;
                    end
                end

                // M5: Đọc 0 cuối cùng
                M5_R0: begin
                    A_BIST_WEN <= 0; A_BIST_REN <= 1;
                    A_BIST_ADDR <= addr_cnt[7:0];
                    if (A_DOUT != 8'h00) fail <= 1;
                    if (addr_cnt == 255) begin
                        state <= IDLE;
                        done <= 1;
                        A_BIST_EN <= 0;
                    end else addr_cnt <= addr_cnt + 1;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
module sib_1687 (
    // 1. Tín hiệu điều khiển từ TAP/Network
    input  wire tck,        // Clock kiểm tra
    input  wire reset,      // Reset hệ thống
    input  wire sel,        // Tín hiệu chọn SIB này (Select)
    input  wire se,         // Shift Enable (cho phép dịch)
    input  wire ce,         // Capture Enable (cho phép chụp dữ liệu)
    input  wire ue,         // Update Enable (cho phép cập nhật trạng thái)
    
    // 2. Đường dữ liệu quét (Scan Path)
    input  wire si,         // Scan Input (từ TDI hoặc SIB trước)
    input  wire from_so,    // Scan Input (từ TDR hoặc mạng con bên dưới quay về)
    output wire so,         // Scan Output (đi tới SIB tiếp theo hoặc TDO)
    
    // 3. Tín hiệu điều khiển thiết bị bên dưới
    output wire to_sel      // Lệnh chọn/kích hoạt TDR/Instrument bên dưới
);

    // Thành phần nội bộ của SIB
    reg shift_stage;    // Shift Stage (FF 1-bit)
    reg update_stage;   // Update Stage (Latch/FF giữ trạng thái đóng/mở)

    // --- LOGIC TẦNG DỊCH (SHIFT STAGE) ---
    always @(posedge tck or posedge reset) begin
        if (reset) begin
            shift_stage <= 1'b0;
        end else if (sel) begin
            if (ce) begin
                // Capture: Chụp giá trị trạng thái từ nhánh bên dưới
                shift_stage <= from_so; 
            end else if (se) begin
                // Shift: Dịch dữ liệu từ đầu vào si
                shift_stage <= si;
            end
        end
    end

    // --- LOGIC TẦNG CẬP NHẬT (UPDATE STAGE) ---
    always @(posedge tck or posedge reset) begin
        if (reset) begin
            update_stage <= 1'b0;
        end else if (sel && ue) begin
            // Update: Chốt giá trị từ tầng dịch vào tầng cập nhật
            update_stage <= shift_stage;
        end
    end

    // --- LOGIC ĐIỀU HƯỚNG MẠNG (NETWORK MUX) ---
    // to_sel chính là giá trị từ Update Stage (có thể qua Delay Stage nếu cần)
    assign to_sel = update_stage;

    // Logic đầu ra 'so' (Scan Out): 
    // Đây là "linh hồn" của mạng 1687
    // Nếu SIB mở (update_stage=1), 'so' lấy dữ liệu đã chạy qua TDR (from_so)
    // Nếu SIB đóng (update_stage=0), 'so' lấy dữ liệu trực tiếp từ shift_stage (Bypass)
    assign so = (update_stage) ? from_so : shift_stage;

endmodule

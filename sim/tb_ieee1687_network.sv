`timescale 1ns/1ps

module tb_ieee1687_network;

    // --- 1. Khai báo tín hiệu ---
    logic tck, tms, tdi, tdo, ext_reset;
    logic soc_clk;
    logic [7:0] soc_addr, soc_din, soc_bm;
    logic soc_men, soc_wen, soc_ren;
    wire  [7:0] soc_dout;

    // --- 2. Khởi tạo DUT ---
    ieee1687_network dut (
        .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo), .ext_reset(ext_reset),
        .soc_clk(soc_clk), .soc_addr(soc_addr), .soc_din(soc_din), 
        .soc_bm(soc_bm), .soc_men(soc_men), .soc_wen(soc_wen), 
        .soc_ren(soc_ren), .soc_dout(soc_dout)
    );

    // --- 3. Tạo xung nhịp ---
    initial tck = 0;
    always #10 tck = ~tck; // 50MHz JTAG

    initial soc_clk = 0;
    always #5 soc_clk = ~soc_clk; // 100MHz SoC

    // --- 4. Các Task JTAG chuẩn hóa ---
    task reset_tap;
        tms = 1; repeat(6) @(posedge tck);
        tms = 0; @(posedge tck); // Trạng thái RUN_TEST_IDLE
    endtask

    task automatic shift_ir(logic [3:0] cmd);
        tms = 1; @(posedge tck); // SELECT_DR
        tms = 1; @(posedge tck); // SELECT_IR
        tms = 0; @(posedge tck); // CAPTURE_IR
        tms = 0; @(posedge tck); // SHIFT_IR
        for (int i=0; i<3; i++) begin
            tdi = cmd[i]; tms = 0; @(posedge tck);
        end
        tdi = cmd[3]; tms = 1; @(posedge tck); // EXIT1_IR
        tms = 1; @(posedge tck); // UPDATE_IR
        tms = 0; @(posedge tck); // IDLE
    endtask

    task automatic shift_dr(logic [31:0] data, int len);
        tms = 1; @(posedge tck); // SELECT_DR
        tms = 0; @(posedge tck); // CAPTURE_DR
        tms = 0; @(posedge tck); // SHIFT_DR
        for (int i=0; i<len-1; i++) begin
            tdi = data[i]; tms = 0; @(posedge tck);
        end
        tdi = data[len-1]; tms = 1; @(posedge tck); // EXIT1_DR
        tms = 1; @(posedge tck); // UPDATE_DR
        tms = 0; @(posedge tck); // IDLE
    endtask

    // Task đặc biệt: Vừa dịch vừa đọc TDO để kiểm tra kết quả
    task automatic shift_dr_and_read_tdo(int total_len);
        logic [63:0] captured_data = 0;
        tms = 1; @(posedge tck); // SELECT_DR
        tms = 0; @(posedge tck); // CAPTURE_DR
        tms = 0; @(posedge tck); // SHIFT_DR
        
        $display("--- Bat dau dich chuoi bit tu TDO (WSO) ---");
        for (int i=0; i<total_len; i++) begin
            tdi = 0; // Dịch 0 vào trong khi đọc ra
            if (i == total_len-1) tms = 1; // Bit cuối chuyển sang EXIT1_DR
            @(posedge tck);
            captured_data[i] = tdo;
            $display("Bit [%0d]: %b (Time: %0t)", i, tdo, $time);

            //if (tdo === 1'b1 && i > 0) // Giả sử bit 0 là SIB, các bit sau là WDR
            //    $display("!!! CANH BAO: Phat hien bit FAIL tai vi tri %0d !!!", i);
            
            // CHỈ KIỂM TRA BIT FAIL THẬT SỰ (Vị trí 26 trong chuỗi 28 bit)
            if (i == 26 && tdo === 1'b1) 
                $display("!!! KET QUA: MBIST THUC SU FAIL (RAM HONG) !!!");
            
            // KIỂM TRA BIT DONE (Vị trí 27)
            if (i == 27 && tdo === 1'b1)
                $display(">>> KET QUA: MBIST DONE (DA HOAN THANH)");

        end
        tms = 1; @(posedge tck); // UPDATE_DR
        tms = 0; @(posedge tck); // IDLE
        $display("Ket qua chuoi DR nhan duoc: %b", captured_data);
    endtask

    // --- 5. Kịch bản mô phỏng ---
    initial begin
        // Khởi tạo
        ext_reset = 0; tms = 1; tdi = 0;
        soc_men = 0; soc_wen = 0; soc_ren = 0;
        #100 ext_reset = 1;
        reset_tap();

        $display("\n[%0t] --- BAT DAU QUY TRINH KIEM THU IJTAG 1687 ---", $time);

        // BƯỚC 1: Mở SIB
        $display("[%0t] B1: Mo SIB (Dich 1 vao DR voi lenh 1001)", $time);
        shift_ir(4'b1001); // CMD_WDR_ACC
        shift_dr(32'h1, 1); // Chuỗi DR lúc này chỉ có 1 bit SIB

        // BƯỚC 2: Nạp lệnh MBIST (Giai đoạn 1)
        $display("[%0t] B2: Nap lenh MBIST (101) vao WIR", $time);
        shift_ir(4'b1000); // CMD_WIR_ACC
        // Chuỗi DR = [WIR (3 bit) | SIB (1 bit)] = 4 bit
        // Ta dịch 101 cho WIR và 1 cho SIB -> 4'b1011
        shift_dr(4'b1011, 4);

        // BƯỚC 3: Đợi MBIST thực thi (Giai đoạn 2)
        $display("[%0t] B3: Dang thuc thi MBIST March C-...", $time);
        // Chờ tín hiệu done từ bên trong Node
        wait(dut.mem_node_inst.mbist_done == 1'b1);
        $display("[%0t] >>> PASS: MBIST bao hoan thanh (Done = 1)", $time);

        // BƯỚC 4: Capture & Shift out kết quả (Giai đoạn 3)
        $display("[%0t] B4: Capture va Shift ket qua ra Console", $time);
        shift_ir(4'b1001); // Quay lại CMD_WDR_ACC để truy cập WDR dữ liệu
        
        // Giả sử WDR dài 27 bit, cộng thêm 1 bit SIB = 28 bit
        shift_dr_and_read_tdo(28);

        $display("\n[%0t] --- KET THUC MO PHONG ---", $time);
        #100 $finish;
    end

    // Ghi file sóng
    initial begin
        $dumpfile("ijtag_sim.vcd");
        $dumpvars(0, tb_ieee1687_network);
    end

endmodule

`timescale 1ns/1ps
module tb_rs_encoder;

    localparam SYM_W = 4;

    logic clk;
    logic rst_n;

    logic start;
    logic [SYM_W-1:0] din;
    logic din_valid;
    logic din_ready;

    logic [SYM_W-1:0] dout;
    logic dout_valid;
    logic dout_ready;
    logic parity_phase;

    rs_encoder #(
        .SYM_W(SYM_W)
    ) u_rs_encoder (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .din(din),
        .din_valid(din_valid),
        .din_ready(din_ready),
        .dout(dout),
        .dout_valid(dout_valid),
        .dout_ready(dout_ready),
        .parity_phase(parity_phase)
    );

    // ---------------- 时钟 ----------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ---------------- 输入数据 / 期望码字 ----------------
    logic [3:0] data_array[0:10];      // 11 个数据符号 1..11
    initial begin
        data_array[0] = 4'h1;  data_array[1] = 4'h2;  data_array[2]  = 4'h3;
        data_array[3] = 4'h4;  data_array[4] = 4'h5;  data_array[5]  = 4'h6;
        data_array[6] = 4'h7;  data_array[7] = 4'h8;  data_array[8]  = 4'h9;
        data_array[9] = 4'ha;  data_array[10] = 4'hb;
    end

    logic [3:0] expected_data[0:14];   // 一个完整码字的期望输出
    initial begin
        expected_data[0] = 4'h1;  expected_data[1] = 4'h2;  expected_data[2]  = 4'h3;
        expected_data[3] = 4'h4;  expected_data[4] = 4'h5;  expected_data[5]  = 4'h6;
        expected_data[6] = 4'h7;  expected_data[7] = 4'h8;  expected_data[8]  = 4'h9;
        expected_data[9] = 4'ha;  expected_data[10] = 4'hb;
        expected_data[11] = 4'd3; expected_data[12] = 4'd3;
        expected_data[13] = 4'd12; expected_data[14] = 4'd12;
    end

    // ---------------- 后台 dout_ready 背压发生器 ----------------
    // bp_en=0 时 dout_ready 恒高;bp_en=1 时每拍翻转(隔拍 stall),
    // 数据/校验两个阶段都会被打断,用来测背压。所有改动在 negedge,避免与 DUT 采样竞争。
    logic bp_en = 0;
    initial begin
        dout_ready = 1'b1;
        forever begin
            @(negedge clk);
            dout_ready = bp_en ? ~dout_ready : 1'b1;
        end
    end

    // ---------------- Scoreboard(全局,可被各测试复用) ----------------
    int exp_idx   = 0;   // 期望码字索引,mod 15(支持连续多码字)
    int sym_seen  = 0;   // 当前测试已采集的输出符号数
    int err_count = 0;   // 全局错误累计
    logic check_en = 0;  // 1 时才比对(各测试自行开关)

    always @(posedge clk) begin
        if (check_en && dout_valid && dout_ready) begin
            if (dout !== expected_data[exp_idx]) begin
                $display("[%0t] MISMATCH idx=%0d exp=%0d got=%0d",
                          $time, exp_idx, expected_data[exp_idx], dout);
                err_count = err_count + 1;
            end
            else begin
                $display("[%0t] OK  dout=%0d (exp_idx=%0d)", $time, dout, exp_idx);
            end
            sym_seen = sym_seen + 1;
            exp_idx  = (exp_idx == 14) ? 0 : exp_idx + 1;
        end
    end

    // ---------------- 复位 task(不再驱动 dout_ready,交给后台发生器) ----------------
    task automatic reset();
        begin
            rst_n     = 0;
            start     = 0;
            din       = '0;
            din_valid = 0;
            repeat(5) @(posedge clk);
            @(negedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    // ---------------- 喂一个符号(加固版:上升沿判定成交) ----------------
    // 摆出数据并保持,直到某个上升沿采样到 din_ready=1(真正成交)才返回。
    // 背压下 din_ready 会掉低,这里会自动 hold,不丢符号。
    task automatic send_data(input logic [SYM_W-1:0] data, input logic first_symbol);
        begin
            @(negedge clk);
            din       = data;
            din_valid = 1'b1;
            start     = first_symbol;
            do @(posedge clk); while (!din_ready);
        end
    endtask

    // ---------------- 发一个完整码字(11 个数据,首符号带 start) ----------------
    task automatic send_codeword();
        begin
            for (int i = 0; i < 11; i++)
                send_data(data_array[i], (i == 0));
            @(negedge clk);
            din_valid = 0;
            start     = 0;
        end
    endtask

    // ---------------- 等待采集到 n 个输出(带超时保护) ----------------
    task automatic wait_outputs(input int n);
        int guard;
        begin
            guard = 0;
            while (sym_seen < n && guard < 1000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (sym_seen < n)
                $display("[%0t] TIMEOUT waiting outputs: %0d/%0d", $time, sym_seen, n);
        end
    endtask

    // ---------------- 单个测试判决 ----------------
    task automatic report_test(input string name, input int errs, input int seen, input int expect_n);
        begin
            if (errs == 0 && seen == expect_n)
                $display(">>> %s PASSED (%0d/%0d symbols)\n", name, seen, expect_n);
            else
                $display(">>> %s FAILED (errors=%0d, seen=%0d/%0d)\n", name, errs, seen, expect_n);
        end
    endtask

    // ================= TEST1:基础黄金向量 =================
    task automatic test1_basic();
        int err_before;
        begin
            $display("\n--- TEST1: basic golden vector ---");
            err_before = err_count;
            reset();
            exp_idx = 0; sym_seen = 0; check_en = 1;
            send_codeword();
            wait_outputs(15);
            check_en = 0;
            report_test("TEST1 basic", err_count - err_before, sym_seen, 15);
        end
    endtask

    // ================= TEST2:背压(中途 stall) =================
    task automatic test2_backpressure();
        int err_before;
        begin
            $display("\n--- TEST2: backpressure (dout_ready toggling) ---");
            err_before = err_count;
            reset();
            exp_idx = 0; sym_seen = 0; check_en = 1;
            bp_en = 1;                 // 打开背压:dout_ready 隔拍 stall
            send_codeword();           // 数据阶段:send_data 自动 hold 等 din_ready
            wait_outputs(15);          // 数据+校验,穿过所有 stall 收满 15 个
            bp_en = 0;                 // 恢复全速
            check_en = 0;
            report_test("TEST2 backpressure", err_count - err_before, sym_seen, 15);
        end
    endtask

    // ================= TEST3:连续两个码字(验证寄存器无残留) =================
    task automatic test3_back_to_back();
        int err_before;
        begin
            $display("\n--- TEST3: back-to-back two codewords ---");
            err_before = err_count;
            reset();
            exp_idx = 0; sym_seen = 0; check_en = 1;
            send_codeword();           // 码字1
            send_codeword();           // 码字2(首符号被加固握手 hold 到码字1校验吐完)
            wait_outputs(30);
            check_en = 0;
            // 期望两个码字输出完全相同(各 1..11,3,3,12,12),mod-15 比对全中
            report_test("TEST3 back-to-back x2", err_count - err_before, sym_seen, 30);
        end
    endtask

    // ================= TEST4:运算中途复位 + 恢复 =================
    task automatic test4_reset_mid();
        int err_before;
        int lfsr_bad;
        begin
            $display("\n--- TEST4: reset mid-operation then recover ---");
            err_before = err_count;
            reset();

            // 发一半数据(3 个)后中途打断,不计分
            check_en = 0;
            send_data(data_array[0], 1'b1);
            send_data(data_array[1], 1'b0);
            send_data(data_array[2], 1'b0);

            // 中途异步复位
            @(negedge clk);
            rst_n     = 0;
            din_valid = 0;
            start     = 0;
            repeat(3) @(posedge clk);

            // 直接检查内部状态已清零(白盒断言)
            lfsr_bad = 0;
            for (int i = 0; i < 4; i++)
                if (u_rs_encoder.lfsr[i] !== '0) lfsr_bad = 1;
            if (lfsr_bad || u_rs_encoder.sym_cnt !== '0 || u_rs_encoder.state !== 0) begin
                $display("[%0t] TEST4 internal not cleared: lfsr_bad=%0d sym_cnt=%0d state=%0d",
                          $time, lfsr_bad, u_rs_encoder.sym_cnt, u_rs_encoder.state);
                err_count = err_count + 1;
            end

            // 释放复位,发一条全新码字,验证完全恢复
            @(negedge clk);
            rst_n = 1;
            @(posedge clk);
            exp_idx = 0; sym_seen = 0; check_en = 1;
            send_codeword();
            wait_outputs(15);
            check_en = 0;
            report_test("TEST4 reset-recovery", err_count - err_before, sym_seen, 15);
        end
    endtask

    // ---------------- 主流程 ----------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_rs_encoder);

        test1_basic();
        test2_backpressure();
        test3_back_to_back();
        test4_reset_mid();

        $display("\n======== SUMMARY ========");
        if (err_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d total errors", err_count);
        $finish;
    end

endmodule

`timescale 1ns/1ps
module tb_banco_registradores_rob;
    reg clk = 0, rst = 1;
    reg [2:0] cdst1 = 0, cdst2 = 0, cdst3 = 0;
    reg [4:0] crid1 = 5'd7, crid2 = 5'd8, crid3 = 5'd9;
    reg [31:0] cr1 = 32'h11110001, cr2 = 32'h22220002, cr3 = 32'h33330003;
    reg [31:0] lb_dado1 = 32'hdead0001, lb_dado2 = 32'hdead0002, lb_dado3 = 32'hdead0003;
    wire [31:0] a1, b1, a2, b2, a3, b3;
    reg [31:0] expected [0:31];
    reg [31:0] commit_data [0:2];
    reg [31:0] load_data [0:2];
    reg [2:0] destinations [0:2];
    reg [4:0] addresses [0:2];
    integer c1, c2, c3, lane, load_index, cases = 0;

    banco_registradores_rob dut (
        .clk(clk), .rst(rst), .rs1_1(5'd7), .rs2_1(5'd8),
        .rs1_2(5'd9), .rs2_2(5'd0), .rs1_3(5'd7), .rs2_3(5'd9),
        .valor_rs1_1(a1), .valor_rs2_1(b1), .valor_rs1_2(a2),
        .valor_rs2_2(b2), .valor_rs1_3(a3), .valor_rs2_3(b3),
        .cdst1(cdst1), .cdst2(cdst2), .cdst3(cdst3),
        .crid1(crid1), .crid2(crid2), .crid3(crid3),
        .cr1(cr1), .cr2(cr2), .cr3(cr3),
        .lb_dado1(lb_dado1), .lb_dado2(lb_dado2), .lb_dado3(lb_dado3)
    );
    always #5 clk = ~clk;
    task check;
        begin
            if (a1 !== expected[7] || b1 !== expected[8] || a2 !== expected[9] ||
                b2 !== 0 || a3 !== expected[7] || b3 !== expected[9])
                $fatal(1, "Adaptador: falha com destinos %b/%b/%b", cdst1, cdst2, cdst3);
        end
    endtask
    task commit;
        begin
            destinations[0] = cdst1; destinations[1] = cdst2; destinations[2] = cdst3;
            addresses[0] = crid1; addresses[1] = crid2; addresses[2] = crid3;
            commit_data[0] = cr1; commit_data[1] = cr2; commit_data[2] = cr3;
            load_data[0] = lb_dado1; load_data[1] = lb_dado2; load_data[2] = lb_dado3;
            load_index = 0;
            // Modelo consome uma fila de dados load em ordem de commit.
            for (lane = 0; lane < 3; lane = lane + 1) begin
                if (destinations[lane] == 3'b010) begin
                    if (addresses[lane] != 0)
                        expected[addresses[lane]] = load_data[load_index];
                    load_index = load_index + 1;
                end else if ((destinations[lane] == 3'b001 || destinations[lane] == 3'b011)
                             && addresses[lane] != 0) begin
                    expected[addresses[lane]] = commit_data[lane];
                end
            end
            @(posedge clk); #1;
            check;
            cases = cases + 1;
        end
    endtask

    initial begin #20000; $fatal(1, "Timeout adaptador"); end
    initial begin
        for (lane = 0; lane < 32; lane = lane + 1) expected[lane] = 0;
        @(posedge clk); #1; check;
        @(negedge clk); #1; rst = 0;
        $display("Adaptador: todas as 512 combinacoes de codigos de destino");
        for (c1 = 0; c1 < 8; c1 = c1 + 1)
            for (c2 = 0; c2 < 8; c2 = c2 + 1)
                for (c3 = 0; c3 < 8; c3 = c3 + 1) begin
                    @(negedge clk); #1;
                    cdst1 = c1; cdst2 = c2; cdst3 = c3;
                    commit;
                end
        $display("Adaptador: loads e calculos colidindo no mesmo rd");
        @(negedge clk); #1;
        crid1 = 7; crid2 = 7; crid3 = 7;
        cdst1 = 1; cdst2 = 2; cdst3 = 3; commit;
        @(negedge clk); #1;
        cdst1 = 1; cdst2 = 3; cdst3 = 2; commit;
        @(negedge clk); #1;
        crid1 = 0; crid2 = 8; crid3 = 9;
        cdst1 = 2; cdst2 = 2; cdst3 = 2; commit;
        $display("PASS adaptador: %0d casos verificados", cases);
        $finish;
    end
endmodule

`timescale 1ns/1ps

//Testbench da unidade de hazard/forwarding (renomeação na alocação).
//Os sinais do despacho, dos caminhos, do ROB e do banco são gerados aqui.
module tb_hazard_forwarding;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [2:0] al_v = 0;
    reg  [4:0] al_rob0 = 0, al_rob1 = 0, al_rob2 = 0;
    reg  [4:0] al_rs1_0 = 0, al_rs1_1 = 0, al_rs1_2 = 0, al_rs2_0 = 0, al_rs2_1 = 0, al_rs2_2 = 0;
    reg  [4:0] al_rd0 = 0, al_rd1 = 0, al_rd2 = 0;
    reg        al_escreve0 = 0, al_escreve1 = 0, al_escreve2 = 0;
    reg        al_alu0 = 0, al_alu1 = 0, al_alu2 = 0;
    reg        al_desvio0 = 0, al_desvio1 = 0, al_desvio2 = 0;
    wire [31:0] pronto;
    wire [2:0]  ck_livres;
    reg        wb1 = 0, wb2 = 0, wb3 = 0, lb_done = 0;
    reg  [4:0] rid1 = 0, rid2 = 0, rid3 = 0, lb_rid = 0;
    reg [31:0] r1 = 0, r2 = 0, r3 = 0, lb_dado = 0;
    reg  [2:0] we = 0;
    reg  [4:0] crd1 = 0, crd2 = 0, crd3 = 0, crob1 = 0, crob2 = 0, crob3 = 0;
    reg        flush_ok = 0;
    reg  [4:0] flush_rob_id = 0;
    reg  [4:0] p1_rob = 0, p2_rob = 0, p3_rob = 0;
    reg [31:0] banco = 32'd99;   //valor que o banco devolve em todas as portas
    wire [31:0] v11, v12, v21, v22, v31, v32;

    hazard_forwarding dut (
        .clk(clk), .rst(rst),
        .al_v(al_v), .al_rob0(al_rob0), .al_rob1(al_rob1), .al_rob2(al_rob2),
        .al_rs1_0(al_rs1_0), .al_rs1_1(al_rs1_1), .al_rs1_2(al_rs1_2),
        .al_rs2_0(al_rs2_0), .al_rs2_1(al_rs2_1), .al_rs2_2(al_rs2_2),
        .al_rd0(al_rd0), .al_rd1(al_rd1), .al_rd2(al_rd2),
        .al_escreve0(al_escreve0), .al_escreve1(al_escreve1), .al_escreve2(al_escreve2),
        .al_alu0(al_alu0), .al_alu1(al_alu1), .al_alu2(al_alu2),
        .al_desvio0(al_desvio0), .al_desvio1(al_desvio1), .al_desvio2(al_desvio2),
        .pronto(pronto), .ck_livres(ck_livres),
        .wb1(wb1), .wb2(wb2), .wb3(wb3), .rid1(rid1), .rid2(rid2), .rid3(rid3), .r1(r1), .r2(r2), .r3(r3),
        .lb_done(lb_done), .lb_rid(lb_rid), .lb_dado(lb_dado),
        .we(we), .crd1(crd1), .crd2(crd2), .crd3(crd3), .crob_id1(crob1), .crob_id2(crob2), .crob_id3(crob3),
        .flush_ok(flush_ok), .flush_rob_id(flush_rob_id),
        .p1_rob(p1_rob), .p2_rob(p2_rob), .p3_rob(p3_rob),
        .banco_p1_rs1(banco), .banco_p1_rs2(banco), .banco_p2_rs1(banco), .banco_p2_rs2(banco),
        .banco_p3_rs1(banco), .banco_p3_rs2(banco),
        .p1_rs1_val(v11), .p1_rs2_val(v12), .p2_rs1_val(v21), .p2_rs2_val(v22), .p3_rs1_val(v31), .p3_rs2_val(v32)
    );

    integer erros = 0;
    task falha(input [8*60-1:0] msg);
        begin $display("FALHOU: %0s (t=%0t)", msg, $time); erros = erros + 1; end
    endtask

    //Aloca uma instrução no slot 0 (as demais ficam desligadas)
    //tipo: 0 = ULA, 1 = load, 2 = desvio sem rd, 3 = JAL/JALR (desvio que escreve rd)
    task aloca(input [4:0] rob, rs1, rs2, rd, input [1:0] tipo);
        begin
            @(negedge clk);
            al_v = 3'b001; al_rob0 = rob; al_rs1_0 = rs1; al_rs2_0 = rs2; al_rd0 = rd;
            al_escreve0 = (tipo != 2) && rd != 0;
            al_alu0     = (tipo != 1);
            al_desvio0  = (tipo >= 2);
            @(posedge clk); #1;
            al_v = 0;
        end
    endtask

    task borda; begin @(posedge clk); #1; end endtask

    initial begin
        $display("INICIO DOS TESTES DO HAZARD/FORWARDING");
        repeat (2) @(posedge clk); #1 rst = 0;

        //1) Sem produtor em andamento: pronto e valor do banco
        aloca(5'd0, 5'd1, 5'd2, 5'd3, 0);              //add x3, x1, x2
        p1_rob = 0; #1;
        if (!pronto[0] || v11 !== 99 || v12 !== 99) falha("sem produtor: valor do banco");
        $display("PASSOU: operandos do banco");

        //2) Dependência: espera o produtor; forwarding no ciclo do resultado e depois
        aloca(5'd1, 5'd0, 5'd0, 5'd5, 0);              //addi x5, x0, ...
        aloca(5'd2, 5'd5, 5'd5, 5'd6, 0);              //add x6, x5, x5
        if (pronto[2]) falha("consumidor pronto antes do produtor");
        @(negedge clk); wb1 = 1; rid1 = 1; r1 = 42; p1_rob = 2; #1;
        if (!pronto[2] || v11 !== 42 || v12 !== 42) falha("forwarding no ciclo do resultado");
        borda; wb1 = 0; #1;
        if (!pronto[2] || v11 !== 42) falha("forwarding pela tabela de resultados");
        $display("PASSOU: espera e forwarding");

        //3) Commit: o consumidor passa a ler o banco, e o rob_id pode ser reaproveitado
        @(negedge clk); we = 3'b001; crd1 = 5; crob1 = 1;
        borda; we = 0; #1;
        if (!pronto[2] || v11 !== 99) falha("depois do commit, deveria ler o banco");
        aloca(5'd1, 5'd0, 5'd0, 5'd20, 0);             //rob 1 reaproveitado por outra instrução
        if (!pronto[2] || v11 !== 99) falha("reaproveitar o rob_id afetou o consumidor");
        $display("PASSOU: commit e reaproveitamento do rob_id");

        //4) Duas escritas no mesmo registrador: vale a mais recente
        aloca(5'd3, 5'd0, 5'd0, 5'd7, 0);
        aloca(5'd4, 5'd0, 5'd0, 5'd7, 0);
        aloca(5'd5, 5'd7, 5'd0, 5'd8, 0);              //add x8, x7, x0
        @(negedge clk); wb1 = 1; rid1 = 3; r1 = 3; #1;
        if (pronto[5]) falha("pronto com o produtor antigo de x7");
        borda; wb1 = 0;
        @(negedge clk); wb2 = 1; rid2 = 4; r2 = 7; p2_rob = 5; #1;
        if (!pronto[5] || v21 !== 7) falha("deveria usar o produtor mais recente de x7");
        borda; wb2 = 0;
        $display("PASSOU: produtor mais recente");

        //5) Load: o endereço do caminho não vale como valor; o dado vem do load buffer
        aloca(5'd6, 5'd1, 5'd0, 5'd9, 1);              //lw x9
        aloca(5'd7, 5'd9, 5'd0, 5'd10, 0);             //add x10, x9, x0
        @(negedge clk); wb1 = 1; rid1 = 6; r1 = 32'h1000; #1;
        if (pronto[7]) falha("endereco do load usado como valor");
        borda; wb1 = 0;
        @(negedge clk); lb_done = 1; lb_rid = 6; lb_dado = 123; p1_rob = 7; #1;
        if (!pronto[7] || v11 !== 123) falha("dado do load");
        borda; lb_done = 0;
        $display("PASSOU: load pelo load buffer");

        //6) JAL: o pc + 4 vem do caminho 3
        aloca(5'd8, 5'd0, 5'd0, 5'd11, 3);             //jal x11
        aloca(5'd9, 5'd11, 5'd0, 5'd12, 0);            //add x12, x11, x0
        @(negedge clk); wb3 = 1; rid3 = 8; r3 = 204; p3_rob = 9; #1;
        if (!pronto[9] || v31 !== 204) falha("resultado do JAL");
        borda; wb3 = 0;
        $display("PASSOU: resultado do caminho 3");

        //7) Descarte: a RAT volta ao estado da alocação do desvio
        aloca(5'd10, 5'd0, 5'd0, 5'd13, 0);            //addi x13 (mais antiga que o desvio)
        aloca(5'd11, 5'd1, 5'd2, 5'd0, 2);             //beq (cópia da RAT)
        aloca(5'd12, 5'd0, 5'd0, 5'd13, 0);            //addi x13 (caminho errado)
        @(negedge clk); flush_ok = 1; flush_rob_id = 11;
        borda; flush_ok = 0;
        aloca(5'd12, 5'd13, 5'd0, 5'd14, 0);           //add x14, x13, x0: deve depender do rob 10
        if (pronto[12]) falha("depois do descarte, deveria esperar o rob 10");
        @(negedge clk); wb1 = 1; rid1 = 10; r1 = 55; p1_rob = 12; #1;
        if (!pronto[12] || v11 !== 55) falha("dependencia restaurada pelo descarte");
        borda; wb1 = 0;
        $display("PASSOU: descarte restaura a RAT");

        //8) Commit depois da cópia: a cópia também é atualizada
        aloca(5'd13, 5'd0, 5'd0, 5'd15, 0);            //addi x15
        aloca(5'd14, 5'd1, 5'd2, 5'd0, 2);             //beq (cópia com x15 -> rob 13)
        @(negedge clk); wb1 = 1; rid1 = 13; r1 = 5;
        borda; wb1 = 0;
        @(negedge clk); we = 3'b001; crd1 = 15; crob1 = 13;
        borda; we = 0;
        @(negedge clk); flush_ok = 1; flush_rob_id = 14;
        borda; flush_ok = 0;
        aloca(5'd13, 5'd0, 5'd0, 5'd16, 0);            //rob 13 reaproveitado, ainda sem resultado
        aloca(5'd15, 5'd15, 5'd0, 5'd17, 0);           //add x17, x15, x0: x15 já está no banco
        p1_rob = 15; #1;
        if (!pronto[15] || v11 !== 99) falha("copia nao foi atualizada pelo commit");
        $display("PASSOU: commit atualiza as copias");


        //9) Quatro cópias: esgotam com 4 desvios pendentes e voltam quando eles se resolvem
        if (ck_livres !== 3'd4) falha("deveria haver 4 copias livres");
        aloca(5'd20, 5'd1, 5'd2, 5'd0, 2);
        aloca(5'd21, 5'd1, 5'd2, 5'd0, 2);
        aloca(5'd22, 5'd1, 5'd2, 5'd0, 3);             //jal tambem usa copia
        aloca(5'd23, 5'd1, 5'd2, 5'd0, 2);
        if (ck_livres !== 3'd0) falha("as 4 copias deveriam estar ocupadas");
        @(negedge clk); wb3 = 1; rid3 = 20; r3 = 0;
        borda; wb3 = 0;
        if (ck_livres !== 3'd1) falha("desvio resolvido deveria liberar a copia");
        @(negedge clk); flush_ok = 1; flush_rob_id = 22;
        borda; flush_ok = 0;
        if (ck_livres !== 3'd4) falha("descarte deveria liberar todas as copias");
        $display("PASSOU: quatro copias, liberacao e descarte");

        if (erros == 0) $display("TODOS OS TESTES PASSARAM");
        else $display("%0d ERRO(S)", erros);
        $finish;
    end

    initial begin #20000; $display("FALHOU: timeout"); $finish; end
endmodule

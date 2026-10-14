`timescale 1ns/1ps
// Usa ROB e Load Buffer originais, sem modificar seus arquivos.
module tb_banco_registradores_integracao;
    reg clk = 0, rst = 1;
    reg [2:0] v = 0, wb = 0;
    reg [2:0] dst1 = 0, dst2 = 0, dst3 = 0;
    reg [4:0] rd1 = 7, rd2 = 8, rd3 = 9;
    reg [4:0] rid1 = 0, rid2 = 1, rid3 = 2;
    reg [31:0] r1 = 0, r2 = 0, r3 = 0;
    reg mem_done = 0;
    reg [31:0] mem_data = 0;
    wire [2:0] cdst1, cdst2, cdst3;
    wire [4:0] crid1, crid2, crid3, crob_id1, crob_id2, crob_id3;
    wire [31:0] cr1, cr2, cr3, lb_dado1, lb_dado2, lb_dado3;
    wire [4:0] lrid, lb_rid, rob_tail;
    wire [31:0] laddr;
    wire lready, lb_done, mem_req, rob_stop, lb_stop;
    wire [31:0] x7, x8, x9, x10, x11, x0;
    wire [2:0] load_commits = {
        cdst3 == 3'b010, cdst2 == 3'b010, cdst1 == 3'b010
    };
    wire [4:0] next_id2 = rob_tail + 5'd1;
    wire [4:0] next_id3 = rob_tail + 5'd2;
    wire [8:0] destinos_commit = {cdst3, cdst2, cdst1};
    wire [14:0] ids_commit = {crob_id3, crob_id2, crob_id1};
    wire [95:0] dados_load = {lb_dado3, lb_dado2, lb_dado1};

    // Scoreboard independente: dados que a memoria realmente devolveu.
    reg retorno_pronto [0:31];
    reg [31:0] retorno_memoria [0:31];
    integer indice_rob, posicao_commit, quantidade_loads, verificacoes_load = 0;
    reg [4:0] id_aposentado;
    reg [3:0] posicao_load;

    rob reorder (
        .clk(clk), .rst(rst), .v(v), .dst1(dst1), .dst2(dst2), .dst3(dst3),
        .rd1(rd1), .rd2(rd2), .rd3(rd3), .wb(wb),
        .rid1(rid1), .rid2(rid2), .rid3(rid3), .r1(r1), .r2(r2), .r3(r3),
        .cdst1(cdst1), .cdst2(cdst2), .cdst3(cdst3),
        .crid1(crid1), .crid2(crid2), .crid3(crid3),
        .cr1(cr1), .cr2(cr2), .cr3(cr3),
        .crob_id1(crob_id1), .crob_id2(crob_id2), .crob_id3(crob_id3),
        .lrid(lrid), .lready(lready), .laddr(laddr), .srid(5'd0), .saddr(),
        .lb_done(lb_done), .lb_rid(lb_rid), .stop(rob_stop), .rob_tail(rob_tail)
    );
    load_buffer loads (
        .clk(clk), .rst(rst), .v(v), .dst1(dst1), .dst2(dst2), .dst3(dst3),
        .rob_id1(rob_tail), .rob_id2(next_id2), .rob_id3(next_id3),
        .lrid(lrid), .lready(lready), .mem_req(mem_req), .mem_data(mem_data),
        .mem_done(mem_done), .lb_done(lb_done), .lb_rid(lb_rid),
        .cv(load_commits), .crob_id1(crob_id1), .crob_id2(crob_id2), .crob_id3(crob_id3),
        .lb_dado1(lb_dado1), .lb_dado2(lb_dado2), .lb_dado3(lb_dado3), .stop(lb_stop)
    );
    banco_registradores_rob architectural (
        .clk(clk), .rst(rst), .rs1_1(5'd7), .rs2_1(5'd8),
        .rs1_2(5'd9), .rs2_2(5'd10), .rs1_3(5'd11), .rs2_3(5'd0),
        .valor_rs1_1(x7), .valor_rs2_1(x8), .valor_rs1_2(x9),
        .valor_rs2_2(x10), .valor_rs1_3(x11), .valor_rs2_3(x0),
        .cdst1(cdst1), .cdst2(cdst2), .cdst3(cdst3),
        .crid1(crid1), .crid2(crid2), .crid3(crid3), .cr1(cr1), .cr2(cr2), .cr3(cr3),
        .lb_dado1(lb_dado1), .lb_dado2(lb_dado2), .lb_dado3(lb_dado3)
    );
    always #5 clk = ~clk;
    // Verifica ANTES da borda atualizar o banco ou avancar o head do LB.
    // As consultas hierarquicas observam as flags/IDs que o LB nao exporta.
    always @(posedge clk) begin
        if (rst) begin
            for (indice_rob = 0; indice_rob < 32; indice_rob = indice_rob + 1) begin
                retorno_pronto[indice_rob] = 1'b0;
                retorno_memoria[indice_rob] = 32'd0;
            end
        end else begin
            quantidade_loads = 0;
            for (posicao_commit = 0; posicao_commit < 3; posicao_commit = posicao_commit + 1) begin
                if (destinos_commit[posicao_commit*3 +: 3] == 3'b010) begin
                    id_aposentado = ids_commit[posicao_commit*5 +: 5];
                    posicao_load = loads.head[3:0] + quantidade_loads;
                    if (loads.buffer[posicao_load][37] !== 1'b1 ||
                        retorno_pronto[id_aposentado] !== 1'b1)
                        $fatal(1, "CONTRATO_LB_PRONTO: load %0d aposentou sem dado pronto", id_aposentado);
                    if (loads.buffer[posicao_load][36:32] !== id_aposentado)
                        $fatal(1, "CONTRATO_LB_ID: dado compacto nao corresponde ao load %0d", id_aposentado);
                    if (dados_load[quantidade_loads*32 +: 32] !== retorno_memoria[id_aposentado])
                        $fatal(1, "CONTRATO_LB_DADO: dado compacto diverge do retorno da memoria");
                    retorno_pronto[id_aposentado] = 1'b0;
                    quantidade_loads = quantidade_loads + 1;
                    verificacoes_load = verificacoes_load + 1;
                end
            end
            if (v[0] && dst1 == 3'b010) retorno_pronto[rob_tail] = 1'b0;
            if (v[1] && dst2 == 3'b010) retorno_pronto[next_id2] = 1'b0;
            if (v[2] && dst3 == 3'b010) retorno_pronto[next_id3] = 1'b0;
            if (mem_done) begin
                retorno_pronto[lb_rid] = 1'b1;
                retorno_memoria[lb_rid] = mem_data;
            end
        end
    end
    task step;
        begin @(posedge clk); #1; @(negedge clk); #1; end
    endtask
    task check;
        input condition;
        input [8*160-1:0] message;
        begin if (condition !== 1'b1) $fatal(1, "%0s", message); end
    endtask
    task return_memory;
        input [31:0] address, data;
        begin
            while (!mem_req) step;
            check(laddr == address, "Endereco do load consultado no ROB");
            // Uma borda registra o ID da requisicao no Load Buffer.
            step;
            mem_data = data; mem_done = 1;
            step;
            mem_done = 0;
        end
    endtask
    initial begin #5000; $fatal(1, "Timeout de integracao"); end
    initial begin
        step; rst = 0;
        check(x7 == 0 && x8 == 0 && x9 == 0 && x0 == 0, "Reset compartilhado");
        $display("Integracao 1: resultados fora de ordem so escrevem ao aposentar");
        v = 3'b111; dst1 = 1; dst2 = 1; dst3 = 1;
        step; v = 0;
        wb = 3'b100; r3 = 130;
        step;
        check(x7 == 0 && x8 == 0 && x9 == 0 && cdst3 == 0,
              "Resultado mais novo nao escreve antes da instrucao antiga");
        wb = 3'b011; r1 = 110; r2 = 120;
        step; wb = 0;
        check(x7 == 0 && x8 == 0 && x9 == 0 && cdst1 == 1 && cdst2 == 1 && cdst3 == 1,
              "Banco nao escreve na borda de writeback da execucao");
        step;
        check(x7 == 110 && x8 == 120 && x9 == 130, "Tres aposentadorias simultaneas");

        $display("Integracao 2: banco/load/load seleciona dados do LB, nao enderecos do ROB");
        v = 3'b111; dst1 = 1; dst2 = 2; dst3 = 2;
        rid1 = rob_tail; rid2 = next_id2; rid3 = next_id3;
        step; v = 0;
        wb = 3'b110; r2 = 128; r3 = 256;
        step; wb = 0;
        return_memory(128, 32'hfeed0080);
        return_memory(256, 32'hfeed0100);
        check(x8 == 120 && x9 == 130,
              "Loads nao escrevem antes da aposentadoria do trio");
        wb = 3'b001; r1 = 200;
        step; wb = 0;
        check(cdst1 == 1 && cdst2 == 2 && cdst3 == 2,
              "Trio misto pronto para aposentar");
        // Modos negativos: demonstram que cada verificacao detecta uma falha.
        // Somente o testbench injeta corrupcao; nenhuma porta RTL foi alterada.
        if ($test$plusargs("falha_load_prontidao"))
            loads.buffer[loads.head[3:0]][37] = 1'b0;
        if ($test$plusargs("falha_load_id"))
            loads.buffer[loads.head[3:0]][36:32] = 5'd31;
        if ($test$plusargs("falha_load_dado"))
            loads.buffer[loads.head[3:0]][31:0] = 32'hbad0bad0;
        step;
        check(x7 == 200 && x8 == 32'hfeed0080 && x9 == 32'hfeed0100,
              "Dado compacto do LB alinhado a cada posicao de commit");

        $display("Integracao 3: store e instrucao sem destino nao escrevem no banco");
        v = 3'b111; dst1 = 4; dst2 = 1; dst3 = 0;
        rid1 = rob_tail; rid2 = next_id2; rid3 = next_id3;
        step; v = 0;
        wb = 3'b111; r1 = 32'hbad00001; r2 = 300; r3 = 32'hbad00003;
        step; wb = 0;
        step;
        check(x7 == 200 && x8 == 300 && x9 == 32'hfeed0100 && x0 == 0,
              "Apenas aposentadoria com destino banco altera registrador");
        check(verificacoes_load == 2, "Contrato verificado nos dois loads aposentados");
        $display("PASS integracao: ROB + Load Buffer + banco originais conectados; %0d loads verificados",
                 verificacoes_load);
        $finish;
    end
endmodule

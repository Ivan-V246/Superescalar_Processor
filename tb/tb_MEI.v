`timescale 1ns/1ps

module tb_MEI;

    localparam TAMANHO = 256;

    reg        clk;
    reg        rst;
    reg  [9:0] pc;

    wire [31:0] saida0;
    wire [31:0] saida1;
    wire [31:0] saida2;

    wire  [9:0] pc0, pc1, pc2;
    wire        previu0, previu1, previu2;
    wire  [9:0] alvo0, alvo1, alvo2;

    // Instancia o DUT (nova versao da MEI sem numero de ordem)
    MEI #(
        .TAMANHO(TAMANHO)
    ) uut (
        .clk(clk),
        .rst(rst),
        .pc(pc),
        .saida0(saida0),
        .saida1(saida1),
        .saida2(saida2),
        .pc0(pc0),
        .pc1(pc1),
        .pc2(pc2),
        .previu0(previu0),
        .previu1(previu1),
        .previu2(previu2),
        .alvo0(alvo0),
        .alvo1(alvo1),
        .alvo2(alvo2)
    );

    // Clock de 10ns (100 MHz)
    always #5 clk = ~clk;

    integer i;
    integer erros_esperados_falha;
    integer erros_inesperados;

    // Task auxiliar para esperar 1 borda de subida do clock e dar tempo de estabilizar
    task passo_clock;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    // Task de verificacao para ciclos ativos (fora do reset):
    // se esperar_erro == 1, o mismatch e INTENCIONAL (caso onde se espera resultado errado)
    task checa_bloco;
        input [9:0]  pc_esperado;
        input [31:0] exp0, exp1, exp2;
        input        esperar_erro;
        reg          falhou;
        begin
            falhou = (saida0 !== exp0) ||
                     (saida1 !== exp1) ||
                     (saida2 !== exp2) ||
                     (pc0    !== pc_esperado) ||
                     (pc1    !== (pc_esperado + 10'd4)) ||
                     (pc2    !== (pc_esperado + 10'd8)) ||
                     (previu0 !== 1'b0) || (previu1 !== 1'b0) || (previu2 !== 1'b0) ||
                     (alvo0   !== 10'b0) || (alvo1   !== 10'b0) || (alvo2   !== 10'b0);

            if (falhou) begin
                if (esperar_erro) begin
                    erros_esperados_falha = erros_esperados_falha + 1;
                    $display("[FALHA ESPERADA @ t=%0t] pc=%0d | obtido=(%h, %h, %h) pcs=(%0d,%0d,%0d) | esperado=(%h, %h, %h) pcs=(%0d,%0d,%0d)",
                             $time, pc, saida0, saida1, saida2, pc0, pc1, pc2,
                             exp0, exp1, exp2, pc_esperado, pc_esperado+10'd4, pc_esperado+10'd8);
                end else begin
                    erros_inesperados = erros_inesperados + 1;
                    $display("[ERRO INESPERADO @ t=%0t] pc=%0d | obtido=(%h, %h, %h) pcs=(%0d,%0d,%0d) | esperado=(%h, %h, %h) pcs=(%0d,%0d,%0d)",
                             $time, pc, saida0, saida1, saida2, pc0, pc1, pc2,
                             exp0, exp1, exp2, pc_esperado, pc_esperado+10'd4, pc_esperado+10'd8);
                end
            end else begin
                if (esperar_erro) begin
                    $display("[AVISO @ t=%0t] Esperava-se resultado errado, mas bateu com o esperado!", $time);
                end else begin
                    $display("[OK @ t=%0t] pc=%0d -> saidas=(%h, %h, %h), pcs=(%0d, %0d, %0d)",
                             $time, pc, saida0, saida1, saida2, pc0, pc1, pc2);
                end
            end
        end
    endtask

    initial begin
        // Geracao do arquivo VCD para o GTKWave
        $dumpfile("tb_MEI.vcd");
        $dumpvars(0, tb_MEI);

        clk = 1'b0;
        rst = 1'b1;
        pc  = 10'd0;
        erros_esperados_falha = 0;
        erros_inesperados = 0;

        // Inicializa memoria com padrao claro: palavra[k] = 32'hA000_0000 + k
        for (i = 0; i < TAMANHO; i = i + 1) begin
            uut.memoria[i] = 32'hA000_0000 + i;
        end

        // ---------------------------------------------------------
        // 1. Teste de Reset (todos os PCs, saidas e previsoes zerados)
        // ---------------------------------------------------------
        passo_clock();
        if ((saida0 !== 32'h0) || (saida1 !== 32'h0) || (saida2 !== 32'h0) ||
            (pc0    !== 10'd0) || (pc1    !== 10'd0) || (pc2    !== 10'd0) ||
            (previu0 !== 1'b0) || (previu1 !== 1'b0) || (previu2 !== 1'b0) ||
            (alvo0  !== 10'd0) || (alvo1  !== 10'd0) || (alvo2  !== 10'd0)) begin
            erros_inesperados = erros_inesperados + 1;
            $display("[ERRO INESPERADO @ t=%0t] Falha no reset: saidas=(%h,%h,%h) pcs=(%0d,%0d,%0d)",
                     $time, saida0, saida1, saida2, pc0, pc1, pc2);
        end else begin
            $display("[OK @ t=%0t] Reset verificado: saidas=(%h,%h,%h), pcs=(%0d,%0d,%0d)",
                     $time, saida0, saida1, saida2, pc0, pc1, pc2);
        end

        // Libera o reset para iniciar a operacao normal
        rst = 1'b0;

        // ---------------------------------------------------------
        // 2. Casos validos (resultado correto esperado)
        // ---------------------------------------------------------
        // pc = 0 -> indices de palavra 0, 1, 2
        pc = 10'd0;
        passo_clock();
        checa_bloco(10'd0, 32'hA000_0000, 32'hA000_0001, 32'hA000_0002, 1'b0);

        // pc = 12 (0x0C) -> indices de palavra 3, 4, 5
        pc = 10'd12;
        passo_clock();
        checa_bloco(10'd12, 32'hA000_0003, 32'hA000_0004, 32'hA000_0005, 1'b0);

        // pc = 40 -> indices de palavra 10, 11, 12
        pc = 10'd40;
        passo_clock();
        checa_bloco(10'd40, 32'hA000_000A, 32'hA000_000B, 32'hA000_000C, 1'b0);

        // ---------------------------------------------------------
        // 3. Casos onde se ESPERA resultado errado (falhas propositais)
        // ---------------------------------------------------------
        $display("\n--- Iniciando casos com expectativa de RESULTADO ERRADO ---");

        // Caso Errado A: Checar o bloco de pc=40 comparando com dados antigos de pc=12
        pc = 10'd40;
        passo_clock();
        checa_bloco(10'd40, 32'hA000_0003, 32'hA000_0004, 32'hA000_0005, 1'b1);

        // Caso Errado B: Simular instrucao corrompida na memoria e comparar contra o valor original
        uut.memoria[4] = 32'hDEAD_BEEF; // corrompe palavra no endereco de byte 16 (pc=12 -> pc1=16)
        pc = 10'd12;
        passo_clock();
        checa_bloco(10'd12, 32'hA000_0003, 32'hA000_0004, 32'hA000_0005, 1'b1);

        // Caso Errado C: Esperar pc1 incorreto (ex.: +2 em vez de +4)
        pc = 10'd4;
        passo_clock();
        if (pc1 !== 10'd6) begin
            erros_esperados_falha = erros_esperados_falha + 1;
            $display("[FALHA ESPERADA @ t=%0t] pc=%0d | pc1 obtido=%0d != pc1 esperado_errado=6",
                     $time, pc, pc1);
        end

        // Caso Errado D: Acesso proximo ao limite superior da memoria (pc = 1020 -> palavra 255, +1 e +2 estouram TAMANHO=256)
        pc = 10'd1020;
        passo_clock();
        checa_bloco(10'd1020, 32'hA000_00FF, 32'hA000_0100, 32'hA000_0101, 1'b1);

        $display("\nResumo da simulacao:");
        $display("  Falhas esperadas detectadas : %0d", erros_esperados_falha);
        $display("  Erros inesperados           : %0d", erros_inesperados);

        #10;
        $finish;
    end

endmodule
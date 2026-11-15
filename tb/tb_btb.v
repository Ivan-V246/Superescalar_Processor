`timescale 1ns/1ps

//IVAN FEATURE: Testbench do BTB
module tb_btb;
    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    reg  [9:0] pc_busca = 0;
    wire       previu0, previu1, previu2;
    wire [9:0] alvo0, alvo1, alvo2;

    reg        upd_valid = 0;
    reg  [9:0] upd_pc = 0;
    reg        upd_tomado = 0;
    reg  [9:0] upd_alvo = 0;

    integer erros = 0;

    btb dut (
        .clk(clk), .rst(rst),
        .pc_busca(pc_busca),
        .previu0(previu0), .previu1(previu1), .previu2(previu2),
        .alvo0(alvo0), .alvo1(alvo1), .alvo2(alvo2),
        .upd_valid(upd_valid), .upd_pc(upd_pc), .upd_tomado(upd_tomado), .upd_alvo(upd_alvo)
    );

    //Um desvio resolvido pelo caminho
    task atualiza;
        input [9:0] pc;
        input       tomado;
        input [9:0] alvo;
        begin
            upd_valid = 1; upd_pc = pc; upd_tomado = tomado; upd_alvo = alvo;
            @(posedge clk); #1;
            upd_valid = 0;
        end
    endtask

    //Consulta de um slot
    task checa;
        input [9:0] pc;
        input integer slot;
        input       esp_previu;
        input [9:0] esp_alvo;
        input [8*44-1:0] nome;
        reg         previu;
        reg  [9:0]  alvo;
        begin
            pc_busca = pc; #1;
            case (slot)
                0: begin previu = previu0; alvo = alvo0; end
                1: begin previu = previu1; alvo = alvo1; end
                default: begin previu = previu2; alvo = alvo2; end
            endcase
            if (previu !== esp_previu || (esp_previu && alvo !== esp_alvo)) begin
                $display("FALHOU (%0s): previu=%b alvo=%0d, esperado previu=%b alvo=%0d",
                    nome, previu, alvo, esp_previu, esp_alvo);
                erros = erros + 1;
            end else begin
                $display("PASSOU: %0s", nome);
            end
        end
    endtask

    //Estado do contador de uma posição
    task checa_estado;
        input [9:0] pc;
        input [1:0] esperado;
        input [8*44-1:0] nome;
        begin
            if (dut.estado[pc[6:2]] !== esperado) begin
                $display("FALHOU (%0s): estado=%b, esperado %b", nome, dut.estado[pc[6:2]], esperado);
                erros = erros + 1;
            end else begin
                $display("PASSOU: %0s (estado=%b)", nome, esperado);
            end
        end
    endtask

    initial begin
        @(posedge clk); #1;
        rst = 0;

        // ── Teste 1: após o reset, nada é previsto ──
        $display("\n=== TESTE 1: reset ===");
        checa(10'd0,   0, 0, 0, "slot 0 apos reset");
        checa(10'd0,   2, 0, 0, "slot 2 apos reset");
        checa(10'd120, 1, 0, 0, "outra posicao apos reset");

        // ── Teste 2: desvio novo que pula já é previsto (01 -> 10) ──
        $display("\n=== TESTE 2: desvio novo que pula ===");
        atualiza(10'd8, 1, 10'd40);
        checa_estado(10'd8, 2'b10, "nasce em 01 e pula");
        checa(10'd8, 0, 1, 10'd40, "PC 8 no slot 0");
        checa(10'd4, 1, 1, 10'd40, "PC 8 no slot 1");
        checa(10'd0, 2, 1, 10'd40, "PC 8 no slot 2");
        checa(10'd0, 0, 0, 0,      "PC 0 continua sem previsao");

        // ── Teste 3: transições do contador ──
        $display("\n=== TESTE 3: contador ===");
        atualiza(10'd8, 1, 10'd40); checa_estado(10'd8, 2'b11, "10 pula");
        checa(10'd8, 0, 1, 10'd40, "11 preve pula");
        atualiza(10'd8, 1, 10'd40); checa_estado(10'd8, 2'b11, "11 pula (saturado)");
        atualiza(10'd8, 0, 10'd0);  checa_estado(10'd8, 2'b10, "11 nao pula");
        checa(10'd8, 0, 1, 10'd40, "10 preve pula");
        atualiza(10'd8, 0, 10'd0);  checa_estado(10'd8, 2'b01, "10 nao pula");
        checa(10'd8, 0, 0, 0,      "01 preve nao pula");
        atualiza(10'd8, 0, 10'd0);  checa_estado(10'd8, 2'b00, "01 nao pula");
        atualiza(10'd8, 0, 10'd0);  checa_estado(10'd8, 2'b00, "00 nao pula (saturado)");
        atualiza(10'd8, 1, 10'd40); checa_estado(10'd8, 2'b01, "00 pula");
        checa(10'd8, 0, 0, 0,      "01 continua prevendo nao pula");

        // ── Teste 4: desvio novo que não pula (01 -> 00) ──
        $display("\n=== TESTE 4: desvio novo que nao pula ===");
        atualiza(10'd12, 0, 10'd0);
        checa_estado(10'd12, 2'b00, "nasce em 01 e nao pula");
        checa(10'd12, 0, 0, 0, "PC 12 sem previsao");

        // ── Teste 5: alvo atualizado quando muda (ex.: jalr) ──
        $display("\n=== TESTE 5: alvo novo ===");
        atualiza(10'd20, 1, 10'd100);
        checa(10'd20, 0, 1, 10'd100, "alvo inicial");
        atualiza(10'd20, 1, 10'd200);
        checa(10'd20, 0, 1, 10'd200, "alvo substituido");
        atualiza(10'd20, 0, 10'd0);
        checa(10'd20, 0, 1, 10'd200, "nao pular mantem o alvo");

        // ── Teste 6: mesma posição, tag diferente (PC 20 e PC 148) ──
        $display("\n=== TESTE 6: conflito de posicao ===");
        atualiza(10'd148, 1, 10'd300);
        checa_estado(10'd148, 2'b10, "posicao reiniciada pela nova tag");
        checa(10'd148, 0, 1, 10'd300, "PC 148 previsto");
        checa(10'd20,  0, 0, 0,       "PC 20 perdeu a posicao");

        // ── Teste 7: consulta no ciclo da atualização vê o valor antigo ──
        $display("\n=== TESTE 7: consulta durante a atualizacao ===");
        pc_busca = 10'd60;
        upd_valid = 1; upd_pc = 10'd60; upd_tomado = 1; upd_alvo = 10'd80;
        #1;
        if (previu0 !== 1'b0) begin
            $display("FALHOU (valor antigo no ciclo da atualizacao): previu0=%b", previu0);
            erros = erros + 1;
        end else begin
            $display("PASSOU: valor antigo no ciclo da atualizacao");
        end
        @(posedge clk); #1;
        upd_valid = 0;
        checa(10'd60, 0, 1, 10'd80, "valor novo no ciclo seguinte");

        // ── Teste 8: reset limpa a tabela ──
        $display("\n=== TESTE 8: reset ===");
        rst = 1;
        @(posedge clk); #1;
        rst = 0;
        checa(10'd148, 0, 0, 0, "PC 148 apos reset");
        checa(10'd60,  0, 0, 0, "PC 60 apos reset");

        if (erros == 0)
            $display("\nTODOS OS TESTES PASSARAM");
        else
            $display("\n%0d ERRO(S)", erros);
        $finish;
    end
endmodule

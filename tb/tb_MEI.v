`timescale 1ns / 1ps

module tb_MEI;

    parameter TAMANHO = 256;
    parameter MAXIMO  = 256;

    // Entradas do DUT
    reg clk;
    reg [9:0] pc;

    // Saídas do DUT
    wire [63:0] saida0;
    wire [63:0] saida1;
    wire [63:0] saida2;

    integer i;

    // Instanciação da MEI
    MEI #(
        .TAMANHO(TAMANHO),
        .MAXIMO(MAXIMO)
    ) uut (
        .clk(clk),
        .pc(pc),
        .saida0(saida0),
        .saida1(saida1),
        .saida2(saida2)
    );

    // Geração do Clock (10ns)
    always #5 clk = ~clk;

    initial begin
        // Arquivo VCD para GTKWave
        $dumpfile("tb_MEI.vcd");
        $dumpvars(0, tb_MEI);

        // Inicialização de Sinais
        clk = 0;
        pc = 10'b0;

        // Inicializa a memória interna com instruções em binário
        for (i = 0; i < TAMANHO; i = i + 1) begin
            uut.memoria[i] = i[31:0]; // Grava o valor do índice na memória
        end

        $display("\n==============================================================================================================");
        $display("                                   SIMULACAO MEI (CONTADOR & SAIDAS EM BINARIO)                              ");
        $display("==============================================================================================================");

        #10;

        // -------------------------------------------------------------
        // TESTE 1: PC = 0 (lê posições 0, 1 e 2 da memória)
        // -------------------------------------------------------------
        pc = 10'b0000000000;
        @(posedge clk); #1;
        $display("Tempo: %0t ns | PC: %b", $time, pc);
        $display("  Saida 0 -> Ordem: %b | Inst: %b", saida0[63:32], saida0[31:0]);
        $display("  Saida 1 -> Ordem: %b | Inst: %b", saida1[63:32], saida1[31:0]);
        $display("  Saida 2 -> Ordem: %b | Inst: %b\n", saida2[63:32], saida2[31:0]);

        // -------------------------------------------------------------
        // TESTE 2: PC = 4 (lê posições 1, 2 e 3 da memória)
        // -------------------------------------------------------------
        pc = 10'b0000000100;
        @(posedge clk); #1;
        $display("Tempo: %0t ns | PC: %b", $time, pc);
        $display("  Saida 0 -> Ordem: %b | Inst: %b", saida0[63:32], saida0[31:0]);
        $display("  Saida 1 -> Ordem: %b | Inst: %b", saida1[63:32], saida1[31:0]);
        $display("  Saida 2 -> Ordem: %b | Inst: %b\n", saida2[63:32], saida2[31:0]);

        // -------------------------------------------------------------
        // TESTE 3: PC = 8 (lê posições 2, 3 e 4 da memória)
        // -------------------------------------------------------------
        pc = 10'b0000001000;
        @(posedge clk); #1;
        $display("Tempo: %0t ns | PC: %b", $time, pc);
        $display("  Saida 0 -> Ordem: %b | Inst: %b", saida0[63:32], saida0[31:0]);
        $display("  Saida 1 -> Ordem: %b | Inst: %b", saida1[63:32], saida1[31:0]);
        $display("  Saida 2 -> Ordem: %b | Inst: %b\n", saida2[63:32], saida2[31:0]);

        // -------------------------------------------------------------
        // TESTE 4: Testando o Estouro Binário do Contador Circular
        // -------------------------------------------------------------
        $display("--- Forcando contador próximo do MAXIMO (254 = 32'b...11111110) ---");
        uut.contador = 32'b00000000000000000000000011111110; // 254 em binário

        pc = 10'b0000001100; // PC = 12
        @(posedge clk); #1;
        $display("Tempo: %0t ns | PC: %b", $time, pc);
        $display("  Saida 0 Ordem (254): %b", saida0[63:32]);
        $display("  Saida 1 Ordem (255): %b", saida1[63:32]);
        $display("  Saida 2 Ordem (000): %b (Reiniciou em Binario!)\n", saida2[63:32]);

        #20;
        $display("==============================================================================================================\n");
        $finish;
    end

endmodule
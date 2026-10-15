`timescale 1ns/1ps

// Testbench da MEI usando o programa de "1792013864066_programa_01"
// (6 instrucoes RV32I, uma palavra hexadecimal por linha)
module tb_MEI;
    parameter ARQUIVO = "programa_01";

    reg clk = 0;
    reg rst = 1;
    reg [9:0] pc = 0;
    wire [63:0] saida0, saida1, saida2;

    integer erros = 0;

    MEI dut (
        .clk(clk), .rst(rst), .pc(pc),
        .saida0(saida0), .saida1(saida1), .saida2(saida2)
    );

    always #5 clk = ~clk;

    // conteudo esperado do programa, so para conferencia neste testbench
    reg [31:0] esperado [0:5];
    initial begin
        esperado[0] = 32'h00500293; // addi x5, x0, 5
        esperado[1] = 32'h00a00313; // addi x6, x0, 10
        esperado[2] = 32'h00532023; // sw   x5, 0(x6)
        esperado[3] = 32'h006282b3; // add  x5, x5, x6
        esperado[4] = 32'h00032303; // lw   x6, 0(x6)
        esperado[5] = 32'h40628fb3; // sub  x31, x5, x6
    end

    task checa;
        input [63:0] saida;
        input [31:0] instr_esperada;
        input [31:0] ordem_esperada;
        input [8*16-1:0] nome;
        begin
            if (saida[31:0] !== instr_esperada) begin
                $display("FALHOU (%0s): instrucao = %h, esperado %h", nome, saida[31:0], instr_esperada);
                erros = erros + 1;
            end else if (saida[63:32] !== ordem_esperada) begin
                $display("FALHOU (%0s): ordem = %0d, esperado %0d", nome, saida[63:32], ordem_esperada);
                erros = erros + 1;
            end else begin
                $display("OK     (%0s): ordem=%0d  instrucao=%h", nome, saida[63:32], saida[31:0]);
            end
        end
    endtask

    initial begin
        // carrega o programa direto no array interno do DUT
        $readmemh(ARQUIVO, dut.memoria);

        // reset
        rst = 1;
        @(posedge clk); #1;
        rst = 0;

        // pc = 0 -> instrucoes 0,1,2 / ordem 0,1,2
        pc = 0;
        @(posedge clk); #1;
        checa(saida0, esperado[0], 32'd0, "pc=0  s0");
        checa(saida1, esperado[1], 32'd1, "pc=0  s1");
        checa(saida2, esperado[2], 32'd2, "pc=0  s2");

        // pc = 4 -> instrucoes 1,2,3 / ordem 3,4,5
        pc = 4;
        @(posedge clk); #1;
        checa(saida0, esperado[1], 32'd3, "pc=4  s0");
        checa(saida1, esperado[2], 32'd4, "pc=4  s1");
        checa(saida2, esperado[3], 32'd5, "pc=4  s2");

        // pc = 4 de novo (sem mudar) -> nao deve buscar de novo nem gastar ordem (stall)
        @(posedge clk); #1;
        checa(saida0, esperado[1], 32'd3, "pc repetido s0");
        checa(saida1, esperado[2], 32'd4, "pc repetido s1");
        checa(saida2, esperado[3], 32'd5, "pc repetido s2");

        // pc = 8 -> instrucoes 2,3,4 / ordem 6,7,8 (continuando de onde parou)
        pc = 8;
        @(posedge clk); #1;
        checa(saida0, esperado[2], 32'd6, "pc=8  s0");
        checa(saida1, esperado[3], 32'd7, "pc=8  s1");
        checa(saida2, esperado[4], 32'd8, "pc=8  s2");

        // pc = 12 -> instrucoes 3,4,5 / ordem 9,10,11
        pc = 12;
        @(posedge clk); #1;
        checa(saida0, esperado[3], 32'd9,  "pc=12 s0");
        checa(saida1, esperado[4], 32'd10, "pc=12 s1");
        checa(saida2, esperado[5], 32'd11, "pc=12 s2");

        // pc = 16 -> alcanca alem das 6 instrucoes carregadas; sem tratamento de
        // limite (decisao do projeto), entao so exibe, sem comparar com nada
        pc = 16;
        @(posedge clk); #1;
        $display("pc=16 (fora do programa carregado): s0=%h s1=%h s2=%h", saida0, saida1, saida2);

        if (erros == 0)
            $display("\nTODOS OS TESTES PASSARAM");
        else
            $display("\n%0d TESTE(S) FALHARAM", erros);

        $finish;
    end
endmodule

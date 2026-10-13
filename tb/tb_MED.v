`timescale 1ns / 1ps

module tb_MED;

    // Sinais de entrada do DUT
    reg clk;
    reg memRead;
    reg memWrite;
    reg [2:0] funct3;
    reg [31:0] ende_dado;
    reg [31:0] dado_entrada;

    // Saída do DUT
    wire [31:0] dado_saida;

    // Instanciação do Módulo de Memória de Dados
    MED dut (
        .clk(clk),
        .memRead(memRead),
        .memWrite(memWrite),
        .funct3(funct3),
        .ende_dado(ende_dado),
        .dado_entrada(dado_entrada),
        .dado_saida(dado_saida)
    );

    // Geração de Clock (período de 10ns)
    always #5 clk = ~clk;

    initial begin
        // Geração do arquivo VCD para GTKWave
        $dumpfile("tb_MED.vcd");
        $dumpvars(0, tb_MED);

        // Inicialização dos sinais
        clk = 0;
        memRead = 0;
        memWrite = 0;
        funct3 = 3'b000;
        ende_dado = 32'd0;
        dado_entrada = 32'd0;

        #10;

        // -------------------------------------------------------------
        // TESTE 1: Escrita e Leitura de Byte (SB / LB / LBU)
        // -------------------------------------------------------------
        // Escreve Byte (0xAB) no endereço 0
        memWrite = 1;
        funct3 = 3'b000; // SB
        ende_dado = 32'd0;
        dado_entrada = 32'h000000AB;
        #10;
        memWrite = 0;

        // Leitura com Extensão de Sinal (LB - deve estender o bit 7 de 0xAB -> 0xFFFFFFAB)
        memRead = 1;
        funct3 = 3'b000; // LB
        #10;

        // Leitura com Extensão de Zero (LBU - deve preencher com zeros -> 0x000000AB)
        funct3 = 3'b100; // LBU
        #10;
        memRead = 0;

        // -------------------------------------------------------------
        // TESTE 2: Escrita e Leitura de Half-Word (SH / LH / LHU)
        // -------------------------------------------------------------
        // Escreve Half-Word (0x8001) no endereço 4
        memWrite = 1;
        funct3 = 3'b001; // SH
        ende_dado = 32'd4;
        dado_entrada = 32'h00008001;
        #10;
        memWrite = 0;

        // Leitura com Extensão de Sinal (LH -> 0xFFFF8001)
        memRead = 1;
        funct3 = 3'b001; // LH
        #10;

        // Leitura com Extensão de Zero (LHU -> 0x00008001)
        funct3 = 3'b101; // LHU
        #10;
        memRead = 0;

        // -------------------------------------------------------------
        // TESTE 3: Escrita e Leitura de Word (SW / LW)
        // -------------------------------------------------------------
        // Escreve Word (0x12345678) no endereço 8
        memWrite = 1;
        funct3 = 3'b010; // SW
        ende_dado = 32'd8;
        dado_entrada = 32'h12345678;
        #10;
        memWrite = 0;

        // Leitura de Word (LW -> 0x12345678)
        memRead = 1;
        funct3 = 3'b010; // LW
        #10;
        memRead = 0;

        #20;
        $finish;
    end

endmodule
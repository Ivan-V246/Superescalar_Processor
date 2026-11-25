//==============================================================================
// MED — Memória de Dados
//
// 2048 bytes, endereçados por byte, em little-endian (o byte menos
// significativo fica no menor endereço).
//
//   - Leitura (combinacional): com memRead, devolve no mesmo ciclo o dado em
//     ende_dado, já com a extensão pelo funct3 (lb/lh com sinal, lbu/lhu com
//     zero, lw inteiro). Sem memRead, a saída é 0.
//   - Escrita (síncrona): com memWrite, grava 1, 2 ou 4 bytes a partir de
//     ende_dado (sb, sh, sw) na borda do clock.
//
// No processador, a escrita (Store Buffer) tem prioridade: a leitura só
// acontece nos ciclos sem escrita, e o topo registra o dado lido para o
// Load Buffer.
//
// PREMISSA: acessos alinhados (sh/lh em endereço par, sw/lw em múltiplo de 4)
// e dentro dos 2048 bytes. Endereços fora disso não são tratados.
//==============================================================================

module MED (
    input wire clk,
    input wire rst,

    input wire        memRead,       // Leitura neste ciclo
    input wire        memWrite,      // Escrita na próxima borda do clock
    input wire [2:0]  funct3,        // Tamanho e extensão do acesso
    input wire [31:0] ende_dado,     // Endereço do byte inicial
    input wire [31:0] dado_entrada,  // Dado a escrever (bytes de baixo)
    output reg [31:0] dado_saida     // Dado lido, já estendido
);
    reg [7:0] memoria [2047:0];

    // Bytes a partir do endereço: 1, 2 e 4 bytes
    reg [7:0] r_byte;
    reg [15:0] r_half;
    reg [31:0] r_word;

    always @(*) begin // LEITURA
        r_byte = memoria[ende_dado];
        r_half = {memoria[ende_dado + 1], memoria[ende_dado]};
        r_word = {memoria[ende_dado + 3], memoria[ende_dado + 2], memoria[ende_dado + 1], memoria[ende_dado]};
        if (rst) begin
            dado_saida = 32'b0;
        end else if (memRead) begin
            case (funct3) // y[vetor[x]] -- y: quantidade de bits estendidos -- x: índice do valor que vai ser estendido
                // Extensão de sinal
                3'b000: dado_saida = {{24{r_byte[7]}}, r_byte};  //lb
                3'b001: dado_saida = {{16{r_half[15]}}, r_half}; //lh
                3'b010: dado_saida = r_word;                     //lw
                // Extensão de zero
                3'b100: dado_saida = {24'b0, r_byte};            //lbu
                3'b101: dado_saida = {16'b0, r_half};            //lhu
                default: dado_saida = 32'b0;
            endcase
        end else begin
            dado_saida = 32'b0;
        end
    end

    always @(posedge clk) begin //ESCRITA
        if (!rst && memWrite) begin
            case (funct3)
                3'b000: memoria[ende_dado] <= dado_entrada[7:0];    //sb
                3'b001: begin                                       //sh
                    memoria[ende_dado]     <= dado_entrada[7:0];
                    memoria[ende_dado + 1] <= dado_entrada[15:8];
                end
                3'b010: begin                                       //sw
                    memoria[ende_dado]     <= dado_entrada[7:0];
                    memoria[ende_dado + 1] <= dado_entrada[15:8];
                    memoria[ende_dado + 2] <= dado_entrada[23:16];
                    memoria[ende_dado + 3] <= dado_entrada[31:24];
                end
                default: ;
            endcase
        end
    end
endmodule

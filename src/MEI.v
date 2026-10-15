// Não tratamos pc > tamanho*4
module MEI #(
    parameter TAMANHO = 256, // tamanho da memoria em numeros de palavra
    parameter MAXIMO = 256   // maximo do numero de ordem [tamanho = pc >> 2]
)(
    input wire clk,
    input wire rst,
    input wire [9:0] pc,// na memoria
    output reg [63:0] saida0,          // instrução = [31-0], numero de ordem = [63-32]
    output reg [63:0] saida1,  
    output reg [63:0] saida2 
);
    reg [31:0] memoria [TAMANHO-1:0]; // largura * profundidade
    reg [31:0] contador;      // numero de ordem da primeira palavra do grupo atual
    reg [9:0] pc_ant;         // pc da ultima palavra do grupo anterior

    // a ideia aqui é atribuir os numeros de forma circular (1023 -> 0 -> 1)
    // exemplo: proximo(1022) = 1023; proximo(1023) == 0; proximo(0) = 1
    function [31:0] proximo;
        input [31:0] nu_ordem;
        begin
            proximo = (nu_ordem == MAXIMO -1) ? 32'b0 : nu_ordem + 32'b1;
        end
    endfunction

    wire novo_pc = (pc != pc_ant);

    wire [31:0] fio0 = contador;      // começo do bloco atual
    wire [31:0] fio1 = proximo(fio0);
    wire [31:0] fio2 = proximo(fio1);
    wire [31:0] fio3 = proximo(fio2); //começo do proximo bloco

    always @(posedge clk) begin
        if (rst) begin
            contador <= 32'b0;
            pc_ant   <= 10'b1111111111;
            saida0   <= 64'b0;
            saida1   <= 64'b0;
            saida2   <= 64'b0;
        end else begin
            pc_ant <= pc;

            if (novo_pc) begin
                saida0 <= {fio0, memoria[pc >> 2]};
                saida1 <= {fio1, memoria[(pc >> 2) + 10'b1]};
                saida2 <= {fio2, memoria[(pc >> 2) + 10'b10]};
                contador <= fio3;
            end
        end
    end
endmodule
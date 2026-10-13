module MED (
    input wire clk,
    input wire rst,
    input wire memRead,
    input wire memWrite,
    input wire [2:0] funct3,
    input wire [31:0] ende_dado,    //endereco do dado
    input wire [31:0] dado_entrada, //dado que será escrito
    output reg [31:0] dado_saida
);
    reg [7:0] memoria [2047:0];

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
            case (funct3) // y[vetor[x]] -- y: quantidade de bits extendidos -- x: indice do valor que vai ser extendido
                // extensãode sinal
                3'b000: dado_saida = {{24{r_byte[7]}}, r_byte};
                3'b001: dado_saida = {{16{r_half[15]}}, r_half};
                3'b010: dado_saida = r_word;
                // extensão de zero
                3'b100: dado_saida = {24'b0, r_byte};
                3'b101: dado_saida = {16'b0, r_half};
                default: dado_saida = 32'b0;
            endcase
        end else begin
            dado_saida = 32'b0;
        end
    end

    always @(posedge clk) begin //ESCRITA
        if (!rst && memWrite) begin
            case (funct3)
                3'b000: memoria[ende_dado] <= dado_entrada[7:0];
                3'b001: begin
                    memoria[ende_dado]      <= dado_entrada[7:0];
                    memoria[ende_dado + 1 ] <= dado_entrada[15:8];
                    end
                3'b010: begin
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
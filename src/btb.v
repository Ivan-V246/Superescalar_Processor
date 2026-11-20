//IVAN FEATURE: Branch Target Buffer
//
//Na busca, prevê para cada slot do grupo (pc, pc+4, pc+8) se ele é um desvio
//que pula e para onde. Aprende com os desvios resolvidos pelo caminho de desvio.
//
//32 posições de mapeamento direto:
//  índice = pc[6:2]  (pc[1:0] é sempre 00)
//  tag    = pc[9:7]  (diferencia os PCs que caem na mesma posição)
//
//Contador de 2 bits com saturação: 00 e 01 preveem "não pula", 10 e 11 "pula".
//Uma posição nova nasce em 01 e recebe o resultado logo em seguida.
module btb (
    input  wire       clk, rst,

    //Consulta (busca)
    input  wire [9:0] pc_busca,                  //PC do grupo: slots pc_busca, +4 e +8
    output wire       previu0, previu1, previu2, //Previsão "pula" de cada slot
    output wire [9:0] alvo0, alvo1, alvo2,       //Alvo previsto (vale se previu)

    //Atualização (caminho de desvio)
    input  wire       upd_valid,                 //Um desvio foi resolvido
    input  wire [9:0] upd_pc,                    //PC desse desvio
    input  wire       upd_tomado,                //Se pulou
    input  wire [9:0] upd_alvo                  //Para onde pulou
);
    //Tabela
    reg        valido [0:31];
    reg [2:0]  tag    [0:31];
    reg [9:0]  alvo   [0:31];
    reg [1:0]  estado [0:31];

    //Consulta
    wire [9:0] pc_s0 = pc_busca;
    wire [9:0] pc_s1 = pc_busca + 10'd4;
    wire [9:0] pc_s2 = pc_busca + 10'd8;

    assign previu0 = valido[pc_s0[6:2]] && (tag[pc_s0[6:2]] == pc_s0[9:7]) && estado[pc_s0[6:2]][1];
    assign previu1 = valido[pc_s1[6:2]] && (tag[pc_s1[6:2]] == pc_s1[9:7]) && estado[pc_s1[6:2]][1];
    assign previu2 = valido[pc_s2[6:2]] && (tag[pc_s2[6:2]] == pc_s2[9:7]) && estado[pc_s2[6:2]][1];

    assign alvo0 = alvo[pc_s0[6:2]];
    assign alvo1 = alvo[pc_s1[6:2]];
    assign alvo2 = alvo[pc_s2[6:2]];

    //Atualização
    wire [4:0] pos_upd   = upd_pc[6:2];
    wire       nova = !valido[pos_upd] || (tag[pos_upd] != upd_pc[9:7]);  //Posição vazia ou de outro desvio
    wire [1:0] atual = nova ? 2'b01 : estado[pos_upd];                //Posição nova nasce em 01

    reg [1:0] proximo;
    always @(*) begin
        case (atual)
            2'b00: proximo = upd_tomado ? 2'b01 : 2'b00;
            2'b01: proximo = upd_tomado ? 2'b10 : 2'b00;
            2'b10: proximo = upd_tomado ? 2'b11 : 2'b01;
            default: proximo = upd_tomado ? 2'b11 : 2'b10;
        endcase
    end

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                valido[i] <= 1'b0;
                tag[i]    <= 3'b0;
                alvo[i]   <= 10'b0;
                estado[i] <= 2'b01;
            end
        end else if (upd_valid) begin
            valido[pos_upd] <= 1'b1;
            tag[pos_upd]    <= upd_pc[9:7];
            estado[pos_upd] <= proximo;
            if (upd_tomado) alvo[pos_upd] <= upd_alvo;
        end
    end
endmodule

//==============================================================================
// ROB — Reorder Buffer
//
// Guarda as instruções desde a alocação até o commit, em ordem de programa, e
// as aposenta em ordem: até 3 por ciclo, a partir do head, enquanto estiverem
// prontas.
//
//   - Alocação (em ordem, na entrada da fila do despacho): até 3 por ciclo, nas
//     posições tail, tail+1, tail+2. O rob_id de cada instrução é a sua posição
//     (o despacho o calcula a partir de rob_tail).
//   - Resultado: chega pelo wb dos caminhos, identificado pelo rob_id.
//     Loads: o wb traz o endereço (addr_ready); o Load Buffer lê esse endereço
//     (lrid/laddr) e avisa quando terminou (lb_done), e só então fica pronto.
//     O dado do Load vai ao banco pelo Load Buffer, não pelo ROB.
//   - Commit: expõe destino, rd e resultado das instruções que saem (c*), e o
//     rob_id delas (crob_id*) para o hazard.
//   - Recuperação: quando o caminho de desvio erra (flush), valida o desvio B
//     (ainda ocupado?), volta o tail para B+1 e limpa as entradas mais novas.
//     Repassa flush_ok e rob_head para as outras unidades.
//
// Ponteiros (6 bits: o bit extra distingue cheio de vazio; 32 posições):
//   head → próxima instrução a commitar
//   tail → próxima posição livre
//   [head, tail) → ocupadas
//
// Idade: as unidades medem a idade de uma entrada pela distância ao head:
//   uma entrada é mais nova que B se (rob_id - rob_head) > (flush_rob_id - rob_head)
//
// Resultados que chegam para posições livres (instruções já descartadas) são
// ignorados. Premissa: uma posição liberada não é realocada antes de o
// resultado atrasado chegar (os caminhos levam 1 ciclo; a realocação leva mais).
//
// stop: mais de 29 posições ocupadas, porque até 3 instruções podem ser
// alocadas no mesmo ciclo.
//
// Premissa: o despacho entrega os slots válidos em sequência (v = 001, 011 ou
// 111) e o slot k recebe o rob_id tail + k - 1; a alocação aqui não é compactada.
//==============================================================================

module rob(
    input wire clk, rst,

    //---- Alocação: despacho, até 3 instruções por ciclo ----
    input  wire [2:0]  v,                            // Slots válidos
    input  wire [2:0]  dst1, dst2, dst3,             // Destino (000 banco, 010 Load, 100 Store)
    input  wire [4:0]  rd1, rd2, rd3,                // Registrador de destino
    output wire [4:0]  rob_tail,                     // Posição da próxima alocação (rob_id)

    //---- Resultado: caminhos ----
    input  wire [2:0]  wb,                           // Resultado válido em cada porta
    input  wire [4:0]  rid1, rid2, rid3,             // rob_id do resultado
    input  wire [31:0] r1, r2, r3,                   // Resultado (endereço, no Load)

    //---- Load Buffer ----
    input  wire [4:0]  lrid,                         // rob_id do Load em execução
    output wire        lready,                       // O endereço dele já chegou
    output wire [31:0] laddr,                        // Endereço do Load
    input  wire        lb_done,                      // Um Load terminou: pode commitar
    input  wire [4:0]  lb_rid,                       // rob_id desse Load

    //---- Commit: banco, buffers e hazard (0 quando a instrução não sai) ----
    output wire [2:0]  cdst1, cdst2, cdst3,          // Destino
    output wire [4:0]  crid1, crid2, crid3,          // Registrador escrito
    output wire [31:0] cr1, cr2, cr3,                // Resultado
    output wire [4:0]  crob_id1, crob_id2, crob_id3, // rob_id

    //---- Recuperação ----
    input  wire        flush,                        // O caminho de desvio errou a previsão
    input  wire [4:0]  flush_rob_id,                 // rob_id do desvio que errou (B)
    output wire        flush_ok,                     // B ainda está no ROB: flush válido
    output wire [4:0]  rob_head,                     // Head: referência de idade

    //---- Controle ----
    output wire        stop                          // ROB quase cheio: o despacho para
);

    // Entradas (a ocupação é dada por head e tail: [head, tail))
    reg        addr_ready [0:31];   // Load: endereço pronto, o Load Buffer pode ler
    reg        ready      [0:31];   // Resultado pronto: pode commitar
    reg [2:0]  dst        [0:31];   // Destino (banco, Load, Store)
    reg [4:0]  rd         [0:31];
    reg [31:0] result     [0:31];   // Resultado (no Load, primeiro o endereço)
    reg [5:0] head, tail;

    //Controle da Head
    wire [5:0] committed;
    wire [5:0] head2 = head + 1;
    wire [5:0] head3 = head + 2;

    //Controle da Tail
    wire [5:0] dispatched;
    wire [5:0] tail2 = tail + 1;
    wire [5:0] tail3 = tail + 2;

    //Flags de commit pra cada instrução das três possíveis
    wire c1 = ready[head[4:0]];
    wire c2 = ready[head2[4:0]] & c1;
    wire c3 = ready[head3[4:0]] & c2;

    //Expõe os dados de cada instrução se for commitada; Senão, expõe apenas 0
    assign {cdst1, crid1, cr1} = c1 ? {dst[head[4:0]],  rd[head[4:0]],  result[head[4:0]]}  : 40'b0;
    assign {cdst2, crid2, cr2} = c2 ? {dst[head2[4:0]], rd[head2[4:0]], result[head2[4:0]]} : 40'b0;
    assign {cdst3, crid3, cr3} = c3 ? {dst[head3[4:0]], rd[head3[4:0]], result[head3[4:0]]} : 40'b0;

    //Cálculo de quantas instruções foram adicionadas ou commitadas
    assign dispatched = v[0] + v[1] + v[2];
    assign committed  = c1 + c2 + c3;

    //Exposição para Load Buffer
    assign lready = addr_ready[lrid];
    assign laddr  = result[lrid];

    assign crob_id1 = c1 ? head[4:0]  : 5'b0;
    assign crob_id2 = c2 ? head2[4:0] : 5'b0;
    assign crob_id3 = c3 ? head3[4:0] : 5'b0;

    //Sinal de parada caso não haja 3 ou mais espaços no buffer
    assign stop = ((tail - head) > 6'd29);

    //Expõe o Tail para acomodar as novas posições
    assign rob_tail = tail[4:0];

    //Recuperação
    assign rob_head = head[4:0];

    wire [5:0] ocupadas = tail - head;
    wire [4:0] dist_B   = flush_rob_id - head[4:0];
    assign flush_ok = flush && ({1'b0, dist_B} < ocupadas);

    wire [4:0] dist_r1 = rid1   - head[4:0];
    wire [4:0] dist_r2 = rid2   - head[4:0];
    wire [4:0] dist_r3 = rid3   - head[4:0];
    wire [4:0] dist_lb = lb_rid - head[4:0];
    wire aceita1  = ({1'b0, dist_r1} < ocupadas);
    wire aceita2  = ({1'b0, dist_r2} < ocupadas);
    wire aceita3  = ({1'b0, dist_r3} < ocupadas);
    wire aceita_lb = ({1'b0, dist_lb} < ocupadas);

    reg [4:0] dist_i;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head <= 6'd0;
            tail <= 6'd0;
            for (i = 0; i < 32; i = i + 1) begin
                addr_ready[i] <= 1'b0;
                ready[i]      <= 1'b0;
            end
        end else begin
            head <= head + committed;

            if (flush_ok)
                tail <= head + {1'b0, dist_B} + 6'd1;
            else
                tail <= tail + dispatched;

            // Se a instrução vem do despacho de forma válida, guarda ela
            if(v[0] && !flush_ok) begin
                dst[tail[4:0]] <= dst1; rd[tail[4:0]] <= rd1; result[tail[4:0]] <= 32'b0;
                addr_ready[tail[4:0]] <= 1'b0; ready[tail[4:0]] <= 1'b0;
            end
            if(v[1] && !flush_ok) begin
                dst[tail2[4:0]] <= dst2; rd[tail2[4:0]] <= rd2; result[tail2[4:0]] <= 32'b0;
                addr_ready[tail2[4:0]] <= 1'b0; ready[tail2[4:0]] <= 1'b0;
            end
            if(v[2] && !flush_ok) begin
                dst[tail3[4:0]] <= dst3; rd[tail3[4:0]] <= rd3; result[tail3[4:0]] <= 32'b0;
                addr_ready[tail3[4:0]] <= 1'b0; ready[tail3[4:0]] <= 1'b0;
            end

            // Se a instrução foi resolvida, guarda o resultado; no Load é o endereço
            // (addr_ready), nas outras o resultado final (ready)
            if(wb[0] && aceita1) begin
                result[rid1] <= r1;
                if(dst[rid1] == 3'b010) addr_ready[rid1] <= 1'b1;
                else                    ready[rid1]      <= 1'b1;
            end

            if(wb[1] && aceita2) begin
                result[rid2] <= r2;
                if(dst[rid2] == 3'b010) addr_ready[rid2] <= 1'b1;
                else                    ready[rid2]      <= 1'b1;
            end

            if(wb[2] && aceita3) begin
                result[rid3] <= r3;
                if(dst[rid3] == 3'b010) addr_ready[rid3] <= 1'b1;
                else                    ready[rid3]      <= 1'b1;
            end

            // Load Buffer sinaliza que o dado chegou — pode commitar
            if(lb_done && aceita_lb) ready[lb_rid] <= 1'b1;

            // Se foi commitada, deixa de estar pronta (a posição fica livre)
            if(c1) begin addr_ready[head[4:0]]  <= 1'b0; ready[head[4:0]]  <= 1'b0; end
            if(c2) begin addr_ready[head2[4:0]] <= 1'b0; ready[head2[4:0]] <= 1'b0; end
            if(c3) begin addr_ready[head3[4:0]] <= 1'b0; ready[head3[4:0]] <= 1'b0; end

            //Limpeza das entradas mais novas que B.
            //Fica por último para vencer os wb do mesmo ciclo (vale a última atribuição).
            if (flush_ok) begin
                for (i = 0; i < 32; i = i + 1) begin
                    dist_i = i[4:0] - head[4:0];
                    if (dist_i > dist_B) begin
                        addr_ready[i] <= 1'b0;
                        ready[i]      <= 1'b0;
                    end
                end
            end
        end
    end
endmodule

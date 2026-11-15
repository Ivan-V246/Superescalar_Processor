module rob(
    input wire clk, rst,                    //Clock e Reset

    //Instruções que vem para serem adicionadas ao ROB
    input wire [2:0]  v,                    //Instruções vinda dos despachos são válidas?
    input wire [2:0]  dst1, dst2, dst3,     //Destino da instrução (banco, pc, memória...)
    input wire [4:0]  rd1, rd2, rd3,        //RDs das instruções vindas

    //Resultados vindo dos caminhos de resolução
    input wire [2:0]  wb,                   //Veio uma resolução do caminho?
    input wire [4:0]  rid1, rid2, rid3,     //Rob id das resoluções que estão vindo
    input wire [31:0] r1, r2, r3,           //Resultados das resoluções

    //Sinais dos commits
    output wire [2:0]  cdst1, cdst2, cdst3,         //Destino da instrução commitada
    output wire [4:0]  crid1, crid2, crid3,         //Aonde essa instrução escreve?
    output wire [31:0] cr1, cr2, cr3,               //Qual o resultado a ser escrito?
    output wire [4:0] crob_id1, crob_id2, crob_id3, //Qual o id das instruções sendo commitadas?

    //Controle do Load Buffer
    input  wire [4:0]  lrid,                //Load Buffer pergunta por esse id
    output wire        lready,              //O endereço já está pronto?
    output wire [31:0] laddr,               //Qual o endereço?

    // Controle do Store Buffer
    input  wire [4:0]  srid,   // Store Buffer pergunta por esse id
    output wire [31:0] saddr,  // Endereço guardado no ROB para esse id

    //Porta de entrada do Load Buffer
    input wire        lb_done,   // Load Buffer sinalizando que o dado chegou
    input wire [4:0]  lb_rid,    // qual rob_id está pronto

    //Sinal de parada para o despacho
    output wire stop,

    //Posição atual da Tail, para o despacho
    output wire [4:0] rob_tail,

    //IVAN FEATURE: Recuperação de desvio com previsão errada
    input  wire       flush,          //O caminho de desvio errou a previsão
    input  wire [4:0] flush_rob_id,   //rob_id do desvio que errou (B)
    output wire       flush_ok,       //Flush válido: B ainda está no ROB (repassado às outras unidades)
    output wire [4:0] rob_head        //Head do ROB: referência de idade para as outras unidades
);
    // Layout do buffer:
    //      32 posições de 43 bits cada:
    // [42]    -> valid
    // [41]    -> addr_ready (endereço pronto, Load Buffer pode buscar)
    // [40]    -> ready (resultado pronto, pode commitar)
    // [39:37] -> destination (3 bits)
    // [36:32] -> rd  (5 bits)
    // [31:0]  -> result
    reg [42:0] buffer [0:31];
    reg [5:0] head, tail;

    //Controle da Head
    wire [5:0] commited;
    wire [5:0] head2 = head + 1;
    wire [5:0] head3 = head + 2;

    //Controle da Tail
    wire [5:0] dispatched;
    wire [5:0] tail2 = tail + 1;
    wire [5:0] tail3 = tail + 2;

    //Flags de commit pra cada instrução das três possíveis
    wire c1 = buffer[head[4:0]][40];
    wire c2 = buffer[head2[4:0]][40] & c1;
    wire c3 = buffer[head3[4:0]][40] & c2;

    //Expõe os dados de cada instrução se for commitada; Senão, expõe apenas 0
    assign {cdst1, crid1, cr1} = c1 ? buffer[head[4:0]][39:0]  : 40'b0;
    assign {cdst2, crid2, cr2} = c2 ? buffer[head2[4:0]][39:0] : 40'b0;
    assign {cdst3, crid3, cr3} = c3 ? buffer[head3[4:0]][39:0] : 40'b0;

    //Cálculo de quantas instruções foram adicionadas ou commitadas
    assign dispatched = v[0] + v[1] + v[2];
    assign commited   = c1 + c2 + c3;

    //Exposição para Load Buffer
    assign lready = buffer[lrid][41];
    assign laddr  = buffer[lrid][31:0];

    assign crob_id1 = c1 ? head[4:0]  : 5'b0;
    assign crob_id2 = c2 ? head2[4:0] : 5'b0;
    assign crob_id3 = c3 ? head3[4:0] : 5'b0;

    //Exposição para Store Buffer
    assign saddr = buffer[srid][31:0];

    //Sinal de parada caso não haja 3 ou mais espaços no buffer
    assign stop = ((tail - head) > 6'd29);

    //Expõe o Tail para acomodar as novas posições
    assign rob_tail = tail[4:0];

    //IVAN FEATURE: Recuperação
    //Uma posição está ocupada se a sua distância ao head é menor que a ocupação.
    //Isso valida o flush (desvio de um caminho já descartado é ignorado) e filtra
    //resultados que chegam para posições livres (instruções já descartadas).
    //Premissa: uma posição liberada não é realocada antes de o resultado atrasado
    //chegar (hoje os caminhos levam 1 ciclo e a realocação leva mais que isso).
    //As outras unidades medem a idade de suas entradas pela distância a este head:
    //uma entrada é mais nova que B se (rob_id - rob_head) > (flush_rob_id - rob_head)
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
            for (i = 0; i < 32; i = i + 1)
                buffer[i][42:40] <= 3'b0;  // limpa valid, addr_ready e ready
        end else begin
            head <= head + commited;

            //IVAN FEATURE: No flush, o tail volta para logo depois de B e as
            //alocações do ciclo (caminho errado) são ignoradas
            if (flush_ok)
                tail <= head + {1'b0, dist_B} + 6'd1;
            else
                tail <= tail + dispatched;

            // Se a instrução vem do despacho de forma válida, guarda ela
            if(v[0] && !flush_ok) buffer[tail[4:0]]  <= {1'b1, 2'b0, dst1, rd1, 32'b0};
            if(v[1] && !flush_ok) buffer[tail2[4:0]] <= {1'b1, 2'b0, dst2, rd2, 32'b0};
            if(v[2] && !flush_ok) buffer[tail3[4:0]] <= {1'b1, 2'b0, dst3, rd3, 32'b0};

            // Se a instrução foi resolvida, atualizamos o res e os bits de controle
            //IVAN FEATURE: só para posições ocupadas (aceita*)
            if(wb[0] && aceita1) begin
                buffer[rid1][31:0] <= r1;
                if(buffer[rid1][39:37] == 3'b010) begin
                    buffer[rid1][41] <= 1'b1;
                end else begin
                    buffer[rid1][40] <= 1'b1;
                end
            end

            if(wb[1] && aceita2) begin
                buffer[rid2][31:0] <= r2;
                if(buffer[rid2][39:37] == 3'b010) begin
                    buffer[rid2][41] <= 1'b1;
                end else begin
                    buffer[rid2][40] <= 1'b1;
                end
            end

            if(wb[2] && aceita3) begin
                buffer[rid3][31:0] <= r3;
                if(buffer[rid3][39:37] == 3'b010) begin
                    buffer[rid3][41] <= 1'b1;
                end else begin
                    buffer[rid3][40] <= 1'b1;
                end
            end

            // Load Buffer sinaliza que o dado chegou — pode commitar
            if(lb_done && aceita_lb) buffer[lb_rid][40] <= 1'b1;  // ready=1 (IVAN FEATURE: só se ocupada)

            // Se foi commitada, torna-se inválida e não pronta
            if(c1) buffer[head[4:0]][42:40]  <= 3'b0;
            if(c2) buffer[head2[4:0]][42:40] <= 3'b0;
            if(c3) buffer[head3[4:0]][42:40] <= 3'b0;

            //IVAN FEATURE: Limpeza das entradas mais novas que B.
            //Fica por último para vencer os wb do mesmo ciclo (vale a última atribuição).
            if (flush_ok) begin
                for (i = 0; i < 32; i = i + 1) begin
                    dist_i = i[4:0] - head[4:0];
                    if (dist_i > dist_B) buffer[i][42:40] <= 3'b0;
                end
            end
        end
    end
endmodule

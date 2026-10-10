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
    output wire [4:0] rob_tail
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

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head <= 6'd0;
            tail <= 6'd0;
            for (i = 0; i < 32; i = i + 1)
                buffer[i][42:40] <= 3'b0;  // limpa valid, addr_ready e ready
        end else begin
            head <= head + commited;
            tail <= tail + dispatched;

            // Se a instrução vem do despacho de forma válida, guarda ela
            if(v[0]) buffer[tail[4:0]]  <= {1'b1, 2'b0, dst1, rd1, 32'b0};
            if(v[1]) buffer[tail2[4:0]] <= {1'b1, 2'b0, dst2, rd2, 32'b0};
            if(v[2]) buffer[tail3[4:0]] <= {1'b1, 2'b0, dst3, rd3, 32'b0};

            // Se a instrução foi resolvida, atualizamos o res e os bits de controle
            if(wb[0]) begin
                buffer[rid1][31:0] <= r1;
                if(buffer[rid1][39:37] == 3'b010) begin
                    buffer[rid1][41] <= 1'b1;
                end else begin
                    buffer[rid1][40] <= 1'b1;
                end
            end

            if(wb[1]) begin
                buffer[rid2][31:0] <= r2;
                if(buffer[rid2][39:37] == 3'b010) begin
                    buffer[rid2][41] <= 1'b1;
                end else begin
                    buffer[rid2][40] <= 1'b1;
                end
            end

            if(wb[2]) begin
                buffer[rid3][31:0] <= r3;
                if(buffer[rid3][39:37] == 3'b010) begin
                    buffer[rid3][41] <= 1'b1;
                end else begin
                    buffer[rid3][40] <= 1'b1;
                end
            end

            // Load Buffer sinaliza que o dado chegou — pode commitar
            if(lb_done) buffer[lb_rid][40] <= 1'b1;  // ready=1

            // Se foi commitada, torna-se inválida e não pronta
            if(c1) buffer[head[4:0]][42:40]  <= 3'b0;
            if(c2) buffer[head2[4:0]][42:40] <= 3'b0;
            if(c3) buffer[head3[4:0]][42:40] <= 3'b0;
        end
    end
endmodule

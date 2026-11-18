module load_buffer(
    input wire clk, rst,

    // Despacho — até 3 instruções por ciclo
    input wire [2:0] v,                         // Quais slots são válidos
    input wire [2:0] dst1, dst2, dst3,           // Destino de cada instrução
    input wire [4:0] rob_id1, rob_id2, rob_id3, // Rob ids

    // Consulta ao ROB
    output wire [4:0]  lrid,    // Rob id do Load mais antigo sem leitura
    input  wire        lready,  // O endereço desse Load já foi calculado?

    // Consulta ao Store Buffer
    input  wire [4:0]  sb_tail,  // Tail do Store Buffer, para a idade do Load
    output wire [4:0]  q_idade,  // Idade do Load mais antigo sem leitura
    input  wire        q_espera, // Há Store mais antigo de endereço desconhecido que pode coincidir
    input  wire        q_hit,    // Há Store mais antigo no mesmo endereço: o dado vem dele
    input  wire [31:0] q_dado,   // Dado do Store (forwarding)

    // Memória
    output wire        mem_req,
    input  wire [31:0] mem_data,
    input  wire        mem_done,

    // Sinaliza pro ROB
    output wire        lb_done,
    output wire [4:0]  lb_rid,

    // Commits do ROB
    input wire [2:0]  cv,
    input wire [4:0] crob_id1, crob_id2, crob_id3,

    // Escrita no banco
    output wire [31:0] lb_dado1, lb_dado2, lb_dado3,

    // Sinal de parada
    output wire stop,

    //IVAN FEATURE: Tail exposto para o ponto de corte dos desvios no despacho
    output wire [4:0] lb_tail,

    //IVAN FEATURE: Recuperação de desvio (aviso do ROB)
    input  wire       flush_ok,       //Desvio B errou e ainda está no ROB
    input  wire [4:0] flush_rob_id,   //rob_id de B
    input  wire [4:0] rob_head        //Head do ROB: referência de idade
);
    // Layout:
    // [37]    → dado_pronto
    // [36:32] → rob_id (5 bits)
    // [31:0]  → dado (32 bits)
    reg [37:0] buffer [0:15];
    reg [4:0]  idade  [0:15];   // Tail do Store Buffer no despacho: Stores mais antigos estão antes dele
    reg [4:0] head, mem_ptr, tail;

    wire [4:0] head2 = head + 1;
    wire [4:0] head3 = head + 2;
    wire [4:0] tail2 = tail + 1;
    wire [4:0] tail3 = tail + 2;

    // Filtragem interna — quais slots são Load
    wire is_load1 = v[0] & (dst1 == 3'b010);
    wire is_load2 = v[1] & (dst2 == 3'b010);
    wire is_load3 = v[2] & (dst3 == 3'b010);

    wire [2:0] dispatched = is_load1 + is_load2 + is_load3;

    // Idade — conta os Stores dos slots anteriores do mesmo grupo
    wire is_store1 = v[0] & (dst1 == 3'b100);
    wire is_store2 = v[1] & (dst2 == 3'b100);

    wire [4:0] idade1 = sb_tail;
    wire [4:0] idade2 = sb_tail + is_store1;
    wire [4:0] idade3 = sb_tail + is_store1 + is_store2;

    // Commit
    wire commit1 = (cv[0] & (crob_id1 == buffer[head[3:0]][36:32]))  |
                   (cv[1] & (crob_id2 == buffer[head[3:0]][36:32]))  |
                   (cv[2] & (crob_id3 == buffer[head[3:0]][36:32]));

    wire commit2 = commit1 &
                   ((cv[1] & (crob_id2 == buffer[head2[3:0]][36:32])) |
                    (cv[2] & (crob_id3 == buffer[head2[3:0]][36:32])));

    wire commit3 = commit2 &
                   (cv[2] & (crob_id3 == buffer[head3[3:0]][36:32]));

    //PEDRO: Correção. A versão anterior comparava o mesmo commit com mais de uma entrada e
    //podia aposentar entradas vazias (rob_id antigo ou 0 do reset), passando o head do tail
    //e deixando o stop ligado para sempre. O ROB aposenta os loads em ordem e eles estão em
    //ordem no buffer, então o número de aposentados é o número de commits de load.
    wire [2:0] aposentados = cv[0] + cv[1] + cv[2];

    assign lrid    = buffer[mem_ptr[3:0]][36:32];
    assign q_idade = idade[mem_ptr[3:0]];

    //IVAN FEATURE: Recuperação
    //Todas as entradas ainda não fizeram commit e estão na ordem do programa, então as
    //mais antigas que B formam o início da fila: o novo tail é head + n_mantidos.
    //Uma entrada é mais antiga que B se está mais perto do head do ROB que B.
    reg        descarta_resposta;    //Ignora o mem_done do ciclo seguinte (Load descartado)
    wire       mem_done_ok = mem_done & !descarta_resposta;

    wire [4:0] dist_B      = flush_rob_id - rob_head;
    wire [4:0] ocupadas_lb = tail - head;
    reg  [4:0] n_mantidos;
    reg  [4:0] pos_k, dist_k, mem_prox;
    integer k;

    always @(*) begin
        n_mantidos = 5'd0;
        for (k = 0; k < 16; k = k + 1) begin
            pos_k  = head + k;
            dist_k = buffer[pos_k[3:0]][36:32] - rob_head;
            if (k < ocupadas_lb && dist_k < dist_B)
                n_mantidos = n_mantidos + 5'd1;
        end
    end

    wire [4:0] tail_flush = head + n_mantidos;

    // O Load em mem_ptr termina pela memória (um ciclo depois do mem_req)
    // ou por forwarding (no mesmo ciclo da consulta)
    //IVAN FEATURE: mem_done_ok no lugar de mem_done (resposta de Load descartado não conta)
    wire pronto = lready & !q_espera & (mem_ptr != tail) & !mem_done_ok;
    wire fwd    = pronto & q_hit;
    assign mem_req = pronto & !q_hit;

    wire        termina   = mem_done_ok | fwd;
    wire [31:0] dado_lido = fwd ? q_dado : mem_data;

    // mem_ptr só avança quando o Load termina, então ele ainda aponta para esse Load
    assign lb_done = termina;
    assign lb_rid  = buffer[mem_ptr[3:0]][36:32];

    assign lb_dado1 = buffer[head[3:0]][31:0];
    assign lb_dado2 = buffer[head2[3:0]][31:0];
    assign lb_dado3 = buffer[head3[3:0]][31:0];

    assign stop = ((tail - head) > 5'd13);

    //IVAN FEATURE
    assign lb_tail = tail;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head         <= 5'd0;
            mem_ptr      <= 5'd0;
            tail         <= 5'd0;
            descarta_resposta <= 1'b0;  //IVAN FEATURE
            for (i = 0; i < 16; i = i + 1) begin
                buffer[i] <= 38'b0;
                idade[i]  <= 5'b0;
            end
        end else begin
            head <= head + aposentados;

            //IVAN FEATURE: No flush, o tail volta para depois do último Load mais antigo
            //que B, e as alocações do ciclo (caminho errado) são ignoradas
            if (flush_ok)
                tail <= tail_flush;
            else
                tail <= tail + dispatched;

            //IVAN FEATURE: Se o Load em mem_ptr foi descartado e pediu a memória neste
            //ciclo, a resposta que chega no próximo ciclo é ignorada (vale só um ciclo)
            descarta_resposta <= flush_ok && mem_req && ((mem_ptr - head) >= n_mantidos);

            // Despacho compactado
            if (!flush_ok)  //IVAN FEATURE
            case({is_load1, is_load2, is_load3})
                3'b001: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id3, 32'b0}; idade[tail[3:0]]  <= idade3;
                end
                3'b010: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id2, 32'b0}; idade[tail[3:0]]  <= idade2;
                end
                3'b011: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id2, 32'b0}; idade[tail[3:0]]  <= idade2;
                    buffer[tail2[3:0]] <= {1'b0, rob_id3, 32'b0}; idade[tail2[3:0]] <= idade3;
                end
                3'b100: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0}; idade[tail[3:0]]  <= idade1;
                end
                3'b101: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0}; idade[tail[3:0]]  <= idade1;
                    buffer[tail2[3:0]] <= {1'b0, rob_id3, 32'b0}; idade[tail2[3:0]] <= idade3;
                end
                3'b110: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0}; idade[tail[3:0]]  <= idade1;
                    buffer[tail2[3:0]] <= {1'b0, rob_id2, 32'b0}; idade[tail2[3:0]] <= idade2;
                end
                3'b111: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0}; idade[tail[3:0]]  <= idade1;
                    buffer[tail2[3:0]] <= {1'b0, rob_id2, 32'b0}; idade[tail2[3:0]] <= idade2;
                    buffer[tail3[3:0]] <= {1'b0, rob_id3, 32'b0}; idade[tail3[3:0]] <= idade3;
                end
            endcase

            if(termina) begin
                buffer[mem_ptr[3:0]][31:0] <= dado_lido;
                buffer[mem_ptr[3:0]][37]   <= 1'b1;
                mem_ptr <= mem_ptr + 1;
            end

            //IVAN FEATURE: Se o mem_ptr (depois do avanço deste ciclo) passou do corte,
            //volta para o novo tail. Fica por último para vencer o avanço.
            if (flush_ok) begin
                mem_prox = termina ? mem_ptr + 5'd1 : mem_ptr;
                if ((mem_prox - head) > n_mantidos)
                    mem_ptr <= tail_flush;
            end
        end
    end
endmodule

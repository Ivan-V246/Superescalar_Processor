//==============================================================================
// Load Buffer
//
// Guarda os Loads desde a alocação até o commit, em ordem de programa, e
// executa um Load por vez: o mais antigo que ainda não tem o dado.
//
//   - Alocação (em ordem, na entrada da fila do despacho): cada Load reserva
//     uma posição com rob_id, funct3 e idade (tail do Store Buffer naquele
//     momento, somando os Stores dos slots anteriores do mesmo grupo).
//   - Execução (Load em mem_ptr): pergunta ao ROB se o endereço já foi
//     calculado (lrid/lready) e ao Store Buffer se pode ler (q_*). Termina
//     por forwarding (no mesmo ciclo) ou pela MED (um ciclo depois do mem_req).
//   - Resultado: avisa o ROB e o hazard (lb_done, lb_rid) e guarda o dado.
//   - Commit: o ROB avisa quantos Loads foram commitados (cv), sempre em ordem;
//     os dados saem em lb_dado1..3 para o banco de registradores.
//   - Recuperação: no flush, descarta os Loads mais novos que B e ignora a
//     resposta da memória de um Load descartado.
//
// Ponteiros (5 bits: o bit extra distingue cheio de vazio; 16 posições):
//   head    → próximo Load a ser commitado
//   mem_ptr → próximo Load a executar
//   tail    → próxima posição livre
//   [head, mem_ptr) → executados, esperando o commit
//   [mem_ptr, tail) → esperando a execução
//
// O endereço do Load não fica aqui: o ROB o entrega (laddr) pelo rob_id em lrid.
// Ele sempre está disponível enquanto é necessário, pois o Load lê sempre
// antes do seu commit.
//
// stop: mais de 13 posições ocupadas, porque até 3 Loads podem ser alocados
// no mesmo ciclo.
//==============================================================================

module load_buffer(
    input wire clk, rst,

    //---- Alocação: despacho, até 3 instruções por ciclo ----
    input wire [2:0]  v,                           // Slots válidos
    input wire [2:0]  dst1, dst2, dst3,            // Tipo de cada slot (010 = Load, 100 = Store)
    input wire [4:0]  rob_id1, rob_id2, rob_id3,   // Identifica o Load no ROB e no flush
    input wire [2:0]  funct3_1, funct3_2, funct3_3,// Tamanho do acesso (lb, lh, lw, lbu, lhu)
    input wire [4:0]  sb_tail,                     // Tail do Store Buffer, para a idade do Load

    //---- Endereço: ROB ----
    output wire [4:0] lrid,                        // rob_id do Load em execução
    input  wire       lready,                      // O endereço dele já foi calculado

    //---- Consulta: Store Buffer ----
    output wire [4:0]  q_idade,                    // Idade do Load em execução
    output wire [2:0]  q_funct3,                   // Tamanho do Load em execução
    input  wire        q_espera,                   // Esperar: Store mais antigo sem endereço,
                                                   // sem dado ou com sobreposição parcial
    input  wire        q_hit,                      // Forwarding: um Store mais antigo cobre o Load
    input  wire [31:0] q_dado,                     // Dado do forwarding, já com a extensão

    //---- Memória: MED ----
    output wire        mem_req,                    // Pedido de leitura (resposta no ciclo seguinte)
    output wire [2:0]  mem_funct3,                 // Tamanho da leitura
    input  wire [31:0] mem_data,                   // Dado lido, já com a extensão
    input  wire        mem_done,                   // Resposta da leitura

    //---- Resultado: ROB e hazard ----
    output wire        lb_done,                    // Um Load terminou neste ciclo
    output wire [4:0]  lb_rid,                     // rob_id desse Load

    //---- Commit: ROB e banco de registradores ----
    input  wire [2:0]  cv,                         // Quais commits do ciclo são Load
    output wire [31:0] lb_dado1, lb_dado2, lb_dado3,// Dados dos Loads commitados, em ordem

    //---- Recuperação: aviso do ROB ----
    input  wire        flush_ok,                   // Desvio B errou e ainda está no ROB
    input  wire [4:0]  flush_rob_id,               // rob_id de B
    input  wire [4:0]  rob_head,                   // Head do ROB: referência de idade
    output wire [4:0]  lb_tail,                    // Tail, ponto de corte guardado pelo despacho

    //---- Controle ----
    output wire        stop                        // Buffer quase cheio: o despacho para
);

    reg [4:0]  rob_id [0:15];
    reg [31:0] dado   [0:15];
    reg [4:0]  idade  [0:15]; // Tail do Store Buffer na alocação: Stores antes dele são mais antigos.
    reg [2:0]  f3     [0:15];
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
    // O ROB aposenta os Loads em ordem e eles estão em ordem no buffer,
    // então o número de aposentados é o número de commits de Load.
    wire [2:0] aposentados = cv[0] + cv[1] + cv[2];

    assign lrid    = rob_id[mem_ptr[3:0]];
    assign q_idade = idade[mem_ptr[3:0]];

    //O Load em mem_ptr é o que consulta o Store Buffer e o que pede a memória
    assign q_funct3   = f3[mem_ptr[3:0]];
    assign mem_funct3 = f3[mem_ptr[3:0]];

    reg        descarta_resposta;    //Ignora o mem_done do ciclo seguinte (Load descartado)
    wire       mem_done_ok = mem_done & !descarta_resposta;

    //Recuperação
    //Todas as entradas ainda não fizeram commit e estão na ordem do programa, então as
    //mais antigas que B formam o início da fila: o novo tail é head + n_mantidos.
    //Uma entrada é mais antiga que B se está mais perto do head do ROB que B.

    wire [4:0] dist_B      = flush_rob_id - rob_head;
    wire [4:0] ocupadas_lb = tail - head;
    reg  [4:0] n_mantidos;
    reg  [4:0] pos_k, dist_k, mem_prox;
    integer k;

    always @(*) begin
        n_mantidos = 5'd0;
        for (k = 0; k < 16; k = k + 1) begin
            pos_k  = head + k;
            dist_k = rob_id[pos_k[3:0]] - rob_head;
            if (k < ocupadas_lb && dist_k < dist_B)
                n_mantidos = n_mantidos + 5'd1;
        end
    end

    wire [4:0] tail_flush = head + n_mantidos;

    // O Load em mem_ptr termina pela memória (um ciclo depois do mem_req)
    // ou por forwarding (no mesmo ciclo da consulta).
    // Usa mem_done_ok, pois a resposta de um Load descartado não conta.
    wire pronto = lready & !q_espera & (mem_ptr != tail) & !mem_done_ok;
    wire fwd    = pronto & q_hit;
    assign mem_req = pronto & !q_hit;

    wire        termina   = mem_done_ok | fwd;
    wire [31:0] dado_lido = fwd ? q_dado : mem_data;

    // mem_ptr só avança quando o Load termina, então ele ainda aponta para esse Load
    assign lb_done = termina;
    assign lb_rid  = rob_id[mem_ptr[3:0]];

    assign lb_dado1 = dado[head[3:0]];
    assign lb_dado2 = dado[head2[3:0]];
    assign lb_dado3 = dado[head3[3:0]];

    assign stop = ((tail - head) > 5'd13);

    assign lb_tail = tail;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head         <= 5'd0;
            mem_ptr      <= 5'd0;
            tail         <= 5'd0;
            descarta_resposta <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                rob_id[i] <= 5'b0;
                dado[i]   <= 32'b0;
                idade[i]  <= 5'b0;
                f3[i]     <= 3'b010;
            end
        end else begin
            head <= head + aposentados;

            //No flush, o tail volta para depois do último Load mais antigo
            //que B, e as alocações do ciclo (caminho errado) são ignoradas
            if (flush_ok)
                tail <= tail_flush;
            else
                tail <= tail + dispatched;

            //Se o Load em mem_ptr foi descartado e pediu a memória neste
            //ciclo, a resposta que chega no próximo ciclo é ignorada (vale só um ciclo)
            descarta_resposta <= flush_ok && mem_req && ((mem_ptr - head) >= n_mantidos);

            //Cada Load guarda o rob_id, a idade e o funct3 na sua posição
            //(o dado chega depois, na execução). No flush não há alocação.
            if (!flush_ok)
            case({is_load1, is_load2, is_load3})
                3'b001: begin
                    rob_id[tail[3:0]] <= rob_id3; idade[tail[3:0]] <= idade3; f3[tail[3:0]] <= funct3_3;
                end
                3'b010: begin
                    rob_id[tail[3:0]] <= rob_id2; idade[tail[3:0]] <= idade2; f3[tail[3:0]] <= funct3_2;
                end
                3'b011: begin
                    rob_id[tail[3:0]]  <= rob_id2; idade[tail[3:0]]  <= idade2; f3[tail[3:0]]  <= funct3_2;
                    rob_id[tail2[3:0]] <= rob_id3; idade[tail2[3:0]] <= idade3; f3[tail2[3:0]] <= funct3_3;
                end
                3'b100: begin
                    rob_id[tail[3:0]] <= rob_id1; idade[tail[3:0]] <= idade1; f3[tail[3:0]] <= funct3_1;
                end
                3'b101: begin
                    rob_id[tail[3:0]]  <= rob_id1; idade[tail[3:0]]  <= idade1; f3[tail[3:0]]  <= funct3_1;
                    rob_id[tail2[3:0]] <= rob_id3; idade[tail2[3:0]] <= idade3; f3[tail2[3:0]] <= funct3_3;
                end
                3'b110: begin
                    rob_id[tail[3:0]]  <= rob_id1; idade[tail[3:0]]  <= idade1; f3[tail[3:0]]  <= funct3_1;
                    rob_id[tail2[3:0]] <= rob_id2; idade[tail2[3:0]] <= idade2; f3[tail2[3:0]] <= funct3_2;
                end
                3'b111: begin
                    rob_id[tail[3:0]]  <= rob_id1; idade[tail[3:0]]  <= idade1; f3[tail[3:0]]  <= funct3_1;
                    rob_id[tail2[3:0]] <= rob_id2; idade[tail2[3:0]] <= idade2; f3[tail2[3:0]] <= funct3_2;
                    rob_id[tail3[3:0]] <= rob_id3; idade[tail3[3:0]] <= idade3; f3[tail3[3:0]] <= funct3_3;
                end
                default: ;
            endcase

            if(termina) begin
                dado[mem_ptr[3:0]] <= dado_lido;
                mem_ptr <= mem_ptr + 1;
            end

            //Se o mem_ptr (depois do avanço deste ciclo) passou do corte,
            //volta para o novo tail. Fica por último para vencer o avanço.
            if (flush_ok) begin
                mem_prox = termina ? mem_ptr + 5'd1 : mem_ptr;
                if ((mem_prox - head) > n_mantidos)
                    mem_ptr <= tail_flush;
            end
        end
    end
endmodule

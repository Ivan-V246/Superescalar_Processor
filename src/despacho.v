//Despacho com envio fora de ordem
//
//Entrada (em ordem): até 3 instruções por ciclo vindas da MEI entram na fila. Nesse
//momento cada uma reserva sua posição no ROB (rob_id) e, se for load ou store, no
//Load ou Store Buffer, e é informada à unidade de hazard/forwarding, que registra de
//quem ela depende (renomeação).
//
//Envio (fora de ordem): a cada ciclo a fila inteira é examinada, da mais antiga para
//a mais nova, e saem até 3 instruções prontas (operandos disponíveis, segundo o vetor
//"pronto" da unidade de hazard):
//  - caminho 1 e 2: a primeira e a segunda instrução comum escolhidas;
//  - caminho 3: o desvio escolhido (BEQ..BGEU, JAL, JALR).
//Regras de ordem:
//  - instruções de ULA passam na frente de qualquer outra;
//  - loads e stores saem em ordem entre si (nenhum passa na frente de outro mais antigo);
//  - desvios saem em ordem entre si;
//  - nada passa na frente de uma instrução de parada (ECALL, EBREAK, toda zero).
//
//As posições da fila continuam em ordem de programa. Uma instrução enviada deixa um
//"buraco" (vivo = 0), e o head avança quando a posição da frente fica vazia.
//
//Descarte (flush_ok): as instruções mais novas que o desvio B que errou são removidas.
//A idade é medida pela distância ao head do ROB, como no ROB e nos buffers. No ciclo
//do descarte nada é enviado nem alocado.
//
//Contadores de desempenho: ver o fim do arquivo.
module despacho(
    input wire clk, rst,

    //Instruções enviadas pela MEI
    input  wire [2:0]  mei_valid,
    input  wire [31:0] mei_instr0, mei_instr1, mei_instr2,
    input  wire [31:0] mei_ordem0, mei_ordem1, mei_ordem2,
    input  wire [9:0]  mei_pc0, mei_pc1, mei_pc2,
    input  wire        mei_previu0, mei_previu1, mei_previu2,
    input  wire [9:0]  mei_alvo0, mei_alvo1, mei_alvo2,

    output wire        mei_stop,       //Fila quase cheia
    output reg         pc_advence,     //O grupo foi aceito: a busca pode avançar
    output wire [4:0]  ocupacao,       //Posições ocupadas da fila

    //Alocação no ROB e nos buffers (na entrada da fila)
    input  wire        stop,           //ROB cheio
    input  wire [4:0]  Rob_tail,
    input  wire        load_buffer_stop,
    input  wire        store_buffer_stop,
    input  wire [4:0]  sb_tail, lb_tail,  //Pontos de corte dos buffers
    output reg  [2:0]  v,
    output reg  [2:0]  dst1, dst2, dst3,
    output reg  [4:0]  rd1, rd2, rd3,
    output reg  [4:0]  rob_id1, rob_id2, rob_id3,
    output wire [31:0] dado1, dado2, dado3,   //Não usados (o dado do store vai no envio)

    //IVAN FEATURE: Tamanho do acesso (funct3) de cada slot alocado, para os Load/Store Buffers
    output reg  [2:0]  funct3_1, funct3_2, funct3_3,

    //Alocação, para a unidade de hazard (mesma ordem de v)
    output reg  [4:0]  al_rs1_0, al_rs1_1, al_rs1_2,
    output reg  [4:0]  al_rs2_0, al_rs2_1, al_rs2_2,
    output reg         al_escreve0, al_escreve1, al_escreve2,
    output reg         al_alu0, al_alu1, al_alu2,
    output reg         al_desvio0, al_desvio1, al_desvio2,

    //Prontidão de cada instrução, pelo rob_id (da unidade de hazard)
    input  wire [31:0] pronto,
    //Cópias livres para desvios na unidade de hazard: um grupo só entra se houver uma
    //por desvio que ele traz
    input  wire [2:0]  ck_livres,

    //Descarte
    input  wire        flush_ok,
    input  wire [4:0]  flush_rob_id,
    input  wire [4:0]  rob_head,

    //Caminhos 1 e 2 (instruções comuns)
    input  wire        path1_ready, path2_ready,
    output reg         path1_valid, path2_valid,
    output reg  [31:0] path1_instr, path2_instr,
    output reg  [31:0] path1_ordem, path2_ordem,
    output reg  [9:0]  path1_pc, path2_pc,
    output reg  [4:0]  path1_rs1_addr, path1_rs2_addr,
    output reg  [4:0]  path2_rs1_addr, path2_rs2_addr,
    output reg  [4:0]  path1_rob_id, path2_rob_id,
    output reg         path1_previu, path2_previu,
    output reg  [9:0]  path1_alvo, path2_alvo,
    output reg  [4:0]  path1_sb_tail, path2_sb_tail,
    output reg  [4:0]  path1_lb_tail, path2_lb_tail,
    output wire [3:0]  path1_alu_op, path2_alu_op,
    output wire [31:0] path1_imm, path2_imm,
    input  wire [31:0] path1_rs1_data, path1_rs2_data,   //Valores certos (da unidade de hazard)
    input  wire [31:0] path2_rs1_data, path2_rs2_data,

    //Dado do store, para o Store Buffer, no envio
    output reg         store1_valid, store2_valid,
    output reg  [4:0]  store1_rob_id, store2_rob_id,
    output reg  [31:0] store1_dado, store2_dado,

    //Caminho 3 (desvios)
    input  wire        path3_ready,
    output reg         path3_valid,
    output reg  [31:0] path3_instr,
    output reg  [31:0] path3_ordem,
    output reg  [9:0]  path3_pc,
    output reg  [4:0]  path3_rs1_addr, path3_rs2_addr,
    output reg  [4:0]  path3_rob_id,
    output reg         path3_previu,
    output reg  [9:0]  path3_alvo,
    output reg  [4:0]  path3_sb_tail, path3_lb_tail,
    output wire [31:0] path3_imm
);
    localparam [2:0] DST_REG   = 3'b000;
    localparam [2:0] DST_LOAD  = 3'b010;
    localparam [2:0] DST_STORE = 3'b100;

    assign dado1 = 32'd0; assign dado2 = 32'd0; assign dado3 = 32'd0;

    //------------------------------------------------------------------
    //Fila
    //Layout de cada posição:
    // [102] parada [101] desvio [100] memória
    // [99:95] lb_tail  [94:90] sb_tail  [89:80] alvo  [79] previu
    // [78:74] rob_id   [73:64] pc       [63:32] ordem [31:0] instr
    //------------------------------------------------------------------
    reg [102:0] buffer [0:15];
    reg [15:0]  vivo;          //posição com instrução ainda não enviada
    //Cópias pequenas dos campos que a seleção e o descarte examinam em todas as posições.
    //Assim a memória da fila só é lida nas 3 posições escolhidas, o que mantém a síntese
    //viável (ler os 103 bits das 16 posições em cada laço estoura a memória do sintetizador).
    reg [15:0]  q_par, q_desv, q_mem;
    reg [79:0]  q_rob;         //16 posições x 5 bits
    reg [4:0]   head, tail;    //5 bits: o bit extra distingue fila cheia de vazia
    wire [4:0]  count = tail - head;   //posições entre head e tail (vivas ou buracos)

    assign ocupacao = count;
    assign mei_stop = (count >= 5'd14);

    //------------------------------------------------------------------
    //Decodificação na entrada
    //------------------------------------------------------------------
    wire [2:0] e_dst  [0:2];
    wire [4:0] e_rd   [0:2];
    wire [4:0] e_rs1  [0:2];
    wire [4:0] e_rs2  [0:2];
    wire       e_desv [0:2];
    wire       e_par  [0:2];
    wire [2:0] e_f3   [0:2];   //IVAN FEATURE: funct3 de memória de cada slot da entrada

    //IVAN FEATURE: .mem_funct3 ligado em e_f3
    decoder decE0 (.instr(mei_instr0), .instr_valid(), .parada(e_par[0]), .ilegal(), .desvio(e_desv[0]),
        .dst(e_dst[0]), .rs1(e_rs1[0]), .rs2(e_rs2[0]), .rd(e_rd[0]), .alu_op(), .mem_funct3(e_f3[0]), .imm());
    decoder decE1 (.instr(mei_instr1), .instr_valid(), .parada(e_par[1]), .ilegal(), .desvio(e_desv[1]),
        .dst(e_dst[1]), .rs1(e_rs1[1]), .rs2(e_rs2[1]), .rd(e_rd[1]), .alu_op(), .mem_funct3(e_f3[1]), .imm());
    decoder decE2 (.instr(mei_instr2), .instr_valid(), .parada(e_par[2]), .ilegal(), .desvio(e_desv[2]),
        .dst(e_dst[2]), .rs1(e_rs1[2]), .rs2(e_rs2[2]), .rd(e_rd[2]), .alu_op(), .mem_funct3(e_f3[2]), .imm());

    //------------------------------------------------------------------
    //Entrada na fila e alocação
    //------------------------------------------------------------------
    reg [2:0] n_in;
    reg [4:0] free_slots;
    reg       ent_load, ent_store, accept_in;
    reg [1:0] n_desv_in;
    reg [1:0] k_aloc;
    integer   j;

    always @* begin
        n_in = {2'b00, mei_valid[0]} + {2'b00, mei_valid[1]} + {2'b00, mei_valid[2]};
        free_slots = 5'd16 - count;

        ent_load  = (mei_valid[0] && e_dst[0] == DST_LOAD)  || (mei_valid[1] && e_dst[1] == DST_LOAD)  ||
                    (mei_valid[2] && e_dst[2] == DST_LOAD);
        ent_store = (mei_valid[0] && e_dst[0] == DST_STORE) || (mei_valid[1] && e_dst[1] == DST_STORE) ||
                    (mei_valid[2] && e_dst[2] == DST_STORE);

        n_desv_in = {1'b0, mei_valid[0] && e_desv[0]} + {1'b0, mei_valid[1] && e_desv[1]} +
                    {1'b0, mei_valid[2] && e_desv[2]};

        //No ciclo do descarte, o que chega da MEI é do caminho errado
        accept_in = !mei_stop && (n_in <= free_slots) && !stop && !flush_ok &&
                    ({1'b0, n_desv_in} <= ck_livres) &&
                    !(ent_load && load_buffer_stop) && !(ent_store && store_buffer_stop);
        pc_advence = accept_in && (n_in != 0);

        v = 3'b000;
        dst1 = DST_REG; dst2 = DST_REG; dst3 = DST_REG;
        rd1 = 5'd0; rd2 = 5'd0; rd3 = 5'd0;
        rob_id1 = Rob_tail; rob_id2 = Rob_tail + 5'd1; rob_id3 = Rob_tail + 5'd2;
        al_rs1_0 = 0; al_rs1_1 = 0; al_rs1_2 = 0; al_rs2_0 = 0; al_rs2_1 = 0; al_rs2_2 = 0;
        al_escreve0 = 0; al_escreve1 = 0; al_escreve2 = 0;
        al_alu0 = 0; al_alu1 = 0; al_alu2 = 0;
        al_desvio0 = 0; al_desvio1 = 0; al_desvio2 = 0;
        funct3_1 = 3'b010; funct3_2 = 3'b010; funct3_3 = 3'b010;  //IVAN FEATURE

        //O k-ésimo válido usa o slot k e o rob_id Rob_tail + k
        k_aloc = 2'd0;
        if (accept_in) begin
            for (j = 0; j < 3; j = j + 1) begin
                if (mei_valid[j]) begin
                    case (k_aloc)
                        2'd0: begin
                            v[0] = 1'b1; dst1 = e_dst[j]; rd1 = e_rd[j];
                            al_rs1_0 = e_rs1[j]; al_rs2_0 = e_rs2[j];
                            al_escreve0 = (e_dst[j] == DST_REG || e_dst[j] == DST_LOAD) && e_rd[j] != 5'd0;
                            al_alu0 = (e_dst[j] == DST_REG); al_desvio0 = e_desv[j];
                            funct3_1 = e_f3[j];  //IVAN FEATURE
                        end
                        2'd1: begin
                            v[1] = 1'b1; dst2 = e_dst[j]; rd2 = e_rd[j];
                            al_rs1_1 = e_rs1[j]; al_rs2_1 = e_rs2[j];
                            al_escreve1 = (e_dst[j] == DST_REG || e_dst[j] == DST_LOAD) && e_rd[j] != 5'd0;
                            al_alu1 = (e_dst[j] == DST_REG); al_desvio1 = e_desv[j];
                            funct3_2 = e_f3[j];  //IVAN FEATURE
                        end
                        default: begin
                            v[2] = 1'b1; dst3 = e_dst[j]; rd3 = e_rd[j];
                            al_rs1_2 = e_rs1[j]; al_rs2_2 = e_rs2[j];
                            al_escreve2 = (e_dst[j] == DST_REG || e_dst[j] == DST_LOAD) && e_rd[j] != 5'd0;
                            al_alu2 = (e_dst[j] == DST_REG); al_desvio2 = e_desv[j];
                            funct3_3 = e_f3[j];  //IVAN FEATURE
                        end
                    endcase
                    k_aloc = k_aloc + 2'd1;
                end
            end
        end
    end

    //------------------------------------------------------------------
    //Seleção fora de ordem
    //------------------------------------------------------------------
    reg        s1_ok, s2_ok, s3_ok;    //caminho recebeu instrução neste ciclo
    reg [3:0]  s1_pos, s2_pos, s3_pos; //posição escolhida para cada caminho
    reg        mem_bloq, desv_bloq, barreira, antiga_esperando;
    reg [3:0]  pos;
    reg [4:0]  rob_i;
    reg        pr, escolhida;
    reg [1:0]  n_out;
    reg [1:0]  n_fora;                 //quantas das escolhidas passaram na frente de alguém
    reg        alguma_viva, alguma_pronta, fim_na_frente;
    integer    i;

    always @* begin
        s1_ok = 0; s2_ok = 0; s3_ok = 0;
        s1_pos = 0; s2_pos = 0; s3_pos = 0;
        mem_bloq = 0; desv_bloq = 0; barreira = 0; antiga_esperando = 0;
        n_out = 0; n_fora = 0;
        alguma_viva = 0; alguma_pronta = 0; fim_na_frente = 0;

        for (i = 0; i < 16; i = i + 1) begin
            pos = head[3:0] + i[3:0];
            if (i < count && vivo[pos] && !barreira) begin
                rob_i = q_rob[pos*5 +: 5];
                if (!alguma_viva && q_par[pos]) fim_na_frente = 1'b1;
                alguma_viva = 1'b1;
                pr = pronto[rob_i] && !flush_ok;
                if (pr && !q_par[pos]) alguma_pronta = 1'b1;
                escolhida = 1'b0;

                if (q_par[pos]) begin
                    //Parada: nada mais novo sai
                    barreira = 1'b1;
                end else if (q_desv[pos]) begin
                    //Desvio: caminho 3, em ordem entre desvios
                    if (!desv_bloq && pr && !s3_ok && path3_ready) begin
                        s3_ok = 1'b1; s3_pos = pos; escolhida = 1'b1;
                    end else
                        desv_bloq = 1'b1;
                end else begin
                    //Comum: caminho 1 ou 2; memória em ordem entre loads e stores
                    if (pr && !(q_mem[pos] && mem_bloq)) begin
                        if (!s1_ok && path1_ready) begin
                            s1_ok = 1'b1; s1_pos = pos; escolhida = 1'b1;
                        end else if (!s2_ok && path2_ready) begin
                            s2_ok = 1'b1; s2_pos = pos; escolhida = 1'b1;
                        end
                    end
                    if (q_mem[pos] && !escolhida) mem_bloq = 1'b1;
                end

                if (escolhida) begin
                    n_out = n_out + 2'd1;
                    if (antiga_esperando) n_fora = n_fora + 2'd1;
                end else
                    antiga_esperando = 1'b1;
            end
        end
    end

    //------------------------------------------------------------------
    //Saídas para os caminhos
    //------------------------------------------------------------------
    wire [102:0] e1 = buffer[s1_pos];   //s*_pos já são índices de 4 bits
    wire [102:0] e2 = buffer[s2_pos];
    wire [102:0] e3 = buffer[s3_pos];

    wire [2:0] d1_dst, d2_dst;
    wire [4:0] d1_rs1, d1_rs2, d2_rs1, d2_rs2, d3_rs1, d3_rs2;

    decoder decS1 (.instr(e1[31:0]), .instr_valid(), .parada(), .ilegal(), .desvio(),
        .dst(d1_dst), .rs1(d1_rs1), .rs2(d1_rs2), .rd(), .alu_op(path1_alu_op), .mem_funct3(), .imm(path1_imm));
    decoder decS2 (.instr(e2[31:0]), .instr_valid(), .parada(), .ilegal(), .desvio(),
        .dst(d2_dst), .rs1(d2_rs1), .rs2(d2_rs2), .rd(), .alu_op(path2_alu_op), .mem_funct3(), .imm(path2_imm));
    decoder decS3 (.instr(e3[31:0]), .instr_valid(), .parada(), .ilegal(), .desvio(),
        .dst(), .rs1(d3_rs1), .rs2(d3_rs2), .rd(), .alu_op(), .mem_funct3(), .imm(path3_imm));

    always @* begin
        path1_valid = s1_ok;
        path1_instr = s1_ok ? e1[31:0] : 32'd0;  path1_ordem = e1[63:32];  path1_pc = e1[73:64];
        path1_rob_id = e1[78:74];  path1_previu = e1[79];  path1_alvo = e1[89:80];
        path1_sb_tail = e1[94:90]; path1_lb_tail = e1[99:95];
        path1_rs1_addr = s1_ok ? d1_rs1 : 5'd0;  path1_rs2_addr = s1_ok ? d1_rs2 : 5'd0;

        path2_valid = s2_ok;
        path2_instr = s2_ok ? e2[31:0] : 32'd0;  path2_ordem = e2[63:32];  path2_pc = e2[73:64];
        path2_rob_id = e2[78:74];  path2_previu = e2[79];  path2_alvo = e2[89:80];
        path2_sb_tail = e2[94:90]; path2_lb_tail = e2[99:95];
        path2_rs1_addr = s2_ok ? d2_rs1 : 5'd0;  path2_rs2_addr = s2_ok ? d2_rs2 : 5'd0;

        path3_valid = s3_ok;
        path3_instr = s3_ok ? e3[31:0] : 32'd0;  path3_ordem = e3[63:32];  path3_pc = e3[73:64];
        path3_rob_id = e3[78:74];  path3_previu = e3[79];  path3_alvo = e3[89:80];
        path3_sb_tail = e3[94:90]; path3_lb_tail = e3[99:95];
        path3_rs1_addr = s3_ok ? d3_rs1 : 5'd0;  path3_rs2_addr = s3_ok ? d3_rs2 : 5'd0;

        //Dado do store vai ao Store Buffer pelo rob_id
        store1_valid = s1_ok && (d1_dst == DST_STORE);
        store1_rob_id = e1[78:74];  store1_dado = path1_rs2_data;
        store2_valid = s2_ok && (d2_dst == DST_STORE);
        store2_rob_id = e2[78:74];  store2_dado = path2_rs2_data;
    end

    //------------------------------------------------------------------
    //Descarte: primeira posição mais nova que B (as seguintes também são)
    //------------------------------------------------------------------
    wire [4:0] dist_B = flush_rob_id - rob_head;
    reg  [4:0] dist_p;
    reg  [4:0] pos_corte;
    reg        achou_corte;
    reg  [3:0] pos_f;
    integer    f;

    always @* begin
        achou_corte = 1'b0;
        pos_corte = tail;
        for (f = 0; f < 16; f = f + 1) begin
            pos_f = head[3:0] + f[3:0];
            dist_p = q_rob[pos_f*5 +: 5] - rob_head;
            if (f < count && !achou_corte && dist_p > dist_B) begin
                achou_corte = 1'b1;
                pos_corte = head + f[4:0];
            end
        end
    end

    //------------------------------------------------------------------
    //Atualização da fila
    //------------------------------------------------------------------
    reg [15:0] vivo_n;
    reg [4:0]  head_n, tail_n, w;
    reg [4:0]  sb_corte, lb_corte;
    reg        parou;
    reg [102:0] nova;
    reg [4:0]  n_rem;
    integer    q;

    always @(posedge clk) begin
        if (rst) begin
            head <= 5'd0; tail <= 5'd0; vivo <= 16'd0;
            q_par <= 16'd0; q_desv <= 16'd0; q_mem <= 16'd0; q_rob <= 80'd0;
            for (q = 0; q < 16; q = q + 1) buffer[q] <= 103'd0;
        end else begin
            vivo_n = vivo;
            tail_n = tail;

            //Enviadas viram buracos
            if (s1_ok) vivo_n[s1_pos] = 1'b0;
            if (s2_ok) vivo_n[s2_pos] = 1'b0;
            if (s3_ok) vivo_n[s3_pos] = 1'b0;

            if (flush_ok) begin
                //Remove as mais novas que B
                if (achou_corte) begin
                    tail_n = pos_corte;
                    //Posições removidas: de pos_corte até o fim da fila
                    n_rem = tail - pos_corte;
                    for (q = 0; q < 16; q = q + 1)
                        if (q < n_rem) vivo_n[pos_corte[3:0] + q[3:0]] = 1'b0;
                end
            end else if (accept_in) begin
                //Entrada em ordem; loads e stores desta entrada ficam antes do corte das seguintes
                w = tail;
                sb_corte = sb_tail;
                lb_corte = lb_tail;
                for (q = 0; q < 3; q = q + 1) begin
                    if (mei_valid[q]) begin
                        case (q)
                            0: nova = {e_par[0], e_desv[0], (e_dst[0] == DST_LOAD || e_dst[0] == DST_STORE),
                                       lb_corte, sb_corte, mei_alvo0, mei_previu0, Rob_tail + (w - tail),
                                       mei_pc0, mei_ordem0, mei_instr0};
                            1: nova = {e_par[1], e_desv[1], (e_dst[1] == DST_LOAD || e_dst[1] == DST_STORE),
                                       lb_corte, sb_corte, mei_alvo1, mei_previu1, Rob_tail + (w - tail),
                                       mei_pc1, mei_ordem1, mei_instr1};
                            default: nova = {e_par[2], e_desv[2], (e_dst[2] == DST_LOAD || e_dst[2] == DST_STORE),
                                       lb_corte, sb_corte, mei_alvo2, mei_previu2, Rob_tail + (w - tail),
                                       mei_pc2, mei_ordem2, mei_instr2};
                        endcase
                        buffer[w[3:0]] <= nova;
                        q_par[w[3:0]]  <= nova[102];
                        q_desv[w[3:0]] <= nova[101];
                        q_mem[w[3:0]]  <= nova[100];
                        q_rob[w[3:0]*5 +: 5] <= nova[78:74];
                        vivo_n[w[3:0]] = 1'b1;
                        if (nova[100] && e_dst[q] == DST_STORE) sb_corte = sb_corte + 5'd1;
                        if (nova[100] && e_dst[q] == DST_LOAD)  lb_corte = lb_corte + 5'd1;
                        w = w + 5'd1;
                    end
                end
                tail_n = w;
            end

            //O head avança sobre os buracos da frente
            head_n = head;
            parou = 1'b0;
            for (q = 0; q < 16; q = q + 1) begin
                if (!parou && head_n != tail_n && !vivo_n[head_n[3:0]]) head_n = head_n + 5'd1;
                else parou = 1'b1;
            end
            head  <= head_n;
            tail  <= tail_n;
            vivo  <= vivo_n;
        end
    end

    //------------------------------------------------------------------
    //Contadores de desempenho (só leitura pelos testbenches, sem portas)
    //  ciclos            -> ciclos desde o reset
    //  enviadas          -> instruções enviadas aos caminhos
    //  fora_de_ordem     -> enviadas passando na frente de uma mais antiga que esperava
    //  envio_1/2/3       -> ciclos em que saíram 1, 2 ou 3 instruções
    //  parado_vazia      -> nada saiu: fila sem instruções a enviar
    //  parado_operandos  -> nada saiu: nenhuma instrução com operandos prontos
    //  parado_estrutura  -> nada saiu: havia pronta, mas caminho ocupado ou ordem a respeitar
    //  parado_descarte   -> ciclo de descarte
    //  parado_fim        -> nada saiu: a mais antiga é uma parada (fim do programa)
    //  entrada_bloqueada -> havia grupo da MEI e ele não entrou (fila, ROB, buffers cheios
    //                       ou falta de cópia para desvio), sem contar depois do fim do programa
    //  sem_copia         -> ciclos em que o grupo não entrou por falta de cópia para desvio
    //------------------------------------------------------------------
    reg [31:0] cnt_ciclos, cnt_enviadas, cnt_fora_de_ordem;
    reg [31:0] cnt_envio_1, cnt_envio_2, cnt_envio_3;
    reg [31:0] cnt_parado_vazia, cnt_parado_operandos, cnt_parado_estrutura;
    reg [31:0] cnt_parado_descarte, cnt_parado_fim, cnt_entrada_bloqueada, cnt_sem_copia;

    always @(posedge clk) begin
        if (rst) begin
            cnt_ciclos <= 0; cnt_enviadas <= 0; cnt_fora_de_ordem <= 0;
            cnt_envio_1 <= 0; cnt_envio_2 <= 0; cnt_envio_3 <= 0;
            cnt_parado_vazia <= 0; cnt_parado_operandos <= 0; cnt_parado_estrutura <= 0;
            cnt_parado_descarte <= 0; cnt_parado_fim <= 0; cnt_entrada_bloqueada <= 0; cnt_sem_copia <= 0;
        end else begin
            cnt_ciclos        <= cnt_ciclos + 1;
            cnt_enviadas      <= cnt_enviadas + n_out;
            cnt_fora_de_ordem <= cnt_fora_de_ordem + n_fora;
            if (n_out == 2'd1) cnt_envio_1 <= cnt_envio_1 + 1;
            if (n_out == 2'd2) cnt_envio_2 <= cnt_envio_2 + 1;
            if (n_out == 2'd3) cnt_envio_3 <= cnt_envio_3 + 1;
            if (n_out == 2'd0) begin
                if (flush_ok)            cnt_parado_descarte  <= cnt_parado_descarte + 1;
                else if (!alguma_viva)   cnt_parado_vazia     <= cnt_parado_vazia + 1;
                else if (fim_na_frente)  cnt_parado_fim       <= cnt_parado_fim + 1;
                else if (!alguma_pronta) cnt_parado_operandos <= cnt_parado_operandos + 1;
                else                     cnt_parado_estrutura <= cnt_parado_estrutura + 1;
            end
            if (mei_valid != 3'b000 && !accept_in && !flush_ok && !fim_na_frente)
                cnt_entrada_bloqueada <= cnt_entrada_bloqueada + 1;
            if (mei_valid != 3'b000 && !flush_ok && ({1'b0, n_desv_in} > ck_livres))
                cnt_sem_copia <= cnt_sem_copia + 1;
        end
    end

endmodule

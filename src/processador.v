// Topo com o despacho fora de ordem, a nova unidade de hazard/forwarding, o caminho de
// desvio (caminho 3) e a recuperação de desvio ligada em todas as unidades (PEDRO).
//
// Busca sem bolha: a MEI recebe o próximo PC (pc_prox) em vez do atual. Como a MEI é
// registrada, a saída dela passa a corresponder sempre ao PC do ciclo, e o grupo fica
// válido em todo ciclo: até 3 instruções por ciclo, em vez de 3 a cada 2.
// No descarte, pc_prox já é o alvo do desvio, então o grupo certo chega no ciclo seguinte.
module processador (input clk, input rst);

    // ---- pc e controle da busca ----
    reg  [9:0] pc;
    reg        grupo_valido;
    wire       flush_ok;
    wire [9:0] alvo_desvio;
    wire       pc_advence;      // vem do despacho
    wire [9:0] pc_prox = rst ? 10'd0 : flush_ok ? alvo_desvio : pc_advence ? pc + 10'd12 : pc;

    always @(posedge clk) begin
        if (rst) begin
            pc           <= 0;
            grupo_valido <= 0;
        end else if (flush_ok) begin
            pc           <= alvo_desvio;          // redireciona a busca
            grupo_valido <= 1;
        end else if (pc_advence) begin
            pc           <= pc + 12;
            grupo_valido <= 1;
        end else begin
            grupo_valido <= 1;               // a MEI já leu o grupo do pc atual
        end
    end

    wire [63:0] mei_saida0;
    wire [63:0] mei_saida1;
    wire [63:0] mei_saida2;

    //IVAN FEATURE: PC de cada slot (vem da MEI, junto com a instrução) e previsão
    //de desvio (fora da MEI). Sem BTB ligado, a previsão é sempre "não pula": a
    //integração troca estes fios pelas saídas do BTB, consultado com mei_pc0.
    wire [9:0] mei_pc0, mei_pc1, mei_pc2;
    wire       mei_previu0 = 1'b0, mei_previu1 = 1'b0, mei_previu2 = 1'b0;
    wire [9:0] mei_alvo0 = 10'd0, mei_alvo1 = 10'd0, mei_alvo2 = 10'd0;

    MEI mei (
        .clk(clk),
        .rst(rst),
        .pc(pc_prox),
        .saida0(mei_saida0),
        .saida1(mei_saida1),
        .saida2(mei_saida2),
        .pc0(mei_pc0), .pc1(mei_pc1), .pc2(mei_pc2)   //IVAN FEATURE
    );

    // ---- fios entre despacho, banco e caminhos ----
    wire        p1_valid, p2_valid;          // despacho → caminho: "tem instrução"
    wire [31:0] p1_instr, p2_instr;          // despacho → caminho: a instrução
    wire [4:0]  p1_rs1, p1_rs2;              // despacho → banco: números dos registradores
    wire [4:0]  p2_rs1, p2_rs2;
    wire [31:0] p1_rs1_val, p1_rs2_val;      // banco → caminho e despacho: valores lidos
    wire [31:0] p2_rs1_val, p2_rs2_val;
    wire        p1_ready, p2_ready;          // caminho → despacho: "estou livre"
    wire [9:0]  p1_pc, p2_pc;                // despacho → caminho: PC da instrução (AUIPC)
    wire [4:0]  rob_id1, rob_id2;            // despacho → caminho: posição no ROB

    // saídas dos caminhos
    wire        wb1, wb2;                    // "terminei"
    wire [4:0]  rid1, rid2;                  // qual rob_id terminou
    wire [31:0] r1, r2;                      // o resultado

    // ---- despacho → ROB: o que foi reservado ----
    wire [2:0] disp_v;                           // quais posições são válidas
    wire [2:0] disp_dst1, disp_dst2, disp_dst3;  // tipo: 000 ALU, 010 load, 100 store
    wire [4:0] disp_rd1,  disp_rd2,  disp_rd3;   // registrador destino

    // ---- ROB → despacho ----
    wire       rob_stop;                         // ROB cheio
    wire [4:0] rob_tail;                         // próxima posição livre

    // ---- commit: ROB → banco ----
    wire [2:0]  commit_dst1, commit_dst2, commit_dst3;
    wire [4:0]  commit_rd1,  commit_rd2,  commit_rd3;
    wire [31:0] commit_r1,   commit_r2,   commit_r3;

    wire [4:0]  rob_id3;
    wire [31:0] disp_dado1, disp_dado2, disp_dado3;
    wire [4:0]  commit_rob_id1, commit_rob_id2, commit_rob_id3;
    wire        sb_mem_req, sb_stop;
    wire [31:0] sb_mem_addr, sb_mem_dado;
    wire [31:0] med_saida;
    wire [2:0]  cv_store;
    wire [4:0]  sb_tail, lb_q_idade;
    wire        sb_q_espera, sb_q_hit;
    wire [31:0] sb_q_dado;

    wire [4:0]  lrid, lb_rid;
    wire        lready, lb_done, lb_mem_req, lb_stop;
    wire [31:0] laddr;
    wire [31:0] lb_dado1, lb_dado2, lb_dado3;
    reg         lb_mem_done;
    reg  [31:0] lb_mem_data;
    wire [2:0]  cv_load;
    wire        load_grant;
    wire [31:0] wdado1, wdado2, wdado3;

    //IVAN FEATURE: Alocação na entrada da fila e envio com o rob_id reservado
    wire [4:0]  p1_rob_id, p2_rob_id;            // despacho → caminho: rob_id reservado na alocação
    wire [4:0]  lb_tail;                         // load buffer → despacho: ponto de corte
    wire        disp_st1_valid, disp_st2_valid;  // despacho → store buffer: dado do Store no envio
    wire [4:0]  disp_st1_rob_id, disp_st2_rob_id;
    wire [31:0] disp_st1_dado, disp_st2_dado;

    //IVAN FEATURE: Tamanho dos acessos à memória (funct3)
    wire [2:0]  disp_f3_1, disp_f3_2, disp_f3_3;    // despacho → buffers: funct3 na alocação
    wire [2:0]  lb_q_funct3;                         // load buffer → store buffer: consulta
    wire [2:0]  lb_mem_funct3, sb_mem_funct3;        // buffers → MED

    //Hazard e forwarding
    wire [4:0]  h_rs1_0, h_rs2_0, h_rs1_1, h_rs2_1;   //despacho -> hazard: o que as instruções da frente leem
    wire [4:0]  h_rd0, h_rd1;                         //e o que escrevem
    wire        h_escreve0, h_escreve1, h_alu0, h_alu1;
    wire        hazard0, hazard1;                     //hazard -> despacho: segura ou não
    wire [31:0] banco_p1_rs1, banco_p1_rs2;           //valor lido no banco (pode estar velho)
    wire [31:0] banco_p2_rs1, banco_p2_rs2;
    wire [31:0] lb_dado_pronto;                       //dado do load que acabou de ficar pronto

    // ---- despacho ----
    wire [4:0] al_rs1_0, al_rs1_1, al_rs1_2, al_rs2_0, al_rs2_1, al_rs2_2;
    wire al_esc0, al_esc1, al_esc2, al_alu0, al_alu1, al_alu2, al_desv0, al_desv1, al_desv2;
    wire [31:0] pronto;
    wire [2:0]  ck_livres;
    wire        p3_valid, p3_ready, p3_previu;
    wire [31:0] p3_instr, p3_rs1_val, p3_rs2_val;
    wire [9:0]  p3_pc, p3_alvo;
    wire [4:0]  p3_rs1, p3_rs2, p3_rob_id;
    wire [31:0] banco_p3_rs1, banco_p3_rs2;
    wire        wb3; wire [4:0] rid3; wire [31:0] r3;
    wire        d_errou, d_tomado;   //IVAN FEATURE: sem d_resolvido (igual ao wb3)
    wire [4:0]  rob_head;

    despacho desp (
        .clk(clk), .rst(rst),
        .mei_valid({3{grupo_valido}}),
        .mei_instr0(mei_saida0[31:0]), .mei_instr1(mei_saida1[31:0]), .mei_instr2(mei_saida2[31:0]),
        .mei_ordem0(mei_saida0[63:32]), .mei_ordem1(mei_saida1[63:32]), .mei_ordem2(mei_saida2[63:32]),
        .mei_pc0(mei_pc0), .mei_pc1(mei_pc1), .mei_pc2(mei_pc2),
        .mei_previu0(mei_previu0), .mei_previu1(mei_previu1), .mei_previu2(mei_previu2),
        .mei_alvo0(mei_alvo0), .mei_alvo1(mei_alvo1), .mei_alvo2(mei_alvo2),
        .mei_stop(), .pc_advence(pc_advence), .ocupacao(),
        .stop(rob_stop), .Rob_tail(rob_tail),
        .load_buffer_stop(lb_stop), .store_buffer_stop(sb_stop),
        .sb_tail(sb_tail), .lb_tail(lb_tail),
        .v(disp_v), .dst1(disp_dst1), .dst2(disp_dst2), .dst3(disp_dst3),
        .rd1(disp_rd1), .rd2(disp_rd2), .rd3(disp_rd3),
        .rob_id1(rob_id1), .rob_id2(rob_id2), .rob_id3(rob_id3),
        .dado1(disp_dado1), .dado2(disp_dado2), .dado3(disp_dado3),
        .funct3_1(disp_f3_1), .funct3_2(disp_f3_2), .funct3_3(disp_f3_3),  //IVAN FEATURE
        .al_rs1_0(al_rs1_0), .al_rs1_1(al_rs1_1), .al_rs1_2(al_rs1_2),
        .al_rs2_0(al_rs2_0), .al_rs2_1(al_rs2_1), .al_rs2_2(al_rs2_2),
        .al_escreve0(al_esc0), .al_escreve1(al_esc1), .al_escreve2(al_esc2),
        .al_alu0(al_alu0), .al_alu1(al_alu1), .al_alu2(al_alu2),
        .al_desvio0(al_desv0), .al_desvio1(al_desv1), .al_desvio2(al_desv2),
        .pronto(pronto), .ck_livres(ck_livres),
        .flush_ok(flush_ok), .flush_rob_id(rid3), .rob_head(rob_head),
        .path1_ready(p1_ready), .path2_ready(p2_ready),
        .path1_valid(p1_valid), .path2_valid(p2_valid),
        .path1_instr(p1_instr), .path2_instr(p2_instr),
        .path1_ordem(), .path2_ordem(), .path1_pc(p1_pc), .path2_pc(p2_pc),
        .path1_rs1_addr(p1_rs1), .path1_rs2_addr(p1_rs2),
        .path2_rs1_addr(p2_rs1), .path2_rs2_addr(p2_rs2),
        .path1_rob_id(p1_rob_id), .path2_rob_id(p2_rob_id),
        .path1_previu(), .path2_previu(), .path1_alvo(), .path2_alvo(),
        .path1_sb_tail(), .path2_sb_tail(), .path1_lb_tail(), .path2_lb_tail(),
        .path1_alu_op(), .path2_alu_op(), .path1_imm(), .path2_imm(),
        .path1_rs1_data(p1_rs1_val), .path1_rs2_data(p1_rs2_val),
        .path2_rs1_data(p2_rs1_val), .path2_rs2_data(p2_rs2_val),
        .store1_valid(disp_st1_valid), .store2_valid(disp_st2_valid),
        .store1_rob_id(disp_st1_rob_id), .store2_rob_id(disp_st2_rob_id),
        .store1_dado(disp_st1_dado), .store2_dado(disp_st2_dado),
        .path3_ready(p3_ready), .path3_valid(p3_valid), .path3_instr(p3_instr),
        .path3_ordem(), .path3_pc(p3_pc), .path3_rs1_addr(p3_rs1), .path3_rs2_addr(p3_rs2),
        .path3_rob_id(p3_rob_id), .path3_previu(p3_previu), .path3_alvo(p3_alvo),
        .path3_sb_tail(), .path3_lb_tail(), .path3_imm()
    );

    // ---- decide quais commits escrevem no banco ----
    wire [2:0] we_banco;
    assign cv_load[0] = (commit_dst1 == 3'b010);
    assign cv_load[1] = (commit_dst2 == 3'b010);
    assign cv_load[2] = (commit_dst3 == 3'b010);

    assign we_banco[0] = (commit_dst1 == 3'b000) | cv_load[0];
    assign we_banco[1] = (commit_dst2 == 3'b000) | cv_load[1];
    assign we_banco[2] = (commit_dst3 == 3'b000) | cv_load[2];

    assign wdado1 = cv_load[0] ? lb_dado1 : commit_r1;
    assign wdado2 = cv_load[1] ? (cv_load[0] ? lb_dado2 : lb_dado1) : commit_r2;
    assign wdado3 = cv_load[2] ? ((cv_load[0] & cv_load[1]) ? lb_dado3 :
                                  (cv_load[0] | cv_load[1]) ? lb_dado2 : lb_dado1) : commit_r3;

    assign cv_store[0] = (commit_dst1 == 3'b100);
    assign cv_store[1] = (commit_dst2 == 3'b100);
    assign cv_store[2] = (commit_dst3 == 3'b100);

    // ---- hazard e forwarding ----
    //O load termina de dois jeitos: lendo a memória (lb_mem_done = 1) ou pegando o dado
    //direto do store buffer (forwarding de store). Aqui escolhe qual dos dois chegou.
    assign lb_dado_pronto = lb_mem_done ? lb_mem_data : sb_q_dado;

    //O banco agora entrega os valores para o hazard_forwarding (banco_p*), e é ele que
    //entrega o valor certo para os caminhos e o despacho (p1_rs1_val etc.)
    hazard_forwarding hz (
        .clk(clk), .rst(rst),
        .al_v(disp_v), .al_rob0(rob_id1), .al_rob1(rob_id2), .al_rob2(rob_id3),
        .al_rs1_0(al_rs1_0), .al_rs1_1(al_rs1_1), .al_rs1_2(al_rs1_2),
        .al_rs2_0(al_rs2_0), .al_rs2_1(al_rs2_1), .al_rs2_2(al_rs2_2),
        .al_rd0(disp_rd1), .al_rd1(disp_rd2), .al_rd2(disp_rd3),
        .al_escreve0(al_esc0), .al_escreve1(al_esc1), .al_escreve2(al_esc2),
        .al_alu0(al_alu0), .al_alu1(al_alu1), .al_alu2(al_alu2),
        .al_desvio0(al_desv0), .al_desvio1(al_desv1), .al_desvio2(al_desv2),
        .pronto(pronto), .ck_livres(ck_livres),
        .wb1(wb1), .wb2(wb2), .wb3(wb3), .rid1(rid1), .rid2(rid2), .rid3(rid3),
        .r1(r1), .r2(r2), .r3(r3),
        .lb_done(lb_done), .lb_rid(lb_rid), .lb_dado(lb_dado_pronto),
        .we(we_banco),
        .crd1(commit_rd1), .crd2(commit_rd2), .crd3(commit_rd3),
        .crob_id1(commit_rob_id1), .crob_id2(commit_rob_id2), .crob_id3(commit_rob_id3),
        .flush_ok(flush_ok), .flush_rob_id(rid3),
        .p1_rob(p1_rob_id), .p2_rob(p2_rob_id), .p3_rob(p3_rob_id),
        .banco_p1_rs1(banco_p1_rs1), .banco_p1_rs2(banco_p1_rs2),
        .banco_p2_rs1(banco_p2_rs1), .banco_p2_rs2(banco_p2_rs2),
        .banco_p3_rs1(banco_p3_rs1), .banco_p3_rs2(banco_p3_rs2),
        .p1_rs1_val(p1_rs1_val), .p1_rs2_val(p1_rs2_val),
        .p2_rs1_val(p2_rs1_val), .p2_rs2_val(p2_rs2_val),
        .p3_rs1_val(p3_rs1_val), .p3_rs2_val(p3_rs2_val)
    );

    // ---- banco de registradores ----
    banco_registradores banco (
        .clk(clk), .rst(rst),

        // leitura: os números vêm do despacho, os valores vão para os caminhos
        .rs1_1(p1_rs1),     .rs2_1(p1_rs2),
        .rs1_2(p2_rs1),     .rs2_2(p2_rs2),
        .rs1_3(p3_rs1),     .rs2_3(p3_rs2),
        .valor_rs1_1(banco_p1_rs1), .valor_rs2_1(banco_p1_rs2),
        .valor_rs1_2(banco_p2_rs1), .valor_rs2_2(banco_p2_rs2),
        .valor_rs1_3(banco_p3_rs1), .valor_rs2_3(banco_p3_rs2),

        .we(we_banco),
        .rd1(commit_rd1),   .rd2(commit_rd2),   .rd3(commit_rd3),
        .dado1(wdado1),     .dado2(wdado2),     .dado3(wdado3)
    );

    // ---- caminhos de execução ----
    caminho caminho1 (
        .clk(clk), .rst(rst),
        .valido(p1_valid),
        .instr(p1_instr),
        .valor_rs1(p1_rs1_val), .valor_rs2(p1_rs2_val),
        .rob_id(p1_rob_id),     //IVAN FEATURE: rob_id do envio, não da alocação
        .pc(p1_pc),             //PEDRO: PC da instrução, para o AUIPC
        .ready(p1_ready),
        .wb(wb1), .rid(rid1), .r(r1)
    );

    caminho caminho2 (
        .clk(clk), .rst(rst),
        .valido(p2_valid),
        .instr(p2_instr),
        .valor_rs1(p2_rs1_val), .valor_rs2(p2_rs2_val),
        .rob_id(p2_rob_id),     //IVAN FEATURE: rob_id do envio, não da alocação
        .pc(p2_pc),             //PEDRO: PC da instrução, para o AUIPC
        .ready(p2_ready),
        .wb(wb2), .rid(rid2), .r(r2)
    );

    caminho_desvio caminho3 (
        .clk(clk), .rst(rst),
        .valido(p3_valid), .instr(p3_instr), .pc(p3_pc),
        .valor_rs1(p3_rs1_val), .valor_rs2(p3_rs2_val),
        .rob_id(p3_rob_id), .previu(p3_previu), .alvo_previsto(p3_alvo),
        .ready(p3_ready),
        .wb(wb3), .rid(rid3), .r(r3),
        .tomado(d_tomado), .alvo(alvo_desvio), .errou(d_errou)
    );

    // ---- ROB ----
    rob rob_u (
        .clk(clk), .rst(rst),

        // reserva, vinda do despacho
        .v(disp_v),
        .dst1(disp_dst1), .dst2(disp_dst2), .dst3(disp_dst3),
        .rd1(disp_rd1),   .rd2(disp_rd2),   .rd3(disp_rd3),

        // resultados, vindos dos caminhos
        .wb({wb3, wb2, wb1}),
        .rid1(rid1), .rid2(rid2), .rid3(rid3),
        .r1(r1),     .r2(r2),     .r3(r3),

        // commit, para o banco
        .cdst1(commit_dst1), .cdst2(commit_dst2), .cdst3(commit_dst3),
        .crid1(commit_rd1),  .crid2(commit_rd2),  .crid3(commit_rd3),
        .cr1(commit_r1),     .cr2(commit_r2),     .cr3(commit_r3),
        .crob_id1(commit_rob_id1), .crob_id2(commit_rob_id2), .crob_id3(commit_rob_id3),

        // loads e stores
        .lrid(lrid), .lready(lready), .laddr(laddr),
        .lb_done(lb_done), .lb_rid(lb_rid),

        // para o despacho
        .stop(rob_stop),
        .rob_tail(rob_tail),

        // recuperação de desvio: o errou do caminho 3 dispara o flush
        .flush(d_errou), .flush_rob_id(rid3), .flush_ok(flush_ok), .rob_head(rob_head)
    );

    store_buffer sbuf (
        .clk(clk), .rst(rst),
        .v(disp_v),
        .dst1(disp_dst1), .dst2(disp_dst2), .dst3(disp_dst3),
        .rob_id1(rob_id1), .rob_id2(rob_id2), .rob_id3(rob_id3),
        // endereços, vindos dos caminhos
        .wb({1'b0, wb2, wb1}),
        .rid1(rid1), .rid2(rid2), .rid3(5'd0),
        .r1(r1),     .r2(r2),     .r3(32'd0),
        //IVAN FEATURE: dado do Store, vindo do envio
        .store1_valid(disp_st1_valid),   .store2_valid(disp_st2_valid),
        .store1_rob_id(disp_st1_rob_id), .store2_rob_id(disp_st2_rob_id),
        .store1_dado(disp_st1_dado),     .store2_dado(disp_st2_dado),
        .cv(cv_store),
        // consulta do load buffer
        .sb_tail(sb_tail), .q_idade(lb_q_idade), .q_addr(laddr),
        .q_espera(sb_q_espera), .q_hit(sb_q_hit), .q_dado(sb_q_dado),
        .mem_req(sb_mem_req), .mem_addr(sb_mem_addr), .mem_dado(sb_mem_dado),
        .stop(sb_stop),

        // recuperação de desvio: descarta as entradas mais novas que o desvio
        .flush_ok(flush_ok), .flush_rob_id(rid3), .rob_head(rob_head),

        //IVAN FEATURE: tamanho dos acessos
        .funct3_1(disp_f3_1), .funct3_2(disp_f3_2), .funct3_3(disp_f3_3),
        .q_funct3(lb_q_funct3), .mem_funct3(sb_mem_funct3)
    );

    load_buffer lbuf (
        .clk(clk), .rst(rst),
        .v(disp_v),
        .dst1(disp_dst1), .dst2(disp_dst2), .dst3(disp_dst3),
        .rob_id1(rob_id1), .rob_id2(rob_id2), .rob_id3(rob_id3),
        .lrid(lrid), .lready(lready),
        .sb_tail(sb_tail), .q_idade(lb_q_idade),
        .q_espera(sb_q_espera), .q_hit(sb_q_hit), .q_dado(sb_q_dado),
        .mem_req(lb_mem_req), .mem_data(lb_mem_data), .mem_done(lb_mem_done),
        .lb_done(lb_done), .lb_rid(lb_rid),
        .cv(cv_load),
        .lb_dado1(lb_dado1), .lb_dado2(lb_dado2), .lb_dado3(lb_dado3),
        .stop(lb_stop),
        .lb_tail(lb_tail),  //IVAN FEATURE

        // recuperação de desvio: descarta as entradas mais novas que o desvio
        .flush_ok(flush_ok), .flush_rob_id(rid3), .rob_head(rob_head),

        //IVAN FEATURE: tamanho dos acessos
        .funct3_1(disp_f3_1), .funct3_2(disp_f3_2), .funct3_3(disp_f3_3),
        .q_funct3(lb_q_funct3), .mem_funct3(lb_mem_funct3)
    );

    assign load_grant = lb_mem_req & !sb_mem_req;

    MED med (
        .clk(clk), .rst(rst),
        .memRead(load_grant),
        .memWrite(sb_mem_req),
        .funct3(sb_mem_req ? sb_mem_funct3 : lb_mem_funct3),  //IVAN FEATURE: era 3'b010
        .ende_dado(sb_mem_req ? sb_mem_addr : laddr),
        .dado_entrada(sb_mem_dado),
        .dado_saida(med_saida)
    );

    always @(posedge clk) begin
        if (rst) begin
            lb_mem_done <= 1'b0;
            lb_mem_data <= 32'd0;
        end else begin
            lb_mem_done <= load_grant;
            if (load_grant) lb_mem_data <= med_saida;
        end
    end

endmodule

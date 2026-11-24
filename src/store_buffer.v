//==============================================================================
// Store Buffer
//
// Guarda os Stores desde a alocação até a escrita na memória, em ordem de
// programa. A memória só é escrita depois do commit, então um Store descartado
// por desvio nunca chega a ela.
//
//   - Alocação (em ordem, na entrada da fila do despacho): cada Store reserva
//     uma posição com o seu rob_id e funct3.
//   - Endereço: chega pelo wb dos caminhos, identificado pelo rob_id.
//   - Dado: chega no envio do despacho, também pelo rob_id.
//   - Commit: o ROB avisa quantos Stores foram commitados (cv), sempre em ordem.
//   - Escrita: um Store commitado por ciclo vai à MED (que sempre aceita).
//   - Consulta: o Load Buffer pergunta se um Load pode ler a memória, deve
//     esperar, ou recebe o dado direto de um Store mais antigo (forwarding).
//   - Recuperação: no flush, descarta os Stores não commitados mais novos que B.
//
// Ponteiros (5 bits: o bit extra distingue cheio de vazio; 16 posições):
//   head → próximo Store a ser escrito na memória
//   cptr → próximo Store a ser commitado
//   tail → próxima posição livre
//   [head, cptr) → commitados, esperando a escrita
//   [cptr, tail) → alocados, esperando o commit
//
// stop: mais de 13 posições ocupadas (contando os commitados ainda não escritos),
// porque até 3 Stores podem ser alocados no mesmo ciclo.
//
// PREMISSA: acessos alinhados (sh em endereço par, sw em múltiplo de 4).
//==============================================================================

module store_buffer(
    input wire clk, rst,

    //---- Alocação: despacho, até 3 instruções por ciclo ----
    input wire [2:0]  v,                           // Slots válidos
    input wire [2:0]  dst1, dst2, dst3,            // Tipo de cada slot (100 = Store)
    input wire [4:0]  rob_id1, rob_id2, rob_id3,   // Identifica o Store na captura e no flush
    input wire [2:0]  funct3_1, funct3_2, funct3_3,// Tamanho do acesso (sb, sh, sw)

    //---- Endereço: resultado dos caminhos ----
    input wire [2:0]  wb,                          // Resultado válido em cada porta
    input wire [4:0]  rid1, rid2, rid3,            // rob_id do resultado
    input wire [31:0] r1, r2, r3,                  // Resultado (endereço, no caso do Store)

    //---- Dado: envio do despacho ----
    input wire        store1_valid, store2_valid,  // Dado de um Store enviado
    input wire [4:0]  store1_rob_id, store2_rob_id,// rob_id do Store
    input wire [31:0] store1_dado, store2_dado,    // Valor de rs2

    //---- Commit: ROB ----
    input wire [2:0]  cv,                          // Quais commits do ciclo são Store

    //---- Consulta: Load Buffer ----
    output wire [4:0]  sb_tail,                    // Tail, para o Load guardar a sua idade
    input  wire [4:0]  q_idade,                    // Idade do Load (Stores antes dela são mais antigos)
    input  wire [31:0] q_addr,                     // Endereço do Load
    input  wire [2:0]  q_funct3,                   // Tamanho do Load

    output reg         q_espera,                   // O Load deve esperar: Store mais antigo sem
                                                   // endereço, sem dado ou com sobreposição parcial
    output reg         q_hit,                      // Forwarding: um Store mais antigo cobre o Load
    output reg  [31:0] q_dado,                     // Dado do forwarding, já com a extensão do Load

    //---- Memória: MED, uma escrita por ciclo ----
    output wire        mem_req,                    // Há Store commitado para escrever
    output wire [31:0] mem_addr,
    output wire [31:0] mem_dado,
    output wire [2:0]  mem_funct3,                 // Tamanho da escrita

    //---- Recuperação: aviso do ROB ----
    input  wire        flush_ok,                   // Desvio B errou e ainda está no ROB
    input  wire [4:0]  flush_rob_id,               // rob_id de B
    input  wire [4:0]  rob_head,                   // Head do ROB: referência de idade

    //---- Controle ----
    output wire        stop                        // Buffer quase cheio: o despacho para
);

    reg [31:0] dado    [0:15];
    reg [31:0] addr    [0:15];
    reg        addr_ok [0:15];
    reg [4:0]  rob_id  [0:15];
    reg        dado_ok [0:15];
    reg [2:0]  f3      [0:15];
    reg [4:0] head, cptr, tail;

    wire [4:0] tail2 = tail + 1;
    wire [4:0] tail3 = tail + 2;

    // Filtragem interna — quais slots indo pro despacho são Store
    wire is_store1 = v[0] & (dst1 == 3'b100);
    wire is_store2 = v[1] & (dst2 == 3'b100);
    wire is_store3 = v[2] & (dst3 == 3'b100);

    wire [2:0] dispatched = is_store1 + is_store2 + is_store3;

    // Commit — o ROB e o buffer estão na mesma ordem
    wire [2:0] committed = cv[0] + cv[1] + cv[2];

    assign mem_req  = (head != cptr);
    assign mem_addr = addr[head[3:0]];
    assign mem_dado = dado[head[3:0]];
    assign mem_funct3 = f3[head[3:0]];

    assign sb_tail = tail;

    // A ocupação conta também os commitados que ainda não foram escritos
    assign stop = ((tail - head) > 5'd13);

    // Consulta — os Stores mais antigos que o Load estão em [head, q_idade).
    // Percorre do mais antigo ao mais novo: um Store que coincide sobrescreve o
    // resultado dos anteriores, e um desconhecido depois dele volta a exigir espera
    wire [4:0] n_antigos = q_idade - head;
    reg  [4:0] ptr;
    integer k;

    //Acessos de tamanhos diferentes
    //Assumimos que o programa só faz acessos alinhados (lh/lhu/sh em endereço par, lw/sw em
    //múltiplo de 4).
    //Dois acessos se sobrepõem se estão na mesma palavra e as máscaras de bytes se cruzam.
    //  - Store no mesmo endereço e do mesmo tamanho do Load: cobre o Load inteiro, forwarding;
    //  - Qualquer outra sobreposição: o Load espera o Store ser escrito na memória.

    function [3:0] mascara;
        input [2:0] f;
        input [1:0] a;
        case (f[1:0])
            2'b00:   mascara = 4'b0001 << a;   //byte
            2'b01:   mascara = 4'b0011 << a;   //meia palavra
            default: mascara = 4'b1111;        //palavra
        endcase
    endfunction

    function [31:0] estende;
        input [2:0]  f;
        input [31:0] d;
        case (f)
            3'b000:  estende = {{24{d[7]}},  d[7:0]};    //lb
            3'b001:  estende = {{16{d[15]}}, d[15:0]};   //lh
            3'b100:  estende = {24'b0, d[7:0]};          //lbu
            3'b101:  estende = {16'b0, d[15:0]};         //lhu
            default: estende = d;                        //lw
        endcase
    endfunction

    wire [3:0] q_mascara = mascara(q_funct3, q_addr[1:0]);
    reg        sobrepoe, cobre;

    always @(*) begin
        q_espera = 1'b0;
        q_hit    = 1'b0;
        q_dado   = 32'b0;
        for (k = 0; k < 16; k = k + 1) begin
            ptr = head + k;

            sobrepoe = (addr[ptr[3:0]][31:2] == q_addr[31:2]) &&
                       ((mascara(f3[ptr[3:0]], addr[ptr[3:0]][1:0]) & q_mascara) != 4'b0);
            cobre    = (addr[ptr[3:0]] == q_addr) && (f3[ptr[3:0]][1:0] == q_funct3[1:0]);

            if (k < n_antigos) begin
                if (!addr_ok[ptr[3:0]]) begin
                    q_espera = 1'b1;
                end else if (sobrepoe) begin
                    //Se o Store que coincide não possui o dado ainda, ou não cobre o Load inteiro: o Load espera;
                    if (cobre && dado_ok[ptr[3:0]]) begin
                        q_hit    = 1'b1;
                        q_espera = 1'b0;
                        q_dado   = estende(q_funct3, dado[ptr[3:0]]);
                    end else begin
                        q_hit    = 1'b0;
                        q_espera = 1'b1;
                    end
                end
            end
        end
    end

    // Entradas esperando o commit, em [cptr, tail) — só elas capturam endereço e dado,
    // pois o rob_id de uma entrada já commitada pode ter sido reutilizado no ROB
    wire [4:0] n_pendentes = tail - cptr;
    reg  [4:0] off;

    //Recuperação
    //Só a região não commitada [cptr, tail) pode ter Stores mais novos que B.
    //Os commitados têm rob_id já liberado pelo ROB. Na ordem do programa, os mais
    //antigos que B formam o início da região: o novo tail é cptr + n_mantidos.
    wire [4:0] dist_B = flush_rob_id - rob_head;
    reg  [4:0] n_mantidos;
    reg  [4:0] pos_m, dist_m;
    integer m;

    always @(*) begin
        n_mantidos = 5'd0;
        for (m = 0; m < 16; m = m + 1) begin
            pos_m  = cptr + m;
            dist_m = rob_id[pos_m[3:0]] - rob_head;
            if (m < n_pendentes && dist_m < dist_B)
                n_mantidos = n_mantidos + 5'd1;
        end
    end

    wire [4:0] tail_flush = cptr + n_mantidos;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head <= 5'd0;
            cptr <= 5'd0;
            tail <= 5'd0;
            for (i = 0; i < 16; i = i + 1) begin
                dado[i]    <= 32'b0;
                addr[i]    <= 32'b0;
                addr_ok[i] <= 1'b0;
                rob_id[i]  <= 5'b0;
                dado_ok[i] <= 1'b0;
                f3[i]      <= 3'b010;
            end
        end else begin
            //No flush, o tail volta para depois do último Store mais antigo
            //que B, e as alocações do ciclo (caminho errado) são ignoradas;
            if (flush_ok)
                tail <= tail_flush;
            else
                tail <= tail + dispatched;

            //Cada Store guarda o rob_id e o funct3 na sua posição ao serem alocados; O dado chega depois, no envio;
            if (!flush_ok)
            case({is_store1, is_store2, is_store3})

                3'b001: begin
                    rob_id[tail[3:0]] <= rob_id3; f3[tail[3:0]] <= funct3_3;
                end

                3'b010: begin
                    rob_id[tail[3:0]] <= rob_id2; f3[tail[3:0]] <= funct3_2;
                end

                3'b011:  begin
                    rob_id[tail[3:0]]  <= rob_id2; f3[tail[3:0]]  <= funct3_2;
                    rob_id[tail2[3:0]] <= rob_id3; f3[tail2[3:0]] <= funct3_3;
                end

                3'b100: begin
                    rob_id[tail[3:0]] <= rob_id1; f3[tail[3:0]] <= funct3_1;
                end

                3'b101: begin
                    rob_id[tail[3:0]]  <= rob_id1; f3[tail[3:0]]  <= funct3_1;
                    rob_id[tail2[3:0]] <= rob_id3; f3[tail2[3:0]] <= funct3_3;
                end

                3'b110: begin
                    rob_id[tail[3:0]]  <= rob_id1; f3[tail[3:0]]  <= funct3_1;
                    rob_id[tail2[3:0]] <= rob_id2; f3[tail2[3:0]] <= funct3_2;
                end

                3'b111: begin
                    rob_id[tail[3:0]]  <= rob_id1; f3[tail[3:0]]  <= funct3_1;
                    rob_id[tail2[3:0]] <= rob_id2; f3[tail2[3:0]] <= funct3_2;
                    rob_id[tail3[3:0]] <= rob_id3; f3[tail3[3:0]] <= funct3_3;
                end

                default: ;
            endcase

            //Entradas alocadas começam sem endereço e sem dado
            if (dispatched >= 3'd1 && !flush_ok) begin addr_ok[tail[3:0]]  <= 1'b0; dado_ok[tail[3:0]]  <= 1'b0; end
            if (dispatched >= 3'd2 && !flush_ok) begin addr_ok[tail2[3:0]] <= 1'b0; dado_ok[tail2[3:0]] <= 1'b0; end
            if (dispatched == 3'd3 && !flush_ok) begin addr_ok[tail3[3:0]] <= 1'b0; dado_ok[tail3[3:0]] <= 1'b0; end

            // Captura do endereço calculado pelos caminhos
            for (i = 0; i < 16; i = i + 1) begin
                off = i[4:0] - cptr;
                if ({1'b0, off[3:0]} < n_pendentes) begin
                    if (wb[0] && rid1 == rob_id[i]) begin
                        addr[i] <= r1; addr_ok[i] <= 1'b1; end

                    if (wb[1] && rid2 == rob_id[i]) begin
                        addr[i] <= r2; addr_ok[i] <= 1'b1; end

                    if (wb[2] && rid3 == rob_id[i]) begin
                        addr[i] <= r3; addr_ok[i] <= 1'b1; end

                    //Captura do dado enviado pelo despacho
                    if (store1_valid && store1_rob_id == rob_id[i]) begin
                        dado[i] <= store1_dado; dado_ok[i] <= 1'b1; end

                    if (store2_valid && store2_rob_id == rob_id[i]) begin
                        dado[i] <= store2_dado; dado_ok[i] <= 1'b1; end
                end
            end

            // Commit — o endereço já foi capturado, pois o ROB só commita após o wb
            cptr <= cptr + committed;

            // Escrita na memória
            if (mem_req) head <= head + 1;
        end
    end
endmodule

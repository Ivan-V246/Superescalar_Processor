module store_buffer(
    input wire clk, rst,

    // Despacho — até 3 instruções por ciclo
    input wire [2:0]  v,                         // Quais slots são válidos
    input wire [2:0]  dst1, dst2, dst3,           // Destino de cada instrução
    input wire [4:0]  rob_id1, rob_id2, rob_id3, // Rob ids, para capturar o endereço
    input wire [31:0] dado1, dado2, dado3,        // Dados a serem escritos

    // Resultados dos caminhos — endereço dos Stores
    input wire [2:0]  wb,                        // Veio uma resolução do caminho?
    input wire [4:0]  rid1, rid2, rid3,          // Rob id das resoluções
    input wire [31:0] r1, r2, r3,                // Resultados (endereço, no caso do Store)

    //IVAN FEATURE: Dado do Store chega no envio, identificado pelo rob_id
    //(dado1..3 da alocação deixam de ser usados)
    input wire        store1_valid, store2_valid,
    input wire [4:0]  store1_rob_id, store2_rob_id,
    input wire [31:0] store1_dado, store2_dado,

    // Commit do ROB — até 3 stores por ciclo, sempre em ordem
    input wire [2:0]  cv,                        // Quais commits são Store

    // Consulta do Load Buffer
    output wire [4:0]  sb_tail,                  // Tail, para o Load Buffer calcular a idade
    input  wire [4:0]  q_idade,                  // Tail visto pelo Load no despacho
    input  wire [31:0] q_addr,                   // Endereço do Load
    output reg         q_espera,                 // Há Store mais antigo de endereço desconhecido que pode coincidir
    output reg         q_hit,                    // O Store mais novo que coincide pode entregar o dado
    output reg  [31:0] q_dado,                   // Dado desse Store (forwarding)

    // Memória — uma escrita por ciclo
    output wire        mem_req,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_dado,

    // Sinal de parada
    output wire stop,

    //IVAN FEATURE: Recuperação de desvio (aviso do ROB)
    input  wire       flush_ok,       //Desvio B errou e ainda está no ROB
    input  wire [4:0] flush_rob_id,   //rob_id de B
    input  wire [4:0] rob_head,       //Head do ROB: referência de idade

    //IVAN FEATURE: Tamanho do acesso (sb, sh, sw)
    input  wire [2:0] funct3_1, funct3_2, funct3_3,  //funct3 de cada slot na alocação
    input  wire [2:0] q_funct3,                      //funct3 do Load em consulta
    output wire [2:0] mem_funct3                     //funct3 do Store escrito na memória
);
    // Ponteiros:
    //   head → próximo Store a ser escrito na memória
    //   cptr → próximo Store a ser commitado
    //   tail → próxima posição livre
    // [head, cptr) → commitados, esperando a escrita
    // [cptr, tail) → despachados, esperando o commit
    reg [31:0] dado    [0:15];
    reg [31:0] addr    [0:15];
    reg        addr_ok [0:15];
    reg [4:0]  rob_id  [0:15];
    reg        dado_ok [0:15];   //IVAN FEATURE: dado já recebido do despacho
    reg [2:0]  f3      [0:15];   //IVAN FEATURE: funct3 de cada Store
    reg [4:0] head, cptr, tail;

    wire [4:0] tail2 = tail + 1;
    wire [4:0] tail3 = tail + 2;

    // Filtragem interna — quais slots são Store
    wire is_store1 = v[0] & (dst1 == 3'b100);
    wire is_store2 = v[1] & (dst2 == 3'b100);
    wire is_store3 = v[2] & (dst3 == 3'b100);

    wire [2:0] dispatched = is_store1 + is_store2 + is_store3;

    // Commit — o ROB e o buffer estão na mesma ordem, então o k-ésimo
    // Store commitado no ciclo é sempre cptr + k - 1
    wire [2:0] commited = cv[0] + cv[1] + cv[2];

    assign mem_req  = (head != cptr);
    assign mem_addr = addr[head[3:0]];
    assign mem_dado = dado[head[3:0]];
    assign mem_funct3 = f3[head[3:0]];   //IVAN FEATURE

    assign sb_tail = tail;

    // A ocupação conta também os commitados que ainda não foram escritos
    assign stop = ((tail - head) > 5'd13);

    // Consulta — os Stores mais antigos que o Load estão em [head, q_idade).
    // Percorre do mais antigo ao mais novo: um Store que coincide sobrescreve o
    // resultado dos anteriores, e um desconhecido depois dele volta a exigir espera
    wire [4:0] n_antigos = q_idade - head;
    reg  [4:0] ptr;
    integer k;

    //IVAN FEATURE: Acessos de tamanhos diferentes
    //PREMISSA: o programa só faz acessos alinhados (lh/lhu/sh em endereço par, lw/sw em
    //múltiplo de 4), como o RV32I permite exigir. Assim todo acesso cabe numa palavra só.
    //Um acesso desalinhado que cruza duas palavras não é detectado aqui, e o Load pode
    //ler um valor antigo da memória.
    //Dois acessos se sobrepõem se estão na mesma palavra e as máscaras de bytes se cruzam.
    //  - Store no mesmo endereço e do mesmo tamanho do Load: cobre o Load inteiro, forwarding
    //    com a extensão do Load (lb/lh com sinal, lbu/lhu com zero);
    //  - qualquer outra sobreposição: o Load espera o Store ser escrito na memória.
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
            //IVAN FEATURE
            sobrepoe = (addr[ptr[3:0]][31:2] == q_addr[31:2]) &&
                       ((mascara(f3[ptr[3:0]], addr[ptr[3:0]][1:0]) & q_mascara) != 4'b0);
            cobre    = (addr[ptr[3:0]] == q_addr) && (f3[ptr[3:0]][1:0] == q_funct3[1:0]);
            if (k < n_antigos) begin
                if (!addr_ok[ptr[3:0]]) begin
                    q_espera = 1'b1;
                end else if (sobrepoe) begin   //IVAN FEATURE: era addr == q_addr
                    //IVAN FEATURE: Store que coincide sem dado ainda, ou que não cobre o
                    //Load inteiro: o Load espera
                    if (cobre && dado_ok[ptr[3:0]]) begin
                        q_hit    = 1'b1;
                        q_espera = 1'b0;
                        q_dado   = estende(q_funct3, dado[ptr[3:0]]);  //IVAN FEATURE
                    end else begin
                        q_hit    = 1'b0;
                        q_espera = 1'b1;
                    end
                end
            end
        end
    end

    // Entradas esperando o commit, em [cptr, tail) — só elas capturam o endereço,
    // pois o rob_id de uma entrada já commitada pode ter sido reutilizado no ROB
    wire [4:0] n_pendentes = tail - cptr;
    reg  [4:0] off;

    //IVAN FEATURE: Recuperação
    //Só a região não commitada [cptr, tail) pode ter Stores mais novos que B (B ainda
    //não fez commit). Os commitados em [head, cptr) têm rob_id já liberado pelo ROB e
    //não podem ser comparados. Na ordem do programa, os mais antigos que B formam o
    //início da região: o novo tail é cptr + n_mantidos.
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
                dado_ok[i] <= 1'b0;  //IVAN FEATURE
                f3[i]      <= 3'b010;  //IVAN FEATURE
            end
        end else begin
            //IVAN FEATURE: No flush, o tail volta para depois do último Store mais antigo
            //que B, e as alocações do ciclo (caminho errado) são ignoradas
            if (flush_ok)
                tail <= tail_flush;
            else
                tail <= tail + dispatched;

            // Despacho compactado
            if (!flush_ok)  //IVAN FEATURE
            case({is_store1, is_store2, is_store3})
                3'b001: begin
                    dado[tail[3:0]] <= dado3; rob_id[tail[3:0]] <= rob_id3; addr_ok[tail[3:0]] <= 1'b0;
                end
                3'b010: begin
                    dado[tail[3:0]] <= dado2; rob_id[tail[3:0]] <= rob_id2; addr_ok[tail[3:0]] <= 1'b0;
                end
                3'b011: begin
                    dado[tail[3:0]]  <= dado2; rob_id[tail[3:0]]  <= rob_id2; addr_ok[tail[3:0]]  <= 1'b0;
                    dado[tail2[3:0]] <= dado3; rob_id[tail2[3:0]] <= rob_id3; addr_ok[tail2[3:0]] <= 1'b0;
                end
                3'b100: begin
                    dado[tail[3:0]] <= dado1; rob_id[tail[3:0]] <= rob_id1; addr_ok[tail[3:0]] <= 1'b0;
                end
                3'b101: begin
                    dado[tail[3:0]]  <= dado1; rob_id[tail[3:0]]  <= rob_id1; addr_ok[tail[3:0]]  <= 1'b0;
                    dado[tail2[3:0]] <= dado3; rob_id[tail2[3:0]] <= rob_id3; addr_ok[tail2[3:0]] <= 1'b0;
                end
                3'b110: begin
                    dado[tail[3:0]]  <= dado1; rob_id[tail[3:0]]  <= rob_id1; addr_ok[tail[3:0]]  <= 1'b0;
                    dado[tail2[3:0]] <= dado2; rob_id[tail2[3:0]] <= rob_id2; addr_ok[tail2[3:0]] <= 1'b0;
                end
                3'b111: begin
                    dado[tail[3:0]]  <= dado1; rob_id[tail[3:0]]  <= rob_id1; addr_ok[tail[3:0]]  <= 1'b0;
                    dado[tail2[3:0]] <= dado2; rob_id[tail2[3:0]] <= rob_id2; addr_ok[tail2[3:0]] <= 1'b0;
                    dado[tail3[3:0]] <= dado3; rob_id[tail3[3:0]] <= rob_id3; addr_ok[tail3[3:0]] <= 1'b0;
                end
            endcase

            //IVAN FEATURE: funct3 guardado na mesma posição compactada do Store
            if (!flush_ok)
            case({is_store1, is_store2, is_store3})
                3'b001: f3[tail[3:0]] <= funct3_3;
                3'b010: f3[tail[3:0]] <= funct3_2;
                3'b011: begin f3[tail[3:0]] <= funct3_2; f3[tail2[3:0]] <= funct3_3; end
                3'b100: f3[tail[3:0]] <= funct3_1;
                3'b101: begin f3[tail[3:0]] <= funct3_1; f3[tail2[3:0]] <= funct3_3; end
                3'b110: begin f3[tail[3:0]] <= funct3_1; f3[tail2[3:0]] <= funct3_2; end
                3'b111: begin f3[tail[3:0]] <= funct3_1; f3[tail2[3:0]] <= funct3_2; f3[tail3[3:0]] <= funct3_3; end
                default: ;
            endcase

            //IVAN FEATURE: Entradas alocadas começam sem dado
            if (dispatched >= 3'd1 && !flush_ok) dado_ok[tail[3:0]]  <= 1'b0;
            if (dispatched >= 3'd2 && !flush_ok) dado_ok[tail2[3:0]] <= 1'b0;
            if (dispatched == 3'd3 && !flush_ok) dado_ok[tail3[3:0]] <= 1'b0;

            // Captura do endereço calculado pelos caminhos
            for (i = 0; i < 16; i = i + 1) begin
                off = i[4:0] - cptr;
                if ({1'b0, off[3:0]} < n_pendentes) begin
                    if (wb[0] && rid1 == rob_id[i]) begin addr[i] <= r1; addr_ok[i] <= 1'b1; end
                    if (wb[1] && rid2 == rob_id[i]) begin addr[i] <= r2; addr_ok[i] <= 1'b1; end
                    if (wb[2] && rid3 == rob_id[i]) begin addr[i] <= r3; addr_ok[i] <= 1'b1; end

                    //IVAN FEATURE: Captura do dado enviado pelo despacho
                    if (store1_valid && store1_rob_id == rob_id[i]) begin dado[i] <= store1_dado; dado_ok[i] <= 1'b1; end
                    if (store2_valid && store2_rob_id == rob_id[i]) begin dado[i] <= store2_dado; dado_ok[i] <= 1'b1; end
                end
            end

            // Commit — o endereço já foi capturado, pois o ROB só commita após o wb
            cptr <= cptr + commited;

            // Escrita na memória — a MED sempre aceita o Store
            if (mem_req) head <= head + 1;
        end
    end
endmodule

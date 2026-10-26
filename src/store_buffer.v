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
    output wire stop
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

    assign sb_tail = tail;

    // A ocupação conta também os commitados que ainda não foram escritos
    assign stop = ((tail - head) > 5'd13);

    // Consulta — os Stores mais antigos que o Load estão em [head, q_idade).
    // Percorre do mais antigo ao mais novo: um Store que coincide sobrescreve o
    // resultado dos anteriores, e um desconhecido depois dele volta a exigir espera
    wire [4:0] n_antigos = q_idade - head;
    reg  [4:0] ptr;
    integer k;

    always @(*) begin
        q_espera = 1'b0;
        q_hit    = 1'b0;
        q_dado   = 32'b0;
        for (k = 0; k < 16; k = k + 1) begin
            ptr = head + k;
            if (k < n_antigos) begin
                if (!addr_ok[ptr[3:0]]) begin
                    q_espera = 1'b1;
                end else if (addr[ptr[3:0]] == q_addr) begin
                    q_hit    = 1'b1;
                    q_espera = 1'b0;
                    q_dado   = dado[ptr[3:0]];
                end
            end
        end
    end

    // Entradas esperando o commit, em [cptr, tail) — só elas capturam o endereço,
    // pois o rob_id de uma entrada já commitada pode ter sido reutilizado no ROB
    wire [4:0] n_pendentes = tail - cptr;
    reg  [4:0] off;

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
            end
        end else begin
            tail <= tail + dispatched;

            // Despacho compactado
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

            // Captura do endereço calculado pelos caminhos
            for (i = 0; i < 16; i = i + 1) begin
                off = i[4:0] - cptr;
                if ({1'b0, off[3:0]} < n_pendentes) begin
                    if (wb[0] && rid1 == rob_id[i]) begin addr[i] <= r1; addr_ok[i] <= 1'b1; end
                    if (wb[1] && rid2 == rob_id[i]) begin addr[i] <= r2; addr_ok[i] <= 1'b1; end
                    if (wb[2] && rid3 == rob_id[i]) begin addr[i] <= r3; addr_ok[i] <= 1'b1; end
                end
            end

            // Commit — o endereço já foi capturado, pois o ROB só commita após o wb
            cptr <= cptr + commited;

            // Escrita na memória — a MED sempre aceita o Store
            if (mem_req) head <= head + 1;
        end
    end
endmodule

module store_buffer(
    input wire clk, rst,

    // Despacho — até 3 instruções por ciclo
    input wire [2:0]  v,                         // Quais slots são válidos
    input wire [2:0]  dst1, dst2, dst3,           // Destino de cada instrução
    input wire [31:0] dado1, dado2, dado3,        // Dados a serem escritos

    // Commit do ROB — até 3 stores por ciclo, sempre em ordem
    input wire [2:0]  cv,                        // Quais commits são Store
    input wire [31:0] cr1, cr2, cr3,             // Resultado do commit (endereço do Store)

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
    reg [31:0] dado [0:15];
    reg [31:0] addr [0:15];
    reg [4:0] head, cptr, tail;

    wire [4:0] tail2 = tail + 1;
    wire [4:0] tail3 = tail + 2;
    wire [4:0] cptr2 = cptr + 1;
    wire [4:0] cptr3 = cptr + 2;

    // Filtragem interna — quais slots são Store
    wire is_store1 = v[0] & (dst1 == 3'b100);
    wire is_store2 = v[1] & (dst2 == 3'b100);
    wire is_store3 = v[2] & (dst3 == 3'b100);

    wire [2:0] dispatched = is_store1 + is_store2 + is_store3;

    // Commit — o ROB e o buffer estão na mesma ordem, então o k-ésimo
    // Store commitado no ciclo é sempre cptr + k - 1
    wire [2:0] commited = cv[0] + cv[1] + cv[2];

    // Endereços dos Stores commitados, compactados na ordem
    wire [31:0] caddr1 = cv[0] ? cr1 : (cv[1] ? cr2 : cr3);
    wire [31:0] caddr2 = (cv[0] & cv[1]) ? cr2 : cr3;
    wire [31:0] caddr3 = cr3;

    assign mem_req  = (head != cptr);
    assign mem_addr = addr[head[3:0]];
    assign mem_dado = dado[head[3:0]];

    // A ocupação conta também os commitados que ainda não foram escritos
    assign stop = ((tail - head) > 5'd13);

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head <= 5'd0;
            cptr <= 5'd0;
            tail <= 5'd0;
            for (i = 0; i < 16; i = i + 1) begin
                dado[i] <= 32'b0;
                addr[i] <= 32'b0;
            end
        end else begin
            tail <= tail + dispatched;

            // Despacho compactado
            case({is_store1, is_store2, is_store3})
                3'b001: dado[tail[3:0]]  <= dado3;
                3'b010: dado[tail[3:0]]  <= dado2;
                3'b011: begin
                    dado[tail[3:0]]  <= dado2;
                    dado[tail2[3:0]] <= dado3;
                end
                3'b100: dado[tail[3:0]]  <= dado1;
                3'b101: begin
                    dado[tail[3:0]]  <= dado1;
                    dado[tail2[3:0]] <= dado3;
                end
                3'b110: begin
                    dado[tail[3:0]]  <= dado1;
                    dado[tail2[3:0]] <= dado2;
                end
                3'b111: begin
                    dado[tail[3:0]]  <= dado1;
                    dado[tail2[3:0]] <= dado2;
                    dado[tail3[3:0]] <= dado3;
                end
            endcase

            // Commit compactado — guarda o endereço, pois a entrada do ROB é liberada
            if (commited >= 3'd1) addr[cptr[3:0]]  <= caddr1;
            if (commited >= 3'd2) addr[cptr2[3:0]] <= caddr2;
            if (commited == 3'd3) addr[cptr3[3:0]] <= caddr3;
            cptr <= cptr + commited;

            // Escrita na memória — a MED sempre aceita o Store
            if (mem_req) head <= head + 1;
        end
    end
endmodule

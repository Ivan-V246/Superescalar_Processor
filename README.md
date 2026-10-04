# README — Organização do Repositório Verilog

## Introdução

Este repositório reúne os módulos Verilog desenvolvidos pelo time. A organização é simples e direta — cada coisa no seu lugar, sem estrutura desnecessária para o porte do projeto.

## Estrutura de Pastas

```
project/
├── src/          # Todos os módulos .v do projeto
│   ├── modulo_a.v
│   ├── modulo_b.v
│   └── top.v     # Módulo top-level
│
├── tb/           # Testbenches
│   ├── tb_modulo_a.v
│   └── tb_modulo_b.v
│
├── .gitignore
└── README.md
```

- **`src/`** — contém todo o código sintetizável. Cada arquivo corresponde a um módulo.
- **`tb/`** — contém os testbenches. O nome do arquivo segue o padrão `tb_<nome_do_modulo>.v`.
- Arquivos gerados pela simulação (`.vcd`, `.vvp`, `.out`) não são versionados — ficam cobertos pelo `.gitignore`.

## Convenções do Time

- **Um módulo por arquivo**, com o nome do arquivo igual ao nome do módulo. Ex: o módulo `alu` fica em `src/alu.v`.
- **Testbench sempre junto**: todo módulo novo deve ter seu testbench no mesmo PR, em `tb/tb_<modulo>.v`.
- **Trabalhe em branches**: crie uma branch com o nome do seu módulo (`feature/alu`, `feature/register_file`) e abra um Pull Request quando terminar.
- **Nada de arquivos gerados no repositório**: `.vcd`, `.vvp` e similares devem estar no `.gitignore`.

### .gitignore mínimo

```gitignore
*.vcd
*.vvp
*.out
```

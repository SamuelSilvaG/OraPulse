# 📡 OraPulse (Advanced Oracle DBA Monitor)

**OraPulse** é um painel de monitoramento e orquestração de sessões em tempo real para ambientes Oracle Database de missão crítica (24/7). Desenvolvido nativamente em Bash, ele substitui scripts soltos e comandos destrutivos (`kill -9`) por uma interface responsiva, segura e focada em proteção de infraestrutura.

Construído para DBAs e Sysadmins, o OraPulse não apenas lista sessões ativas e locks, mas atua como um escudo: ele calcula o custo de Rollback antes de você derrubar uma sessão, previne esgotamento de disco com integração ao ADRCI e captura interrupções abruptas para evitar Traces órfãos.

## 🚀 Principais Funcionalidades

*   **📊 Monitoramento em Tempo Real (Auto-Refresh):** Visualização de sessões ativas da aplicação e árvores de bloqueio (Locks/Enqueues) ignorando o ruído de processos de background (`oracle_maintained = 'N'`).
*   **🛡️ Extermínio Seguro de 2 Fases (Kill):** Nunca mais corrompa blocos. O script tenta um `DISCONNECT IMMEDIATE` nativo. Se o processo físico sobreviver, ele oferece o `kill -9` no SO.
*   **🧮 Calculadora de UNDO/Rollback:** Antes do abate de uma sessão, o OraPulse calcula os blocos de UNDO pendentes e converte para Megabytes. Se a transação for massiva, ele emite um alerta visual crítico, evitando degradação de I/O (`free buffer waits`).
*   **🧹 Escudo de Storage (ADRCI Integrado):** Pré-check inteligente que lê a `V$DIAG_INFO` e a montagem do disco. Se o uso ultrapassar 80%, ele oferece um expurgo limpo de traces antigos (> 7 dias) usando a ferramenta oficial da Oracle.
*   **🕵️ Captura de Trace Blindada:** Ativação de traces via `DBMS_MONITOR`. Possui um gatilho nativo (`trap` de CTRL+C) que desativa o trace no banco automaticamente caso a conexão SSH caia ou o operador aborte a operação, salvando o disco.
*   **🔄 Troca Dinâmica de Instância:** Lê os processos `PMON` do Linux em tempo real, listando e permitindo trocar de CDB/PDB sem precisar sair do painel.
*   **📱 Interface Responsiva:** As barras de divisão calculam o `tput cols` do Linux e se esticam dinamicamente de acordo com a largura da sua janela SSH.

## 📋 Pré-requisitos

*   Sistema Operacional: Linux (RedHat, CentOS, Oracle Linux, Ubuntu, etc.)
*   Banco de Dados: Oracle Database (Testado em 12c, 19c e 21c).
*   Acesso: Usuário pertencente ao grupo `dba` (ex: usuário `oracle`) com permissões para rodar `sqlplus / as sysdba`.

## 🛠️ Instalação

1. Clone o repositório ou baixe o script diretamente para o seu servidor.
```bash
git clone [https://github.com/SEU_USUARIO/orapulse.git](https://github.com/SEU_USUARIO/orapulse.git)
cd orapulse
Se você transferiu o arquivo de um ambiente Windows, purifique as quebras de linha para evitar erros de sintaxe no Bash:

Bash
sed -i 's/\r//g' orapulse.sh
Aplique a permissão de execução:

Bash
chmod +x orapulse.sh
🎮 Como Usar
Basta executar o script no terminal. Se as variáveis de ambiente ($ORACLE_SID e $ORACLE_HOME) já estiverem exportadas, ele abrirá imediatamente.

Bash
./orapulse.sh
Comandos Interativos:
[T] Trace: Inicia uma captura de tkprof com limite de tempo e auto-desligamento.

[S] SQL: Extrai o sql_fulltext em memória que uma sessão está executando agora.

[K] Kill: Inicia a rotina de avaliação de UNDO e extermínio de 2 fases.

[I] Instância: Lista os PMONs locais e migra o painel para outra base de dados.

[CTRL+C]: Interrompe com segurança qualquer operação e sai do painel.

🤝 Contribuição
Sinta-se à vontade para abrir Issues ou enviar Pull Requests. Toda melhoria focada na estabilidade e segurança do ecossistema Oracle é bem-vinda.

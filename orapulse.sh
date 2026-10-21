#!/bin/bash

if [[ -z "$ORACLE_SID" ]]; then echo -e "\e[1;31mERRO:\e[0m Instância não definida. Execute '. oraenv'"; exit 1; fi

# Cores
C_CYAN="\e[1;36m"; C_GREEN="\e[1;32m"; C_YELLOW="\e[1;33m"; C_RED="\e[1;31m"; C_WHITE="\e[1;37m"; C_RESET="\e[0m"

# ==============================================================================
# MECANISMO DE SEGURANÇA 1: TRAP (ANTI-TRAVAMENTO)
# ==============================================================================
CURRENT_TRACE_SID=""
CURRENT_TRACE_SERIAL=""

cleanup_and_exit() {
    echo -e "\n\n${C_RED}🛑 [ALERTA] INTERRUPÇÃO FORÇADA DETECTADA (CTRL+C) 🛑${C_RESET}"
    if [[ -n "$CURRENT_TRACE_SID" && -n "$CURRENT_TRACE_SERIAL" ]]; then
        echo -e "${C_YELLOW}⚠️ Desligando emergencialmente o Trace da sessão ${CURRENT_TRACE_SID}...${C_RESET}"
        echo "EXEC DBMS_MONITOR.session_trace_disable($CURRENT_TRACE_SID, $CURRENT_TRACE_SERIAL); EXIT;" | sqlplus -s / as sysdba > /dev/null
        echo -e "${C_GREEN}✅ Trace desativado com segurança no banco!${C_RESET}"
    fi
    echo -e "👋 Painel DBA encerrado."
    exit 0
}
trap 'cleanup_and_exit' SIGINT

# ==============================================================================
# MOTOR RESPONSIVO PARA AS BARRAS DO TERMINAL
# ==============================================================================
get_bars() {
    TERM_WIDTH=$(tput cols 2>/dev/null || echo 120)
    BAR_EQ=$(printf '%*s' "$TERM_WIDTH" '' | tr ' ' '=')
    BAR_DASH=$(printf '%*s' "$TERM_WIDTH" '' | tr ' ' '-')
}
get_bars

# ==============================================================================
# MECANISMO DE SEGURANÇA 2: ESPAÇO EM DISCO E EXPURGO ADRCI
# ==============================================================================
clear
echo -e "${C_CYAN}${BAR_EQ}${C_RESET}"
echo -e "${C_WHITE} 🔍 PRÉ-ANÁLISE DE SAÚDE E ARMAZENAMENTO...${C_RESET}"

DIAG_PATH=$(echo "SET HEAD OFF PAGES 0 FEEDBACK OFF
SELECT value FROM v\$diag_info WHERE name = 'Diag Trace';
EXIT;" | sqlplus -s / as sysdba | xargs)

if [[ -n "$DIAG_PATH" && -d "$DIAG_PATH" ]]; then
    DISK_USE=$(df -Ph "$DIAG_PATH" | awk 'NR==2 {print $5}' | sed 's/%//')
    MOUNT_POINT=$(df -Ph "$DIAG_PATH" | awk 'NR==2 {print $6}')
    
    if [[ "$DISK_USE" =~ ^[0-9]+$ ]] && [[ "$DISK_USE" -ge 80 ]]; then
        echo -e "\n${C_RED}⚠️ ALERTA DE DISCO: A montagem $MOUNT_POINT está com ${DISK_USE}% de uso!${C_RESET}"
        echo -e -n "${C_YELLOW}Deseja expurgar TRACES com mais de 7 dias via ADRCI? (s/n): ${C_RESET}"
        read RESP_LIMPEZA
        if [[ "$RESP_LIMPEZA" == "s" || "$RESP_LIMPEZA" == "S" ]]; then
            echo -e "${C_WHITE}Iniciando limpeza segura (ADRCI) de traces > 10080 minutos...${C_RESET}"
            adrci exec="show homes" | grep -i "diag/rdbms" | while read -r adr_home; do
                echo -e "  Limpando home: $adr_home"
                adrci exec="set homepath $adr_home; purge -age 10080 -type TRACE" > /dev/null 2>&1
            done
            NOVO_USE=$(df -Ph "$DIAG_PATH" | awk 'NR==2 {print $5}')
            echo -e "${C_GREEN}✅ Limpeza concluída! Uso atual do disco: $NOVO_USE${C_RESET}\n"
        fi
    else
        echo -e "${C_GREEN}✅ Disco $MOUNT_POINT saudável (${DISK_USE}% de uso).${C_RESET}"
    fi
fi

# ==============================================================================
# MECANISMO DE SEGURANÇA 3: CHECAGEM DE TRACES ÓRFÃOS
# ==============================================================================
QTD_TRACES=$(echo "SET HEAD OFF FEEDBACK OFF PAGES 0
SELECT COUNT(*) FROM v\$session WHERE sql_trace = 'ENABLED' OR sql_trace = 'TRUE';
EXIT;" | sqlplus -s / as sysdba | xargs)

if [[ "$QTD_TRACES" =~ ^[0-9]+$ ]] && [[ "$QTD_TRACES" -gt 0 ]]; then
    echo -e "\n${C_RED}⚠️ ATENÇÃO CRÍTICA: EXISTEM $QTD_TRACES SESSÃO(ÕES) COM TRACE ATIVADO NESTE MOMENTO!${C_RESET}"
    echo "SET ECHO OFF VERIFY OFF FEEDBACK OFF HEADING ON LINESIZE 200 PAGESIZE 100
    COL SID FORMAT 99999
    COL USERNAME FORMAT A15
    COL OSUSER FORMAT A15
    COL MACHINE FORMAT A25
    SELECT sid, serial#, username, osuser, substr(machine,1,25) as maquina FROM v\$session WHERE sql_trace = 'ENABLED' OR sql_trace = 'TRUE';
    EXIT;" | sqlplus -s / as sysdba
    echo -e -n "\n${C_WHITE}👉 Pressione [ENTER] para ciente e abrir o monitor...${C_RESET}"
    read
else
    echo -e "${C_GREEN}✅ Nenhum trace órfão detectado na instância.${C_RESET}"
    sleep 1
fi

# ==============================================================================
# LOOP PRINCIPAL DO MONITOR
# ==============================================================================
while true; do
    
    # Recalcula a largura em cada refresh (permite redimensionar a janela)
    get_bars

    RESUMO_CONEXOES=$(echo "SET HEAD OFF FEEDBACK OFF PAGES 0
    SELECT '👥 APP: Ativas=' || SUM(CASE WHEN type='USER' AND status='ACTIVE' THEN 1 ELSE 0 END) || ' | Inativas(Pool)=' || SUM(CASE WHEN type='USER' AND status='INACTIVE' THEN 1 ELSE 0 END) || '   ⚙️ ORACLE: Background=' || SUM(CASE WHEN type='BACKGROUND' THEN 1 ELSE 0 END) FROM v\$session;
    EXIT;" | sqlplus -s / as sysdba | xargs)

    clear
    echo -e "${C_CYAN}${BAR_EQ}${C_RESET}"
    echo -e "${C_WHITE} 📡 MONITOR DBA (Auto-Refresh) - Instância: ${C_YELLOW}${ORACLE_SID}${C_RESET}"
    echo -e "${C_WHITE} 📊 STATUS: ${C_YELLOW}${RESUMO_CONEXOES}${C_RESET}"
    echo -e "${C_CYAN}${BAR_EQ}${C_RESET}\n"
    
    echo -e "${C_GREEN}>>> SESSÕES DA APLICAÇÃO ATIVAS (COM MONITOR DE ROLLBACK):${C_RESET}"
    echo -e "${BAR_DASH}"
    echo "SET ECHO OFF VERIFY OFF FEEDBACK OFF HEADING ON LINESIZE 200 PAGESIZE 100
    COL SID FORMAT 99999
    COL SERIAL FORMAT 999999 HEADING 'SERIAL#'
    COL STATUS FORMAT A10
    COL USUARIO FORMAT A15
    COL MAQUINA FORMAT A20
    COL EVENTO FORMAT A30
    COL SEGUNDOS_ATIVO FORMAT 999999 HEADING 'SEG|ATIVO'
    COL UNDO_BLK FORMAT 9999999 HEADING 'UNDO|BLKS'
    SELECT s.sid AS SID, s.serial# AS SERIAL, s.status AS STATUS, s.username AS USUARIO, SUBSTR(s.machine, 1, 20) AS MAQUINA, SUBSTR(s.event, 1, 30) AS EVENTO, s.last_call_et AS SEGUNDOS_ATIVO, NVL(t.used_ublk, 0) AS UNDO_BLK FROM v\$session s JOIN cdb_users u ON s.username = u.username AND s.con_id = u.con_id LEFT JOIN v\$transaction t ON s.taddr = t.addr WHERE s.type = 'USER' AND s.status IN ('ACTIVE', 'KILLED') AND s.username IS NOT NULL AND u.oracle_maintained = 'N' ORDER BY s.last_call_et DESC;
    EXIT;" | sqlplus -s / as sysdba

    echo -e "\n${C_RED}>>> BLOQUEIOS (LOCKS) ATIVOS NESTE MOMENTO:${C_RESET}"
    echo -e "${BAR_DASH}"
    echo "SET ECHO OFF VERIFY OFF FEEDBACK OFF HEADING ON LINESIZE 200 PAGESIZE 100
    COL SID_TRAV FORMAT 99999 HEADING 'SID|TRAV'
    COL SID_BLOQ FORMAT 99999 HEADING 'SID|BLOQ(VILÃO)'
    COL USUARIO_BLOQ FORMAT A15 HEADING 'USER BLOQ'
    COL EVENTO_TRAV FORMAT A30 HEADING 'EVENTO ESPERADO'
    COL TEMPO_ESPERA FORMAT 999999 HEADING 'SEG|ESPERA'
    SELECT l2.sid AS SID_TRAV, l1.sid AS SID_BLOQ, l1.username AS USUARIO_BLOQ, SUBSTR(l2.event, 1, 30) AS EVENTO_TRAV, l2.seconds_in_wait AS TEMPO_ESPERA FROM gv\$lock l JOIN gv\$lock l3 ON (l.id1 = l3.id1 AND l.id2 = l3.id2) JOIN gv\$session l1 ON (l3.sid = l1.sid AND l3.inst_id = l1.inst_id) JOIN gv\$session l2 ON (l.sid = l2.sid AND l.inst_id = l2.inst_id) WHERE l.block = 1 AND l3.request > 0;
    EXIT;" | sqlplus -s / as sysdba

    echo -e "\n${C_CYAN}${BAR_EQ}${C_RESET}"
    echo -e -n "⏳ 5s... [${C_YELLOW}T${C_RESET}] Trace | [${C_YELLOW}S${C_RESET}] SQL | [${C_RED}K${C_RESET}] Kill | [${C_YELLOW}I${C_RESET}] Instância | [${C_CYAN}CTRL+C${C_RESET}] Sair: "
    read -t 5 -n 1 input
    
    # OPÇÃO [I] - MUDAR INSTÂNCIA
    if [[ "$input" == "I" || "$input" == "i" ]]; then
        echo -e "\n\n${C_CYAN}🔄 MUDAR INSTÂNCIA ORACLE${C_RESET}"
        echo -e "${BAR_DASH}"
        ps -eo args | grep '^ora_pmon_' | sed 's/ora_pmon_//g' | while read -r inst; do echo -e "  ▶ ${C_WHITE}$inst${C_RESET}"; done
        echo -e -n "\n${C_YELLOW}🔹 Digite o novo ORACLE_SID: ${C_RESET}"; read NOVO_SID
        NOVO_SID=$(echo "$NOVO_SID" | tr -d ' \r\n')
        if [[ -n "$NOVO_SID" ]]; then
            export ORACLE_SID=$NOVO_SID
            export ORAENV_ASK=NO; . oraenv > /dev/null 2>&1; export ORAENV_ASK=YES
        fi

    # OPÇÃO [T] - MODO TRACE BLINDADO
    elif [[ "$input" == "T" || "$input" == "t" ]]; then
        echo -e "\n\n${C_GREEN}>>> CONFIGURAR CAPTURA DE TRACE${C_RESET}"
        echo -e -n "${C_YELLOW}🔹 Digite SID, SERIAL# e TEMPO (ex: 883 13335 60): ${C_RESET}"; read SESS_SID SESS_SERIAL TEMPO
        if [[ -n "$SESS_SID" && -n "$SESS_SERIAL" && -n "$TEMPO" ]]; then
            CURRENT_TRACE_SID=$SESS_SID; CURRENT_TRACE_SERIAL=$SESS_SERIAL
            TRACE_FILE=$(echo "SET HEAD OFF FEEDBACK OFF PAGES 0
            EXEC DBMS_MONITOR.session_trace_enable($SESS_SID, $SESS_SERIAL, TRUE, TRUE);
            SELECT p.tracefile FROM v\$session s JOIN v\$process p ON s.paddr = p.addr WHERE s.sid = $SESS_SID;
            EXIT;" | sqlplus -s / as sysdba | grep "\.trc" | xargs)
            
            if [[ -n "$TRACE_FILE" ]]; then
                echo -e "🟢 Trace ativado! Gravando em: ${C_WHITE}$TRACE_FILE${C_RESET}"
                echo -e "⏳ A aguardar ${TEMPO}s (Aperte CTRL+C para abortar de forma segura)..."
                sleep "$TEMPO"
                echo "EXEC DBMS_MONITOR.session_trace_disable($SESS_SID, $SESS_SERIAL); EXIT;" | sqlplus -s / as sysdba > /dev/null
                tkprof "$TRACE_FILE" "/home/oracle/scripts/trc_${SESS_SID}_$(date +%H%M).txt" sys=no waits=yes > /dev/null
                echo -e "✅ CONCLUÍDO! Leia com: cat /home/oracle/scripts/trc_${SESS_SID}_$(date +%H%M).txt"
            else
                echo -e "\n${C_RED}[!] ERRO: Sessão não encontrada.${C_RESET}"
            fi
            CURRENT_TRACE_SID=""; CURRENT_TRACE_SERIAL=""
        fi
        echo -e -n "\n👉 Pressione [ENTER] para voltar..."; read

    # OPÇÃO [S] - MODO INSPEÇÃO DE SQL
    elif [[ "$input" == "S" || "$input" == "s" ]]; then
        echo -e "\n\n${C_CYAN}🔎 MODO INSPEÇÃO DE SQL${C_RESET}"
        echo -e -n "${C_YELLOW}🔹 Digite o SID: ${C_RESET}"; read SQL_SID
        if [[ -n "$SQL_SID" ]]; then
            echo "SET ECHO OFF VERIFY OFF FEEDBACK OFF HEADING OFF LINESIZE 200 PAGESIZE 0 LONG 999999
            SELECT NVL((SELECT sql_fulltext FROM v\$sql WHERE sql_id = s.sql_id AND ROWNUM = 1), TO_CLOB('Nenhum SQL ativo.')) FROM v\$session s WHERE sid = $SQL_SID;
            EXIT;" | sqlplus -s / as sysdba
        fi
        echo -e -n "\n👉 Pressione [ENTER] para voltar..."; read

    # OPÇÃO [K] - MODO EXTERMÍNIO AVANÇADO
    elif [[ "$input" == "K" || "$input" == "k" ]]; then
        echo -e "\n\n${C_RED}☠️ EXTERMÍNIO AVANÇADO DE SESSÃO${C_RESET}"
        echo -e -n "${C_YELLOW}🔹 Digite o SID: ${C_RESET}"; read KILL_SID
        if [[ -n "$KILL_SID" ]]; then
            INFO=$(echo "SET HEAD OFF FEEDBACK OFF PAGES 0
            SELECT s.serial# || ',' || NVL(p.spid, '0') || ',' || NVL(t.used_ublk, 0) || ',' || s.status FROM v\$session s LEFT JOIN v\$process p ON s.paddr = p.addr LEFT JOIN v\$transaction t ON s.taddr = t.addr WHERE s.sid = $KILL_SID;
            EXIT;" | sqlplus -s / as sysdba | xargs)
            
            KILL_SERIAL=$(echo "$INFO" | awk -F',' '{print $1}')
            KILL_SPID=$(echo "$INFO" | awk -F',' '{print $2}')
            UNDO_BLK=$(echo "$INFO" | awk -F',' '{print $3}')
            
            if [[ -n "$KILL_SERIAL" ]]; then
                if [[ ! "$UNDO_BLK" =~ ^[0-9]+$ ]]; then UNDO_BLK=0; fi
                UNDO_MB=$(( UNDO_BLK * 8 / 1024 ))
                
                echo -e "\nDiagnóstico: SPID=${C_WHITE}$KILL_SPID${C_RESET} | Rollback=${C_YELLOW}$UNDO_BLK Blocos (~${UNDO_MB} MB)${C_RESET}"
                
                if [[ "$UNDO_BLK" -gt 10000 ]]; then
                    echo -e "\n${C_RED}${BAR_EQ}${C_RESET}"
                    echo -e "${C_RED} ⚠️ CRÍTICO: TRANSAÇÃO MASSIVA DETECTADA!${C_RESET}"
                    echo -e "${C_YELLOW} Derrubar esta sessão forçará o PMON a fazer rollback de ~${UNDO_MB} MB.${C_RESET}"
                    echo -e "${C_YELLOW} Isso gerará alta carga de I/O em background.${C_RESET}"
                    echo -e "${C_RED}${BAR_EQ}${C_RESET}"
                fi
                
                echo -e -n "\n1. Enviar DISCONNECT IMMEDIATE via Oracle? (s/n): "; read RESP_ORA
                if [[ "$RESP_ORA" == "s" || "$RESP_ORA" == "S" ]]; then
                    echo "ALTER SYSTEM DISCONNECT SESSION '$KILL_SID,$KILL_SERIAL' IMMEDIATE; EXIT;" | sqlplus -s / as sysdba > /dev/null
                    echo -e "${C_GREEN}✅ Ordem Oracle executada.${C_RESET}"
                    sleep 2
                fi
                
                if [[ "$KILL_SPID" != "0" ]] && ps -p $KILL_SPID > /dev/null 2>&1; then
                    echo -e -n "\n${C_YELLOW}2. Processo Linux sobreviveu. Forçar kill -9 bruto no SO? (s/n): ${C_RESET}"; read RESP_OS
                    if [[ "$RESP_OS" == "s" || "$RESP_OS" == "S" ]]; then
                        kill -9 $KILL_SPID 2>/dev/null
                        echo -e "${C_GREEN}✅ Processo aniquilado! O PMON fará o rollback agora.${C_RESET}"
                    fi
                fi
            else
                echo -e "\n${C_RED}[!] ERRO: Sessão $KILL_SID não encontrada.${C_RESET}"
            fi
        fi
        echo -e -n "\n👉 Pressione [ENTER] para voltar..."; read
    fi
done

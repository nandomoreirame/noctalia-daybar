# Revisão — daybar-v5

- **Rodada:** 2026-10-19
- **Achados abertos:** 6
- **Estado:** aguardando correção
- **Implementado por:** claude

> Arquivo reescrito por inteiro a cada `/rpi-review`. Um achado só desaparece
> daqui por ter deixado de existir no código: quem corrige não marca resolvido.

<!-- findings:begin -->

| Severidade | Arquivo:linha | Problema | Correção sugerida |
|------------|---------------|----------|-------------------|
| Medium | toolbar.luau:98 | O toolbar só lê view.requestedTab no onOpen: com o toolbar já aberto, `noctalia msg plugin ...:core all open <aba>` publica o requestedTab (service.luau:1360) mas o render ignora, e a aba não muda (REQ-012). | Em render (ou no watch de "view"), quando v.requestedTab mudar e for uma aba válida diferente da atual, trocar activeTab para ela; cobrir com teste em tests/toolbar.test.luau. |
| Low | lib/store.luau:182 | migrate reconstrói o data com uma lista fixa de chaves e descarta qualquer chave de topo desconhecida na primeira regravação (round-trip não tolerante); um campo de uma versão futura ou editado à mão some em silêncio. | Copiar as chaves desconhecidas de raw para o resultado (ou guardá-las num campo extra) e testar que sobrevivem a parse e serialize. |
| Low | lib/store.luau:185 | reminders entra sem validação; um lembrete importado com date ou time inválido chega a Dates.toDate (lib/dates.luau:88), que com data inválida cai em os.date("*t", nil) (agora) e dispara ou expira o lembrete no horário errado. | Filtrar no migrate os lembretes sem id, sem date ISO válida ou sem time HH:MM, e fazer Dates.toDate devolver nil para entrada inválida. |
| Low | views/client.luau:24 | O callback de um comando só roda quando chega o ack com a seq exata; se o host descartar um evento de watch (fila limitada), o callback do create da nota nunca roda e note.luau fica com creating = true, sem salvar mais nada (note.luau:69). | Ao receber um ack, resolver também os callbacks com seq menor (com ok = nil) e, no note.luau, liberar creating nesse caso e reenviar o texto pendente. |
| Low | tests/service-agenda.test.luau:111 | Asserção tautológica: compara H.pending(s)[1] com ele mesmo e não prova nada. | Remover a linha ou trocá-la por uma asserção sobre o argv pendente. |
| Low | service.luau:578 | startCalendar roda uma vez no boot; se o khal for instalado ou configurado depois, o calendário fica indisponível até reiniciar o Noctalia, e reloadCalendar só responde calendar-not-configured. | Em reloadCalendar com calendar.available false, rodar startCalendar de novo. |

<!-- findings:end -->

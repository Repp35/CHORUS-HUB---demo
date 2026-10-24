
# Chorus Hub MM2

Hub modular para uso no cliente de Murder Mystery 2. A interface e os recursos são carregados pelo `loader.luau`; módulos ficam em `src/`.

## Regras de funcionamento

| Recurso | Requisitos |
| --- | --- |
| ESP de jogadores | Só precisa estar ligado e o personagem estar no Workspace. No lobby, mostra jogador; durante rodada, mostra papel conhecido apenas enquanto o jogador estiver vivo. |
| ESP de moedas e arma | ESP ligado e filtro correspondente ligado; moedas exigem um mapa ativo com `CoinContainer`; armas usam o tag `GunDrop` e só aparecem depois de permanecerem paradas. |
| Auto Farm | Toggle ligado, rodada ativa (`MapID` e `CoinContainer`), personagem local vivo e com `HumanoidRootPart`. Pode coletar moedas com qualquer papel. |
| Resetar com bolsa cheia | Auto Farm ligado, bolsa cheia, personagem vivo e papel registrado como Inocente. |
| Auto Pick Up Gun | Toggle ligado, rodada ativa, local vivo, papel Inocente registrado, arma caída no mapa e sem arma no inventário. A checagem de perigo depende do toggle de segurança. |
| Teleportes para jogadores | Rodada ativa, jogador local vivo e alvo vivo com papel registrado. Xerife também aceita Hero. |
| Anti AFK | Independe de rodada ou papel. |
| Anti Fling | Independe de rodada ou papel; protege colisão/velocidade dos personagens acompanhados. |
| Speed dinâmico, Noclip, Fly e Infinite Jump | Independe de rodada ou papel; cada recurso exige seu toggle ligado. Speed vai de 0 a 100, começa no WalkSpeed atual, é reaplicado após respawn e restaura o valor original ao desligar. |
| Invisicam | Só funciona enquanto algum recurso que o solicita estiver ativo. |

Os papéis são obtidos de `GetPlayerData`; atributos de vida e estado do personagem são conferidos separadamente. Se os dados de papel não estiverem disponíveis, o hub não presume que o jogador é Inocente nem executa ações que exigem esse papel.

## Padrões

Sem uma configuração salva, começam ligados o ESP (com nome, você, filtros de Assassino/Xerife/Inocentes e arma caída parada), Auto Pick Up Gun, Anti AFK, Anti Fling e Invisicam. A segurança contra o Murderer começa desligada, conforme solicitado.

Começam desligados Auto Farm, reset por bolsa cheia, Speed dinâmico, Noclip, Infinite Jump, Fly, e o filtro de moedas. Uma configuração salva pelo usuário prevalece sobre estes padrões.

## Estrutura

- `loader.luau`: valida ambiente/jogo, busca módulos do commit mais recente e inicializa um único runtime.
- `src/Core/`: configuração, serviços Roblox comuns, runtime e utilitários.
- `src/MM2/Services/` e `src/MM2/Features/`: serviços e recursos específicos do Murder Mystery 2.
- `src/Universal/Features/`: recursos que não dependem do jogo ou de papéis, como Fly e Anti AFK.
- `src/UI/`: adaptação da Orion, construção e agrupamento dos controles.

O `src/Manifest.luau` registra módulos por grupo (`MM2` e `Universal`). O loader pré-carrega os caminhos dos grupos e o inicializador os expõe nas APIs de serviços e recursos.

## Ordem das opções

Cada controle pode definir `Importance`: `Critical` (1), `High` (2), `Normal` (3, padrão) ou `Low` (4). Números menores aparecem antes; controles empatados mantêm a ordem declarada. Os controles filhos são ordenados apenas entre os filhos do mesmo controle pai.

## Desenvolvimento

Os módulos Luau devem retornar fábricas que recebem `API`. O `Runtime` é a única autoridade para conexões, tarefas e limpeza. Antes de publicar, valide sintaxe Luau, `git diff --check` e o comportamento em uma sessão Roblox; a verificação estática não substitui teste no jogo.

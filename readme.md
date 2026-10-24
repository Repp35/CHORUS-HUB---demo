
# Chorus Hub MM2

Hub modular para uso no cliente de Murder Mystery 2. A interface e os recursos são carregados pelo `loader.luau`; módulos ficam em `src/`.

## Regras de funcionamento

| Recurso | Requisitos |
| --- | --- |
| ESP de jogadores | Só precisa estar ligado e o personagem estar no Workspace. No lobby, mostra jogador; durante rodada, mostra papel conhecido apenas enquanto o jogador estiver vivo. |
| ESP de moedas e arma | ESP ligado e filtro correspondente ligado; moedas exigem um mapa ativo com `CoinContainer`, armas são descobertas no Workspace. |
| Auto Farm | Toggle ligado, rodada ativa (`MapID` e `CoinContainer`), personagem local vivo e com `HumanoidRootPart`. Pode coletar moedas com qualquer papel. |
| Resetar com bolsa cheia | Auto Farm ligado, bolsa cheia, personagem vivo e papel registrado como Inocente. |
| Auto Pick Up Gun | Toggle ligado, rodada ativa, local vivo, papel Inocente registrado, arma caída no mapa e sem arma no inventário. A checagem de perigo depende do toggle de segurança. |
| Teleportes para jogadores | Rodada ativa, jogador local vivo e alvo vivo com papel registrado. Xerife também aceita Hero. |
| Anti AFK | Independe de rodada ou papel. |
| Anti Fling | Independe de rodada ou papel; protege colisão/velocidade dos personagens acompanhados. |
| Speed dinâmico, Noclip, Fly e Infinite Jump | Independe de rodada ou papel; cada recurso exige seu toggle ligado. Speed vai de 0 a 100, começa no WalkSpeed atual, é reaplicado após respawn e restaura o valor original ao desligar. |
| Invisicam | Só funciona enquanto algum recurso que o solicita estiver ativo. |

Os papéis são obtidos de `GetPlayerData`; atributos de vida e estado do personagem são conferidos separadamente. Se os dados de papel não estiverem disponíveis, o hub não presume que o jogador é Inocente nem executa ações que exigem esse papel.

## Estrutura

- `loader.luau`: valida ambiente/jogo, busca módulos do commit mais recente e inicializa um único runtime.
- `src/Core/`: configuração, serviços Roblox comuns, runtime e utilitários.
- `src/Services/`: contexto de rodada, mapa e moedas.
- `src/Features/`: recursos independentes, cada um com ciclo Start/Stop e limpeza no encerramento.
- `src/UI/`: adaptação da Orion, construção e agrupamento dos controles.

## Desenvolvimento

Os módulos Luau devem retornar fábricas que recebem `API`. O `Runtime` é a única autoridade para conexões, tarefas e limpeza. Antes de publicar, valide sintaxe Luau, `git diff --check` e o comportamento em uma sessão Roblox; a verificação estática não substitui teste no jogo.

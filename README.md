# Chorus Hub | Demo

Chorus para Murder Mystery 2, organizado em módulos. O arquivo principal é o loader; ele resolve o SHA mais recente da branch `main` e carrega todos os módulos do mesmo commit para evitar misturar versões.

## Loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Repp35/CHORUS-HUB---demo/main/ChorusMM2Delta.lua"))()
```

O loader encerra sem inicializar fora do MM2 (`66654135`).

## Estrutura

- `ChorusMM2Delta.lua`: valida a experiência, resolve o commit e expõe a API do loader.
- `src/Main.lua`: inicialização e composição dos módulos.
- `src/Manifest.lua`: registro ordenado de serviços e funcionalidades.
- `src/Core/`: configuração, serviços Roblox, ciclo de vida e utilitários compartilhados.
- `src/Services/`: moedas, mapas e estado da partida.
- `src/Features/`: ESP, Auto Farm, Anti AFK e Anti Fling.
- `src/UI/`: Orion, janela, registro de controles e configurações.

## API interna

Cada módulo retorna uma fábrica que recebe `API`. A API central fornece `Config`, `Roblox`, `Player`, `Runtime`, `Services`, `Features`, `UI`, `Fetch`, `Compile` e `Require`. `Require` cacheia módulos e carrega tudo pelo mesmo SHA.

Use `Runtime:Track(connection)`, `Runtime:TrackTask(thread)` e `Runtime:OnShutdown(callback)` para que eventos, tarefas e recursos sejam limpos ao recarregar o script.

## Adicionar uma funcionalidade

1. Crie um módulo independente em `src/Features/`.
2. Registre o módulo em `src/Manifest.lua`.
3. Crie os controles em `src/UI/Settings.lua`, referenciando funcionalidades por `API.Features`.

Mantenha dependências compartilhadas na API ou nos serviços existentes, em vez de copiar helpers entre arquivos. O loader sempre busca o commit mais recente da branch `main`.

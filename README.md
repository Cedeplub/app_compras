# App Compras CEDEP (v2)

Versão online do modelo de compras e precificação da CEDEP: uma planilha de 8.841 SKUs
e 122 colunas de decisão, reproduzida em um fluxo **dbt** (schema Oracle `COMPRAS`) e
servida por um **dashboard** FastAPI + React.

Este README é só a porta de entrada. O conteúdo mora em dois documentos.

## Comece por `CONTEXTO.md`

Leia **`CONTEXTO.md` §0** primeiro — é o ponto de partida para sessão nova ou
desenvolvedor novo: o que o projeto é, a fronteira de acesso ao banco, como subir em
desenvolvimento e em produção, o socket órfão que confunde quem chega, onde cada coisa
mora, o que está no ar hoje e o que fazer primeiro. Os `§1`–`§7` seguintes trazem
convenções de código, banco e o índice das regras de negócio.

## Regras de negócio: `REGRAS.md`

O detalhe de cada regra fiscal, de margem, preço, curva ABC, alerta e das decisões já
tomadas pelo Diretor de Compras mora em **`REGRAS.md`** — separado do `CONTEXTO.md` para
que quem não mexe em cálculo não precise carregá-lo.

## Estrutura, em uma linha cada

```
CONTEXTO.md         ponto de partida (§0) + convenções + índice de regras
REGRAS.md           o detalhe das regras de negócio, decididas e medidas
app/                API FastAPI (só /api — sem HTML)
web/                front React + Vite
dbt/compras/        o fluxo dbt (models, seeds, tests)
sql/                DDL do schema Oracle COMPRAS
infra/              produção: serviço NSSM + nginx
validar/            scripts que comparam o dbt com a planilha
docs/, referencia/  gabaritos e os originais (planilha, PDF)
historico/          registros passados — não é fonte de verdade
```

Dado que falta no dashboard não se busca direto no `CEDEP`: a fronteira de acesso é o
schema `COMPRAS`, sem exceção (`CONTEXTO.md §2`).

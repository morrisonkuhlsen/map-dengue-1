# Dengue por Estado Brasileiro (2020)

Este repositório contém um script em Julia para visualização das internações por dengue no estado de Pernambuco no ano de 2024, utilizando dados do Datasus e shapefiles geográficos.

## Descrição

O script `src.jl` realiza as seguintes etapas:

1. **Leitura dos dados**: Carrega a tabela `sih_cnv_nibr111825170_150_81_250.csv` com os valores do PIB por estado.
2. **Filtragem**: Seleciona apenas os dados referentes ao ano de 2024.
3. **Geometria**: Obtém as geometrias dos estados brasileiros usando o submódulo `GeoBR`.
4. **Visualização**: Plota um mapa de Pernambuco, colorindo cada município de acordo com o valor das internações (escala logarítmica).
5. **Top 10**: Exibe no terminal os 10 municípios mais críticos.

## Como executar

1. Instale o Julia (versão 1.6 ou superior recomendada).
2. Instale os pacotes necessários. No REPL do Julia, execute:

```julia
using Pkg
Pkg.add(["GeoArtifacts", "GeoInterface", "CairoMakie", "DataFrames", "CSV", "ColorSchemes", "Colors", "Statistics"])
```

3. Execute o script:

```julia
julia src.jl
```

O script irá gerar um mapa com o número de internações por dengue no estado de Pernambuco e imprimir os 10 maiores no terminal.

## Estrutura dos arquivos

- `src.jl`: Script principal para leitura, processamento e visualização dos dados.
- `sih_cnv_nibr111825170_150_81_250.csv`: Dados do PIB por estado (fonte: IBGE).

## Dependências
- [GeoArtifacts](https://github.com/JuliaEarth/GeoArtifacts.jl)
- [GeoInterface](https://github.com/JuliaGeo/GeoInterface.jl)
- [CairoMakie](https://github.com/JuliaPlots/CairoMakie.jl)
- [DataFrames](https://github.com/JuliaData/DataFrames.jl)
- [CSV](https://github.com/JuliaData/CSV.jl)
- [ColorSchemes](https://github.com/JuliaGraphics/ColorSchemes.jl)
- [Colors](https://github.com/JuliaGraphics/Colors.jl)
- [Statistics](https://docs.julialang.org/en/v1/stdlib/Statistics/)

---

![Logo da Empresa](https://raw.githubusercontent.com/morrisonkulsenn/public/refs/heads/main/mk-logo-300x.png)

> **Sinta-se à vontade para abrir issues ou contribuir com melhorias!** 

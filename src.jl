using CSV
using DataFrames
using GeoArtifacts
using GeoInterface
using CairoMakie
using ColorSchemes
using Colors
using Statistics
using Unicode   # para normalização de acentos

set_theme!(theme_dark())

# ============================
# 0. Parâmetros gerais
# ============================

const UF_ALVO  = "PE"          # <<<<< TROCAR AQUI para outra UF se quiser (ex: "PE", "CE"...)
const NOME_UF  = "Pernambuco"       # Nome “bonito” da UF
const ARQ_MUN  = "sih_cnv_nibr111825170_150_81_250.csv"  # arquivo SIH/SUS municipal
const ANO      = 2024          # ano que você quer usar

# ============================
# 1. Funções auxiliares
# ============================

"Normaliza nome para chave ASCII (minúsculo, sem acento, só letras e dígitos)."
function norm_key(s::AbstractString)
    s = strip(String(s))
    # decompõe acentos e coloca tudo em minúsculo
    s = lowercase(Unicode.normalize(s, :NFD))

    buf = IOBuffer()
    for c in s
        # mantém só letras a–z e dígitos 0–9 (ASCII)
        if ('a' <= c <= 'z') || ('0' <= c <= '9')
            write(buf, c)
        end
        # resto (acentos, espaços, hífens etc.) é ignorado
    end
    return String(take!(buf))
end

"Escolhe texto preto ou branco dependendo da cor de fundo."
function text_color(c)
    rgb = convert(RGB, c)
    luminance = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
    return luminance > 0.6 ? RGB(0,0,0) : RGB(1,1,1)
end

"Centro aproximado de um polígono/multipolígono."
function approximate_center(geom)
    coords = GeoInterface.coordinates(geom)
    xs = Float64[]
    ys = Float64[]
    for poly in coords
        exterior = poly[1]
        append!(xs, first.(exterior))
        append!(ys, last.(exterior))
    end
    return Point2f(mean(xs), mean(ys))
end

"Retorna true se a célula parece um ano 20xx (aceita Int ou String)."
is_year_cell(v) = !ismissing(v) && occursin(r"^20\d{2}$", string(v))

# mapa de código IBGE da UF -> sigla
const CODIGO_UF = Dict(
    11=>"RO", 12=>"AC", 13=>"AM", 14=>"RR", 15=>"PA", 16=>"AP", 17=>"TO",
    21=>"MA", 22=>"PI", 23=>"CE", 24=>"RN", 25=>"PB", 26=>"PE", 27=>"AL", 28=>"SE", 29=>"BA",
    31=>"MG", 32=>"ES", 33=>"RJ", 35=>"SP",
    41=>"PR", 42=>"SC", 43=>"RS",
    50=>"MS", 51=>"MT", 52=>"GO", 53=>"DF"
)

"Extrai UF a partir do código IBGE (6 dígitos no início da string)."
function extrair_uf_codigo(s::AbstractString)
    t = strip(String(s))
    m = match(r"^(\d{6})", t)
    m === nothing && return missing
    cod_mun = parse(Int, m.captures[1])
    cod_uf  = cod_mun ÷ 10000           # ex.: 260170 -> 26
    return get(CODIGO_UF, cod_uf, missing)
end

"Extrai o código IBGE do município (6 dígitos no início da string)."
function extrair_cod_muni(s::AbstractString)
    t = strip(String(s))
    m = match(r"^(\d{6})", t)
    m === nothing && return missing
    return m.captures[1]   # devolve como String "260160"
end

"Limpa o nome do município (remove código IBGE inicial)."
function limpar_nome_muni(s::AbstractString)
    s1 = String(s)
    s1 = replace(s1,
        r"^\s*\d{6}\s*-\s*" => "",   # '260170 - Petrolina'
        r"^\s*\d{6}\s+"      => "",  # '260170 Petrolina'
    )
    return strip(s1)
end

# ============================
# 2. Leitura do CSV municipal SIH/SUS (sem header fixo)
# ============================

# Lê tudo sem header
df0 = DataFrame(CSV.File(ARQ_MUN; delim=';', header=false, missingstring=["-","."]))

println("Primeiras linhas brutas do df0:")
show(first(df0, 8), allcols=true); println("\n")

# Descobre linha onde estão os anos 20xx (cabeçalho de verdade)
header_row = findfirst(1:nrow(df0)) do i
    any(is_year_cell(df0[i,j]) for j in 2:ncol(df0))
end
header_row === nothing && error("Não encontrei linha de cabeçalho com anos 20xx no arquivo.")

println("Linha de cabeçalho detectada: ", header_row)

# Monta nomes de coluna a partir dessa linha
raw_header = df0[header_row, :]
colnames = String[]
for j in 1:ncol(df0)
    v = raw_header[j]
    s = strip(string(ismissing(v) ? "" : v))
    if isempty(s)
        push!(colnames, "col$(j)")
    else
        push!(colnames, s)
    end
end

println("Cabeçalho detectado:")
println(colnames)

# DataFrame definitivo: linhas abaixo do cabeçalho
df_raw = df0[(header_row + 1):end, :]
rename!(df_raw, Symbol.(colnames))

# Renomeia primeira coluna para :muni_raw
rename!(df_raw, names(df_raw)[1] => :muni_raw)

println("\nColunas do df_raw após correção de header:")
println(names(df_raw))

# ============================
# 3. Filtrar municípios da UF alvo e pegar internações do ANO
# ============================

# Mantém linhas que têm código de município no começo (começam com dígitos)
df_mun = filter(:muni_raw => x -> occursin(r"^\s*\d", string(x)), df_raw)

df_mun.muni_str = string.(df_mun.muni_raw)

# Código IBGE do município (string de 6 dígitos) – só pra diagnosticar se quiser
df_mun.code6_str = extrair_cod_muni.(df_mun.muni_str)

# Usa código IBGE para descobrir UF
df_mun.uf_sigla = extrair_uf_codigo.(df_mun.muni_str)

# Fica só com a UF alvo (BA)
df_mun = filter(:uf_sigla => x -> !ismissing(x) && x == UF_ALVO, df_mun)

println("\nMunicípios de $(UF_ALVO) no CSV: ", nrow(df_mun))

df_mun.muni_nome = limpar_nome_muni.(df_mun.muni_str)
df_mun.mun_key   = norm_key.(df_mun.muni_nome)

col_ano_str = string(ANO)
if !(col_ano_str in String.(names(df_mun)))
    error("Ano $ANO não existe em df_mun; colunas = $(names(df_mun))")
end

df_mun.internacoes = Float64.(coalesce.(df_mun[!, col_ano_str], 0.0))

println("\nPrimeiras linhas df_mun ($(UF_ALVO)):")
println(first(select(df_mun, [:mun_key, :muni_nome, :uf_sigla, :internacoes]), 10))

# ============================
# 4. Malha de municípios da UF (GeoBR)
# ============================

muni_uf = GeoBR.municipality(UF_ALVO)   # só a UF alvo
df_geo  = DataFrame(muni_uf)

println("\nColunas da malha de municípios de $(NOME_UF):")
println(names(df_geo))

# coluna do nome:
name_col = :name_muni

# chave normalizada a partir do nome do shapefile
df_geo.mun_key = norm_key.(String.(df_geo[!, name_col]))

# Centros para rótulos
centers = [approximate_center(df_geo.geometry[i]) for i in 1:nrow(df_geo)]
df_geo.center_x = [p[1] for p in centers]
df_geo.center_y = [p[2] for p in centers]

# ============================
# 5. Join SIH/SUS x malha (por mun_key)
# ============================

df_map = leftjoin(
    df_geo,
    df_mun[:, [:mun_key, :muni_nome, :internacoes]],
    on = :mun_key,
)

df_map.internacoes = coalesce.(df_map.internacoes, 0.0)

println("\nAlgumas linhas após o join:")
println(first(select(df_map, [name_col, :mun_key, :muni_nome, :internacoes]), 10))

# ============================
# 6. Escala de cores (com proteção vmin == vmax)
# ============================

vals = df_map.internacoes
vmin, vmax = extrema(vals)

println("DEBUG – vmin = $vmin, vmax = $vmax")

cmap = ColorSchemes.viridis
colors = RGB{Float64}[]
cb_min = vmin
cb_max = vmax

if vmin == vmax
    # todos os municípios com o mesmo valor -> cor única e range artificial
    colors = [get(cmap, 0.5) for _ in vals]
    cb_min = vmin - 0.5
    cb_max = vmax + 0.5
else
    colors = [get(cmap, (v - vmin) / (vmax - vmin + eps())) for v in vals]
    cb_min = vmin
    cb_max = vmax
end

# Extensão espacial do mapa
xs = Float64[]
ys = Float64[]
for g in df_map.geometry
    coords = GeoInterface.coordinates(g)
    for poly in coords
        ext = poly[1]
        append!(xs, first.(ext))
        append!(ys, last.(ext))
    end
end
lon_min, lon_max = extrema(xs)
lat_min, lat_max = extrema(ys)

# ============================
# 7. Plot do mapa da UF
# ============================

fig = Figure(size = (900, 800))

ax = Axis(fig[1, 1];
    title  = "Internações por Dengue – Municípios de $(NOME_UF) ($ANO, SIH/SUS)",
    xlabel = "Longitude",
    ylabel = "Latitude",
    aspect = DataAspect(),
    limits = (lon_min, lon_max, lat_min, lat_max),
)

ax.xgridvisible = true
ax.ygridvisible = true
ax.xgridcolor   = (:gray, 0.2)
ax.ygridcolor   = (:gray, 0.2)
ax.xgridstyle   = :dash
ax.ygridstyle   = :dash

for i in 1:nrow(df_map)
    geom = df_map.geometry[i]
    coords = GeoInterface.coordinates(geom)

    for poly in coords
        exterior = poly[1]
        pts = Point2f.(first.(exterior), last.(exterior))
        poly!(ax, pts;
            color       = colors[i],
            strokecolor = (:black, 0.3),
            strokewidth = 0.3,
        )
    end
end

# --- Top N com marcadores e legenda dentro do mapa ---
top_n  = min(10, nrow(df_map))
df_top = sort(df_map, :internacoes, rev = true)[1:top_n, :]

# Cores bem distintas para os pontos
palette = distinguishable_colors(top_n)

handles = Scatter[]   # séries para a legenda
labels  = String[]    # nomes dos municípios

for (k, row) in enumerate(eachrow(df_top))
    cx = row.center_x
    cy = row.center_y

    sc = scatter!(ax, [cx], [cy];
                  color       = palette[k],
                  markersize  = 11,
                  strokecolor = :black,
                  strokewidth = 0.4)

    push!(handles, sc)

    nome = !ismissing(row.muni_nome) ? String(row.muni_nome) : String(row[name_col])
    push!(labels, nome)
end

# Legenda “grudada” no eixo, organizada
axislegend(ax, handles, labels;
    title        = "Top $(top_n) municípios (internações)",
    position     = :rt,          # :rt = canto superior direito
    orientation  = :vertical,
    framevisible = true,
    bgcolor      = (:black, 0.6),
    labelsize    = 8,
    titlesize    = 9,
)

# --- Colorbar ---
Colorbar(fig[1, 2];
    limits   = (cb_min, cb_max),
    colormap = cmap,
    label    = "Internações por Dengue ($ANO)",
    width    = 20,
    ticks    = LinearTicks(5),
)

display(fig)
# save("mapa_dengue_municipios_$(UF_ALVO)_$(ANO).png", fig)  # se quiser salvar

# ============================
# 8. Rankings para conferência
# ============================

println("\nTop 10 municípios de $(UF_ALVO) em internações por Dengue ($ANO):")
for (i, row) in enumerate(eachrow(first(df_top, min(10, nrow(df_top)))))
    nome = !ismissing(row.muni_nome) ? String(row.muni_nome) : String(row[name_col])
    println("$(i). $(nome): $(round(row.internacoes; digits=0)) internações")
end

df_bottom = sort(df_map, :internacoes, rev = false)

println("\n10 municípios de $(UF_ALVO) com MENOS internações por Dengue ($ANO):")
for (i, row) in enumerate(eachrow(first(df_bottom, min(10, nrow(df_bottom)))))
    nome = !ismissing(row.muni_nome) ? String(row.muni_nome) : String(row[name_col])
    println("$(i). $(nome): $(round(row.internacoes; digits=0)) internações")
end

df_zero = filter(:internacoes => ==(0.0), df_map)

println("\nMunicípios de $(UF_ALVO) com 0 internações registradas em $ANO:")
for row in eachrow(df_zero)
    nome = !ismissing(row.muni_nome) ? String(row.muni_nome) : String(row[name_col])
    println("- $(nome)")
end

# ============================
# 9. Checagens extras de consistência
# ============================

println("\n===== CHECAGENS DE CONSISTÊNCIA =====")
println("N municípios na malha (GeoBR $(UF_ALVO)): ", nrow(df_geo))
println("N municípios de $(UF_ALVO) no CSV (df_mun): ", nrow(df_mun))
println("N linhas no df_map (join): ", nrow(df_map))

df_join_raw = leftjoin(
    df_geo,
    df_mun[:, [:mun_key, :muni_nome, :internacoes]],
    on = :mun_key,
)

sem_dado = filter(:internacoes => ismissing, df_join_raw)
println("\nMunicípios de $(UF_ALVO) SEM registro de internação em $ANO (antes do coalesce):")
for row in eachrow(sem_dado)
    println("- ", String(row[name_col]))
end

total_uf_csv  = sum(df_mun.internacoes)
total_uf_mapa = sum(df_map.internacoes)

println("\nTotal de internações $(NOME_UF) no CSV:  ", total_uf_csv)
println("Total de internações $(NOME_UF) no mapa: ", total_uf_mapa)

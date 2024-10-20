module CGT

using CurrencyAmounts
using DataFrames
using Dates
using DelimitedFiles
using FixedPointDecimals
using HTTP
using XLSX

Fixed = FixedDecimal{Int, 2}

@currencies USD, EUR

const Tax = Fixed(0.33)
const Allowance = 1270EUR

struct ExchangeRates{From <: Currency, To <: Currency}
	cache::Dict{Date, ExchangeRate{<: Number, To, From}}
end
ExchangeRates(::From, ::To) where {From <: Currency, To <: Currency} = ExchangeRates{From, To}(Dict())

function fetch(date, from, to)
	url = "https://data-api.ecb.europa.eu/service/data/EXR/D.$from.$to.SP00.A?detail=dataonly&startPeriod=$date&endPeriod=$date"
	(data, header) = readdlm(HTTP.get(url, ["Accept" => "text/csv"]).body, ','; header=true)
	Fixed(data[findfirst(isequal("OBS_VALUE"), header)])
end

function Base.getindex(rates::ExchangeRates{From, To}, date) where {From, To}
	if !haskey(rates.cache, date)
		from = From()
		to = To()
		rates.cache[date] = fetch(date, from, to) * from / to
	end
	rates.cache[date]
end

struct Sales{C <: Currency}
	df::DataFrame
end
Sales(c::Currency, df::DataFrame) = Sales{typeof(c)}(df)

function Base.convert(::Type{Sales{To}}, s::Sales{From}, rates::ExchangeRates{From, To}) where {To <: Currency, From <: Currency}
	exchange(date::Date, c::CurrencyAmount{<: Number, From}) =  convert(To(), c, rates[date])
	exchange(::Date, c::Any) = c
	transform(s.df, AsTable(:) => ByRow(r -> (map(c -> exchange(r.Date, c), r)..., Rate=rates[r.Date])) => AsTable) |> Sales{To}
end
Base.convert(t::Type{Sales{To}}, s::Sales{From}) where {To <: Currency, From <: Currency} = convert(t, s, ExchangeRates(From(), To()))

function load(file)
	fmt = DateFormat("m/d/y")
	to_usd(s) = Fixed(s)*USD

	df = DataFrame(XLSX.gettable(XLSX.readxlsx(file)[1])...)
	filter!("Record Type" => isequal("Sell"), df)
	select!(df, "Date Sold" => ByRow(d -> Date(d, fmt)) => "Date", "Plan Type" => "Type", "Total Proceeds" => ByRow(to_usd) => "Proceeds", "Adjusted Gain/Loss" => ByRow(to_usd) => "Gains")
	sort!(df, :Date)

	Sales(USD, df)
end

function period(c::Currency, df::AbstractDataFrame; details=false)
	gain = sum(df.Gains)
	cols = propertynames(df)

	if details
		show(df; allrows=true, allcols=true, summary=false, eltypes=false, show_row_number=false, vlines=:all, newline_at_end=true, hlines=[:begin, :header, :end], filters_col=((_, i) -> cols[i] != :Late,))
	end
	println("Gain/Loss: ", gain)
	println("Tax: ", max(0c, gain) * Tax)

	gain
end

function by_period(sales::Sales{C}; details=false) where {C <: Currency}
	if !(:Late in propertynames(sales.df))
		transform!(sales.df, :Date => ByRow(d -> Dates.month(d) == 12) => :Late)
	end

	year = Dates.year(sales.df[1, :Date])
	total_gain = 0 * C()
	for (key, sdf) in pairs(groupby(sales.df, :Late; sort=true))
		println("Period ", key.Late ? "$year-12-01 - $year-12-31" : "$year-01-01 - $year-11-30")
		total_gain += period(C(), sdf; details)
		println("")
	end

	total_gain
end

function compute(sales::Sales{Currency{:EUR}}; details=false)
	total_gain = by_period(sales; details)
	net_gain = total_gain >= Allowance ? total_gain - Allowance : total_gain
	tax = max(net_gain, 0EUR) * Tax

	println("Total gain/loss: ", total_gain)
	println("Net gain/loss excluding the allowance: ", net_gain)
	println("Total tax: ", tax)

	tax
end

end

using Pkg
Pkg.activate(".")
Pkg.instantiate()

using ArgParse
using CGT
using CurrencyAmounts

function parse_commandline()
	s = ArgParseSettings(description="Computes the capital gain tax (in Ireland)")

	@add_arg_table s begin
		"--verbose", "-v"
			help = "Show transactions"
			action = :store_true
		"file"
			help = "Etrade Excel file"
			required = true
	end

	return parse_args(s)
end

function main()
	parsed_args = parse_commandline()

	sales = CGT.load(parsed_args["file"])
	sales = convert(CGT.Sales{Currency{:EUR}}, sales)
	CGT.compute(sales; details=parsed_args["verbose"])
end

main()

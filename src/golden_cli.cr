require "./golden"
require "./golden/review"
require "./golden/cli"

result = Golden::CLI.dispatch(ARGV.dup)
puts result unless result.empty?

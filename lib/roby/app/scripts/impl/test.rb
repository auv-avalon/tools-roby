require 'roby'
require 'roby/app'
require 'test/unit'
(r = Test::Unit::AutoRunner.new(true)).process_args(ARGV) or
  abort r.options.banner + " tests..."
exit r.run

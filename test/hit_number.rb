#!/usr/bin/env ruby
target = 1000
ARGV.each do |arg|
    target = target - arg.to_i
end
puts "some useless"
puts "lines to ignore"
puts target

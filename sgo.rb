#!/usr/bin/env ruby

require 'parallel'
require 'etc'
require 'fsfifo'

# Mutate, promote and kill members of multiple families to find the best parameters for your target script. 
# Call this as: sgo.rb [params] /path/to/targetscript [min|max]

Member = Struct.new(:params, :result) do
    # randomly change all params
    def mutate!(range)
        prng = Random.new

        mutated = []
        self.params.each do |param|
            if ((param.is_a? Integer) || (param.is_a? Float))
                start = 2
                start = 2.0 if param.is_a? Float
                minimum = 0
                minimum = 0.0 if param.is_a? Float
                
                if prng.rand(2) == 1
                    # note that the call to Random.rand includes the chance to keep the param as is
                    mutation = [minimum, param + prng.rand([start, param * range].max)].max
                else
                    mutation = [minimum, param - prng.rand([start, param * range].max)].max
                end
                mutation = mutation.to_f
                mutation = mutation.to_i if (param.is_a? Integer)
                mutated.push(mutation)
            end
        end
        self.params = mutated
    end
end

Family = Struct.new(:members, :history) do
    # randomly change all params of all members
    def mutate!(range = 0.1)
        members.each {|x| x.mutate!(range) } 
    end

    # Evalute fitness of members by executing the target script with their params
    def evaluate!(script)
        members.each do |member|
            argString = member.params.join(' ')
            member.result = %x{ #{script} #{argString} }.lines.last.chomp.to_f
        end
    end

    # Evolve family by replacing the worst performing member with a mutation of the best member
    def evolve!(target)
        self.members = self.members.sort_by{|x| x.result }

        if target == :min
            bestMember = self.members.first
            self.members[-1] = Member.new(bestMember.params, nil)
        end
        if target == :max
            bestMember = self.members.last
            self.members[0] = Member.new(bestMember.params, nil)
        end
        self.history.push(bestMember.result)
    end

    def trend
        y_values = self.history
        size = y_values.size
        x_values = (1..size).to_a

        #initialize everything to 0
        sum_x = 0 
        sum_y = 0 
        sum_xx = 0 
        sum_xy = 0 

        # calculate the sums
        y_values.zip(x_values).each do |y, x|
          sum_xy += x*y 
          sum_xx += x*x 
          sum_x  += x
          sum_y  += y
        end 

        # calculate the slope
        slope = 1.0 * ((size * sum_xy) - (sum_x * sum_y)) / ((size * sum_xx) - (sum_x * sum_x))
        #~ intercept = 1.0 * (sum_y - (slope * sum_x)) / size
        return slope
    end
end


def main(params, script, target)
    puts 'main'
    # evaling the given parameters converts them from strings to Integers and Floats
    params = params.map{|x| eval(x) rescue x }
    families = []
        
    threadcount = Etc.nprocessors
    puts "I will now start #{threadcount} search processes"
    1.upto(threadcount) {|_| families.push(Family.new([1, 2, 3, 4].map{|_| Member.new(params, nil) }, FSFIFO.new(10))) }

    # Find real distinct starting points randomly distributed on the implicitely calculated search area
    families.each do |family|
        family.mutate!(1.0)
    end
    
    Parallel.each(families, in_processes: families.length) do |family|
        loop do
            family.mutate!
            family.evaluate!(script)
            if target == :min
                bestMember = family.members.sort_by{|x| x.result }.first
            else
                # target == :max
                bestMember = family.members.sort_by{|x| x.result }.last
            end
            p bestMember.result

            if (bestMember.result <= 0) || (family.history.size == 10 && family.trend.abs < 0.3)
                puts "got a final result for #{bestMember.result.to_s}:"
                p bestMember.params
                raise Parallel::Kill  
            end

            family.evolve!(target)
        end
    end
    
end


target = :min
script = nil
if ARGV.last == 'min' || ARGV.last == 'max'
    if ARGV.last == 'max'
        target = :max
    end
    script = ARGV[-2]
    args = ARGV[0...-2]
else
    script = ARGV.last
    args = ARGV[0...-1]
end

main(args, script, target)

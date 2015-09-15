class A
	def finalize
		LibC.printf "#{self}.finalize\n"
	end
end

def thjoin th
	th.join
	1
rescue ex
	p ex
	0
end

def sthread
	Thread.new do
#		A.new
#		LibC.printf "hello\n"
		3.times { GC.collect }
#		raise "here" if rand(3) == 0
#		LibC.printf "#{Fiber.current}\n"
#		GC.collect
# BUG: GC.collect returns Void which crashes Thread.join in `if is_a?`.  wtf
#		"#{Fiber}"
	end
end

threads = 10.times.map do
	sthread
end.to_a

sleep 0.1
puts ""
puts ""

success = 0
success = threads.map { |th| thjoin th }.sum
threads.clear

sleep 0.1
puts ""
puts "last gc collect success=#{success}"

10.times do
	GC.collect
end
